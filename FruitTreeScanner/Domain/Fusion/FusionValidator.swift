// FusionValidator.swift
// 图像检测 ↔ 点云聚类融合验证

import CoreGraphics
import Foundation
import simd

// MARK: - Fusion Validator

/// 使用同帧 RGB、可靠深度与点云候选决定水果证据来源。
final class FusionValidator: Sendable {

    // MARK: - Properties

    let config: FruitScanConfig
    let experimentConfiguration: FusionExperimentConfig

    // MARK: - Initialization

    init(config: FruitScanConfig = .default, experimentConfiguration: FusionExperimentConfig = .default) {
        self.config = config
        self.experimentConfiguration = experimentConfiguration
    }

    // MARK: - Validation

    func validate(observations: [Observation], candidates: [FruitCandidate]) -> [ValidatedFruit] {
        let projectionService = DepthProjectionService()
        let candidateMatcher = CandidateMatcher(config: config, experimentConfiguration: experimentConfiguration)
        let decisionPolicy = FusionDecisionPolicy()
        var seenCandidateIDs = Set<UUID>()
        let matchingCandidates = candidates.filter { seenCandidateIDs.insert($0.id).inserted }
        var projections: [(detection: Observation, context: FusionProjectionContext, result: DepthProjectionResult)] = []
        projections.reserveCapacity(observations.count)
        for detection in observations {
            guard detection.depthConfidenceProvenance != .copyFailed,
                  let cameraIntrinsics = detection.cameraIntrinsics,
                  let cameraTransform = detection.cameraTransform,
                  let imageSize = detection.imageSize else { continue }
            let context = FusionProjectionContext(
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            )
            projections.append((detection, context, projectionService.project(detection: detection, context: context)))
        }

        var options: [FusionAssignment.Option] = []
        for (detectionIndex, item) in projections.enumerated() {
            guard let position = item.result.depthProjectedPosition else { continue }
            for (candidateIndex, candidate) in matchingCandidates.enumerated() {
                guard let score = candidateMatcher.matchScore(
                    position: position,
                    candidate: candidate,
                    detection: item.detection,
                    cameraIntrinsics: item.context.cameraIntrinsics,
                    cameraTransform: item.context.cameraTransform,
                    imageSize: item.context.imageSize
                ) else { continue }
                options.append(.init(detectionIndex: detectionIndex, candidateIndex: candidateIndex, score: score))
            }
        }
        let assignments = FusionAssignment.match(
            detectionCount: projections.count,
            candidateCount: matchingCandidates.count,
            options: options
        )
        var validatedFruits: [ValidatedFruit] = []
        for (detectionIndex, item) in projections.enumerated() {
            let detection = item.detection
            let matchedCandidate = assignments[detectionIndex].map { matchingCandidates[$0] }
            // 被深度规则否决的候选不能通过图像回退重新升级为 fused。
            let rejectedByDepthCandidate = item.result.depthProjectedPosition.map { depthProjectedPosition in
                candidateMatcher.hasRejectedDetectionDepthCandidate(
                    near: depthProjectedPosition,
                    candidates: candidates,
                    detection: detection,
                    context: item.context
                )
            } ?? false

            switch decisionPolicy.decide(
                projectedPosition: item.result.projectedPosition,
                matchedCandidate: matchedCandidate,
                rejectedByDepthCandidate: rejectedByDepthCandidate
            ) {
            case let .fused(candidate):
                // 只有决策策略明确返回 fused 的证据才进入可靠产量链路。
                let validatedFruit = ValidatedFruit(
                    category: detection.category,
                    position: candidate.position,
                    confidence: decisionPolicy.fusedConfidence(detection: detection, candidate: candidate),
                    source: .fused,
                    measuredDiameter: candidate.diameter,
                    sourceCandidateIDs: [candidate.id]
                )
                validatedFruits.append(validatedFruit)
            case let .imageOnly(position):
                // imageOnly 仅用于诊断和可视化，后续产量管线会继续过滤。
                let validatedFruit = ValidatedFruit(
                    category: detection.category,
                    position: position,
                    confidence: detection.confidence,
                    source: .imageOnly
                )
                validatedFruits.append(validatedFruit)
            case .rejected:
                continue
            }
        }

        return validatedFruits
    }

}
