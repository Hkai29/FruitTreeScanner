import Foundation

struct ReliableYieldEvidence: Sendable, Identifiable {
    fileprivate let fruit: ValidatedFruit

    fileprivate init?(admitted fruit: ValidatedFruit) {
        guard fruit.source == .fused else { return nil }
        self.fruit = fruit
    }

    var id: UUID { fruit.id }
    var validatedFruit: ValidatedFruit { fruit }
}

enum FusionEvidenceDiagnostic: Equatable, Sendable {
    case missingAlignedDepthContext(observationCount: Int)
}

struct FusionEvidencePipelineOutput {
    let reliableEvidence: [ReliableYieldEvidence]
    let deduplicatedDetectionCount: Int
    let evidenceDetections: [Observation]
    let cloudOnlyConservativeMode: Bool
    let diagnostic: FusionEvidenceDiagnostic?

    init(
        reliableEvidence: [ReliableYieldEvidence],
        deduplicatedDetectionCount: Int,
        evidenceDetections: [Observation],
        cloudOnlyConservativeMode: Bool,
        diagnostic: FusionEvidenceDiagnostic? = nil
    ) {
        self.reliableEvidence = reliableEvidence
        self.deduplicatedDetectionCount = deduplicatedDetectionCount
        self.evidenceDetections = evidenceDetections
        self.cloudOnlyConservativeMode = cloudOnlyConservativeMode
        self.diagnostic = diagnostic
    }

    /// Compatibility projection for diagnostics, display, and result encoding.
    var validatedFruits: [ValidatedFruit] { reliableEvidence.map(\.validatedFruit) }
}

struct FusionEvidencePipeline {
    let fusionConfig: FruitScanConfig
    var experimentConfiguration: FusionExperimentConfig = .default

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
            return conservativeOutput(
                diagnostic: .missingAlignedDepthContext(observationCount: observations.count)
            )
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
        evidenceDetections: [Observation] = [],
        diagnostic: FusionEvidenceDiagnostic? = nil
    ) -> FusionEvidencePipelineOutput {
        // 保守输出保留诊断计数，但可靠水果集合必须为空。
        FusionEvidencePipelineOutput(
            reliableEvidence: [],
            deduplicatedDetectionCount: deduplicatedDetectionCount,
            evidenceDetections: evidenceDetections,
            cloudOnlyConservativeMode: true,
            diagnostic: diagnostic
        )
    }
}
