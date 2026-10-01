import Foundation
import os

struct PointCloudCandidatePipelineOutput {
    let colorFilteredPoints: [ColoredPoint]
    let clusteringPoints: [ColoredPoint]
    let denoising: PointCloudDenoisingResult<ColoredPoint>
    let candidates: [FruitCandidate]
}

struct PointCloudCandidatePipeline {
    func run(_ input: ScanFusionYieldBuilder.Input) async -> PointCloudCandidatePipelineOutput {
        // 点云分支依次执行颜色筛选、离群点抑制和有界聚类。
        let colorFilteredPoints = Self.colorFilteredPoints(from: input)
        let denoising = Self.denoiseClusteringPoints(
            colorFilteredPoints,
            clusterConfig: input.clusterConfig,
            experimentConfig: input.experimentConfiguration.pointCloud
        )
        let clusteringPoints = denoising.samples
        let clusterer = PointCloudCluster(config: input.clusterConfig)
        let candidates = await clusterer.process(points: clusteringPoints)

        return PointCloudCandidatePipelineOutput(
            colorFilteredPoints: colorFilteredPoints,
            clusteringPoints: clusteringPoints,
            denoising: denoising,
            candidates: candidates
        )
    }

    private static func colorFilteredPoints(from input: ScanFusionYieldBuilder.Input) -> [ColoredPoint] {
        guard let filter = input.colorFilter ?? input.fruitCategory?.colorFilter else {
            return input.points
        }
        return input.points.filter { filter.matches(r: $0.r, g: $0.g, b: $0.b) }
    }

    private static func denoiseClusteringPoints(
        _ points: [ColoredPoint],
        clusterConfig: ClusterConfig,
        experimentConfig: PointCloudExperimentConfig
    ) -> PointCloudDenoisingResult<ColoredPoint> {
        // 小样本跳过去噪，避免邻域统计在点数不足时误删有效果实点。
        let minimumDenoisingPointCount = max(
            clusterConfig.minPoints * experimentConfig.denoisingMinPointMultiplier,
            experimentConfig.denoisingMinPointFloor
        )
        guard points.count >= minimumDenoisingPointCount else {
            return PointCloudDenoiser.unchangedResult(samples: points)
        }
        return PointCloudDenoiser.statisticalOutlierRemovalDetailed(
            samples: points,
            k: experimentConfig.denoisingNeighborCount,
            stdMultiplier: experimentConfig.denoisingStdMultiplier,
            position: { $0.pos }
        )
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

struct ReliableYieldEvidence: Sendable, Identifiable {
    fileprivate let fruit: ValidatedFruit

    fileprivate init?(admitted fruit: ValidatedFruit) {
        guard fruit.source == .fused else { return nil }
        self.fruit = fruit
    }

    var id: UUID { fruit.id }
    var validatedFruit: ValidatedFruit { fruit }
}

struct FusionEvidencePipelineOutput {
    let reliableEvidence: [ReliableYieldEvidence]
    let deduplicatedDetectionCount: Int
    let evidenceDetections: [Observation]
    let cloudOnlyConservativeMode: Bool

    /// Compatibility projection for diagnostics, display, and result encoding.
    var validatedFruits: [ValidatedFruit] { reliableEvidence.map(\.validatedFruit) }
}

struct FusionEvidencePipeline {
    let fusionConfig: FruitScanConfig
    var experimentConfiguration: FusionExperimentConfig = .default

    func run(
        detections: [DetectedFruit],
        candidates: [FruitCandidate]
    ) -> FusionEvidencePipelineOutput {
        run(observations: detections.map { $0.resolvedObservation() }, candidates: candidates)
    }

    func run(
        observations: [Observation],
        candidates: [FruitCandidate]
    ) -> FusionEvidencePipelineOutput {
        // 没有图像证据时保持 cloud-only 保守模式，不输出可靠产量。
        guard !observations.isEmpty else {
            return conservativeOutput()
        }

        // 仅同帧 RGB、深度、内参与位姿齐全的检测允许进入融合。
        let alignedObservations = observations.filter(\.hasAlignedDepthContext)
        guard !alignedObservations.isEmpty else {
            Log.fusion.warning("Skipping \(observations.count) image detections because none carried aligned depth context")
            return conservativeOutput()
        }

        // 跨帧稳定性过滤可排除单帧误检和短暂遮挡造成的跳变。
        let stableEvidenceDetections = DetectionDeduplicator.stableEvidenceDetections(
            observations: alignedObservations,
            minimumObservations: fusionConfig.minimumStableDetectionsForYield,
            minimumConfidence: fusionConfig.minConfidence,
            timeWindow: fusionConfig.stableDetectionTimeWindow
        )
        guard !stableEvidenceDetections.isEmpty else {
            return conservativeOutput()
        }

        let deduplicatedDetections = DetectionDeduplicator.deduplicate2D(
            observations: stableEvidenceDetections
        )
        let fusionValidator = FusionValidator(config: fusionConfig, experimentConfiguration: experimentConfiguration)
        let validationResults = fusionValidator.validate(
            observations: deduplicatedDetections,
            candidates: candidates
        )
        if validationResults.isEmpty {
            return conservativeOutput(deduplicatedDetectionCount: deduplicatedDetections.count)
        }

        // 先隔离唯一可靠的 fused 证据，再做三维去重，避免诊断候选占用可靠轨迹。
        let reliableFruits = ValidatedFruit.deduplicate3D(
            validationResults.filter { $0.source == .fused }
        )
        guard !reliableFruits.isEmpty else {
            return conservativeOutput(
                deduplicatedDetectionCount: deduplicatedDetections.count,
                evidenceDetections: stableEvidenceDetections
            )
        }

        return FusionEvidencePipelineOutput(
            reliableEvidence: reliableFruits.compactMap(ReliableYieldEvidence.init(admitted:)),
            deduplicatedDetectionCount: deduplicatedDetections.count,
            evidenceDetections: stableEvidenceDetections,
            cloudOnlyConservativeMode: false
        )
    }

    private func conservativeOutput(
        deduplicatedDetectionCount: Int = 0,
        evidenceDetections: [Observation] = []
    ) -> FusionEvidencePipelineOutput {
        // 保守输出保留诊断计数，但可靠水果集合必须为空。
        FusionEvidencePipelineOutput(
            reliableEvidence: [],
            deduplicatedDetectionCount: deduplicatedDetectionCount,
            evidenceDetections: evidenceDetections,
            cloudOnlyConservativeMode: true
        )
    }
}
