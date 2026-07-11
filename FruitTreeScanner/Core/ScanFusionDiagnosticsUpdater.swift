enum ScanFusionDiagnosticsUpdater {
    static func makeInitialDiagnostics(input: ScanFusionYieldBuilder.Input) -> ScanYieldDiagnostics {
        var diagnostics = ScanDiagnosticsBuilder.makeDiagnostics(
            pointCloudPointCount: input.points.count,
            depthAvailable: input.savedDetections.contains { $0.hasAlignedDepthContext },
            imageDiagnostics: input.imageDiagnostics
        )
        diagnostics.imageDetectionCount = input.savedDetections.count
        if let verification = input.categoryVerification {
            diagnostics.selectedCategory = verification.selectedCategory.rawValue
            diagnostics.detectedCategoryCounts = verification.detectedCategoryCounts
            diagnostics.nonTargetDetectionCount = verification.nonTargetDetectionCount
            diagnostics.dominantNonTargetCategory = verification.dominantNonTargetCategory?.rawValue ?? ""
            diagnostics.categoryMismatchDetected = verification.categoryMismatchDetected
            diagnostics.automaticSuggestionCategory = verification.automaticSuggestion?.category.rawValue ?? ""
            diagnostics.automaticSuggestionConfidence = verification.automaticSuggestion?.confidence ?? 0
            diagnostics.automaticSuggestionFrameCount = verification.automaticSuggestion?.supportingFrameCount ?? 0
        }
        if input.savedDetections.contains(where: { $0.depthConfidenceProvenance == .copyFailed }) {
            diagnostics.depthConfidenceFailureReason = DepthConfidenceProvenance.copyFailureReason
        }
        return diagnostics
    }

    static func applyCalibration(
        _ calibration: YieldCalibrationCorrection,
        to diagnostics: inout ScanYieldDiagnostics
    ) {
        diagnostics.localCalibrationCountFactor = calibration.countFactor
        diagnostics.localCalibrationYieldFactor = calibration.yieldFactor
        diagnostics.localCalibrationCountSampleCount = calibration.countSampleCount
        diagnostics.localCalibrationYieldSampleCount = calibration.yieldSampleCount
    }

    static func applyCanopy(
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

    static func applyPointCloudOutput(
        _ output: PointCloudCandidatePipelineOutput,
        to diagnostics: inout ScanYieldDiagnostics
    ) {
        diagnostics.pointCloudColorFilteredCount = output.colorFilteredPoints.count
        diagnostics.pointCloudDenoisedPointCount = output.denoising.stats.retainedCount
        diagnostics.pointCloudOutlierPointCount = output.denoising.stats.removedCount
        diagnostics.pointCloudOutlierRatio = output.denoising.stats.removalRatio
        diagnostics.pointCloudClusterCandidateCount = output.candidates.count
    }

    static func applyDetectionDepthOutput(
        _ output: DetectionDepthCandidatePipelineOutput,
        combinedCandidateCount: Int,
        to diagnostics: inout ScanYieldDiagnostics
    ) {
        diagnostics.detectionDepthCandidateCount = output.candidates.count
        diagnostics.detectionDepthSupportRatio = CandidateCombiner.averageDepthSupportRatio(output.candidates)
        diagnostics.pointCloudCandidateCount = combinedCandidateCount
    }

    static func applyFusionOutput(
        _ output: FusionEvidencePipelineOutput,
        to diagnostics: inout ScanYieldDiagnostics
    ) {
        diagnostics.cloudOnlyConservativeMode = output.cloudOnlyConservativeMode
        diagnostics.deduplicatedImageDetectionCount = output.deduplicatedDetectionCount
        diagnostics.fusedFruitCount = output.validatedFruits.count
        applyValidationSourceDiagnostics(output.validatedFruits, to: &diagnostics)
        diagnostics.validationSourceReliability = validationSourceReliability(output.validatedFruits)
    }

    static func applyOcclusion(
        _ occlusion: YieldResultComposer.OcclusionCorrection,
        to diagnostics: inout ScanYieldDiagnostics
    ) {
        diagnostics.pointCloudAngleCoverage = occlusion.pointAngleCoverage
        diagnostics.cameraAngleCoverage = occlusion.cameraAngleCoverage
        diagnostics.scanAngleCoverage = occlusion.scanAngleCoverage
    }

    static func applyCanopyGeometry(
        _ canopyGeometry: CanopyGeometryEstimate?,
        to result: inout YieldResult
    ) {
        guard let canopyGeometry else { return }
        result.treeHeightM = canopyGeometry.treeHeightM
        result.crownVolM3 = canopyGeometry.crownVolumeM3
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
}
