// PointCloudCluster.swift
// DBSCAN聚类 - 从3D点云提取球形物体候选

import Foundation
import simd

// MARK: - Delegate Protocol

protocol PointCloudClusterDelegate: AnyObject {
    func pointCloudCluster(_ cluster: PointCloudCluster, didFind candidates: [FruitCandidate])
}

// MARK: - PointCloudCluster

final class PointCloudCluster {
    weak var delegate: PointCloudClusterDelegate?
    var config: ClusterConfig

    init(config: ClusterConfig = .default) {
        self.config = config
    }

    func updateConfig(_ newConfig: ClusterConfig) {
        self.config = newConfig
    }

    // MARK: - Public API

    /// 处理 ColoredPoint 数组（异步）
    func process(points: [ColoredPoint]) async -> [FruitCandidate] {
        let positions = points.map { $0.pos }
        let colors = points.map { SIMD3<Float>($0.r, $0.g, $0.b) }
        return await processInMemory(position: positions, colors: colors)
    }

    /// 处理内存中的点云数据（异步）
    func processInMemory(position: [SIMD3<Float>], colors: [SIMD3<Float>]) async -> [FruitCandidate] {
        guard position.count >= config.minPoints else { return [] }

        return await withCheckedContinuation { continuation in
            DispatchQueue.global(qos: .userInitiated).async {
                let candidates = self.dbscanClustering(positions: position, colors: colors)
                continuation.resume(returning: candidates)
            }
        }
    }

    // MARK: - DBSCAN Implementation

    private struct ClusterPoint {
        var pos: SIMD3<Float>
        var color: SIMD3<Float>
        var visited: Bool = false
        var clusterId: Int = -1
    }

    private func dbscanClustering(positions: [SIMD3<Float>], colors: [SIMD3<Float>]) -> [FruitCandidate] {
        var points = zip(positions, colors).map { ClusterPoint(pos: $0.0, color: $0.1) }

        // 构建 KD-Tree
        let kdtree = KDTree(points: points.map { $0.pos })

        var clusterId = 0
        var candidates: [FruitCandidate] = []

        for i in 0..<points.count {
            if points[i].visited { continue }
            points[i].visited = true

            // 自适应 epsilon
            let distance = simd_length(points[i].pos)
            let eps = adaptiveEps(baseEps: config.baseEps, distance: distance)

            let neighbors = regionQuery(index: i, points: points, kdtree: kdtree, eps: eps)

            if neighbors.count < config.minPoints {
                // 噪声点，不处理
                continue
            }

            // 扩展聚类
            expandCluster(index: i, neighbors: neighbors, clusterId: clusterId, eps: eps, points: &points, kdtree: kdtree)
            clusterId += 1
        }

        // 分析每个聚类
        for id in 0..<clusterId {
            var clusterPoints: [ClusterPoint] = []
            for point in points where point.clusterId == id {
                clusterPoints.append(point)
            }

            if let candidate = analyzeCluster(clusterPoints) {
                candidates.append(candidate)
            }
        }

        return candidates
    }

    private func expandCluster(index: Int, neighbors: [Int], clusterId: Int, eps: Float, points: inout [ClusterPoint], kdtree: KDTree) {
        points[index].clusterId = clusterId
        var neighborList = neighbors

        var i = 0
        while i < neighborList.count {
            let neighborIndex = neighborList[i]
            if !points[neighborIndex].visited {
                points[neighborIndex].visited = true
                let neighborDistance = simd_length(points[neighborIndex].pos)
                let neighborEps = adaptiveEps(baseEps: config.baseEps, distance: neighborDistance)
                let newNeighbors = regionQuery(index: neighborIndex, points: points, kdtree: kdtree, eps: neighborEps)

                if newNeighbors.count >= config.minPoints {
                    let existingNeighbors = Set(neighborList)
                    neighborList.append(contentsOf: newNeighbors.filter { !existingNeighbors.contains($0) })
                }
            }

            if points[neighborIndex].clusterId == -1 {
                points[neighborIndex].clusterId = clusterId
            }
            i += 1
        }
    }

