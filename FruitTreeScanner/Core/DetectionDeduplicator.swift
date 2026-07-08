// DetectionDeduplicator.swift
// 2D 边界框去重 + 3D 空间去重，消除同一果实的重复计数

import Foundation
import CoreGraphics
@preconcurrency import CoreVideo
import simd

// MARK: - 2D IoU 去重

struct DetectionDeduplicator {
    private enum DetectionSpatialRelationship {
        case unavailable
        case associated
        case separated
    }

    private struct StableDetectionTrack {
        var representative: DetectedFruit
        var observations: [DetectedFruit]
        var observationCount: Int
        var firstTimestamp: TimeInterval
        var lastTimestamp: TimeInterval

        init(seed: DetectedFruit) {
            representative = seed
            observations = [seed]
            observationCount = 1
            firstTimestamp = seed.timestamp
            lastTimestamp = seed.timestamp
        }

        mutating func add(_ detection: DetectedFruit) {
            observations.append(detection)
            observationCount += 1
            firstTimestamp = min(firstTimestamp, detection.timestamp)
            lastTimestamp = max(lastTimestamp, detection.timestamp)
            if detection.confidence > representative.confidence {
                representative = detection
            }
        }

        var duration: TimeInterval {
            lastTimestamp - firstTimestamp
        }

        func canAccept(
            _ detection: DetectedFruit,
            maxGap: TimeInterval,
            centerDistanceThreshold: CGFloat,
            projectedPositions: inout [UUID: SIMD3<Float>]
        ) -> Bool {
            guard representative.category == detection.category else { return false }
            guard abs(detection.timestamp - lastTimestamp) <= maxGap else { return false }
            switch DetectionDeduplicator.spatialRelationshipIn3D(
                representative,
                detection,
                projectedPositions: &projectedPositions
            ) {
            case .separated:
                return false
            case .associated:
                return true
            case .unavailable:
                break
            }
            return normalizedCenterDistance(representative.boundingBox, detection.boundingBox) <= centerDistanceThreshold &&
                areaSimilarity(representative.boundingBox, detection.boundingBox) >= 0.45
        }
    }

    static func stableDetections(
        _ detections: [DetectedFruit],
        minimumObservations: Int = 2,
        minimumConfidence: Float = 0.85,
        timeWindow: TimeInterval = 3.5,
        centerDistanceThreshold: CGFloat = 0.16,
        minimumDuration: TimeInterval = 0.35
    ) -> [DetectedFruit] {
        stableTracks(
            detections,
            minimumObservations: minimumObservations,
            minimumConfidence: minimumConfidence,
            timeWindow: timeWindow,
            centerDistanceThreshold: centerDistanceThreshold,
            minimumDuration: minimumDuration,
            recentOnly: false
        ).map(\.representative)
    }

    static func stableEvidenceDetections(
        _ detections: [DetectedFruit],
        minimumObservations: Int = 2,
        minimumConfidence: Float = 0.85,
        timeWindow: TimeInterval = 3.5,
        centerDistanceThreshold: CGFloat = 0.16,
        minimumDuration: TimeInterval = 0.35,
        recentOnly: Bool = false
    ) -> [DetectedFruit] {
        stableTracks(
            detections,
            minimumObservations: minimumObservations,
            minimumConfidence: minimumConfidence,
            timeWindow: timeWindow,
            centerDistanceThreshold: centerDistanceThreshold,
            minimumDuration: minimumDuration,
            recentOnly: recentOnly
        ).flatMap(\.observations)
    }

