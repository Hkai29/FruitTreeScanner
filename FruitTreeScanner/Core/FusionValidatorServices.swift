import CoreGraphics
import Foundation
@preconcurrency import CoreVideo
import simd

struct FusionProjectionContext {
    let depthMap: CVPixelBuffer?
    let depthConfidenceMap: CVPixelBuffer?
    let cameraIntrinsics: matrix_float3x3
    let cameraTransform: simd_float4x4
    let imageSize: CGSize
}

struct DepthProjectionResult {
    let projectedPosition: SIMD3<Float>
    let depthProjectedPosition: SIMD3<Float>?
}

struct DepthProjectionService {
    let validator: FusionValidator

    func project(
        detection: DetectedFruit,
        context: FusionProjectionContext
    ) -> DepthProjectionResult {
        let projectedPosition = validator.projectDetectionTo3D(
            detection: detection,
            depthMap: context.depthMap,
            depthConfidenceMap: context.depthConfidenceMap,
            cameraIntrinsics: context.cameraIntrinsics,
            cameraTransform: context.cameraTransform,
            imageSize: context.imageSize
        )
        let depthProjectedPosition = validator.projectDetectionTo3DWithValidDepth(
            detection: detection,
            depthMap: context.depthMap,
            depthConfidenceMap: context.depthConfidenceMap,
            cameraIntrinsics: context.cameraIntrinsics,
            cameraTransform: context.cameraTransform,
            imageSize: context.imageSize
        )

        return DepthProjectionResult(
            projectedPosition: projectedPosition,
            depthProjectedPosition: depthProjectedPosition
        )
    }
}

struct CandidateMatcher {
    let validator: FusionValidator

    func nearestCandidate(
        position: SIMD3<Float>?,
        candidates: [FruitCandidate],
        detection: DetectedFruit,
        context: FusionProjectionContext
    ) -> FruitCandidate? {
        position.flatMap { projectedPosition in
            validator.findNearestCandidate(
                position: projectedPosition,
                candidates: candidates,
                detection: detection,
                cameraIntrinsics: context.cameraIntrinsics,
                cameraTransform: context.cameraTransform,
                imageSize: context.imageSize
            )
        }
    }

    func hasRejectedDetectionDepthCandidate(
        near projectedPosition: SIMD3<Float>,
        candidates: [FruitCandidate],
        detection: DetectedFruit,
        context: FusionProjectionContext
    ) -> Bool {
        let experimentConfig = FruitScanExperimentConfig.default.fusion
        let expandedBox = detection.boundingBox.insetBy(
            dx: -detection.boundingBox.width * CGFloat(experimentConfig.projectedBoxExpansionFraction),
            dy: -detection.boundingBox.height * CGFloat(experimentConfig.projectedBoxExpansionFraction)
        )

        return candidates.contains { candidate in
            guard candidate.sourceCategory == detection.category,
                  candidate.depthSupportRatio != nil else {
                return false
            }

            let distance = simd_distance(projectedPosition, candidate.position)
            let distanceThreshold = max(
                experimentConfig.rejectedDepthCandidateMinimumDistance,
                min(
                    candidate.diameter * experimentConfig.relaxedDistanceMultiplier,
                    experimentConfig.rejectedDepthCandidateMaximumDistance
                )
            )
            if distance <= distanceThreshold {
                return true
            }

            guard let projectedCandidate = FusionValidator.projectWorldPointToNormalizedImage(
                candidate.position,
                cameraIntrinsics: context.cameraIntrinsics,
                cameraTransform: context.cameraTransform,
                imageSize: context.imageSize
            ) else {
                return false
            }
            return expandedBox.contains(projectedCandidate)
        }
    }
}

enum FusionValidationDecision {
    case fused(FruitCandidate)
    case imageOnly(SIMD3<Float>)
    case rejected
}

struct FusionDecisionPolicy {
    func decide(
        detection: DetectedFruit,
        projectedPosition: SIMD3<Float>,
        matchedCandidate: FruitCandidate?,
        rejectedByDepthCandidate: Bool
    ) -> FusionValidationDecision {
        if let matchedCandidate {
            return .fused(matchedCandidate)
        }
        if rejectedByDepthCandidate {
            return .rejected
        }
        return .imageOnly(projectedPosition)
    }

    func fusedConfidence(detection: DetectedFruit, candidate: FruitCandidate) -> Float {
        let depthSupportQuality: Float
        if let depthSupportRatio = candidate.depthSupportRatio {
            let clampedRatio = min(max(depthSupportRatio, 0), 1)
            depthSupportQuality = 0.55 + clampedRatio * 0.45
        } else {
            depthSupportQuality = 1
        }
        return min(max(detection.confidence * candidate.sphericity * depthSupportQuality, 0), 1)
    }
}
