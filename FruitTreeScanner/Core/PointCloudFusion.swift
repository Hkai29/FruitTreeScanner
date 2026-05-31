// PointCloudFusion.swift
// 点云帧融合模块
// 功能：
// 1. 帧质量评估与筛选
// 2. 基于 AR 位姿的点云对齐
// 3. 体素滤波去重
// 4. 多帧融合

import Foundation
import simd
import ARKit

// MARK: - 融合用点（独立定义，避免编译顺序问题）

struct FusedPoint {
    let pos: SIMD3<Float>
    let r: Float
    let g: Float
    let b: Float
}

// MARK: - 点云帧

struct PointCloudFrame {
    let points: [FusedPoint]      // 点云数据
    let transform: simd_float4x4    // AR 相机位姿
    let timestamp: TimeInterval      // 时间戳
    let pointCount: Int             // 点数
    let trackingQuality: TrackingQuality  // 追踪质量

    var quality: FrameQuality {
        // 综合质量评分
        let trackingScore: Float
        switch trackingQuality {
        case .normal: trackingScore = 1.0
        case .limited: trackingScore = 0.6
        case .notAvailable: trackingScore = 0.2
        }

        let densityScore: Float = min(1.0, Float(pointCount) / 1000.0)

        let totalScore = trackingScore * 0.6 + densityScore * 0.4

        if totalScore > 0.7 { return .high }
        if totalScore > 0.4 { return .medium }
        return .low
    }
}

// MARK: - 帧质量

enum FrameQuality {
    case high, medium, low
}

// MARK: - 追踪质量

enum TrackingQuality {
    case normal, limited, notAvailable
}

// MARK: - 融合后的点云

struct FusedPointCloud {
    var points: [FusedPoint]  // 融合后的点
    var frameCount: Int          // 融合的帧数
    var rejectedFrames: Int      // 丢弃的帧数

    var pointCount: Int { points.count }
}

// MARK: - 点云帧融合器

class PointCloudFusion {

    // MARK: - 参数

    /// 体素大小（米），用于降采样
    var voxelSize: Float = 0.01  // 1cm 体素

    /// 最小帧质量阈值
    var minQualityThreshold: FrameQuality = .low

    /// 最大融合帧数
    var maxFrames: Int = 30

    /// 位置融合距离阈值（米）
    var positionMergeThreshold: Float = 0.005  // 5mm

    // MARK: - 存储

    private var frames: [PointCloudFrame] = []
    private var lastTransform: simd_float4x4?

    // MARK: - 添加帧

    /// 添加一帧点云（从 Renderer 调用）
    func addFrame(
        points: [FusedPoint],
        transform: simd_float4x4,
        timestamp: TimeInterval,
        trackingQuality: TrackingQuality
    ) {
        let frame = PointCloudFrame(
            points: points,
            transform: transform,
            timestamp: timestamp,
            pointCount: points.count,
            trackingQuality: trackingQuality
        )

        frames.append(frame)

        // 限制帧数
        if frames.count > maxFrames {
            frames.removeFirst()
        }

        lastTransform = transform
    }

    // MARK: - 帧质量评估

    /// 评估并筛选高质量帧
    func selectHighQualityFrames() -> [PointCloudFrame] {
        let qualityFiltered = frames.filter { frame in
            if frame.trackingQuality == .notAvailable { return false }
            if frame.quality == .low { return false }
            return true
        }

        guard !qualityFiltered.isEmpty else { return [] }

        var selected: [PointCloudFrame] = [qualityFiltered[0]]
        for frame in qualityFiltered.dropFirst() {
            guard let prev = selected.last else { break }
            let movement = simd_distance(
                frame.transform.columns.3,
                prev.transform.columns.3
            )
            if movement >= 0.01 {
                selected.append(frame)
            }
        }
        return selected
    }

    // MARK: - 体素滤波（降采样）

    /// 体素网格降采样 - 保留每个体素中心点
    func voxelDownsample(points: [FusedPoint], voxelSize: Float) -> [FusedPoint] {
        guard !points.isEmpty else { return [] }

        // 建立体素网格
        var voxelMap: [String: [FusedPoint]] = [:]

        for point in points {
            let key = voxelKey(point.pos, voxelSize: voxelSize)
            voxelMap[key, default: []].append(point)
        }

        // 每个体素只保留一个点（中心点 or 第一个点）
        var downsampled: [FusedPoint] = []
        for (_, pointsInVoxel) in voxelMap {
            // 使用颜色加权平均的位置
            let avgPosition = averagePosition(pointsInVoxel)
            let avgColor = averageColor(pointsInVoxel)
            downsampled.append(FusedPoint(
                pos: avgPosition,
                r: avgColor.x,
                g: avgColor.y,
                b: avgColor.z
            ))
        }

        return downsampled
    }