    private static func stableTracks(
        _ detections: [DetectedFruit],
        minimumObservations: Int,
        minimumConfidence: Float,
        timeWindow: TimeInterval,
        centerDistanceThreshold: CGFloat,
        minimumDuration: TimeInterval,
        recentOnly: Bool
    ) -> [StableDetectionTrack] {
        guard !detections.isEmpty else { return [] }
        let requiredObservations = max(minimumObservations, 1)
        let latestTimestamp = detections.map(\.timestamp).max() ?? 0
        let recentDetections = detections
            .filter { detection in
                detection.confidence >= minimumConfidence && (
                    !recentOnly || latestTimestamp - detection.timestamp <= timeWindow
                )
            }
            .sorted { $0.timestamp < $1.timestamp }

        if requiredObservations == 1 {
            return recentDetections.map(StableDetectionTrack.init(seed:))
        }

        var tracks: [StableDetectionTrack] = []
        var projectedPositions: [UUID: SIMD3<Float>] = [:]
        for detection in recentDetections {
            if let trackIndex = tracks.firstIndex(where: { track in
                track.canAccept(
                    detection,
                    maxGap: timeWindow,
                    centerDistanceThreshold: centerDistanceThreshold,
                    projectedPositions: &projectedPositions
                )
            }) {
                tracks[trackIndex].add(detection)
            } else {
                tracks.append(StableDetectionTrack(seed: detection))
            }
        }

        return tracks.filter { track in
            track.observationCount >= requiredObservations &&
                track.duration >= minimumDuration
        }
    }

