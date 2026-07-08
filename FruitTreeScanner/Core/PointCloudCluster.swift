// PointCloudCluster.swift
// DBSCAN聚类 - 从3D点云提取球形物体候选

import Foundation
import simd

// MARK: - PointCloudCluster

final class PointCloudCluster: Sendable {
    let config: ClusterConfig

    init(config: ClusterConfig = .default) {
        self.config = config
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

    func debugAdaptiveEps(distance: Float, density: Float) -> Float {
        adaptiveEps(baseEps: config.baseEps, distance: distance, density: density)
    }

    func debugLocalSpacingFactors(points: [SIMD3<Float>]) -> [Float] {
        let clusterPoints = points.map { ClusterPoint(pos: $0, color: .zero) }
        return computeLocalSpacingFactors(clusterPoints, kdtree: KDTree(points: points))
    }

    // MARK: - DBSCAN Implementation

    struct ClusterPoint {
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

        // 第二步：计算全局密度与局部间距，用于自适应 EPS
        let avgPointDensity = computePointDensity(points)
        let localSpacingFactors = computeLocalSpacingFactors(points, kdtree: kdtree)

        for i in 0..<points.count {
            if points[i].visited { continue }
            points[i].visited = true

            // 自适应 epsilon - 根据距离和点云密度动态调整
            let distance = simd_length(points[i].pos)
            let eps = adaptiveEps(
                baseEps: config.baseEps,
                distance: distance,
                density: avgPointDensity,
                localSpacingFactor: localSpacingFactors[i]
            )

            let neighbors = regionQuery(index: i, points: points, kdtree: kdtree, eps: eps)

            if neighbors.count < config.minPoints {
                continue
            }

            expandCluster(
                index: i,
                neighbors: neighbors,
                clusterId: clusterId,
                eps: eps,
                points: &points,
                kdtree: kdtree,
                density: avgPointDensity,
                localSpacingFactors: localSpacingFactors
            )
            clusterId += 1
        }

        // 第三步：按 clusterId 分组，分析每个聚类
        var clusterBuckets = [[ClusterPoint]](repeating: [], count: clusterId)
        for point in points where point.clusterId >= 0 && point.clusterId < clusterId {
            clusterBuckets[point.clusterId].append(point)
        }
        for bucket in clusterBuckets {
            if let candidate = analyzeCluster(bucket) {
                candidates.append(candidate)
            }
        }

        return candidates
    }

    // MARK: - 噪声过滤（KD-Tree 加速，O(n log n)）

    private func applyNoiseFilter(_ points: [ClusterPoint]) -> [ClusterPoint] {
        guard points.count >= 10 else { return points }

        let positions = points.map { $0.pos }
        let kdtree = KDTree(points: positions)
        let k = 6

        var meanDistances = [Float](repeating: 0, count: points.count)
        var globalSum: Double = 0
        var validCount = 0

        for i in 0..<points.count {
            let nearest = kdtree.kNearest(center: positions[i], k: k)
            var distSum: Float = 0
            var count = 0
            for n in nearest where n != i {
                distSum += simd_distance(positions[i], positions[n])
                count += 1
            }
            let mean = count > 0 ? distSum / Float(count) : Float.greatestFiniteMagnitude
            meanDistances[i] = mean
            if mean < Float.greatestFiniteMagnitude {
                globalSum += Double(mean)
                validCount += 1
            }
        }

        guard validCount > 0 else { return points }

        let globalMean = Float(globalSum / Double(validCount))
        var varianceSum: Double = 0
        for d in meanDistances where d < Float.greatestFiniteMagnitude {
            let diff = Double(d - globalMean)
            varianceSum += diff * diff
        }
        let globalStd = Float(sqrt(varianceSum / Double(validCount)))
        let threshold = globalMean + 2.0 * globalStd
        let radialDistances = positions.map { max(simd_length($0), 0.3) }.sorted()
        let medianDistance = radialDistances[radialDistances.count / 2]

        return points.enumerated().compactMap { i, point in
            // Consumer LiDAR returns become sparser with range. A single
            // global kNN threshold can incorrectly remove a coherent distant
            // fruit cluster before adaptive DBSCAN sees it, so only relax the
            // threshold for points farther than the scan's median range.
            let pointDistance = max(simd_length(point.pos), 0.3)
            let distanceScale = min(
                max(pointDistance / max(medianDistance, 0.3), 1.0),
                3.0
            )
            return meanDistances[i] <= threshold * distanceScale ? point : nil
        }
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

    private func computeLocalSpacingFactors(_ points: [ClusterPoint], kdtree: KDTree) -> [Float] {
        guard points.count > 2 else {
            return Array(repeating: 1.0, count: points.count)
        }

        let neighborCount = min(max(config.minPoints + 1, 6), points.count)
        var meanSpacings = [Float](repeating: 0, count: points.count)

        for i in points.indices {
            let nearest = kdtree.kNearest(center: points[i].pos, k: neighborCount)
            var distanceSum: Float = 0
            var validCount = 0

            for neighborIndex in nearest where neighborIndex != i {
                let distance = simd_distance(points[i].pos, points[neighborIndex].pos)
                if distance.isFinite, distance > 0 {
                    distanceSum += distance
                    validCount += 1
                }
            }

            meanSpacings[i] = validCount > 0
                ? distanceSum / Float(validCount)
                : Float.nan
        }

        let validSpacings = meanSpacings
            .filter { $0.isFinite && $0 > 0 }
            .sorted()
        guard !validSpacings.isEmpty else {
            return Array(repeating: 1.0, count: points.count)
        }

        let medianSpacing = max(validSpacings[validSpacings.count / 2], 1e-4)
        return meanSpacings.map { spacing in
            guard spacing.isFinite, spacing > 0 else { return 1.0 }
            let relativeSpacing = spacing / medianSpacing
            let factor = sqrt(max(relativeSpacing, 0))
            return min(max(factor, 0.85), 1.35)
        }
    }

    // MARK: - 扩展聚类

    private func expandCluster(
        index: Int,
        neighbors: [Int],
        clusterId: Int,
        eps: Float,
        points: inout [ClusterPoint],
        kdtree: KDTree,
        density: Float,
        localSpacingFactors: [Float]
    ) {
        points[index].clusterId = clusterId
        var neighborList = neighbors
        var inCluster = Set(neighbors)
        inCluster.insert(index)

        var i = 0
        while i < neighborList.count {
            let neighborIndex = neighborList[i]
            if !points[neighborIndex].visited {
                points[neighborIndex].visited = true
                let neighborDistance = simd_length(points[neighborIndex].pos)
                let localSpacingFactor = neighborIndex < localSpacingFactors.count
                    ? localSpacingFactors[neighborIndex]
                    : 1.0
                let neighborEps = adaptiveEps(
                    baseEps: config.baseEps,
                    distance: neighborDistance,
                    density: density,
                    localSpacingFactor: localSpacingFactor
                )
                let newNeighbors = regionQuery(index: neighborIndex, points: points, kdtree: kdtree, eps: neighborEps)

                if newNeighbors.count >= config.minPoints {
                    for n in newNeighbors where !inCluster.contains(n) {
                        inCluster.insert(n)
                        neighborList.append(n)
                    }
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

    private func adaptiveEps(
        baseEps: Float,
        distance: Float,
        density: Float,
        localSpacingFactor: Float = 1.0
    ) -> Float {
        // 基础距离缩放：LiDAR点密度 ∝ 1/d²，所以eps应该用sqrt(d)缩放
        let distanceFactor = sqrt(max(distance, 0.3))

        // 点云密度调整：密度高时可以用较小的eps，密度低时需要较大的eps
        let densityFactor: Float = {
            if density > 500 { return 0.8 }
            if density < 50 { return 1.5 }
            return 1.0
        }()

        // 果实尺寸约束：eps不应超过最大果实半径的一半
        let boundedLocalSpacingFactor = localSpacingFactor.isFinite
            ? min(max(localSpacingFactor, 0.85), 1.35)
            : 1.0
        let scaledEps = baseEps * distanceFactor * densityFactor * boundedLocalSpacingFactor

        // 边界约束
        let minEps = baseEps * 0.5
        let maxEps = min(baseEps * 2.0, max(config.maxDiameter * 0.75, baseEps))

        return min(max(scaledEps, minEps), maxEps)
    }

}
