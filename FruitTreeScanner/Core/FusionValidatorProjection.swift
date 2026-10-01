import CoreGraphics
import simd

// Source-compatible projection entry points. Production numeric consumers use
// ObservationProjection directly; buffer adapters live in Infrastructure.
extension FusionValidator {
    static func robustDepth(from rawDepths: [Float]) -> Float? {
        ObservationProjection.robustDepth(from: rawDepths)
    }

    static func projectWorldPointToNormalizedImage(
        _ worldPoint: SIMD3<Float>, cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4, imageSize: CGSize
    ) -> CGPoint? {
        ObservationProjection.projectWorldPointToNormalizedImage(worldPoint,
            cameraIntrinsics: cameraIntrinsics, cameraTransform: cameraTransform, imageSize: imageSize)
    }

    static func depthSamplePoint(normalizedPoint: CGPoint, imageSize: CGSize, depthSize: CGSize) -> CGPoint {
        ObservationProjection.depthSamplePoint(normalizedPoint: normalizedPoint, imageSize: imageSize, depthSize: depthSize)
    }

    static func cameraPointFromImagePoint(
        _ imagePoint: SIMD3<Float>, depth: Float, cameraIntrinsics: matrix_float3x3
    ) -> SIMD3<Float>? {
        ObservationProjection.cameraPointFromImagePoint(imagePoint, depth: depth, cameraIntrinsics: cameraIntrinsics)
    }

    func projectObservationTo3D(
        detection: Observation, cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4, imageSize: CGSize, fallbackDepth: Float?
    ) -> SIMD3<Float>? {
        ObservationProjection.projectObservationTo3D(detection: detection,
            cameraIntrinsics: cameraIntrinsics, cameraTransform: cameraTransform,
            imageSize: imageSize, fallbackDepth: fallbackDepth)
    }
}