    static func stableTrackCount(
        _ detections: [DetectedFruit],
        minimumObservations: Int = 2,
        minimumConfidence: Float = 0.85,
        timeWindow: TimeInterval = 3.5
    ) -> Int {
        stableTracks(
            detections,
            minimumObservations: minimumObservations,
            minimumConfidence: minimumConfidence,
            timeWindow: timeWindow,
            centerDistanceThreshold: 0.16,
            minimumDuration: 0.35,
            recentOnly: true
        ).count
    }

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
        var projectedPositions: [UUID: SIMD3<Float>] = [:]

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
                    timeWindow: timeWindow,
                    projectedPositions: &projectedPositions
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
        timeWindow: TimeInterval,
        projectedPositions: inout [UUID: SIMD3<Float>]
    ) -> Bool {
        let timeDelta = abs(candidate.timestamp - kept.timestamp)
        // Normalized image coordinates are only comparable while the camera is
        // observing nearly the same view. Across a whole walk-around scan, two
        // distinct fruits can occupy the same 2D box at different times.
        guard timeDelta <= timeWindow else {
            return false
        }

        switch spatialRelationshipIn3D(candidate, kept, projectedPositions: &projectedPositions) {
        case .separated:
            return false
        case .associated:
            return true
        case .unavailable:
            break
        }

        let iou = computeIoU(kept.boundingBox, candidate.boundingBox)
        if iou > iouThreshold {
            return true
        }

        guard timeDelta > 0.03, timeDelta <= timeWindow else {
            return false
        }

        let centerDistance = normalizedCenterDistance(kept.boundingBox, candidate.boundingBox)
        guard centerDistance < centerDistanceThreshold else {
            return false
        }

        return areaSimilarity(kept.boundingBox, candidate.boundingBox) >= 0.45
    }

    private static func spatialRelationshipIn3D(
        _ lhs: DetectedFruit,
        _ rhs: DetectedFruit,
        projectedPositions: inout [UUID: SIMD3<Float>]
    ) -> DetectionSpatialRelationship {
        guard let lhsPosition = projectedWorldPosition(for: lhs, cache: &projectedPositions),
              let rhsPosition = projectedWorldPosition(for: rhs, cache: &projectedPositions) else {
            return .unavailable
        }

        let maxExpectedDiameter = max(lhs.category.sizeRange.upperBound, rhs.category.sizeRange.upperBound)
        let distance = simd_distance(lhsPosition, rhsPosition)
        let associationThreshold = max(0.04, min(maxExpectedDiameter * 0.75, 0.085))
        if distance <= associationThreshold {
            return .associated
        }

        let separationThreshold = max(0.06, min(maxExpectedDiameter * 1.2, 0.16))
        if distance > separationThreshold {
            return .separated
        }
        return .unavailable
    }

    private static func projectedWorldPosition(
        for detection: DetectedFruit,
        cache: inout [UUID: SIMD3<Float>]
    ) -> SIMD3<Float>? {
        if let cached = cache[detection.id] {
            return cached
        }

        guard let depthMap = detection.depthMap,
              let cameraIntrinsics = detection.cameraIntrinsics,
              let cameraTransform = detection.cameraTransform,
              let imageSize = detection.imageSize else {
            return nil
        }

        guard let depth = robustDetectionDepth(
            for: detection,
            depthMap: depthMap,
            imageSize: imageSize
        ) else {
            return nil
        }

        let normCenterX = detection.boundingBox.midX
        let normCenterY = detection.boundingBox.midY
        let centerX = normCenterX * imageSize.width
        let centerY = (1 - normCenterY) * imageSize.height
        let imagePoint = SIMD3<Float>(Float(centerX), Float(centerY), 1.0)
        guard let cameraPoint = FusionValidator.cameraPointFromImagePoint(
            imagePoint,
            depth: depth,
            cameraIntrinsics: cameraIntrinsics
        ) else {
            return nil
        }

        let worldPoint = cameraTransform * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1.0)
        let position = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else {
            return nil
        }
        cache[detection.id] = position
        return position
    }

    private static func robustDetectionDepth(
        for detection: DetectedFruit,
        depthMap: CVPixelBuffer,
        imageSize: CGSize
    ) -> Float? {
        guard imageSize.width > 0,
              imageSize.height > 0,
              let depthSampler = DetectionDepthSampler(depthMap: depthMap) else {
            return nil
        }

        let sampleGrid = 9
        var validDepths: [Float] = []
        validDepths.reserveCapacity(sampleGrid * sampleGrid)
        for row in 0..<sampleGrid {
            for col in 0..<sampleGrid {
                let normalizedPoint = CGPoint(
                    x: detection.boundingBox.origin.x + detection.boundingBox.width * (CGFloat(col) + 0.5) / CGFloat(sampleGrid),
                    y: detection.boundingBox.origin.y + detection.boundingBox.height * (CGFloat(row) + 0.5) / CGFloat(sampleGrid)
                )
                let depthPoint = FusionValidator.depthSamplePoint(
                    normalizedPoint: normalizedPoint,
                    imageSize: imageSize,
                    depthSize: CGSize(width: depthSampler.width, height: depthSampler.height)
                )
                if let depth = depthSampler.depth(x: Int(depthPoint.x), y: Int(depthPoint.y)) {
                    validDepths.append(depth)
                }
            }
        }

        return FusionValidator.robustDepth(from: validDepths)
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

    private final class DetectionDepthSampler {
        let width: Int
        let height: Int

        private let depthMap: CVPixelBuffer
        private let baseAddress: UnsafeMutableRawPointer
        private let pixelFormat: FourCharCode

        init?(depthMap: CVPixelBuffer) {
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
                return nil
            }

            self.depthMap = depthMap
            self.baseAddress = baseAddress
            self.width = CVPixelBufferGetWidth(depthMap)
            self.height = CVPixelBufferGetHeight(depthMap)
            self.pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        }

        deinit {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        func depth(x: Int, y: Int) -> Float? {
            guard width > 0, height > 0 else { return nil }

            let clampedX = max(0, min(x, width - 1))
            let clampedY = max(0, min(y, height - 1))
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let fp32: FourCharCode = 0x66703233
            let up16: FourCharCode = 0x75703136
            let depth: Float

            if pixelFormat == fp32 ||
                pixelFormat == kCVPixelFormatType_DepthFloat32 ||
                pixelFormat == kCVPixelFormatType_OneComponent32Float {
                let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
                let rowFloats = bytesPerRow / MemoryLayout<Float>.size
                depth = floatBuffer[clampedY * rowFloats + clampedX]
            } else if pixelFormat == kCVPixelFormatType_DepthFloat16 ||
                pixelFormat == kCVPixelFormatType_OneComponent16Half {
                let halfBuffer = baseAddress.assumingMemoryBound(to: UInt16.self)
                let rowHalfs = bytesPerRow / MemoryLayout<UInt16>.size
                depth = Float(Float16(bitPattern: halfBuffer[clampedY * rowHalfs + clampedX]))
            } else if pixelFormat == up16 {
                let shortBuffer = baseAddress.assumingMemoryBound(to: UInt16.self)
                let rowShorts = bytesPerRow / MemoryLayout<UInt16>.size
                depth = Float(shortBuffer[clampedY * rowShorts + clampedX]) / 1000.0
            } else {
                return nil
            }

            guard depth > 0.1, depth < 10.0 else { return nil }
            return depth
        }
    }
}

// MARK: - Detection retention