    /// 生成体素键值
    private func voxelKey(_ pos: SIMD3<Float>, voxelSize: Float) -> String {
        let safeVoxelSize = max(voxelSize, 0.001)
        let inv = 1.0 / safeVoxelSize
        let x = Int(floor(pos.x * inv))
        let y = Int(floor(pos.y * inv))
        let z = Int(floor(pos.z * inv))
        return "\(x)_\(y)_\(z)"
    }

    /// 计算平均位置
    private func averagePosition(_ points: [FusedPoint]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        var sum = SIMD3<Float>(0, 0, 0)
        for p in points {
            sum += p.pos
        }
        return sum / Float(points.count)
    }

    /// 计算平均颜色
    private func averageColor(_ points: [FusedPoint]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        var sum = SIMD3<Float>(0, 0, 0)
        for p in points {
            sum += SIMD3<Float>(p.r, p.g, p.b)
        }
        return sum / Float(points.count)
    }

    // MARK: - 点云对齐（基于位姿）

    /// 将点云从世界坐标转换到统一参考系
    func alignPointsToReference(
        _ points: [FusedPoint],
        fromTransform: simd_float4x4,
        toTransform: simd_float4x4
    ) -> [FusedPoint] {
        // 计算相对变换
        let toWorld = toTransform.inverse
        let relativeTransform = toWorld * fromTransform

        // 转换每个点
        return points.map { point in
            let transformedPos = transformPoint(point.pos, by: relativeTransform)
            return FusedPoint(
                pos: transformedPos,
                r: point.r,
                g: point.g,
                b: point.b
            )
        }
    }

    /// 变换点坐标
    private func transformPoint(_ point: SIMD3<Float>, by transform: simd_float4x4) -> SIMD3<Float> {
        let p = SIMD4<Float>(point.x, point.y, point.z, 1)
        let transformed = transform * p
        return SIMD3<Float>(transformed.x, transformed.y, transformed.z)
    }

    // MARK: - 融合多帧

    /// 执行多帧融合
    func fuse() -> FusedPointCloud {
        // 1. 选择高质量帧
        let selectedFrames = selectHighQualityFrames()

        guard !selectedFrames.isEmpty else {
            return FusedPointCloud(points: [], frameCount: 0, rejectedFrames: frames.count)
        }

        guard let referenceFrame = selectedFrames.first else {
            return FusedPointCloud(points: [], frameCount: 0, rejectedFrames: frames.count)
        }

        // 3. 对齐所有帧到参考帧
        var allPoints: [FusedPoint] = []

        for frame in selectedFrames {
            let alignedPoints: [FusedPoint]
            if frame.transform == referenceFrame.transform {
                alignedPoints = frame.points
            } else {
                alignedPoints = alignPointsToReference(
                    frame.points,
                    fromTransform: frame.transform,
                    toTransform: referenceFrame.transform
                )
            }
            allPoints.append(contentsOf: alignedPoints)
        }

        // 4. 体素滤波去重
        let fusedPoints = voxelDownsample(points: allPoints, voxelSize: voxelSize)

        // 5. 可选：统计离群点移除
        let cleanedPoints = statisticalOutlierRemoval(points: fusedPoints, k: 10, stdDev: 2.0)

        return FusedPointCloud(
            points: cleanedPoints,
            frameCount: selectedFrames.count,
            rejectedFrames: frames.count - selectedFrames.count
        )
    }

    // MARK: - 统计离群点移除

