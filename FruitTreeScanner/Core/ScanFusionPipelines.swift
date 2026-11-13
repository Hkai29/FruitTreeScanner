import Foundation

extension PointCloudCandidatePipeline {
    func run(_ input: ScanFusionYieldBuilder.Input) async -> PointCloudCandidatePipelineOutput {
        await run(PointCloudCandidateInput(
            points: input.points,
            colorFilter: input.colorFilter ?? input.fruitCategory?.colorFilter,
            clusterConfig: input.clusterConfig,
            experimentConfiguration: input.experimentConfiguration.pointCloud
        ))
    }
}

struct DetectionDepthCandidatePipelineOutput {
    let rawCandidates: [FruitCandidate]
    let candidates: [FruitCandidate]
    let fusionCandidates: [FruitCandidate]
}

struct DetectionDepthCandidatePipeline {
    func run(_ input: ScanFusionYieldBuilder.Input) -> DetectionDepthCandidatePipelineOutput {
        // 深度候选先在检测框内构建，再去重并按本次扫描类别过滤。
        let rawCandidates = DetectionDepthCandidateBuilder.makeCandidates(
            from: input.observations,
            clusterConfig: input.clusterConfig
        )
        let candidates = CandidateCombiner.mergeDetectionDepthCandidates(
            rawCandidates,
            configuration: input.experimentConfiguration.candidateMerge
        )
        let fusionCandidates = ScanFusionCategoryFilter.candidates(
            candidates,
            targetCategory: input.fruitCategory
        )

        return DetectionDepthCandidatePipelineOutput(
            rawCandidates: rawCandidates,
            candidates: candidates,
            fusionCandidates: fusionCandidates
        )
    }
}

enum ScanFusionCategoryFilter {
    struct DetectionFilterResult<Detection> {
        let detections: [Detection]
        let filteredBySelectedFruitTypeCount: Int
    }

    static func detections(
        _ detections: [DetectedFruit],
        targetCategory: FruitCategory?
    ) -> [DetectedFruit] {
        detectionFilterResult(detections, targetCategory: targetCategory).detections
    }

    static func detectionFilterResult(
        _ detections: [DetectedFruit],
        targetCategory: FruitCategory?
    ) -> DetectionFilterResult<DetectedFruit> {
        filter(detections, targetCategory: targetCategory) { $0.category }
    }

    static func detections(
        _ detections: [Observation],
        targetCategory: FruitCategory?
    ) -> [Observation] {
        detectionFilterResult(detections, targetCategory: targetCategory).detections
    }

    static func detectionFilterResult(
        _ detections: [Observation],
        targetCategory: FruitCategory?
    ) -> DetectionFilterResult<Observation> {
        filter(detections, targetCategory: targetCategory) { $0.category }
    }

    private static func filter<Detection>(
        _ detections: [Detection],
        targetCategory: FruitCategory?,
        category: (Detection) -> FruitCategory
    ) -> DetectionFilterResult<Detection> {
        // 类别过滤发生在融合前，防止其他水果检测参与目标品类产量。
        guard let targetCategory else {
            return DetectionFilterResult(
                detections: detections,
                filteredBySelectedFruitTypeCount: 0
            )
        }
        let filtered = detections.filter { category($0) == targetCategory }
        return DetectionFilterResult(
            detections: filtered,
            filteredBySelectedFruitTypeCount: detections.count - filtered.count
        )
    }

    static func candidates(
        _ candidates: [FruitCandidate],
        targetCategory: FruitCategory?
    ) -> [FruitCandidate] {
        guard let targetCategory else { return candidates }
        return candidates.filter { candidate in
            candidate.sourceCategory == nil || candidate.sourceCategory == targetCategory
        }
    }
}
