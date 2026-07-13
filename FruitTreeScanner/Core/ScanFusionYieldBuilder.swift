import Foundation
import os

enum ScanFusionYieldBuilder {
    /// 一次估算所需的不可变扫描快照，避免后台任务读取活动采集状态。
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
        var categoryVerification: FruitCategoryVerificationSummary? = nil
    }

    static func build(from input: Input) async -> (YieldResult, FruitCountResult) {
        // 未标定季节在进入聚类和融合前直接返回人工复核结果。
        guard input.season.supportsYieldEstimation else {
            return YieldResultComposer.makeUncalibratedSeasonResult(input: input)
        }

        var diagnostics = ScanFusionDiagnosticsUpdater.makeInitialDiagnostics(input: input)
        ScanFusionDiagnosticsUpdater.applyCalibration(input.calibrationCorrection, to: &diagnostics)

        let canopyGeometry = CanopyGeometryEstimator.estimate(points: input.points)
        ScanFusionDiagnosticsUpdater.applyCanopy(canopyGeometry, to: &diagnostics)

        // 点云与检测深度分支独立构造候选，随后统一合并证据。
        let pointCloudOutput = await PointCloudCandidatePipeline().run(input)
        ScanFusionDiagnosticsUpdater.applyPointCloudOutput(pointCloudOutput, to: &diagnostics)

        let detectionDepthOutput = DetectionDepthCandidatePipeline().run(input)
        let candidates = CandidateCombiner.combine(
            pointCloudCandidates: pointCloudOutput.candidates,
            detectionDepthCandidates: detectionDepthOutput.fusionCandidates
        )
        ScanFusionDiagnosticsUpdater.applyDetectionDepthOutput(
            detectionDepthOutput,
            combinedCandidateCount: candidates.count,
            to: &diagnostics
        )

        Log.fusion.info("Clustering: \(input.points.count) raw points / \(pointCloudOutput.colorFilteredPoints.count) color-filtered / \(pointCloudOutput.denoising.stats.retainedCount) SOR-retained → \(pointCloudOutput.candidates.count) cloud candidates + \(detectionDepthOutput.rawCandidates.count) ROI-depth observations / \(detectionDepthOutput.candidates.count) merged ROI-depth candidates")

        let detectionFilterResult = ScanFusionCategoryFilter.detectionFilterResult(
            input.savedDetections,
            targetCategory: input.fruitCategory
        )
        diagnostics.filteredBySelectedFruitTypeCount = detectionFilterResult.filteredBySelectedFruitTypeCount
        // FusionEvidencePipeline 是可靠产量的唯一准入边界。
        let fusionOutput = FusionEvidencePipeline(fusionConfig: input.fusionConfig).run(
            detections: detectionFilterResult.detections,
            candidates: candidates
        )
        ScanFusionDiagnosticsUpdater.applyFusionOutput(fusionOutput, to: &diagnostics)

        // 结果合成只负责计数、遮挡修正、校准和诊断落盘。
        return YieldResultComposer().compose(
            input: input,
            candidates: candidates,
            pointCloudOutput: pointCloudOutput,
            fusionOutput: fusionOutput,
            canopyGeometry: canopyGeometry,
            diagnostics: &diagnostics
        )
    }

    static func combineCandidates(
        pointCloudCandidates: [FruitCandidate],
        detectionDepthCandidates: [FruitCandidate]
    ) -> [FruitCandidate] {
        CandidateCombiner.combine(
            pointCloudCandidates: pointCloudCandidates,
            detectionDepthCandidates: detectionDepthCandidates
        )
    }
}
