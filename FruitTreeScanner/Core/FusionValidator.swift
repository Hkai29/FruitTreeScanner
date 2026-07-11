// FusionValidator.swift
// 图像检测 ↔ 点云聚类融合验证

import CoreGraphics
import Foundation
@preconcurrency import CoreVideo
import simd

// MARK: - Fusion Validator

final class FusionValidator: Sendable {

    // MARK: - Properties

    let config: FruitScanConfig

    // MARK: - Initialization

    init(config: FruitScanConfig = .default) {
        self.config = config
    }

    // MARK: - Validation

    func validate(
        detections: [DetectedFruit],
        candidates: [FruitCandidate],
        depthMap: CVPixelBuffer?,
        depthConfidenceMap: CVPixelBuffer? = nil,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> [ValidatedFruit] {
        validate(detections: detections, candidates: candidates) { detection in
            guard detection.depthConfidenceProvenance != .copyFailed else { return nil }
            return FusionProjectionContext(
                depthMap: depthMap,
                depthConfidenceMap: depthConfidenceMap,
                cameraIntrinsics: detection.cameraIntrinsics ?? cameraIntrinsics,
                cameraTransform: detection.cameraTransform ?? cameraTransform,
                imageSize: detection.imageSize ?? imageSize
            )
        }
    }

    /// Validates live scan detections only when each one carries the depth map
    /// captured with its RGB frame. This avoids projecting old detections
    /// through a later ARFrame's depth map after the operator has moved.
    func validate(
        detections: [DetectedFruit],
        candidates: [FruitCandidate]
    ) -> [ValidatedFruit] {
        validate(detections: detections, candidates: candidates) { detection in
            guard detection.hasAlignedDepthContext,
                  let depthMap = detection.depthMap,
                  let cameraIntrinsics = detection.cameraIntrinsics,
                  let cameraTransform = detection.cameraTransform,
                  let imageSize = detection.imageSize
            else {
                return nil
            }
            return FusionProjectionContext(
                depthMap: depthMap,
                depthConfidenceMap: detection.depthConfidenceMap,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            )
        }
    }

    private func validate(
        detections: [DetectedFruit],
        candidates: [FruitCandidate],
        projectionContext: (DetectedFruit) -> FusionProjectionContext?
    ) -> [ValidatedFruit] {
        let projectionService = DepthProjectionService(validator: self)
        let candidateMatcher = CandidateMatcher(validator: self)
        let decisionPolicy = FusionDecisionPolicy()
        var validatedFruits: [ValidatedFruit] = []
        var usedCandidateIDs = Set<UUID>()

        for detection in detections {
            guard let context = projectionContext(detection) else { continue }

            let projection = projectionService.project(
                detection: detection,
                context: context
            )

            let availableCandidates = candidates.filter { !usedCandidateIDs.contains($0.id) }
            let matchedCandidate = candidateMatcher.nearestCandidate(
                position: projection.depthProjectedPosition,
                candidates: availableCandidates,
                detection: detection,
                context: context
            )
            let rejectedByDepthCandidate = projection.depthProjectedPosition.map { depthProjectedPosition in
                candidateMatcher.hasRejectedDetectionDepthCandidate(
                    near: depthProjectedPosition,
                    candidates: availableCandidates,
                    detection: detection,
                    context: context
                )
            } ?? false

            switch decisionPolicy.decide(
                detection: detection,
                projectedPosition: projection.projectedPosition,
                matchedCandidate: matchedCandidate,
                rejectedByDepthCandidate: rejectedByDepthCandidate
            ) {
            case let .fused(candidate):
                usedCandidateIDs.insert(candidate.id)
                let validatedFruit = ValidatedFruit(
                    category: detection.category,
                    position: candidate.position,
                    confidence: decisionPolicy.fusedConfidence(detection: detection, candidate: candidate),
                    source: .fused
                )
                validatedFruits.append(validatedFruit)
            case let .imageOnly(position):
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
