// FusionValidatorProjection.swift
// 2D detection projection and depth sampling helpers for fusion validation.

import CoreGraphics
@preconcurrency import CoreVideo
import simd

extension FusionValidator {
    static func robustDepth(from rawDepths: [Float]) -> Float? {
        let depths = rawDepths
            .filter { $0.isFinite && $0 > 0.1 && $0 < 10.0 }
            .sorted()
        guard !depths.isEmpty else { return nil }

        let globalMedian = median(depths)
        let maxClusterGap = max(0.12, globalMedian * 0.06)
        var clusters: [[Float]] = []
        var current: [Float] = []

        for depth in depths {
            if let last = current.last, depth - last > maxClusterGap {
                clusters.append(current)
                current = [depth]
            } else {
                current.append(depth)
            }
        }
        if !current.isEmpty {
            clusters.append(current)
        }

        let minimumForegroundSupport = max(3, Int(ceil(Float(depths.count) * 0.10)))
        let foregroundCluster = clusters.first { $0.count >= minimumForegroundSupport }
            ?? clusters.max { lhs, rhs in
                if lhs.count == rhs.count {
                    return median(lhs) > median(rhs)
                }
                return lhs.count < rhs.count
            }

        guard let foregroundCluster, !foregroundCluster.isEmpty else {
            return globalMedian
        }
        return median(foregroundCluster)
    }

