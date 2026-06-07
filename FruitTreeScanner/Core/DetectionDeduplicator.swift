// DetectionDeduplicator.swift
// 2D 边界框去重 + 3D 空间去重，消除同一果实的重复计数

import Foundation
import CoreGraphics
import simd

// MARK: - 2D IoU 去重

struct DetectionDeduplicator {

    /// 基于 2D 边界框 IoU 去重
    /// 同一果实在连续帧中会被反复检测，边界框高度重叠 → 保留高置信度
    static func deduplicate2D(
        _ detections: [DetectedFruit],
        iouThreshold: Float = 0.5,
        centerDistanceThreshold: CGFloat = 0.16,
        timeWindow: TimeInterval = 2.0
    ) -> [DetectedFruit] {
        guard !detections.isEmpty else { return [] }

        // 按置信度降序排列
        let sorted = detections.sorted { $0.confidence > $1.confidence }
        var kept: [DetectedFruit] = []
        var suppressed = Set<Int>()

        for i in sorted.indices {
            if suppressed.contains(i) { continue }
            kept.append(sorted[i])

            for j in (i + 1)..<sorted.count where !suppressed.contains(j) {
                // 同类别 + 同一帧强重叠，或连续帧中心位置接近 → 抑制低置信度。
                // 连续扫描时手机会移动，单靠 IoU 会漏掉同一果实的重复检测。
                guard sorted[i].category == sorted[j].category else { continue }
                if shouldSuppress(
                    sorted[j],
                    becauseOf: sorted[i],
                    iouThreshold: iouThreshold,
                    centerDistanceThreshold: centerDistanceThreshold,
                    timeWindow: timeWindow
                ) {
                    suppressed.insert(j)
                }
            }
        }

        return kept
    }

    /// 计算两个边界框的 IoU
    static func computeIoU(_ a: CGRect, _ b: CGRect) -> Float {
        let intersection = a.intersection(b)
        guard !intersection.isNull else { return 0 }
        let intersectionArea = intersection.width * intersection.height
        let unionArea = a.width * a.height + b.width * b.height - intersectionArea
        guard unionArea > 0 else { return 0 }
        return Float(intersectionArea / unionArea)
    }

    private static func shouldSuppress(
        _ candidate: DetectedFruit,
        becauseOf kept: DetectedFruit,
        iouThreshold: Float,
        centerDistanceThreshold: CGFloat,
        timeWindow: TimeInterval
    ) -> Bool {
        let iou = computeIoU(kept.boundingBox, candidate.boundingBox)
        if iou > iouThreshold {
            return true
        }

        let timeDelta = abs(candidate.timestamp - kept.timestamp)
        guard timeDelta > 0.03, timeDelta <= timeWindow else {
            return false
        }

        let centerDistance = normalizedCenterDistance(kept.boundingBox, candidate.boundingBox)
        guard centerDistance < centerDistanceThreshold else {
            return false
        }

        return areaSimilarity(kept.boundingBox, candidate.boundingBox) >= 0.45
    }

    private static func normalizedCenterDistance(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let ac = CGPoint(x: a.midX, y: a.midY)
        let bc = CGPoint(x: b.midX, y: b.midY)
        let dx = ac.x - bc.x
        let dy = ac.y - bc.y
        return sqrt(dx * dx + dy * dy)
    }

    private static func areaSimilarity(_ a: CGRect, _ b: CGRect) -> CGFloat {
        let areaA = max(a.width * a.height, 0)
        let areaB = max(b.width * b.height, 0)
        let larger = max(areaA, areaB)
        guard larger > 0 else { return 0 }
        return min(areaA, areaB) / larger
    }
}

// MARK: - 3D 空间去重

extension ValidatedFruit {

    private struct FruitTrack {
        var representative: ValidatedFruit
        var totalWeight: Float
        var weightedPosition: SIMD3<Float>
        var observationCount: Int

        init(seed: ValidatedFruit) {
            let weight = Self.weight(for: seed)
            representative = seed
            totalWeight = weight
            weightedPosition = seed.position * weight
            observationCount = 1
        }

        var center: SIMD3<Float> {
            guard totalWeight > 0 else { return representative.position }
            return weightedPosition / totalWeight
        }

        mutating func add(_ fruit: ValidatedFruit) {
            let weight = Self.weight(for: fruit)
            weightedPosition += fruit.position * weight
            totalWeight += weight
            observationCount += 1

            if Self.rank(fruit) > Self.rank(representative) ||
                (Self.rank(fruit) == Self.rank(representative) && fruit.confidence > representative.confidence) {
                representative = fruit
            }
        }

        func mergedFruit() -> ValidatedFruit {
            ValidatedFruit(
                id: representative.id,
                category: representative.category,
                position: center,
                confidence: min(max(representative.confidence, Float(observationCount) * 0.15), 1.0),
                source: representative.source
            )
        }

        static func weight(for fruit: ValidatedFruit) -> Float {
            max(fruit.confidence, 0.05) * fruit.source.countWeight
        }

        static func rank(_ fruit: ValidatedFruit) -> Float {
            fruit.source.countWeight * 2 + fruit.confidence
        }
    }

    /// 融合验证后，对 3D 位置做空间聚类去重
    /// 同一果实可能被多帧检测到，投影到 3D 后位置接近
    /// 距离阈值与果实尺寸挂钩：取类别半径，避免大果实被错误去重
    static func deduplicate3D(_ fruits: [ValidatedFruit], distanceThreshold: Float? = nil) -> [ValidatedFruit] {
        guard !fruits.isEmpty else { return [] }

        let sorted = fruits.sorted {
            FruitTrack.rank($0) > FruitTrack.rank($1)
        }
        var tracks: [FruitTrack] = []

        for fruit in sorted {
            let threshold = distanceThreshold ?? (fruit.category?.sizeRange.upperBound ?? 0.10) / 2

            let compatibleTrackIndices = tracks.indices.filter { index in
                let category = tracks[index].representative.category
                return category == nil || fruit.category == nil || category == fruit.category
            }

            if let trackIndex = compatibleTrackIndices.min(by: { lhs, rhs in
                simd_distance(tracks[lhs].center, fruit.position) < simd_distance(tracks[rhs].center, fruit.position)
            }) {
                let track = tracks[trackIndex]
                let distance = simd_distance(track.center, fruit.position)

                if distance < threshold {
                    tracks[trackIndex].add(fruit)
                    continue
                }
            }

            tracks.append(FruitTrack(seed: fruit))
        }

        return tracks.map { $0.mergedFruit() }
    }
}
