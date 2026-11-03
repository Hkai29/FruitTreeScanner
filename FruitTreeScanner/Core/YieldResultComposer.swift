import Foundation

struct YieldResultComposer {
    typealias OcclusionCorrection = YieldOcclusionCorrection

    /// Adapt the frozen pipeline values into numerical assessment, then retain
    /// the existing result schema, diagnostics, display and calibration identity.
    func compose(
        input: ScanFusionYieldBuilder.Input,
        candidates: [FruitCandidate],
        pointCloudOutput: PointCloudCandidatePipelineOutput,
        fusionOutput: FusionEvidencePipelineOutput,
        canopyGeometry: CanopyGeometryEstimate?,
        diagnostics: inout ScanYieldDiagnostics
    ) -> (YieldResult, FruitCountResult) {
        let assessment = YieldAssessmentEvaluator.assess(YieldAssessmentInput(
            points: input.points,
            targetFruitPoints: pointCloudOutput.clusteringPoints,
            reliableEvidence: fusionOutput.reliableEvidence,
            evidenceObservations: fusionOutput.evidenceDetections,
            candidates: candidates,
            paramsByCategory: input.paramsSnapshot,
            defaultParams: input.defaultParams,
            defaultCategory: input.fruitCategory ?? .apple,
            occlusionConfiguration: input.experimentConfiguration.occlusion,
            calibration: input.calibrationCorrection,
            validationSourceReliability: diagnostics.validationSourceReliability
        ))
        ScanFusionDiagnosticsUpdater.applyOcclusion(assessment.occlusion, to: &diagnostics)

        switch assessment.outcome {
        case .visible(let visible):
            return (
                makeVisibleYieldResult(
                    input: input,
                    diagnostics: diagnostics,
                    assessment: assessment,
                    visible: visible,
                    canopyGeometry: canopyGeometry
                ),
                assessment.countResult
            )
        case .zero:
            diagnostics.zeroYieldReasons = ScanDiagnosticsBuilder.zeroYieldReasons(
                diagnostics: diagnostics,
                pointCloudMinimum: max(input.clusterConfig.minPoints, 30)
            )
            return (
                makeZeroYieldResult(
                    input: input,
                    diagnostics: diagnostics,
                    occlusionCorrection: assessment.occlusion.correction,
                    canopyGeometry: canopyGeometry
                ),
                assessment.countResult
            )
        }
    }

    /// 非成熟季节没有适用模型时返回可解释的人工复核结果。
    static func makeUncalibratedSeasonResult(
        input: ScanFusionYieldBuilder.Input
    ) -> (YieldResult, FruitCountResult) {
        var diagnostics = ScanFusionDiagnosticsUpdater.makeInitialDiagnostics(input: input)
        let assessment = YieldAssessmentEvaluator.assessUncalibratedSeason(
            points: input.points, defaultCategory: input.fruitCategory ?? .apple
        )
        ScanFusionDiagnosticsUpdater.applyCanopy(assessment.canopyGeometry, to: &diagnostics)
        diagnostics.zeroYieldReasons = ScanDiagnosticsBuilder.zeroYieldReasonDescriptions([assessment.reason])

        var result = YieldResult()
        result.yieldFinalKg = assessment.finalYieldKg
        result.confidence = "manual_review"
        result.methodUsed = "crown_untrained"
        result.note = diagnostics.zeroYieldReasons[0]
        result.pointCloudSize = input.points.count
        result.fruitCategory = input.fruitCategory?.displayName ?? input.fruitType
        result.colorFilterDesc = "N/A"
        ScanFusionDiagnosticsUpdater.applyCanopyGeometry(assessment.canopyGeometry, to: &result)
        result.diagnostics = diagnostics
        return (result, assessment.countResult)
    }

    private func makeVisibleYieldResult(
        input: ScanFusionYieldBuilder.Input,
        diagnostics: ScanYieldDiagnostics,
        assessment: YieldAssessment,
        visible: VisibleYieldAssessment,
        canopyGeometry: CanopyGeometryEstimate?
    ) -> YieldResult {
        let calibration = input.calibrationCorrection
        let occlusion = assessment.occlusion
        let visibleYieldEstimate = assessment.visibleYield
        var result = YieldResult()
        result.nLidar = visible.calibratedCount
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
        result.calibrationBaseYieldKg = visible.calibrationBaseYieldKg
        result.correctionK = occlusion.correction
        result.yieldFinalKg = visible.finalYieldKg
        result.yieldBVisibleKg = visibleYieldEstimate.yieldKg
        result.yieldBCorrectedKg = visible.finalYieldKg
        result.meanDiameterCm = visibleYieldEstimate.meanDiameterCm
        result.meanVolumeCm3 = visibleYieldEstimate.meanVolumeCm3
        result.confidence = visible.confidence
        result.methodUsed = visible.methodUsed
        var note = visible.sourceDescription
        note += visible.noteSuffix
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
        result.validatedFruits = assessment.validatedFruits.map { ValidatedFruitData(from: $0) }
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