    private func regionQuery(index: Int, points: [ClusterPoint], kdtree: KDTree, eps: Float) -> [Int] {
        let target = points[index].pos
        let indices = kdtree.rangeQuery(center: target, radius: eps)
        return indices
    }

    private func adaptiveEps(baseEps: Float, distance: Float) -> Float {
        // LiDAR 点云近密远疏，自适应 epsilon
        // 远处需要更大的邻域半径才能找到足够的邻居
        return baseEps * (1.0 + distance / 10.0)
    }

    // MARK: - Cluster Analysis

    private func analyzeCluster(_ clusterPoints: [ClusterPoint]) -> FruitCandidate? {
        guard clusterPoints.count >= config.minPoints else { return nil }

        // 计算中心位置
        let center = computeCentroid(clusterPoints.map { $0.pos })

        // 计算直径（包围盒对角线）
        let diameter = computeDiameter(positions: clusterPoints.map { $0.pos }, center: center)

        // 尺寸过滤
        if diameter < config.minDiameter || diameter > config.maxDiameter {
            return nil
        }

        // 计算球形度
        let sphericity = computeSphericity(positions: clusterPoints.map { $0.pos }, center: center)

        // 球形度过滤
        if sphericity <= config.sphericityThreshold {
            return nil
        }

        return FruitCandidate(
            position: center,
            diameter: diameter,
            sphericity: sphericity,
            pointCount: clusterPoints.count,
            averageColor: computeAverageColor(clusterPoints.map { $0.color })
        )
    }

    /// 计算平均颜色
    private func computeAverageColor(_ colors: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !colors.isEmpty else { return SIMD3<Float>(0.5, 0.5, 0.5) }
        var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
        for color in colors {
            sumR += color.x
            sumG += color.y
            sumB += color.z
        }
        let count = Float(colors.count)
        return SIMD3<Float>(sumR / count, sumG / count, sumB / count)
    }

    private func computeCentroid(_ positions: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !positions.isEmpty else { return SIMD3<Float>(0, 0, 0) }
        var sum = SIMD3<Float>(0, 0, 0)
        for pos in positions {
            sum += pos
        }
        return sum / Float(positions.count)
    }

    private func computeDiameter(positions: [SIMD3<Float>], center: SIMD3<Float>) -> Float {
        var maxDist: Float = 0
        for pos in positions {
            let dist = simd_distance(pos, center)
            maxDist = max(maxDist, dist)
        }
        return maxDist * 2.0 // 半径转直径
    }

    private func computeSphericity(positions: [SIMD3<Float>], center: SIMD3<Float>) -> Float {
        // 计算协方差矩阵
        let n = Float(positions.count)
        guard n > 1 else { return 1.0 }

        var cov = simd_float3x3()
        var m01: Float = 0, m02: Float = 0, m12: Float = 0

        for pos in positions {
            let d = pos - center
            cov.columns.0.x += d.x * d.x
            cov.columns.1.y += d.y * d.y
            cov.columns.2.z += d.z * d.z
            m01 += d.x * d.y
            m02 += d.x * d.z
            m12 += d.y * d.z
        }

        // 对称化并归一化
        let denom = n - 1
        cov.columns.0.x /= denom
        cov.columns.1.y /= denom
        cov.columns.2.z /= denom
        cov.columns.1.x = m01 / denom
        cov.columns.2.x = m02 / denom
        cov.columns.2.y = m12 / denom
        cov.columns.0.y = cov.columns.1.x
        cov.columns.0.z = cov.columns.2.x
        cov.columns.1.z = cov.columns.2.y

        // 求特征值（使用幂迭代法）
        let eigenvalues = computeEigenvalues(cov)

        guard eigenvalues.count == 3 else { return 0.0 }

        let lambdaMin = eigenvalues.min() ?? 0
        let lambdaMax = eigenvalues.max() ?? 1

        if lambdaMax < 1e-6 { return 0.0 }

        return lambdaMin / lambdaMax
    }

