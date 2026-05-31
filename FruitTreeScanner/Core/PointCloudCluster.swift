// PointCloudCluster.swift
// DBSCAN聚类 - 从3D点云提取球形物体候选

import Foundation
import simd

// MARK: - Delegate Protocol

protocol PointCloudClusterDelegate: AnyObject {
    func pointCloudCluster(_ cluster: PointCloudCluster, didFind candidates: [FruitCandidate])
}

// MARK: - PointCloudCluster

final class PointCloudCluster: @unchecked Sendable {
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

    /// 处理 ColoredPoint 数组（同步，用于 YieldEstimator）
    func processSync(points: [ColoredPoint]) -> [FruitCandidate] {
        let positions = points.map { $0.pos }
        let colors = points.map { SIMD3<Float>($0.r, $0.g, $0.b) }
        return dbscanClustering(positions: positions, colors: colors)
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

    func debugRangeQuery(points: [SIMD3<Float>], center: SIMD3<Float>, radius: Float) -> [Int] {
        KDTree(points: points).rangeQuery(center: center, radius: radius)
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

        // 第一步：噪声过滤 - 移除孤立点和边界噪声
        points = applyNoiseFilter(points)
        guard points.count >= config.minPoints else { return [] }

        // 构建 KD-Tree
        let kdtree = KDTree(points: points.map { $0.pos })

        var clusterId = 0
        var candidates: [FruitCandidate] = []

        // 第二步：计算点云密度，用于自适应 EPS
        let avgPointDensity = computePointDensity(points)

        for i in 0..<points.count {
            if points[i].visited { continue }
            points[i].visited = true

            // 自适应 epsilon - 根据距离和点云密度动态调整
            let distance = simd_length(points[i].pos)
            let eps = adaptiveEps(baseEps: config.baseEps, distance: distance, density: avgPointDensity)

            let neighbors = regionQuery(index: i, points: points, kdtree: kdtree, eps: eps)

            if neighbors.count < config.minPoints {
                continue
            }

            expandCluster(index: i, neighbors: neighbors, clusterId: clusterId, eps: eps, points: &points, kdtree: kdtree, density: avgPointDensity)
            clusterId += 1
        }

        // 第三步：分析每个聚类，添加额外过滤
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

    // MARK: - 噪声过滤

    private func applyNoiseFilter(_ points: [ClusterPoint]) -> [ClusterPoint] {
        guard points.count >= 10 else { return points }

        // 计算所有点的平均距离
        let avgDist = computeAverageNeighborDistance(points, k: 5)

        // 过滤掉距离其他点太远的孤立点
        let threshold = avgDist * 3.0
        let filtered = points.filter { point in
            var minDist: Float = .greatestFiniteMagnitude
            for other in points where other.pos != point.pos {
                let dist = simd_distance(point.pos, other.pos)
                minDist = min(minDist, dist)
            }
            return minDist < threshold
        }

        return filtered
    }

    private func computeAverageNeighborDistance(_ points: [ClusterPoint], k: Int) -> Float {
        guard points.count >= k + 1 else { return 0.1 }

        let positions = points.map { $0.pos }
        let kdtree = KDTree(points: positions)
        var totalDist: Float = 0
        var count: Int = 0

        for (i, point) in points.enumerated() {
            let neighbors = kdtree.rangeQuery(center: point.pos, radius: 0.5)
            let otherNeighbors = neighbors.filter { $0 != i }.prefix(k)
            for n in otherNeighbors {
                totalDist += simd_distance(point.pos, positions[n])
                count += 1
            }
        }

        return count > 0 ? totalDist / Float(count) : 0.1
    }

    // MARK: - 点云密度计算

    private func computePointDensity(_ points: [ClusterPoint]) -> Float {
        guard points.count > 0 else { return 100 }

        // 计算边界框体积
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude

        for point in points {
            minX = min(minX, point.pos.x)
            maxX = max(maxX, point.pos.x)
            minY = min(minY, point.pos.y)
            maxY = max(maxY, point.pos.y)
            minZ = min(minZ, point.pos.z)
            maxZ = max(maxZ, point.pos.z)
        }

        let volume = (maxX - minX) * (maxY - minY) * (maxZ - minZ)
        return volume > 0 ? Float(points.count) / volume : 100
    }

    // MARK: - 扩展聚类

    private func expandCluster(index: Int, neighbors: [Int], clusterId: Int, eps: Float, points: inout [ClusterPoint], kdtree: KDTree, density: Float) {
        points[index].clusterId = clusterId
        var neighborList = neighbors

        var i = 0
        while i < neighborList.count {
            let neighborIndex = neighborList[i]
            if !points[neighborIndex].visited {
                points[neighborIndex].visited = true
                let neighborDistance = simd_length(points[neighborIndex].pos)
                let neighborEps = adaptiveEps(baseEps: config.baseEps, distance: neighborDistance, density: density)
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

    // MARK: - 自适应 EPS 计算

    private func adaptiveEps(baseEps: Float, distance: Float, density: Float) -> Float {
        // 基础距离缩放：LiDAR点密度 ∝ 1/d²，所以eps应该用sqrt(d)缩放
        let distanceFactor = sqrt(max(distance, 0.3))

        // 点云密度调整：密度高时可以用较小的eps，密度低时需要较大的eps
        let densityFactor: Float = {
            if density > 500 { return 0.8 }
            if density < 50 { return 1.5 }
            return 1.0
        }()

        // 果实尺寸约束：eps不应超过最大果实半径的一半
        let scaledEps = baseEps * distanceFactor * densityFactor

        // 边界约束
        let minEps = baseEps * 0.5
        let maxEps = min(baseEps * 2.0, 0.08)

        return min(max(scaledEps, minEps), maxEps)
    }

    // MARK: - Cluster Analysis

    private func analyzeCluster(_ clusterPoints: [ClusterPoint]) -> FruitCandidate? {
        guard clusterPoints.count >= config.minPoints else { return nil }

        let center = computeCentroid(clusterPoints.map { $0.pos })
        let diameter = computeDiameter(positions: clusterPoints.map { $0.pos }, center: center)

        // 尺寸过滤
        if diameter < config.minDiameter || diameter > config.maxDiameter {
            return nil
        }

        // 计算球形度
        let sphericity = computeSphericity(positions: clusterPoints.map { $0.pos }, center: center)

        if sphericity <= config.sphericityThreshold {
            return nil
        }

        // 颜色过滤：检查是否具有果实颜色
        let avgColor = computeAverageColor(clusterPoints.map { $0.color })
        if !FruitCategory.isFruitColor(avgColor) {
            return nil
        }

        // 形状规则性检查
        if !isShapeRegular(clusterPoints, center: center, diameter: diameter) {
            return nil
        }

        return FruitCandidate(
            position: center,
            diameter: diameter,
            sphericity: sphericity,
            pointCount: clusterPoints.count,
            averageColor: avgColor
        )
    }

    // MARK: - 形状规则性检查

    private func isShapeRegular(_ points: [ClusterPoint], center: SIMD3<Float>, diameter: Float) -> Bool {
        let radius = diameter / 2.0
        guard radius > 0 else { return false }
        let positions = points.map { $0.pos }
        guard !positions.isEmpty else { return false }

        let distances = positions.map { simd_distance($0, center) }
        let avgDist = distances.reduce(0, +) / Float(distances.count)

        // 计算距离方差，判断形状是否规则
        var variance: Float = 0
        for d in distances {
            variance += (d - avgDist) * (d - avgDist)
        }
        variance /= Float(distances.count)
        let stdDev = sqrt(variance)

        // 标准差不应超过半径的30%
        return stdDev < radius * 0.3
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
        let dists = positions.map { simd_distance($0, center) }.sorted()
        guard !dists.isEmpty else { return 0 }
        let idx90 = max(0, Int(Float(dists.count) * 0.90) - 1)
        return dists[idx90] * 2.0
    }

    private func computeSphericity(positions: [SIMD3<Float>], center: SIMD3<Float>) -> Float {
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

        let eigenvalues = computeEigenvalues(cov)

        guard eigenvalues.count == 3 else { return 0.0 }

        let lambdaMin = eigenvalues.min() ?? 0
        let lambdaMax = eigenvalues.max() ?? 1

        if lambdaMax < 1e-6 { return 0.0 }

        return lambdaMin / lambdaMax
    }

    private func computeEigenvalues(_ matrix: simd_float3x3) -> [Float] {
        var eigenvalues: [Float] = []
        var eigenvectors: [SIMD3<Float>] = []

        for _ in 0..<3 {
            var current = SIMD3<Float>(1, 0, 0)

            for v in eigenvectors {
                current -= simd_dot(current, v) * v
            }
            let initNorm = simd_length(current)
            if initNorm < 1e-6 { break }
            current /= initNorm

            var prevLambda: Float = 0
            for iter in 0..<50 {
                var next: SIMD3<Float> = matrix * current
                for v in eigenvectors {
                    next -= simd_dot(next, v) * v
                }
                let norm = simd_length(next)
                if norm < 1e-6 { break }
                current = next / norm

                let lambda = simd_dot(current, matrix * current)
                if iter > 0 && abs(lambda - prevLambda) < 1e-4 { break }
                prevLambda = lambda
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
    private var rootNodeIndex: Int?

    struct KDNode {
        var point: SIMD3<Float>
        var index: Int
        var left: Int?
        var right: Int?
        var axis: Int
    }

    init(points: [SIMD3<Float>]) {
        nodes = []
        rootNodeIndex = nil
        guard !points.isEmpty else {
            return
        }

        var indices = Array(points.indices)
        rootNodeIndex = buildTree(points: points, indices: &indices, depth: 0, range: 0..<points.count)
    }

    private mutating func buildTree(points: [SIMD3<Float>], indices: inout [Int], depth: Int, range: Range<Int>) -> Int? {
        guard range.lowerBound < range.upperBound else { return nil }

        let axis = depth % 3
        let mid = (range.lowerBound + range.upperBound) / 2

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
        guard let rootNodeIndex else { return [] }
        var result: [Int] = []
        rangeSearch(nodeIndex: rootNodeIndex, center: center, radius: radius, result: &result)
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