    /// 移除孤立的离群点
    private func statisticalOutlierRemoval(points: [FusedPoint], k: Int, stdDev: Float) -> [FusedPoint] {
        guard points.count > k else { return points }

        // 限制处理规模：超过 50000 点时随机采样计算阈值，再应用到全部点
        let maxSampleCount = 50000
        let sampleIndices: [Int]
        if points.count > maxSampleCount {
            sampleIndices = Array(Array(0..<points.count).shuffled().prefix(maxSampleCount))
        } else {
            sampleIndices = Array(0..<points.count)
        }

        // 用采样点构建简易 KD-Tree 加速 kNN
        let samplePositions = sampleIndices.map { points[$0].pos }
        let kdtree = SimpleKDTree(points: samplePositions)

        var meanDists: [(index: Int, meanDist: Float)] = []
        for i in sampleIndices {
            let neighbors = kdtree.kNearest(center: points[i].pos, k: k)
            let meanDist = neighbors.reduce(0.0) { $0 + $1.distance } / Float(max(neighbors.count, 1))
            meanDists.append((i, meanDist))
        }

        let allDists = meanDists.map { $0.meanDist }
        guard !allDists.isEmpty else { return points }
        let mean = allDists.reduce(0, +) / Float(allDists.count)
        let variance = allDists.map { ($0 - mean) * ($0 - mean) }.reduce(0, +) / Float(allDists.count)
        let std = sqrt(variance)

        let threshold = mean + stdDev * std
        let outlierIndices = Set(meanDists.filter { $0.meanDist > threshold }.map { $0.index })
        return points.enumerated().filter { !outlierIndices.contains($0.offset) }.map { $0.element }
    }

    // MARK: - 重置

    /// 清空所有帧数据
    func reset() {
        frames.removeAll()
        lastTransform = nil
    }

    /// 获取当前帧数
    var frameCount: Int { frames.count }
}

// MARK: - Simple KD-Tree for kNN

private struct SimpleKDTree {
    struct Node {
        let point: SIMD3<Float>
        let index: Int
        let axis: Int
        let left: Int?
        let right: Int?
    }

    struct Neighbor {
        let index: Int
        let distance: Float
    }

    private var nodes: [Node] = []

    init(points: [SIMD3<Float>]) {
        guard !points.isEmpty else { return }
        var indices = Array(points.indices)
        _ = build(points: points, indices: &indices, depth: 0, range: 0..<points.count)
    }

    private mutating func build(points: [SIMD3<Float>], indices: inout [Int], depth: Int, range: Range<Int>) -> Int? {
        guard range.lowerBound < range.upperBound else { return nil }
        let axis = depth % 3
        indices[range].sort { points[$0][axis] < points[$1][axis] }
        let mid = (range.lowerBound + range.upperBound) / 2
        let left = build(points: points, indices: &indices, depth: depth + 1, range: range.lowerBound..<mid)
        let right = build(points: points, indices: &indices, depth: depth + 1, range: mid + 1..<range.upperBound)
        nodes.append(Node(point: points[indices[mid]], index: indices[mid], axis: axis, left: left, right: right))
        return nodes.count - 1
    }

    func kNearest(center: SIMD3<Float>, k: Int) -> [Neighbor] {
        var heap: [Neighbor] = []
        search(nodeIdx: nodes.count - 1, center: center, k: k, heap: &heap)
        return heap
    }

    private func search(nodeIdx: Int?, center: SIMD3<Float>, k: Int, heap: inout [Neighbor]) {
        guard let idx = nodeIdx, idx < nodes.count else { return }
        let node = nodes[idx]
        let dist = simd_distance(node.point, center)

        if heap.count < k {
            heap.append(Neighbor(index: node.index, distance: dist))
            heap.sort { $0.distance > $1.distance }
        } else if dist < heap[0].distance {
            heap[0] = Neighbor(index: node.index, distance: dist)
            heap.sort { $0.distance > $1.distance }
        }

        let diff = center[node.axis] - node.point[node.axis]
        let (first, second) = diff <= 0 ? (node.left, node.right) : (node.right, node.left)
        search(nodeIdx: first, center: center, k: k, heap: &heap)
        if heap.count < k || abs(diff) < heap[0].distance {
            search(nodeIdx: second, center: center, k: k, heap: &heap)
        }
    }
}

// MARK: - 便捷扩展

extension PointCloudFusion {
    /// 快速融合（用于导出时）
    /// - Parameters:
    ///   - points: 点云
    ///   - transform: AR 位姿
    ///   - trackingQuality: 追踪质量
    /// - Returns: 融合后的点云
    static func quickFusion(
        points: [FusedPoint],
        transform: simd_float4x4,
        trackingQuality: TrackingQuality
    ) -> [FusedPoint] {
        let fusion = PointCloudFusion()
        fusion.addFrame(
            points: points,
            transform: transform,
            timestamp: Date().timeIntervalSince1970,
            trackingQuality: trackingQuality
        )

        // 如果有多帧，融合它们
        if fusion.frameCount > 1 {
            let result = fusion.fuse()
            return result.points
        }

        // 单帧，只做简单的体素滤波
        return fusion.voxelDownsample(points: points, voxelSize: 0.005)
    }
}
