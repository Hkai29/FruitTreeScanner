import CoreVideo
import Foundation
import os
import simd
import UIKit

struct ScanFusionFrameContext: @unchecked Sendable {
    let depthMap: CVPixelBuffer?
    let cameraIntrinsics: simd_float3x3
    let cameraTransform: simd_float4x4
    let imageSize: CGSize
}

enum ScanFusionYieldBuilder {
    struct Input: @unchecked Sendable {
        let points: [ColoredPoint]
        let savedDetections: [DetectedFruit]
        let imageDiagnostics: ImageDetectionDiagnostics
        let frameContext: ScanFusionFrameContext?
        let fruitType: String
        let fruitCategory: FruitCategory?
        let paramsSnapshot: [String: FruitVarietyParams]
        let defaultParams: FruitVarietyParams
        let clusterConfig: ClusterConfig
        let fusionConfig: FruitScanConfig
        let colorFilter: ColorFilter?
    }

    static func build(from input: Input) async -> (YieldResult, FruitCountResult) {
        var diagnostics = ScanDiagnosticsBuilder.makeDiagnostics(
            pointCloudPointCount: input.points.count,
            depthAvailable: input.frameContext?.depthMap != nil,
            imageDiagnostics: input.imageDiagnostics
        )
        diagnostics.imageDetectionCount = input.savedDetections.count

        let clusterer = PointCloudCluster(config: input.clusterConfig)
        let candidates = await clusterer.processInMemory(
            position: input.points.map { $0.pos },
            colors: input.points.map { SIMD3<Float>($0.r, $0.g, $0.b) }
        )
        diagnostics.pointCloudCandidateCount = candidates.count
        Log.fusion.info("Clustering: \(input.points.count) points → \(candidates.count) candidates")

        let fusion = makeValidatedFruits(
            detections: input.savedDetections,
            candidates: candidates,
            frameContext: input.frameContext,
            fusionConfig: input.fusionConfig,
            diagnostics: &diagnostics
        )
        diagnostics.deduplicatedImageDetectionCount = fusion.deduplicatedDetectionCount
        diagnostics.fusedFruitCount = fusion.validatedFruits.count

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
        let occlusion = makeOcclusionCorrection(
            points: input.points,
            visibleCountForCorrection: max(Int(visualCorrection.visibleCount.rounded()), fusion.validatedFruits.count),
            weightedVisibleCount: visualCorrection.visibleCount
        )

        if visualCorrection.visibleCount > 0 {
            return (
                makeVisibleYieldResult(
                    input: input,
                    diagnostics: diagnostics,
                    validatedFruits: fusion.validatedFruits,
                    visibleYieldEstimate: visibleYieldEstimate,
                    visualCorrection: visualCorrection,
                    occlusion: occlusion
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
                occlusionCorrection: occlusion.correction
            ),
            countResult
        )
    }

    private static func makeValidatedFruits(
        detections: [DetectedFruit],
        candidates: [FruitCandidate],
        frameContext: ScanFusionFrameContext?,
        fusionConfig: FruitScanConfig,
        diagnostics: inout ScanYieldDiagnostics
    ) -> (validatedFruits: [ValidatedFruit], deduplicatedDetectionCount: Int) {
        if !detections.isEmpty, let frameContext {
            let deduplicatedDetections = DetectionDeduplicator.deduplicate2D(detections)
            let fusionValidator = FusionValidator(config: fusionConfig)
            let fusedFruits = fusionValidator.validate(
                detections: deduplicatedDetections,
                candidates: candidates,
                depthMap: frameContext.depthMap,
                cameraIntrinsics: frameContext.cameraIntrinsics,
                cameraTransform: frameContext.cameraTransform,
                imageSize: frameContext.imageSize
            )
            return (ValidatedFruit.deduplicate3D(fusedFruits), deduplicatedDetections.count)
        }

        diagnostics.cloudOnlyConservativeMode = true
        guard detections.isEmpty else {
            return ([], 0)
        }

        let cloudOnlyFruits = candidates.compactMap { candidate -> ValidatedFruit? in
            guard candidate.sphericity > 0.7, candidate.hasFruitColor() else { return nil }
            return ValidatedFruit(
                category: nil,
                position: candidate.position,
                confidence: candidate.sphericity * 0.5,
                source: .cloudOnly
            )
        }
        return (cloudOnlyFruits, 0)
    }

    private static func makeOcclusionCorrection(
        points: [ColoredPoint],
        visibleCountForCorrection: Int,
        weightedVisibleCount: Float
    ) -> (correction: Float, correctedCount: Int) {
        let crownRadius = OcclusionCorrector.estimateCrownRadius(from: points)
        let crownDepth = OcclusionCorrector.estimateCrownDepth(from: points)
        let scanAngleCoverage = OcclusionCorrector.estimateScanAngleCoverage(from: points)
        let occlusionResult = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: visibleCountForCorrection,
            crownRadiusM: crownRadius,
            crownDepthM: crownDepth,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: scanAngleCoverage
        )
        return (occlusionResult.k, Int((weightedVisibleCount * occlusionResult.k).rounded()))
    }

    private static func makeVisibleYieldResult(
        input: Input,
        diagnostics: ScanYieldDiagnostics,
        validatedFruits: [ValidatedFruit],
        visibleYieldEstimate: ScanYieldEstimateHelpers.VisibleYieldEstimate,
        visualCorrection: ScanYieldEstimateHelpers.VisibleEstimateCorrection,
        occlusion: (correction: Float, correctedCount: Int)
    ) -> YieldResult {
        let yieldAfterOcclusion = visualCorrection.visibleYieldKg * occlusion.correction
        let estimateQuality = ScanYieldEstimateHelpers.estimateQuality(
            for: validatedFruits
        )

        var result = YieldResult()
        result.nLidar = occlusion.correctedCount
        result.correctionK = occlusion.correction
        result.yieldFinalKg = yieldAfterOcclusion
        result.yieldBVisibleKg = visualCorrection.visibleYieldKg
        result.yieldBCorrectedKg = yieldAfterOcclusion
        result.meanDiameterCm = visibleYieldEstimate.meanDiameterCm
        result.meanVolumeCm3 = visibleYieldEstimate.meanVolumeCm3
        result.confidence = estimateQuality.confidence
        result.methodUsed = estimateQuality.methodUsed
        result.note = visualCorrection.note.replacingOccurrences(
            of: "RGB+LiDAR 融合检测",
            with: estimateQuality.sourceDescription
        )
        result.pointCloudSize = input.points.count
        result.clusterEps = input.clusterConfig.baseEps
        result.clusterMinPoints = input.clusterConfig.minPoints
        result.fruitCategory = input.fruitCategory?.displayName ?? input.fruitType
        result.colorFilterDesc = (input.colorFilter ?? input.fruitCategory?.colorFilter)?.description ?? "N/A"
        result.occlusionK = occlusion.correction
        result.diagnostics = diagnostics
        result.fruitMassEstimates = visibleYieldEstimate.massEstimates
        return result
    }

    private static func makeZeroYieldResult(
        input: Input,
        diagnostics: ScanYieldDiagnostics,
        occlusionCorrection: Float
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
        result.diagnostics = diagnostics
        return result
    }
}
