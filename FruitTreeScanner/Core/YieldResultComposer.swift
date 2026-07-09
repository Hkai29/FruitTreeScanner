import CoreGraphics
import Foundation
import simd

struct YieldResultComposer {
    struct OcclusionCorrection {
        let correction: Float
        let correctedCount: Int
        let pointAngleCoverage: Float
        let cameraAngleCoverage: Float
        let scanAngleCoverage: Float
    }

    func compose(
        input: ScanFusionYieldBuilder.Input,
        candidates: [FruitCandidate],
        pointCloudOutput: PointCloudCandidatePipelineOutput,
        fusionOutput: FusionEvidencePipelineOutput,
        canopyGeometry: CanopyGeometryEstimate?,
        diagnostics: inout ScanYieldDiagnostics
    ) -> (YieldResult, FruitCountResult) {
        let fruitCounter = FruitCounter()
        let countResult = fruitCounter.count(
            fusionOutput.validatedFruits,
            defaultCategory: input.fruitCategory ?? .apple
        )
        let weightedVisibleCount = fruitCounter.weightedTotal(fusionOutput.validatedFruits)

        let visibleYieldEstimate = ScanYieldEstimateHelpers.computeYieldFromValidatedFruits(
            fusionOutput.validatedFruits,
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
        let occlusion = Self.makeOcclusionCorrection(
            points: input.points,
            fruitColoredPoints: pointCloudOutput.clusteringPoints,
            detections: fusionOutput.evidenceDetections,
            validatedFruits: fusionOutput.validatedFruits,
            validationSourceReliability: diagnostics.validationSourceReliability,
            visibleCountForCorrection: visibleCountForCorrection,
            weightedVisibleCount: visualCorrection.visibleCount
        )
        ScanFusionDiagnosticsUpdater.applyOcclusion(occlusion, to: &diagnostics)

        if visualCorrection.visibleCount > 0 {
            return (
                makeVisibleYieldResult(
                    input: input,
                    diagnostics: diagnostics,
                    validatedFruits: fusionOutput.validatedFruits,
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

    static func makeUncalibratedSeasonResult(
        input: ScanFusionYieldBuilder.Input
    ) -> (YieldResult, FruitCountResult) {
        var diagnostics = ScanFusionDiagnosticsUpdater.makeInitialDiagnostics(input: input)
        let canopyGeometry = CanopyGeometryEstimator.estimate(points: input.points)
        ScanFusionDiagnosticsUpdater.applyCanopy(canopyGeometry, to: &diagnostics)
        diagnostics.zeroYieldReasons = ["非成熟期冠层回归模型尚未标定，本次未生成产量估算"]

        var result = YieldResult()
        result.yieldFinalKg = 0
        result.confidence = "manual_review"
        result.methodUsed = "crown_untrained"
        result.note = diagnostics.zeroYieldReasons[0]
        result.pointCloudSize = input.points.count
        result.fruitCategory = input.fruitCategory?.displayName ?? input.fruitType
        result.colorFilterDesc = "N/A"
        ScanFusionDiagnosticsUpdater.applyCanopyGeometry(canopyGeometry, to: &result)
        result.diagnostics = diagnostics

        let countResult = FruitCounter().count(
            [],
            defaultCategory: input.fruitCategory ?? .apple
        )
        return (result, countResult)
    }

    private static func makeOcclusionCorrection(
        points: [ColoredPoint],
        fruitColoredPoints: [ColoredPoint],
        detections: [DetectedFruit],
        validatedFruits: [ValidatedFruit],
        validationSourceReliability: Float,
        visibleCountForCorrection: Int,
        weightedVisibleCount: Float
    ) -> OcclusionCorrection {
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
            lidarPenetrationM: FruitScanExperimentConfig.default.occlusion.lidarPenetrationMeters,
            scanAngleCoverage: scanAngleCoverage,
            visualDetectionCount: detections.count,
            lidarDetectionCount: lidarBackedFruitCount(validatedFruits)
        )
        return OcclusionCorrection(
            correction: occlusionResult.k,
            correctedCount: Int((weightedVisibleCount * occlusionResult.k).rounded()),
            pointAngleCoverage: pointAngleCoverage,
            cameraAngleCoverage: cameraAngleCoverage,
            scanAngleCoverage: scanAngleCoverage
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

        if detection.depthMap != nil {
            return nil
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

        return FusionValidator().projectDetectionTo3DWithValidDepth(
            detection: detection,
            depthMap: depthMap,
            depthConfidenceMap: detection.depthConfidenceMap,
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

    private func makeVisibleYieldResult(
        input: ScanFusionYieldBuilder.Input,
        diagnostics: ScanYieldDiagnostics,
        validatedFruits: [ValidatedFruit],
        visibleYieldEstimate: ScanYieldEstimateHelpers.VisibleYieldEstimate,
        visualCorrection: ScanYieldEstimateHelpers.VisibleEstimateCorrection,
        occlusion: OcclusionCorrection,
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
        ScanFusionDiagnosticsUpdater.applyCanopyGeometry(canopyGeometry, to: &result)
        result.diagnostics = diagnostics
        result.fruitMassEstimates = visibleYieldEstimate.massEstimates
        result.validatedFruits = validatedFruits.map { ValidatedFruitData(from: $0) }
        return result
    }

    private func makeZeroYieldResult(
        input: ScanFusionYieldBuilder.Input,
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
        ScanFusionDiagnosticsUpdater.applyCanopyGeometry(canopyGeometry, to: &result)
        result.diagnostics = diagnostics
        return result
    }
}
