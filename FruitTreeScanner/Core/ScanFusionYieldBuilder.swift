import Foundation
import os

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
            return YieldResultComposer.makeUncalibratedSeasonResult(input: input)
        }

        var diagnostics = ScanFusionDiagnosticsUpdater.makeInitialDiagnostics(input: input)
        ScanFusionDiagnosticsUpdater.applyCalibration(input.calibrationCorrection, to: &diagnostics)

        let canopyGeometry = CanopyGeometryEstimator.estimate(points: input.points)
        ScanFusionDiagnosticsUpdater.applyCanopy(canopyGeometry, to: &diagnostics)

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

        let targetDetections = ScanFusionCategoryFilter.detections(
            input.savedDetections,
            targetCategory: input.fruitCategory
        )
        let fusionOutput = FusionEvidencePipeline(fusionConfig: input.fusionConfig).run(
            detections: targetDetections,
            candidates: candidates
        )
        ScanFusionDiagnosticsUpdater.applyFusionOutput(fusionOutput, to: &diagnostics)

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
