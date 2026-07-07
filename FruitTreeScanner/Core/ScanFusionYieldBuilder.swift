import Foundation
import os
import simd

enum ScanFusionYieldBuilder {
    struct Input: @unchecked Sendable {
        let points: [ColoredPoint]
        let savedDetections: [DetectedFruit]
        let imageDiagnostics: ImageDetectionDiagnostics
        let fruitType: String
        let fruitCategory: FruitCategory?
        let paramsSnapshot: [String: FruitVarietyParams]
        let defaultParams: FruitVarietyParams
        let clusterConfig: ClusterConfig
        let fusionConfig: FruitScanConfig
        let colorFilter: ColorFilter?
        var season: Season = .mature
        var calibrationCorrection: YieldCalibrationCorrection = .neutral
    }

    static func build(from input: Input) async -> (YieldResult, FruitCountResult) {
        guard input.season.supportsYieldEstimation else {
            return makeUncalibratedSeasonResult(input: input)
        }

        let hasAlignedDetectionDepth = input.savedDetections.contains { $0.hasAlignedDepthContext }
        var diagnostics = ScanDiagnosticsBuilder.makeDiagnostics(
            pointCloudPointCount: input.points.count,
            depthAvailable: hasAlignedDetectionDepth,
            imageDiagnostics: input.imageDiagnostics
        )
        diagnostics.imageDetectionCount = input.savedDetections.count
        applyCalibrationDiagnostics(input.calibrationCorrection, to: &diagnostics)
        let canopyGeometry = CanopyGeometryEstimator.estimate(points: input.points)
        applyCanopyDiagnostics(canopyGeometry, to: &diagnostics)

        let colorFilteredPoints = colorFilteredPoints(from: input)
        let denoising = denoiseClusteringPoints(
            colorFilteredPoints,
            clusterConfig: input.clusterConfig
        )
        let clusteringPoints = denoising.samples
        diagnostics.pointCloudColorFilteredCount = colorFilteredPoints.count
        diagnostics.pointCloudDenoisedPointCount = denoising.stats.retainedCount
        diagnostics.pointCloudOutlierPointCount = denoising.stats.removedCount
        diagnostics.pointCloudOutlierRatio = denoising.stats.removalRatio
        let clusterer = PointCloudCluster(config: input.clusterConfig)
        let pointCloudCandidates = await clusterer.processInMemory(
            position: clusteringPoints.map { $0.pos },
            colors: clusteringPoints.map { SIMD3<Float>($0.r, $0.g, $0.b) }
        )
        let rawDetectionDepthCandidates = DetectionDepthCandidateBuilder.makeCandidates(
            from: input.savedDetections,
            clusterConfig: input.clusterConfig
        )
        let detectionDepthCandidates = mergeDetectionDepthCandidates(rawDetectionDepthCandidates)
        let candidates = combineCandidates(
            pointCloudCandidates: pointCloudCandidates,
            detectionDepthCandidates: detectionDepthCandidates
        )
        diagnostics.pointCloudClusterCandidateCount = pointCloudCandidates.count
        diagnostics.detectionDepthCandidateCount = detectionDepthCandidates.count
        diagnostics.detectionDepthSupportRatio = averageDepthSupportRatio(detectionDepthCandidates)
        diagnostics.pointCloudCandidateCount = candidates.count
        Log.fusion.info("Clustering: \(input.points.count) raw points / \(colorFilteredPoints.count) color-filtered / \(denoising.stats.retainedCount) SOR-retained → \(pointCloudCandidates.count) cloud candidates + \(rawDetectionDepthCandidates.count) ROI-depth observations / \(detectionDepthCandidates.count) merged ROI-depth candidates")

        let fusion = makeValidatedFruits(
            detections: input.savedDetections,
            candidates: candidates,
            fusionConfig: input.fusionConfig,
            diagnostics: &diagnostics
        )
        diagnostics.deduplicatedImageDetectionCount = fusion.deduplicatedDetectionCount
        diagnostics.fusedFruitCount = fusion.validatedFruits.count
        applyValidationSourceDiagnostics(fusion.validatedFruits, to: &diagnostics)
        diagnostics.validationSourceReliability = validationSourceReliability(fusion.validatedFruits)

        let fruitCounter = FruitCounter()
        let countResult = fruitCounter.count(
            fusion.validatedFruits,
            defaultCategory: input.fruitCategory ?? .apple
        )
        let weightedVisibleCount = fruitCounter.weightedTotal(fusion.validatedFruits)

        let visibleYieldEstimate = ScanYieldEstimateHelpers.computeYieldFromValidatedFruits(
            fusion.validatedFruits,
            candidates: candidates,
            paramsByCategory: input.paramsSnapshot,
            defaultParams: input.defaultParams
        )
        let visualCorrection = ScanYieldEstimateHelpers.VisibleEstimateCorrection(
            visibleCount: weightedVisibleCount,
            visibleYieldKg: visibleYieldEstimate.yieldKg,
            note: "RGB+LiDAR 融合检测"
        )
        let visibleCountForCorrection = visualCorrection.visibleCount > 0
            ? max(Int(visualCorrection.visibleCount.rounded()), 1)
            : 0
        let occlusion = makeOcclusionCorrection(
            points: input.points,
            fruitColoredPoints: clusteringPoints,
            detections: fusion.evidenceDetections,
            validatedFruits: fusion.validatedFruits,
            validationSourceReliability: diagnostics.validationSourceReliability,
            visibleCountForCorrection: visibleCountForCorrection,
            weightedVisibleCount: visualCorrection.visibleCount
        )
        diagnostics.pointCloudAngleCoverage = occlusion.pointAngleCoverage
        diagnostics.cameraAngleCoverage = occlusion.cameraAngleCoverage
        diagnostics.scanAngleCoverage = occlusion.scanAngleCoverage

        if visualCorrection.visibleCount > 0 {
            return (
                makeVisibleYieldResult(
                    input: input,
                    diagnostics: diagnostics,
                    validatedFruits: fusion.validatedFruits,
                    visibleYieldEstimate: visibleYieldEstimate,
                    visualCorrection: visualCorrection,
                    occlusion: occlusion,
                    canopyGeometry: canopyGeometry
                ),
                countResult
            )
        }

        diagnostics.zeroYieldReasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: max(input.clusterConfig.minPoints, 30)
        )
        return (
            makeZeroYieldResult(
                input: input,
                diagnostics: diagnostics,
                occlusionCorrection: occlusion.correction,
                canopyGeometry: canopyGeometry
            ),
            countResult
        )
    }

    private static func colorFilteredPoints(from input: Input) -> [ColoredPoint] {
        guard let filter = input.colorFilter ?? input.fruitCategory?.colorFilter else {
            return input.points
        }
        return input.points.filter { filter.matches(r: $0.r, g: $0.g, b: $0.b) }
    }

    private static func denoiseClusteringPoints(
        _ points: [ColoredPoint],
        clusterConfig: ClusterConfig
    ) -> PointCloudDenoisingResult<ColoredPoint> {
        let minimumDenoisingPointCount = max(clusterConfig.minPoints * 12, 50)
        guard points.count >= minimumDenoisingPointCount else {
            return PointCloudDenoiser.unchangedResult(samples: points)
        }
        return PointCloudDenoiser.statisticalOutlierRemovalDetailed(
            samples: points,
            k: 12,
            stdMultiplier: 1.5,
            position: { $0.pos }
        )
    }

    private static func applyCalibrationDiagnostics(
        _ calibration: YieldCalibrationCorrection,
        to diagnostics: inout ScanYieldDiagnostics
    ) {
        diagnostics.localCalibrationCountFactor = calibration.countFactor
        diagnostics.localCalibrationYieldFactor = calibration.yieldFactor
        diagnostics.localCalibrationCountSampleCount = calibration.countSampleCount
        diagnostics.localCalibrationYieldSampleCount = calibration.yieldSampleCount
    }

    private static func applyCanopyDiagnostics(
        _ canopyGeometry: CanopyGeometryEstimate?,
        to diagnostics: inout ScanYieldDiagnostics
    ) {
        guard let canopyGeometry else { return }
        diagnostics.canopyPointCount = canopyGeometry.pointCount
        diagnostics.canopyPreprocessedPointCount = canopyGeometry.preprocessedPointCount
        diagnostics.canopyGroundFilteredPointCount = canopyGeometry.groundFilteredPointCount
        diagnostics.canopyTrunkFilteredPointCount = canopyGeometry.trunkFilteredPointCount
        diagnostics.canopyNeighborFilteredPointCount = canopyGeometry.neighborFilteredPointCount
        diagnostics.canopyClusterCount = canopyGeometry.canopyClusterCount
        diagnostics.canopyRobustPointCount = canopyGeometry.robustPointCount
        diagnostics.canopyHeightM = canopyGeometry.treeHeightM
        diagnostics.canopyWidthM = canopyGeometry.crownWidthM
        diagnostics.canopyDepthM = canopyGeometry.crownDepthM
        diagnostics.canopyOuterVolumeM3 = canopyGeometry.outerCrownVolumeM3
        diagnostics.canopyVolumeM3 = canopyGeometry.crownVolumeM3
        diagnostics.canopyEffectiveVolumeCoefficient = canopyGeometry.effectiveVolumeCoefficient
        diagnostics.canopyProjectionXYCoefficient = canopyGeometry.projectionXYCoefficient
        diagnostics.canopyProjectionXZCoefficient = canopyGeometry.projectionXZCoefficient
        diagnostics.canopyProjectionYZCoefficient = canopyGeometry.projectionYZCoefficient
        diagnostics.canopyProjectionEffectiveCoefficient = canopyGeometry.projectionEffectiveCoefficient
        diagnostics.canopyVoxelSizeM = canopyGeometry.voxelSizeM
        diagnostics.canopyPartitionSizeM = canopyGeometry.partitionSizeM
        diagnostics.canopyPartitionCount = canopyGeometry.partitionCount
    }

    private static func applyCanopyGeometry(
        _ canopyGeometry: CanopyGeometryEstimate?,
        to result: inout YieldResult
    ) {
        guard let canopyGeometry else { return }
        result.treeHeightM = canopyGeometry.treeHeightM
        result.crownVolM3 = canopyGeometry.crownVolumeM3
    }

    private static func makeUncalibratedSeasonResult(
        input: Input
    ) -> (YieldResult, FruitCountResult) {
        var diagnostics = ScanDiagnosticsBuilder.makeDiagnostics(
            pointCloudPointCount: input.points.count,
            depthAvailable: input.savedDetections.contains { $0.hasAlignedDepthContext },
            imageDiagnostics: input.imageDiagnostics
        )
        diagnostics.imageDetectionCount = input.savedDetections.count
        let canopyGeometry = CanopyGeometryEstimator.estimate(points: input.points)
        applyCanopyDiagnostics(canopyGeometry, to: &diagnostics)
        diagnostics.zeroYieldReasons = ["非成熟期冠层回归模型尚未标定，本次未生成产量估算"]

        var result = YieldResult()
        result.yieldFinalKg = 0
        result.confidence = "manual_review"
        result.methodUsed = "crown_untrained"
        result.note = diagnostics.zeroYieldReasons[0]
        result.pointCloudSize = input.points.count
        result.fruitCategory = input.fruitCategory?.displayName ?? input.fruitType
        result.colorFilterDesc = "N/A"
        applyCanopyGeometry(canopyGeometry, to: &result)
        result.diagnostics = diagnostics

        let countResult = FruitCounter().count(
            [],
            defaultCategory: input.fruitCategory ?? .apple
        )
        return (result, countResult)
    }

    private static func makeValidatedFruits(
        detections: [DetectedFruit],
        candidates: [FruitCandidate],
        fusionConfig: FruitScanConfig,
        diagnostics: inout ScanYieldDiagnostics
    ) -> (
        validatedFruits: [ValidatedFruit],
        deduplicatedDetectionCount: Int,
        evidenceDetections: [DetectedFruit]
    ) {
        if !detections.isEmpty {
            let alignedDetections = detections.filter(\.hasAlignedDepthContext)
            guard !alignedDetections.isEmpty else {
                diagnostics.cloudOnlyConservativeMode = true
                Log.fusion.warning("Skipping \(detections.count) image detections because none carried aligned depth context")
                return (makeCloudOnlyFruits(from: candidates), 0, [])
            }
            let deduplicatedDetections = DetectionDeduplicator.deduplicate2D(alignedDetections)
            let fusionValidator = FusionValidator(config: fusionConfig)
            let fusedFruits = fusionValidator.validate(
                detections: deduplicatedDetections,
                candidates: candidates
            )
            if fusedFruits.isEmpty {
                diagnostics.cloudOnlyConservativeMode = true
                return (makeCloudOnlyFruits(from: candidates), deduplicatedDetections.count, [])
            }
            return (
                ValidatedFruit.deduplicate3D(fusedFruits),
                deduplicatedDetections.count,
                deduplicatedDetections
            )
        }

        diagnostics.cloudOnlyConservativeMode = true

        return (makeCloudOnlyFruits(from: candidates), 0, [])
    }

    private static func makeCloudOnlyFruits(from candidates: [FruitCandidate]) -> [ValidatedFruit] {
        candidates.compactMap { candidate -> ValidatedFruit? in
            guard candidate.sourceCategory == nil,
                  candidate.depthSupportRatio == nil,
                  candidate.sphericity > 0.7,
                  candidate.hasFruitColor() else {
                return nil
            }
            return ValidatedFruit(
                category: nil,
                position: candidate.position,
                confidence: candidate.sphericity * 0.5,
                source: .cloudOnly
            )
        }
    }

    private static func applyValidationSourceDiagnostics(
        _ validatedFruits: [ValidatedFruit],
        to diagnostics: inout ScanYieldDiagnostics
    ) {
        diagnostics.validatedFruitCount = validatedFruits.count
        diagnostics.fusedValidationCount = validatedFruits.filter { $0.source == .fused }.count
        diagnostics.trackedImageFruitCount = validatedFruits.filter { $0.source == .trackedImage }.count
        diagnostics.imageOnlyFruitCount = validatedFruits.filter { $0.source == .imageOnly }.count
        diagnostics.cloudOnlyFruitCount = validatedFruits.filter { $0.source == .cloudOnly }.count
    }

    private static func validationSourceReliability(_ validatedFruits: [ValidatedFruit]) -> Float {
        guard !validatedFruits.isEmpty else { return 0 }
        let reliability = validatedFruits.reduce(Float(0)) { total, fruit in
            total + FruitCounter.evidenceWeight(for: fruit)
        } / Float(validatedFruits.count)
        return min(max(reliability, 0), 1)
    }

    static func combineCandidates(
        pointCloudCandidates: [FruitCandidate],
        detectionDepthCandidates: [FruitCandidate]
    ) -> [FruitCandidate] {
        mergeCandidateEvidence(pointCloudCandidates + detectionDepthCandidates)
    }

    private struct CandidateTrack {
        var totalWeight: Float
        var weightedPosition: SIMD3<Float>
        var weightedDiameter: Float
        var weightedColor: SIMD3<Float>
        var maxSphericity: Float
        var pointCount: Int
        var points: [SIMD3<Float>]
        var sourceCategory: FruitCategory?
        var weightedDepthSupport: Float
        var depthSupportWeight: Float
        var hasPointCloudEvidence: Bool

        init(seed: FruitCandidate) {
            let weight = Self.weight(for: seed)
            totalWeight = weight
            weightedPosition = seed.position * weight
            weightedDiameter = seed.diameter * weight
            weightedColor = seed.averageColor * weight
            maxSphericity = seed.sphericity
            pointCount = seed.pointCount
            points = Array(seed.points.prefix(Self.maxPointSamples))
            sourceCategory = seed.sourceCategory
            hasPointCloudEvidence = seed.sourceCategory == nil && seed.depthSupportRatio == nil
            if let depthSupportRatio = seed.depthSupportRatio {
                weightedDepthSupport = Self.clampedRatio(depthSupportRatio) * weight
                depthSupportWeight = weight
            } else {
                weightedDepthSupport = 0
                depthSupportWeight = 0
            }
        }

        var center: SIMD3<Float> {
            guard totalWeight > 0 else { return .zero }
            return weightedPosition / totalWeight
        }

        mutating func add(_ candidate: FruitCandidate) {
            let weight = Self.weight(for: candidate)
            weightedPosition += candidate.position * weight
            weightedDiameter += candidate.diameter * weight
            weightedColor += candidate.averageColor * weight
            totalWeight += weight
            maxSphericity = max(maxSphericity, candidate.sphericity)
            pointCount += candidate.pointCount

            let remainingCapacity = Self.maxPointSamples - points.count
            if remainingCapacity > 0 {
                points.append(contentsOf: candidate.points.prefix(remainingCapacity))
            }
            if sourceCategory == nil {
                sourceCategory = candidate.sourceCategory
            }
            if candidate.sourceCategory == nil && candidate.depthSupportRatio == nil {
                hasPointCloudEvidence = true
            }
            if let depthSupportRatio = candidate.depthSupportRatio {
                weightedDepthSupport += Self.clampedRatio(depthSupportRatio) * weight
                depthSupportWeight += weight
            }
        }

        func mergedCandidate() -> FruitCandidate {
            let safeWeight = max(totalWeight, 1e-6)
            let depthSupportRatio = !hasPointCloudEvidence && depthSupportWeight > 0
                ? weightedDepthSupport / depthSupportWeight
                : nil
            return FruitCandidate(
                position: weightedPosition / safeWeight,
                diameter: weightedDiameter / safeWeight,
                sphericity: maxSphericity,
                pointCount: max(pointCount, points.count),
                averageColor: weightedColor / safeWeight,
                points: points,
                sourceCategory: sourceCategory,
                depthSupportRatio: depthSupportRatio
            )
        }

        private static let maxPointSamples = 256

        private static func weight(for candidate: FruitCandidate) -> Float {
            max(Float(max(candidate.pointCount, candidate.points.count)), 1) * max(candidate.sphericity, 0.05)
        }

        private static func clampedRatio(_ ratio: Float) -> Float {
            guard ratio.isFinite else { return 0 }
            return min(max(ratio, 0), 1)
        }
    }

    private static func mergeDetectionDepthCandidates(_ candidates: [FruitCandidate]) -> [FruitCandidate] {
        mergeCandidateEvidence(candidates)
    }

    private static func mergeCandidateEvidence(_ candidates: [FruitCandidate]) -> [FruitCandidate] {
        guard candidates.count > 1 else { return candidates }

        let sorted = candidates.sorted {
            if $0.pointCount == $1.pointCount {
                return $0.sphericity > $1.sphericity
            }
            return $0.pointCount > $1.pointCount
        }
        var tracks: [CandidateTrack] = []

        for candidate in sorted {
            let mergeableTrackIndices = tracks.indices.filter { index in
                shouldMergeDepthCandidate(candidate, into: tracks[index].mergedCandidate())
            }

            if let trackIndex = mergeableTrackIndices.min(by: { lhs, rhs in
                simd_distance(tracks[lhs].center, candidate.position) < simd_distance(tracks[rhs].center, candidate.position)
            }) {
                tracks[trackIndex].add(candidate)
                continue
            }

            tracks.append(CandidateTrack(seed: candidate))
        }

        return tracks.map { $0.mergedCandidate() }
    }

    private static func shouldMergeDepthCandidate(
        _ candidate: FruitCandidate,
        into trackCandidate: FruitCandidate
    ) -> Bool {
        guard categoriesAreCompatible(candidate.sourceCategory, trackCandidate.sourceCategory) else {
            return false
        }

        let largerDiameter = max(candidate.diameter, trackCandidate.diameter)
        guard largerDiameter > 0 else { return false }

        let diameterSimilarity = min(candidate.diameter, trackCandidate.diameter) / largerDiameter
        guard diameterSimilarity >= 0.55 else { return false }

        let averageDiameter = (candidate.diameter + trackCandidate.diameter) * 0.5
        let mergeDistance = max(0.035, min(averageDiameter * 0.75, 0.08))
        return simd_distance(candidate.position, trackCandidate.position) < mergeDistance
    }

    private static func categoriesAreCompatible(
        _ lhs: FruitCategory?,
        _ rhs: FruitCategory?
    ) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }

    private static func averageDepthSupportRatio(_ candidates: [FruitCandidate]) -> Float {
        let ratios = candidates.compactMap(\.depthSupportRatio).filter { $0.isFinite }
        guard !ratios.isEmpty else { return 0 }
        let average = ratios.reduce(0, +) / Float(ratios.count)
        return min(max(average, 0), 1)
    }

    private static func makeOcclusionCorrection(
        points: [ColoredPoint],
        fruitColoredPoints: [ColoredPoint],
        detections: [DetectedFruit],
        validatedFruits: [ValidatedFruit],
        validationSourceReliability: Float,
        visibleCountForCorrection: Int,
        weightedVisibleCount: Float
    ) -> (
        correction: Float,
        correctedCount: Int,
        pointAngleCoverage: Float,
        cameraAngleCoverage: Float,
        scanAngleCoverage: Float
    ) {
        let crownRadius = OcclusionCorrector.estimateCrownRadius(from: points)
        let crownDepth = OcclusionCorrector.estimateCrownDepth(from: points)
        let pointAngleCoverage = targetFruitAngleCoverage(
            allPoints: points,
            fruitColoredPoints: fruitColoredPoints
        )
        let cameraAngleCoverage = estimateCameraAngleCoverage(
            from: detections,
            around: validatedFruits
        )
        let effectiveCameraAngleCoverage = cameraAngleCoverage * min(max(validationSourceReliability, 0), 1)
        let scanAngleCoverage = max(pointAngleCoverage, effectiveCameraAngleCoverage)
        let occlusionResult = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: visibleCountForCorrection,
            crownRadiusM: crownRadius,
            crownDepthM: crownDepth,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: scanAngleCoverage,
            visualDetectionCount: detections.count,
            lidarDetectionCount: lidarBackedFruitCount(validatedFruits)
        )
        return (
            occlusionResult.k,
            Int((weightedVisibleCount * occlusionResult.k).rounded()),
            pointAngleCoverage,
            cameraAngleCoverage,
            scanAngleCoverage
        )
    }

    private static func targetFruitAngleCoverage(
        allPoints: [ColoredPoint],
        fruitColoredPoints: [ColoredPoint]
    ) -> Float {
        let allPointCoverage = OcclusionCorrector.estimateScanAngleCoverage(from: allPoints)
        guard !fruitColoredPoints.isEmpty,
              fruitColoredPoints.count < allPoints.count else {
            return allPointCoverage
        }

        let fruitPointCoverage = OcclusionCorrector.estimateScanAngleCoverage(from: fruitColoredPoints)
        return min(allPointCoverage, fruitPointCoverage)
    }

    private static func lidarBackedFruitCount(_ validatedFruits: [ValidatedFruit]) -> Int {
        validatedFruits.filter { fruit in
            switch fruit.source {
            case .fused, .cloudOnly:
                return true
            case .imageOnly, .trackedImage:
                return false
            }
        }.count
    }

    private static func estimateCameraAngleCoverage(
        from detections: [DetectedFruit],
        around validatedFruits: [ValidatedFruit],
        binCount: Int = 36
    ) -> Float {
        guard !detections.isEmpty, !validatedFruits.isEmpty, binCount > 3 else { return 0 }

        var detectionsByFruit = Array(repeating: [DetectedFruit](), count: validatedFruits.count)
        for detection in detections {
            guard let fruitIndex = associatedFruitIndex(
                for: detection,
                in: validatedFruits
            ) else {
                continue
            }
            detectionsByFruit[fruitIndex].append(detection)
        }

        let coverages = validatedFruits.indices.map { index in
            cameraAngleCoverage(
                for: detectionsByFruit[index],
                around: validatedFruits[index].position,
                binCount: binCount
            )
        }
        guard coverages.contains(where: { $0 > 0 }) else { return 0 }
        let average = coverages.reduce(Float(0), +) / Float(coverages.count)
        return max(min(average, 1), 0)
    }

    private static func associatedFruitIndex(
        for detection: DetectedFruit,
        in validatedFruits: [ValidatedFruit]
    ) -> Int? {
        if let projectedPosition = projectedDetectionPosition(for: detection),
           let nearest = nearestFruitIndex(
               to: projectedPosition,
               detection: detection,
               in: validatedFruits
           ) {
            return nearest
        }

        guard let cameraIntrinsics = detection.cameraIntrinsics,
              let cameraTransform = detection.cameraTransform,
              let imageSize = detection.imageSize else {
            return nil
        }

        let expandedBox = expandedDetectionBox(detection.boundingBox, by: 0.15)
        let center = CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY)
        var bestIndex: Int?
        var bestDistance = CGFloat.infinity

        for index in validatedFruits.indices {
            let fruit = validatedFruits[index]
            if let category = fruit.category, category != detection.category {
                continue
            }
            guard let projected = FusionValidator.projectWorldPointToNormalizedImage(
                fruit.position,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            ), expandedBox.contains(projected) else {
                continue
            }

            let dx = projected.x - center.x
            let dy = projected.y - center.y
            let distance = sqrt(dx * dx + dy * dy)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }
        return bestIndex
    }

    private static func projectedDetectionPosition(for detection: DetectedFruit) -> SIMD3<Float>? {
        guard let depthMap = detection.depthMap,
              let cameraIntrinsics = detection.cameraIntrinsics,
              let cameraTransform = detection.cameraTransform,
              let imageSize = detection.imageSize else {
            return nil
        }

        return FusionValidator().projectDetectionTo3D(
            detection: detection,
            depthMap: depthMap,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize
        )
    }

    private static func nearestFruitIndex(
        to projectedPosition: SIMD3<Float>,
        detection: DetectedFruit,
        in validatedFruits: [ValidatedFruit]
    ) -> Int? {
        let maxDiameter = detection.category.sizeRange.upperBound
        let associationThreshold = max(0.08, min(maxDiameter * 1.75, 0.22))
        var bestIndex: Int?
        var bestDistance = Float.infinity

        for index in validatedFruits.indices {
            let fruit = validatedFruits[index]
            if let category = fruit.category, category != detection.category {
                continue
            }

            let distance = simd_distance(projectedPosition, fruit.position)
            if distance < bestDistance {
                bestDistance = distance
                bestIndex = index
            }
        }

        guard bestDistance <= associationThreshold else {
            return nil
        }
        return bestIndex
    }

    private static func cameraAngleCoverage(
        for detections: [DetectedFruit],
        around center: SIMD3<Float>,
        binCount: Int
    ) -> Float {
        guard !detections.isEmpty, binCount > 3 else { return 0 }
        var binOccupancy = [Int](repeating: 0, count: binCount)

        for detection in detections {
            guard let cameraTransform = detection.cameraTransform else { continue }
            let cameraPosition = cameraTransform.columns.3
            let dx = cameraPosition.x - center.x
            let dz = cameraPosition.z - center.z
            guard hypot(dx, dz) >= 0.05 else { continue }

            var normalizedAngle = (atan2(dz, dx) + Float.pi) / (2 * Float.pi)
            if normalizedAngle >= 1 {
                normalizedAngle = 0
            }
            let bin = min(max(Int(floor(normalizedAngle * Float(binCount))), 0), binCount - 1)
            binOccupancy[bin] += 1
        }

        let occupied = binOccupancy.map { $0 > 0 }
        guard occupied.contains(true) else { return 0 }

        var longestEmptyRun = 0
        var currentEmptyRun = 0
        for index in 0..<(binCount * 2) {
            if occupied[index % binCount] {
                currentEmptyRun = 0
            } else {
                currentEmptyRun += 1
                longestEmptyRun = min(max(longestEmptyRun, currentEmptyRun), binCount)
            }
        }

        let coverage = 1.0 - Float(longestEmptyRun) / Float(binCount)
        return max(min(coverage, 1.0), 0)
    }

    private static func expandedDetectionBox(_ box: CGRect, by fraction: CGFloat) -> CGRect {
        let dx = box.width * fraction
        let dy = box.height * fraction
        let expanded = box.insetBy(dx: -dx, dy: -dy)
        let minX = max(0, expanded.minX)
        let minY = max(0, expanded.minY)
        let maxX = min(1, expanded.maxX)
        let maxY = min(1, expanded.maxY)
        guard maxX > minX, maxY > minY else { return box }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }

    private static func makeVisibleYieldResult(
        input: Input,
        diagnostics: ScanYieldDiagnostics,
        validatedFruits: [ValidatedFruit],
        visibleYieldEstimate: ScanYieldEstimateHelpers.VisibleYieldEstimate,
        visualCorrection: ScanYieldEstimateHelpers.VisibleEstimateCorrection,
        occlusion: (
            correction: Float,
            correctedCount: Int,
            pointAngleCoverage: Float,
            cameraAngleCoverage: Float,
            scanAngleCoverage: Float
        ),
        canopyGeometry: CanopyGeometryEstimate?
    ) -> YieldResult {
        let calibration = input.calibrationCorrection
        let yieldAfterOcclusion = visualCorrection.visibleYieldKg
            * occlusion.correction
            * calibration.yieldFactor
        let calibratedCount = max(
            Int((Float(occlusion.correctedCount) * calibration.countFactor).rounded()),
            0
        )
        let estimateQuality = ScanYieldEstimateHelpers.estimateQuality(
            for: validatedFruits
        )
        let adjustedQuality = ScanYieldEstimateHelpers.adjustQualityForCoverageRisk(
            confidence: estimateQuality.confidence,
            methodUsed: estimateQuality.methodUsed,
            sourceDescription: estimateQuality.sourceDescription,
            correctionK: occlusion.correction,
            scanAngleCoverage: occlusion.scanAngleCoverage
        )

        var result = YieldResult()
        result.nLidar = calibratedCount
        result.correctionK = occlusion.correction
        result.yieldFinalKg = yieldAfterOcclusion
        result.yieldBVisibleKg = visualCorrection.visibleYieldKg
        result.yieldBCorrectedKg = yieldAfterOcclusion
        result.meanDiameterCm = visibleYieldEstimate.meanDiameterCm
        result.meanVolumeCm3 = visibleYieldEstimate.meanVolumeCm3
        result.confidence = adjustedQuality.confidence
        result.methodUsed = adjustedQuality.methodUsed
        var note = visualCorrection.note.replacingOccurrences(
            of: "RGB+LiDAR 融合检测",
            with: adjustedQuality.sourceDescription
        )
        note += adjustedQuality.noteSuffix
        if calibration.hasEvidence {
            note += String(
                format: "；本地校准 count×%.2f(%d) yield×%.2f(%d)",
                calibration.countFactor,
                calibration.countSampleCount,
                calibration.yieldFactor,
                calibration.yieldSampleCount
            )
        }
        result.note = note
        result.pointCloudSize = input.points.count
        result.clusterEps = input.clusterConfig.baseEps
        result.clusterMinPoints = input.clusterConfig.minPoints
        result.fruitCategory = input.fruitCategory?.displayName ?? input.fruitType
        result.colorFilterDesc = (input.colorFilter ?? input.fruitCategory?.colorFilter)?.description ?? "N/A"
        result.occlusionK = occlusion.correction
        applyCanopyGeometry(canopyGeometry, to: &result)
        result.diagnostics = diagnostics
        result.fruitMassEstimates = visibleYieldEstimate.massEstimates
        return result
    }

    private static func makeZeroYieldResult(
        input: Input,
        diagnostics: ScanYieldDiagnostics,
        occlusionCorrection: Float,
        canopyGeometry: CanopyGeometryEstimate?
    ) -> YieldResult {
        var result = YieldResult()
        result.nLidar = 0
        result.yieldFinalKg = 0
        result.confidence = "low"
        result.methodUsed = "fusion_only"
        result.note = ScanDiagnosticsBuilder.zeroYieldNote(reasons: diagnostics.zeroYieldReasons)
        result.pointCloudSize = input.points.count
        result.clusterEps = input.clusterConfig.baseEps
        result.clusterMinPoints = input.clusterConfig.minPoints
        result.fruitCategory = input.fruitCategory?.displayName ?? input.fruitType
        result.colorFilterDesc = (input.colorFilter ?? input.fruitCategory?.colorFilter)?.description ?? "N/A"
        result.occlusionK = occlusionCorrection
        applyCanopyGeometry(canopyGeometry, to: &result)
        result.diagnostics = diagnostics
        return result
    }
}
