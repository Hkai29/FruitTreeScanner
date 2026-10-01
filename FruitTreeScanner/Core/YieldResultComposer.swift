import CoreGraphics
import Foundation
import simd

struct YieldResultComposer {
    // 汇总遮挡修正所需的计数和多种角度覆盖指标。
    struct OcclusionCorrection {
        let correction: Float
        let correctedCount: Int
        let pointAngleCoverage: Float
        let cameraAngleCoverage: Float
        let scanAngleCoverage: Float
    }

    /// 把可靠融合证据组合为计数、重量、置信度和可追溯诊断结果。
    /// 本层不重新接纳 imageOnly 或 cloudOnly 候选。
    func compose(
        input: ScanFusionYieldBuilder.Input,
        candidates: [FruitCandidate],
        pointCloudOutput: PointCloudCandidatePipelineOutput,
        fusionOutput: FusionEvidencePipelineOutput,
        canopyGeometry: CanopyGeometryEstimate?,
        diagnostics: inout ScanYieldDiagnostics
    ) -> (YieldResult, FruitCountResult) {
        // 计数和重量仅使用融合管线返回的 fused 集合。
        let fruitCounter = FruitCounter()
        let reliableEvidence = fusionOutput.reliableEvidence
        let validatedFruits = reliableEvidence.map(\.validatedFruit)
        let countResult = fruitCounter.count(
            reliableEvidence,
            defaultCategory: input.fruitCategory ?? .apple
        )
        let weightedVisibleCount = fruitCounter.weightedTotal(reliableEvidence)

        // 先按每个可靠果实估算可见重量，再统一应用遮挡和本地校准。
        let visibleYieldEstimate = ScanYieldEstimateHelpers.computeYieldFromReliableEvidence(
            reliableEvidence,
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
        // 遮挡修正结合点云与相机角度覆盖，并受证据可靠性约束。
        let occlusion = Self.makeOcclusionCorrection(
            points: input.points,
            fruitColoredPoints: pointCloudOutput.clusteringPoints,
            detections: fusionOutput.evidenceDetections,
            validatedFruits: validatedFruits,
            validationSourceReliability: diagnostics.validationSourceReliability,
            visibleCountForCorrection: visibleCountForCorrection,
            weightedVisibleCount: visualCorrection.visibleCount,
            configuration: input.experimentConfiguration.occlusion
        )
        ScanFusionDiagnosticsUpdater.applyOcclusion(occlusion, to: &diagnostics)

        // 无可靠果实时返回零产量，并保留诊断原因。
        if visualCorrection.visibleCount > 0 {
            return (
                makeVisibleYieldResult(
                    input: input,
                    diagnostics: diagnostics,
                    validatedFruits: validatedFruits,
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

    /// 非成熟季节没有适用模型时返回可解释的人工复核结果。
    static func makeUncalibratedSeasonResult(
        input: ScanFusionYieldBuilder.Input
    ) -> (YieldResult, FruitCountResult) {
        // 未标定季节明确要求人工复核，不复用成熟期回归参数。
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
            [] as [ValidatedFruit],
            defaultCategory: input.fruitCategory ?? .apple
        )
        return (result, countResult)
    }

    /// 综合树冠几何、点云覆盖和相机环绕覆盖计算遮挡修正系数。
    private static func makeOcclusionCorrection(
        points: [ColoredPoint],
        fruitColoredPoints: [ColoredPoint],
        detections: [Observation],
        validatedFruits: [ValidatedFruit],
        validationSourceReliability: Float,
        visibleCountForCorrection: Int,
        weightedVisibleCount: Float,
        configuration: OcclusionExperimentConfig
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
        // 相机覆盖按证据可靠性折减，避免大量低质量检测放大修正系数。
        let effectiveCameraAngleCoverage = cameraAngleCoverage * min(max(validationSourceReliability, 0), 1)
        let scanAngleCoverage = max(pointAngleCoverage, effectiveCameraAngleCoverage)
        let occlusionResult = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: visibleCountForCorrection,
            crownRadiusM: crownRadius,
            crownDepthM: crownDepth,
            lidarPenetrationM: configuration.lidarPenetrationMeters,
            scanAngleCoverage: scanAngleCoverage,
            // 多帧观测不是独立果实数量，不能作为视觉/LiDAR 数量比。
            visualDetectionCount: nil,
            lidarDetectionCount: nil
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
        // 果实点覆盖不能高于整棵树的扫描覆盖，取更保守的下界。
        let allPointCoverage = OcclusionCorrector.estimateScanAngleCoverage(from: allPoints)
        guard !fruitColoredPoints.isEmpty,
              fruitColoredPoints.count < allPoints.count else {
            return allPointCoverage
        }

        let fruitPointCoverage = OcclusionCorrector.estimateScanAngleCoverage(from: fruitColoredPoints)
        return min(allPointCoverage, fruitPointCoverage)
    }

    /// 先把多帧检测关联到可靠果实，再平均每个果实的相机方位覆盖。
    private static func estimateCameraAngleCoverage(
        from detections: [Observation],
        around validatedFruits: [ValidatedFruit],
        binCount: Int = 36
    ) -> Float {
        guard !detections.isEmpty, !validatedFruits.isEmpty, binCount > 3 else { return 0 }

        // 同一检测只分配给一个最近的同类别可靠果实。
        var detectionsByFruit = Array(repeating: [Observation](), count: validatedFruits.count)
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
        for detection: Observation,
        in validatedFruits: [ValidatedFruit]
    ) -> Int? {
        // 优先使用可靠深度投影；深度存在但失效时禁止退化为纯 2D 关联。
        if let projectedPosition = projectedDetectionPosition(for: detection),
           let nearest = nearestFruitIndex(
               to: projectedPosition,
               detection: detection,
               in: validatedFruits
           ) {
            return nearest
        }

        if detection.hasDepthMap {
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
            guard let projected = ObservationProjection.projectWorldPointToNormalizedImage(
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

    // 仅使用与检测帧对齐且通过置信度检查的深度生成三维关联位置。
    private static func projectedDetectionPosition(for detection: Observation) -> SIMD3<Float>? {
        guard detection.hasAlignedDepthContext,
              let cameraIntrinsics = detection.cameraIntrinsics,
              let cameraTransform = detection.cameraTransform,
              let imageSize = detection.imageSize else {
            return nil
        }

        return ObservationProjection.projectObservationTo3D(
            detection: detection,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize,
            fallbackDepth: nil
        )
    }

    /// 在同类别可靠果实中查找最近三维位置，并限制最大关联距离。
    private static func nearestFruitIndex(
        to projectedPosition: SIMD3<Float>,
        detection: Observation,
        in validatedFruits: [ValidatedFruit]
    ) -> Int? {
        let maxDiameter = detection.category.sizeRange.upperBound
        // 阈值随品类尺寸变化，同时设置上下限防止过严或跨目标关联。
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
        for detections: [Observation],
        around center: SIMD3<Float>,
        binCount: Int
    ) -> Float {
        // 使用环形方位分箱估计绕树覆盖，最长空缺区决定覆盖风险。
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

    // 无深度回退关联时适度扩框，并始终限制在归一化图像边界内。
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
        // 校准因子仅在融合和遮挡修正完成后应用，保留原始可见产量诊断。
        let calibration = input.calibrationCorrection
        let yieldAfterOcclusion = visualCorrection.visibleYieldKg
            * occlusion.correction
            * calibration.yieldFactor
        let calibratedCount = max(
            Int((Float(occlusion.correctedCount) * calibration.countFactor).rounded()),
            0
        )
        let estimateQuality = ScanYieldEstimateHelpers.estimateQuality(
            for: validatedFruits,
            massEstimate: visibleYieldEstimate
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
        result.algorithmRevision = input.calibrationIdentity?.algorithmRevision ?? YieldAlgorithmRevision.current
        if let identity = input.calibrationIdentity {
            result.calibrationContext = identity.context
        } else {
            // Raw callers with nondefault legacy calibration settings supply
            // ScanCalibrationIdentity explicitly. This fallback uses the old default.
            result.calibrationContext = YieldCalibrationContext.make(
                parameters: input.paramsSnapshot, cluster: input.clusterConfig,
                fusion: input.fusionConfig, color: input.colorFilter,
                experimentConfiguration: input.experimentConfiguration,
                legacyFusionSphericityThreshold: YieldCalibrationContext.legacyDefaultFusionSphericityThreshold
            )
        }
        result.calibrationBaseCount = occlusion.correctedCount
        result.calibrationBaseYieldKg = visualCorrection.visibleYieldKg * occlusion.correction
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
        if visibleYieldEstimate.fallbackFruitCount > 0 {
            note += "；\(visibleYieldEstimate.fallbackFruitCount) 个果实缺少关联几何，重量使用品类均值，需复核"
        }
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
        // 零产量结果保留扫描质量和融合诊断。
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