enum DetectionRetentionPolicy {
    /// Keep a generous window of image-detection frames so long scans cannot
    /// retain an unbounded number of copied depth maps. Point-cloud capture is
    /// unaffected; this only bounds RGB/depth evidence held for fusion.
    static let defaultMaxFrameCount = 360

    static func trimmedByFrameLimit(
        _ detections: [DetectedFruit],
        maxFrameCount: Int = defaultMaxFrameCount
    ) -> [DetectedFruit] {
        guard maxFrameCount > 0 else { return [] }
        let frameTimestamps = Array(Set(detections.map(\.timestamp))).sorted()
        guard frameTimestamps.count > maxFrameCount else { return detections }

        let retainedTimestamps = Set(frameTimestamps.suffix(maxFrameCount))
        return detections.filter { retainedTimestamps.contains($0.timestamp) }
    }
}

// MARK: - 3D 空间去重

extension ValidatedFruit {

    private struct FruitTrack {
        var representative: ValidatedFruit
        var totalWeight: Float
        var weightedPosition: SIMD3<Float>
        var observationCount: Int
        var imageObservationCount: Int
        var accumulatedEvidence: Float

        init(seed: ValidatedFruit) {
            let weight = Self.weight(for: seed)
            representative = seed
            totalWeight = weight
            weightedPosition = seed.position * weight
            observationCount = 1
            imageObservationCount = seed.source.isImageBased ? 1 : 0
            accumulatedEvidence = Self.evidence(for: seed)
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
            if fruit.source.isImageBased {
                imageObservationCount += 1
            }
            accumulatedEvidence = Self.combinedEvidence(accumulatedEvidence, Self.evidence(for: fruit))

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
                confidence: min(max(representative.confidence, accumulatedEvidence), 1.0),
                source: mergedSource
            )
        }

        private var mergedSource: ValidationSource {
            if representative.source == .fused {
                return .fused
            }
            if imageObservationCount >= 2 {
                return .trackedImage
            }
            return representative.source
        }

        var isUnfusedImageTrack: Bool {
            imageObservationCount > 0 && representative.source != .fused
        }

        static func weight(for fruit: ValidatedFruit) -> Float {
            max(fruit.confidence, 0.05) * fruit.source.countWeight
        }

        static func rank(_ fruit: ValidatedFruit) -> Float {
            fruit.source.countWeight * 2 + fruit.confidence
        }

        static func evidence(for fruit: ValidatedFruit) -> Float {
            min(max(fruit.confidence, 0), 1) * fruit.source.countWeight
        }

        static func combinedEvidence(_ lhs: Float, _ rhs: Float) -> Float {
            1 - (1 - min(max(lhs, 0), 1)) * (1 - min(max(rhs, 0), 1))
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
            let compatibleTrackIndices = tracks.indices.filter { index in
                let category = tracks[index].representative.category
                return category == nil || fruit.category == nil || category == fruit.category
            }

            if let trackIndex = compatibleTrackIndices.min(by: { lhs, rhs in
                simd_distance(tracks[lhs].center, fruit.position) < simd_distance(tracks[rhs].center, fruit.position)
            }) {
                let track = tracks[trackIndex]
                let distance = simd_distance(track.center, fruit.position)
                let threshold = associationThreshold(
                    for: fruit,
                    with: track,
                    override: distanceThreshold
                )

                if distance < threshold {
                    tracks[trackIndex].add(fruit)
                    continue
                }
            }

            tracks.append(FruitTrack(seed: fruit))
        }

        return tracks.map { $0.mergedFruit() }
    }

    private static func associationThreshold(
        for fruit: ValidatedFruit,
        with track: FruitTrack,
        override: Float?
    ) -> Float {
        if let override {
            return override
        }

        let category = fruit.category ?? track.representative.category
        let upperDiameter = category?.sizeRange.upperBound ?? 0.10
        let baseThreshold = upperDiameter / 2

        guard fruit.source.isImageBased,
              fruit.source != .fused,
              track.isUnfusedImageTrack else {
            return baseThreshold
        }

        let confidence = min(max(min(fruit.confidence, track.representative.confidence), 0), 1)
        let confidenceScale = 0.55 + confidence * 0.25
        let driftTolerance = min(upperDiameter * confidenceScale, 0.085)
        return max(baseThreshold, driftTolerance)
    }
}
