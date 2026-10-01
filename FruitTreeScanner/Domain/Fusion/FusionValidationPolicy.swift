import CoreGraphics
import Foundation
import simd

struct FusionProjectionContext: Sendable {
    let cameraIntrinsics: matrix_float3x3
    let cameraTransform: simd_float4x4
    let imageSize: CGSize
}

struct DepthProjectionResult: Sendable {
    let projectedPosition: SIMD3<Float>
    let depthProjectedPosition: SIMD3<Float>?
}

struct DepthProjectionService: Sendable {

    func project(
        detection: Observation,
        context: FusionProjectionContext
    ) -> DepthProjectionResult {
        let projectedPosition = ObservationProjection.projectObservationTo3D(
            detection: detection,
            cameraIntrinsics: context.cameraIntrinsics,
            cameraTransform: context.cameraTransform,
            imageSize: context.imageSize,
            fallbackDepth: 2.0
        ) ?? SIMD3<Float>(0, 0, -2)
        let depthProjectedPosition = detection.hasAlignedDepthContext
            ? ObservationProjection.projectObservationTo3D(
                detection: detection,
                cameraIntrinsics: context.cameraIntrinsics,
                cameraTransform: context.cameraTransform,
                imageSize: context.imageSize,
                fallbackDepth: nil
            )
            : nil

        return DepthProjectionResult(
            projectedPosition: projectedPosition,
            depthProjectedPosition: depthProjectedPosition
        )
    }
}

enum FusionValidationDecision: Sendable {
    case fused(FruitCandidate)
    case imageOnly(SIMD3<Float>)
    case rejected
}

struct FusionDecisionPolicy: Sendable {
    func decide(
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

    func fusedConfidence(detection: Observation, candidate: FruitCandidate) -> Float {
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