    static func projectWorldPointToNormalizedImage(
        _ worldPoint: SIMD3<Float>,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> CGPoint? {
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let cameraPoint4 = cameraTransform.inverse * SIMD4<Float>(
            worldPoint.x,
            worldPoint.y,
            worldPoint.z,
            1.0
        )
        let cameraPoint = SIMD3<Float>(cameraPoint4.x, cameraPoint4.y, cameraPoint4.z)
        guard cameraPoint.z > 0.05,
              cameraPoint.x.isFinite,
              cameraPoint.y.isFinite,
              cameraPoint.z.isFinite else {
            return nil
        }

        let fx = cameraIntrinsics[0][0]
        let fy = cameraIntrinsics[1][1]
        let cx = cameraIntrinsics[2][0]
        let cy = cameraIntrinsics[2][1]
        guard fx.isFinite, fy.isFinite, cx.isFinite, cy.isFinite,
              abs(fx) > 1e-6, abs(fy) > 1e-6 else {
            return nil
        }

        let imageX = (fx * cameraPoint.x / cameraPoint.z) + cx
        let imageY = (fy * cameraPoint.y / cameraPoint.z) + cy
        let normalizedX = CGFloat(imageX) / imageSize.width
        let normalizedY = 1.0 - CGFloat(imageY) / imageSize.height

        guard normalizedX.isFinite, normalizedY.isFinite else { return nil }
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    static func depthSamplePoint(
        normalizedPoint: CGPoint,
        imageSize: CGSize,
        depthSize: CGSize
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0,
              depthSize.width > 0, depthSize.height > 0 else {
            return .zero
        }

        let imagePoint = CGPoint(
            x: normalizedPoint.x * imageSize.width,
            y: (1 - normalizedPoint.y) * imageSize.height
        )

        return CGPoint(
            x: imagePoint.x * depthSize.width / imageSize.width,
            y: imagePoint.y * depthSize.height / imageSize.height
        )
    }

    static func cameraPointFromImagePoint(
        _ imagePoint: SIMD3<Float>,
        depth: Float,
        cameraIntrinsics: matrix_float3x3
    ) -> SIMD3<Float>? {
        guard depth.isFinite, depth > 0.1 else { return nil }

        let ray = cameraIntrinsics.inverse * imagePoint
        guard ray.x.isFinite,
              ray.y.isFinite,
              ray.z.isFinite,
              abs(ray.z) > 1e-6 else {
            return nil
        }

        let cameraPoint = ray * (depth / ray.z)
        guard cameraPoint.x.isFinite,
              cameraPoint.y.isFinite,
              cameraPoint.z.isFinite,
              cameraPoint.z > 0 else {
            return nil
        }
        return cameraPoint
    }

    func projectDetectionTo3D(
        detection: DetectedFruit,
        depthMap: CVPixelBuffer?,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> SIMD3<Float> {
        projectDetectionTo3D(
            detection: detection,
            depthMap: depthMap,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize,
            fallbackDepth: 2.0
        ) ?? SIMD3<Float>(0, 0, 2)
    }

    func projectDetectionTo3DWithValidDepth(
        detection: DetectedFruit,
        depthMap: CVPixelBuffer?,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> SIMD3<Float>? {
        projectDetectionTo3D(
            detection: detection,
            depthMap: depthMap,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize,
            fallbackDepth: nil
        )
    }

    private func projectDetectionTo3D(
        detection: DetectedFruit,
        depthMap: CVPixelBuffer?,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize,
        fallbackDepth: Float?
    ) -> SIMD3<Float>? {
        let box = detection.boundingBox

        // A 9x9 grid plus foreground-cluster selection follows the same idea as
        // frustum-based fruit localization: keep the near, coherent depth
        // surface inside the 2D detection instead of letting background leaves
        // dominate a simple center or whole-box median.
        var validDepths: [Float] = []
        if let depthMap = depthMap, let depthSampler = DepthSampler(depthMap: depthMap) {
            let sampleGrid = 9
            validDepths.reserveCapacity(sampleGrid * sampleGrid)
            for row in 0..<sampleGrid {
                for col in 0..<sampleGrid {
                    let normalizedPoint = CGPoint(
                        x: box.origin.x + box.size.width * (CGFloat(col) + 0.5) / CGFloat(sampleGrid),
                        y: box.origin.y + box.size.height * (CGFloat(row) + 0.5) / CGFloat(sampleGrid)
                    )
                    let depthPoint = Self.depthSamplePoint(
                        normalizedPoint: normalizedPoint,
                        imageSize: imageSize,
                        depthSize: CGSize(width: depthSampler.width, height: depthSampler.height)
                    )

                    if let d = depthSampler.depth(x: Int(depthPoint.x), y: Int(depthPoint.y)) {
                        validDepths.append(d)
                    }
                }
            }
        }

        let depth: Float
        if let robustDepth = Self.robustDepth(from: validDepths) {
            depth = robustDepth
        } else if let fallbackDepth {
            depth = fallbackDepth
        } else {
            return nil
        }

        let normCenterX = box.origin.x + box.size.width / 2
        let normCenterY = box.origin.y + box.size.height / 2
        let centerX = normCenterX * imageSize.width
        let centerY = (1 - normCenterY) * imageSize.height

        let imagePoint = SIMD3<Float>(Float(centerX), Float(centerY), 1.0)
        let cameraPoint = Self.cameraPointFromImagePoint(
            imagePoint,
            depth: depth,
            cameraIntrinsics: cameraIntrinsics
        ) ?? SIMD3<Float>(0, 0, depth)

        let worldPoint = cameraTransform * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1.0)
        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    private static func median(_ sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        let mid = sortedValues.count / 2
        if sortedValues.count % 2 == 0 {
            return (sortedValues[mid - 1] + sortedValues[mid]) / 2
        }
        return sortedValues[mid]
    }
}

enum DetectionDepthCandidateBuilder {
    private static let roiSampleGrid = 9

    private struct DepthWorldSample {
        let row: Int
        let col: Int
        let worldPoint: SIMD3<Float>
    }

    static func makeCandidates(
        from detections: [DetectedFruit],
        clusterConfig: ClusterConfig
    ) -> [FruitCandidate] {
        detections.compactMap { detection in
            makeCandidate(from: detection, clusterConfig: clusterConfig)
        }
    }

    private static func makeCandidate(
        from detection: DetectedFruit,
        clusterConfig: ClusterConfig
    ) -> FruitCandidate? {
        guard let depthMap = detection.depthMap,
              let cameraIntrinsics = detection.cameraIntrinsics,
              let cameraTransform = detection.cameraTransform,
              let imageSize = detection.imageSize,
              let depthSampler = DepthSampler(depthMap: depthMap),
              imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }

        var samples: [(point: CGPoint, depth: Float, row: Int, col: Int)] = []
        samples.reserveCapacity(roiSampleGrid * roiSampleGrid)

        for row in 0..<roiSampleGrid {
            for col in 0..<roiSampleGrid {
                let normalizedPoint = CGPoint(
                    x: detection.boundingBox.origin.x + detection.boundingBox.width * (CGFloat(col) + 0.5) / CGFloat(roiSampleGrid),
                    y: detection.boundingBox.origin.y + detection.boundingBox.height * (CGFloat(row) + 0.5) / CGFloat(roiSampleGrid)
                )
                let depthPoint = FusionValidator.depthSamplePoint(
                    normalizedPoint: normalizedPoint,
                    imageSize: imageSize,
                    depthSize: CGSize(width: depthSampler.width, height: depthSampler.height)
                )
                guard let depth = depthSampler.depth(x: Int(depthPoint.x), y: Int(depthPoint.y)) else {
                    continue
                }
                samples.append((normalizedPoint, depth, row, col))
            }
        }

        guard let foregroundDepth = roiForegroundDepth(from: samples.map { $0.depth }) else {
            return nil
        }

        let foregroundThreshold = max(0.08, foregroundDepth * 0.05)
        let foregroundSamples = samples.filter { abs($0.depth - foregroundDepth) <= foregroundThreshold }
        guard foregroundSamples.count >= max(3, min(clusterConfig.minPoints, 8)) else {
            return nil
        }

        let preliminaryDiameter = estimatedDiameter(
            detection: detection,
            depth: foregroundDepth,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize,
            clusterConfig: clusterConfig
        )

        var worldSamples: [DepthWorldSample] = []
        worldSamples.reserveCapacity(foregroundSamples.count)
        for sample in foregroundSamples {
            if let worldPoint = projectNormalizedImagePointToWorld(
                sample.point,
                depth: sample.depth,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform
            ) {
                worldSamples.append(DepthWorldSample(row: sample.row, col: sample.col, worldPoint: worldPoint))
            }
        }
        let referencePoint = projectNormalizedImagePointToWorld(
            CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY),
            depth: foregroundDepth,
            imageSize: imageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform
        )
        let selectedCluster = selectDominantCluster(
            from: worldSamples,
            referencePoint: referencePoint,
            distanceThreshold: roiClusterDistance(
                diameter: preliminaryDiameter,
                category: detection.category
            )
        )
        let worldPoints = selectedCluster.map(\.worldPoint)
        guard worldPoints.count >= max(3, min(clusterConfig.minPoints, 8)) else {
            return nil
        }
        let shapeQuality = roiClusterShapeQuality(selectedCluster)
        guard shapeQuality >= roiClusterShapeQualityThreshold(for: detection.category) else {
            return nil
        }

        let center = centroid(of: worldPoints)
        let depthSupportRatio = Float(worldPoints.count) / Float(roiSampleGrid * roiSampleGrid)
        let diameter = estimatedDiameter(
            detection: detection,
            depth: foregroundDepth,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize,
            clusterConfig: clusterConfig,
            worldPoints: worldPoints,
            shapeQuality: shapeQuality,
            depthSupportRatio: depthSupportRatio
        )
        guard diameter >= clusterConfig.minDiameter, diameter <= clusterConfig.maxDiameter else {
            return nil
        }

        return FruitCandidate(
            position: center,
            diameter: diameter,
            sphericity: roiCandidateSphericity(shapeQuality: shapeQuality, category: detection.category),
            pointCount: worldPoints.count,
            averageColor: representativeColor(for: detection.category),
            points: worldPoints,
            sourceCategory: detection.category,
            depthSupportRatio: depthSupportRatio
        )
    }

    private static func roiClusterShapeQuality(_ samples: [DepthWorldSample]) -> Float {
        guard samples.count >= 3 else { return 0 }
        let rows = samples.map(\.row)
        let cols = samples.map(\.col)
        guard let minRow = rows.min(), let maxRow = rows.max(),
              let minCol = cols.min(), let maxCol = cols.max() else {
            return 0
        }

        let rowSpan = maxRow - minRow + 1
        let colSpan = maxCol - minCol + 1
        guard rowSpan >= 2, colSpan >= 2 else { return 0 }

        let aspect = Float(min(rowSpan, colSpan)) / Float(max(rowSpan, colSpan))
        let boundingCells = max(rowSpan * colSpan, 1)
        let fillRatio = Float(samples.count) / Float(boundingCells)
        return min(max(aspect * sqrt(min(max(fillRatio, 0), 1)), 0), 1)
    }

    private static func roiForegroundDepth(from rawDepths: [Float]) -> Float? {
        let depths = rawDepths
            .filter { $0.isFinite && $0 > 0.1 && $0 < 10.0 }
            .sorted()
        guard !depths.isEmpty else { return nil }

        let globalMedian = median(of: depths)
        let maxClusterGap = max(0.12, globalMedian * 0.06)
        var clusters: [[Float]] = []
        var current: [Float] = []

        for depth in depths {
            if let last = current.last, depth - last > maxClusterGap {
                clusters.append(current)
                current = [depth]
            } else {
                current.append(depth)
            }
        }
        if !current.isEmpty {
            clusters.append(current)
        }

        guard let nearestCluster = clusters.first, !nearestCluster.isEmpty else {
            return nil
        }
        if clusters.count == 1 {
            return median(of: nearestCluster)
        }

        let minimumForegroundSupport = max(3, Int(ceil(Float(depths.count) * 0.10)))
        guard nearestCluster.count >= minimumForegroundSupport else {
            return nil
        }
        return median(of: nearestCluster)
    }

    private static func median(of sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        let mid = sortedValues.count / 2
        if sortedValues.count % 2 == 0 {
            return (sortedValues[mid - 1] + sortedValues[mid]) / 2
        }
        return sortedValues[mid]
    }

    private static func roiClusterShapeQualityThreshold(for category: FruitCategory) -> Float {
        switch category {
        case .mango, .papaya, .pear, .fig:
            return 0.22
        case .grape, .blueberry, .mulberry:
            return 0.28
        default:
            return 0.30
        }
    }

    private static func roiCandidateSphericity(shapeQuality: Float, category: FruitCategory) -> Float {
        let base = max(category.sphericityThreshold + 0.05, 0.55)
        let qualityBoost = min(max(shapeQuality, 0), 1) * 0.35
        return min(max(base + qualityBoost, base), 0.95)
    }

    private static func selectDominantCluster(
        from samples: [DepthWorldSample],
        referencePoint: SIMD3<Float>?,
        distanceThreshold: Float
    ) -> [DepthWorldSample] {
        guard !samples.isEmpty else { return [] }
        var visited = Array(repeating: false, count: samples.count)
        var bestCluster: [DepthWorldSample] = []
        var bestScore = -Float.infinity

        for startIndex in samples.indices where !visited[startIndex] {
            var cluster: [DepthWorldSample] = []
            var stack = [startIndex]
            visited[startIndex] = true

            while let index = stack.popLast() {
                let sample = samples[index]
                cluster.append(sample)

                for nextIndex in samples.indices where !visited[nextIndex] {
                    let distance = simd_distance(sample.worldPoint, samples[nextIndex].worldPoint)
                    if distance <= distanceThreshold {
                        visited[nextIndex] = true
                        stack.append(nextIndex)
                    }
                }
            }

            let score = clusterScore(
                cluster,
                referencePoint: referencePoint,
                distanceScale: max(distanceThreshold, 0.025)
            )
            if score > bestScore {
                bestScore = score
                bestCluster = cluster
            }
        }

        return bestCluster
    }

    private static func clusterScore(
        _ cluster: [DepthWorldSample],
        referencePoint: SIMD3<Float>?,
        distanceScale: Float
    ) -> Float {
        var score = Float(cluster.count)
        score -= roiCenterDistancePenalty(for: cluster)
        if let referencePoint {
            let center = centroid(of: cluster.map(\.worldPoint))
            let normalizedDistance = simd_distance(center, referencePoint) / max(distanceScale, 1e-6)
            score -= min(normalizedDistance, 3.0) * 0.5
        }
        return score
    }

    private static func roiCenterDistancePenalty(for cluster: [DepthWorldSample]) -> Float {
        guard !cluster.isEmpty else { return 0 }
        let averageRow = cluster.reduce(Float(0)) { $0 + Float($1.row) } / Float(cluster.count)
        let averageCol = cluster.reduce(Float(0)) { $0 + Float($1.col) } / Float(cluster.count)
        let centerIndex = Float(roiSampleGrid - 1) * 0.5
        let maxGridDistance = sqrt(centerIndex * centerIndex * 2)
        let gridDistance = hypot(averageRow - centerIndex, averageCol - centerIndex)
        let normalizedDistance = min(max(gridDistance / max(maxGridDistance, 1), 0), 1)
        return normalizedDistance * Float(cluster.count) * 0.65
    }

    private static func roiClusterDistance(
        diameter: Float,
        category: FruitCategory
    ) -> Float {
        let categoryDiameter = (category.sizeRange.lowerBound + category.sizeRange.upperBound) * 0.5
        let referenceDiameter = max(
            min(diameter, category.sizeRange.upperBound * 1.2),
            categoryDiameter * 0.6
        )
        return max(0.025, min(referenceDiameter * 1.10, 0.14))
    }

    private static func projectNormalizedImagePointToWorld(
        _ normalizedPoint: CGPoint,
        depth: Float,
        imageSize: CGSize,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float>? {
        guard depth.isFinite, depth > 0.1, imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        let imageX = Float(normalizedPoint.x * imageSize.width)
        let imageY = Float((1 - normalizedPoint.y) * imageSize.height)
        let imagePoint = SIMD3<Float>(imageX, imageY, 1.0)
        guard let cameraPoint = FusionValidator.cameraPointFromImagePoint(
            imagePoint,
            depth: depth,
            cameraIntrinsics: cameraIntrinsics
        ) else {
            return nil
        }
        let worldPoint = cameraTransform * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1.0)
        let result = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
        guard result.x.isFinite, result.y.isFinite, result.z.isFinite else { return nil }
        return result
    }

    private static func estimatedDiameter(
        detection: DetectedFruit,
        depth: Float,
        cameraIntrinsics: matrix_float3x3,
        imageSize: CGSize,
        clusterConfig: ClusterConfig,
        worldPoints: [SIMD3<Float>] = [],
        shapeQuality: Float = 0.5,
        depthSupportRatio: Float = 0
    ) -> Float {
        let categoryRange = detection.category.sizeRange
        let expectedDiameter = (categoryRange.lowerBound + categoryRange.upperBound) / 2
        let imageDiameter = projectedImageDiameter(
            detection: detection,
            depth: depth,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize
        )
        let clusterDiameter = spatialExtentDiameter(of: worldPoints)
        let plausibleMeasuredDiameter = measuredDiameter(
            imageDiameter: imageDiameter,
            clusterDiameter: clusterDiameter,
            categoryRange: categoryRange
        )
        var measurementReliability = min(
            max(0.20 + min(max(shapeQuality, 0), 1) * 0.35 + min(max(depthSupportRatio, 0), 1) * 0.30, 0.20),
            0.75
        )
        if imageDiameter < categoryRange.lowerBound * 0.60 ||
            imageDiameter > categoryRange.upperBound * 1.50 {
            measurementReliability *= 0.5
        }

        let blended = plausibleMeasuredDiameter * measurementReliability
            + expectedDiameter * (1 - measurementReliability)
        let minDiameter = max(clusterConfig.minDiameter, categoryRange.lowerBound * 0.75)
        let maxDiameter = min(clusterConfig.maxDiameter, categoryRange.upperBound * 1.05)
        return min(max(blended, minDiameter), maxDiameter)
    }

    private static func projectedImageDiameter(
        detection: DetectedFruit,
        depth: Float,
        cameraIntrinsics: matrix_float3x3,
        imageSize: CGSize
    ) -> Float {
        let fx = max(abs(cameraIntrinsics[0][0]), 1)
        let fy = max(abs(cameraIntrinsics[1][1]), 1)
        let widthM = Float(detection.boundingBox.width * imageSize.width) / fx * depth
        let heightM = Float(detection.boundingBox.height * imageSize.height) / fy * depth
        let diameter = max((widthM + heightM) / 2, 0)
        return diameter.isFinite ? diameter : 0
    }

    private static func spatialExtentDiameter(of points: [SIMD3<Float>]) -> Float {
        guard points.count >= 2 else { return 0 }
        var minPoint = points[0]
        var maxPoint = points[0]
        for point in points.dropFirst() {
            minPoint = SIMD3<Float>(
                Swift.min(minPoint.x, point.x),
                Swift.min(minPoint.y, point.y),
                Swift.min(minPoint.z, point.z)
            )
            maxPoint = SIMD3<Float>(
                Swift.max(maxPoint.x, point.x),
                Swift.max(maxPoint.y, point.y),
                Swift.max(maxPoint.z, point.z)
            )
        }
        let extent = maxPoint - minPoint
        let diameter = simd_length(extent)
        return diameter.isFinite ? diameter : 0
    }

    private static func measuredDiameter(
        imageDiameter: Float,
        clusterDiameter: Float,
        categoryRange: ClosedRange<Float>
    ) -> Float {
        guard imageDiameter.isFinite && imageDiameter > 0 else {
            return categoryRange.lowerBound <= categoryRange.upperBound
                ? (categoryRange.lowerBound + categoryRange.upperBound) / 2
                : 0
        }
        let cappedImageDiameter = min(max(imageDiameter, categoryRange.lowerBound * 0.40), categoryRange.upperBound * 1.50)
        let clusterLowerBound = clusterDiameter.isFinite && clusterDiameter > 0
            ? clusterDiameter * 1.25
            : 0
        return max(cappedImageDiameter, clusterLowerBound)
    }

    private static func centroid(of points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        var sum = SIMD3<Float>.zero
        for point in points {
            sum += point
        }
        return sum / Float(points.count)
    }

    private static func representativeColor(for category: FruitCategory) -> SIMD3<Float> {
        switch category {
        case .apple, .cherry, .persimmon, .pomegranate, .hawthorn, .bayberry:
            return SIMD3<Float>(0.75, 0.18, 0.12)
        case .orange, .mandarin, .pomelo, .peach, .loquat, .mango, .papaya:
            return SIMD3<Float>(0.95, 0.48, 0.10)
        case .pear, .kiwi, .grape, .fig, .coconut:
            return SIMD3<Float>(0.45, 0.58, 0.20)
        case .plum, .mulberry, .blueberry:
            return SIMD3<Float>(0.22, 0.14, 0.45)
        case .lychee, .longan, .jujube, .chestnut, .strawberry:
            return SIMD3<Float>(0.70, 0.28, 0.18)
        }
    }
}

private final class DepthSampler {
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

        let fp32: FourCharCode = 0x66703233 // 'fp32' legacy/custom float map
        let depthFloat32 = kCVPixelFormatType_DepthFloat32
        let oneComponentFloat32 = kCVPixelFormatType_OneComponent32Float
        let depthFloat16 = kCVPixelFormatType_DepthFloat16
        let oneComponentFloat16 = kCVPixelFormatType_OneComponent16Half
        let up16: FourCharCode = 0x75703136 // 'up16' = kCVPixelFormatType_16U
        let depth: Float

        if pixelFormat == fp32 || pixelFormat == depthFloat32 || pixelFormat == oneComponentFloat32 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            let rowBytes = bytesPerRow / MemoryLayout<Float>.size
            depth = floatBuffer[clampedY * rowBytes + clampedX]
        } else if pixelFormat == depthFloat16 || pixelFormat == oneComponentFloat16 {
            let halfBuffer = baseAddress.assumingMemoryBound(to: UInt16.self)
            let rowHalfs = bytesPerRow / MemoryLayout<UInt16>.size
            depth = Float(Float16(bitPattern: halfBuffer[clampedY * rowHalfs + clampedX]))
        } else if pixelFormat == up16 {
            let shortBuffer = baseAddress.assumingMemoryBound(to: UInt16.self)
            let rowShorts = bytesPerRow / MemoryLayout<UInt16>.size
            let rawDepth = shortBuffer[clampedY * rowShorts + clampedX]
            depth = Float(rawDepth) / 1000.0
        } else {
            return nil
        }

        guard depth > 0.1, depth < 10.0 else { return nil }
        return depth
    }
}