    private func computeEigenvalues(_ matrix: simd_float3x3) -> [Float] {
        // 使用带正交化约束的幂迭代法求对称矩阵的特征值
        var eigenvalues: [Float] = []
        var eigenvectors: [SIMD3<Float>] = []

        for _ in 0..<3 {
            var current = SIMD3<Float>(1, 0, 0)

            // 与已求得的特征向量正交化，确保收敛到新的特征方向
            for v in eigenvectors {
                current -= simd_dot(current, v) * v
            }
            let initNorm = simd_length(current)
            if initNorm < 1e-6 { break }
            current /= initNorm

            // 幂迭代（每步正交化）
            for _ in 0..<10 {
                var next: SIMD3<Float> = matrix * current
                // 正交化约束：投影到已求特征向量的正交补空间
                for v in eigenvectors {
                    next -= simd_dot(next, v) * v
                }
                let norm = simd_length(next)
                if norm < 1e-6 { break }
                current = next / norm
            }

            let lambda = simd_dot(current, matrix * current)
            eigenvalues.append(lambda)
            eigenvectors.append(current)
        }

        return eigenvalues.sorted()
    }
}

// MARK: - KD-Tree

private struct KDTree {
    private var nodes: [KDNode]

    struct KDNode {
        var point: SIMD3<Float>
        var index: Int
        var left: Int?
        var right: Int?
        var axis: Int
    }

    init(points: [SIMD3<Float>]) {
        nodes = []
        guard !points.isEmpty else { return }

        var indices = Array(points.indices)
        _ = buildTree(points: points, indices: &indices, depth: 0, range: 0..<points.count)
    }

    private mutating func buildTree(points: [SIMD3<Float>], indices: inout [Int], depth: Int, range: Range<Int>) -> Int? {
        guard range.lowerBound < range.upperBound else { return nil }

        let axis = depth % 3
        let mid = (range.lowerBound + range.upperBound) / 2

        // nth_element 分区
        indices[range].sort { a, b in
            let posA = points[a]
            let posB = points[b]
            if axis == 0 {
                return posA.x < posB.x
            } else if axis == 1 {
                return posA.y < posB.y
            } else {
                return posA.z < posB.z
            }
        }
        let pivotIndex = indices[mid]

        let leftRange: Range<Int>? = range.lowerBound < mid ? range.lowerBound..<mid : nil
        let rightRange: Range<Int>? = mid + 1 < range.upperBound ? mid + 1..<range.upperBound : nil

        let leftChildId: Int? = leftRange != nil ? buildTree(points: points, indices: &indices, depth: depth + 1, range: leftRange!) : nil
        let rightChildId: Int? = rightRange != nil ? buildTree(points: points, indices: &indices, depth: depth + 1, range: rightRange!) : nil

        let node = KDNode(
            point: points[pivotIndex],
            index: pivotIndex,
            left: leftChildId,
            right: rightChildId,
            axis: axis
        )
        nodes.append(node)

        return nodes.count - 1
    }

    func rangeQuery(center: SIMD3<Float>, radius: Float) -> [Int] {
        var result: [Int] = []
        rangeSearch(nodeIndex: 0, center: center, radius: radius, result: &result)
        return result
    }

    private func rangeSearch(nodeIndex: Int, center: SIMD3<Float>, radius: Float, result: inout [Int]) {
        guard nodeIndex < nodes.count else { return }

        let node = nodes[nodeIndex]
        let dist = simd_distance(node.point, center)

        if dist <= radius {
            result.append(node.index)
        }

        let axis = node.axis
        let coord = axis == 0 ? center.x : (axis == 1 ? center.y : center.z)
        let nodeCoord = axis == 0 ? node.point.x : (axis == 1 ? node.point.y : node.point.z)

        if nodeCoord - radius <= coord, let left = node.left {
            rangeSearch(nodeIndex: left, center: center, radius: radius, result: &result)
        }
        if nodeCoord + radius >= coord, let right = node.right {
            rangeSearch(nodeIndex: right, center: center, radius: radius, result: &result)
        }
    }
}

// MARK: - Point Cloud Cluster
