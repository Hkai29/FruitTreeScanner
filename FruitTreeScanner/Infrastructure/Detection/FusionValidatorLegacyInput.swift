import CoreGraphics
import Foundation
@preconcurrency import CoreVideo
import simd

// Compatibility adapters reduce legacy buffer input before entering the numeric core.
extension FusionValidator {
    func validate(
        detections: [DetectedFruit],
        candidates: [FruitCandidate],
        depthMap: CVPixelBuffer?,
        depthConfidenceMap: CVPixelBuffer? = nil,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> [ValidatedFruit] {
        let observations = detections.map { detection in
            Observation.capture(
                id: detection.id,
                frameID: detection.observation?.frameID ?? FrameID(),
                category: detection.category,
                boundingBox: detection.boundingBox,
                confidence: detection.confidence,
                timestamp: detection.timestamp,
                cameraTransform: detection.cameraTransform ?? cameraTransform,
                cameraIntrinsics: detection.cameraIntrinsics ?? cameraIntrinsics,
                imageSize: detection.imageSize ?? imageSize,
                depthMap: depthMap,
                depthConfidenceMap: depthConfidenceMap,
                depthConfidenceProvenance: detection.depthConfidenceProvenance
            )
        }
        return validate(observations: observations, candidates: candidates)
    }

    /// Validates live scan detections only when each one carries the depth map
    /// captured with its RGB frame. This avoids projecting old detections
    /// through a later ARFrame's depth map after the operator has moved.
    func validate(
        detections: [DetectedFruit],
        candidates: [FruitCandidate]
    ) -> [ValidatedFruit] {
        let alignedObservations = detections
            .filter(\.hasAlignedDepthContext)
            .map { $0.resolvedObservation() }
        return validate(observations: alignedObservations, candidates: candidates)
    }

    /// 供诊断和可视化使用的兼容入口；缺少深度时允许固定距离回退。
    func projectDetectionTo3D(
        detection: DetectedFruit,
        depthMap: CVPixelBuffer?,
        depthConfidenceMap: CVPixelBuffer? = nil,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> SIMD3<Float> {
        let observation = Observation.capture(
            id: detection.id,
            frameID: detection.observation?.frameID ?? FrameID(),
            category: detection.category,
            boundingBox: detection.boundingBox,
            confidence: detection.confidence,
            timestamp: detection.timestamp,
            cameraTransform: detection.cameraTransform ?? cameraTransform,
            cameraIntrinsics: detection.cameraIntrinsics ?? cameraIntrinsics,
            imageSize: detection.imageSize ?? imageSize,
            depthMap: depthMap,
            depthConfidenceMap: depthConfidenceMap,
            depthConfidenceProvenance: detection.depthConfidenceProvenance
        )
        return ObservationProjection.projectObservationTo3D(
            detection: observation,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize,
            fallbackDepth: 2.0
        ) ?? SIMD3<Float>(0, 0, -2)
    }

    /// 可靠融合入口；只有取得有效深度时才返回三维位置。
    func projectDetectionTo3DWithValidDepth(
        detection: DetectedFruit,
        depthMap: CVPixelBuffer?,
        depthConfidenceMap: CVPixelBuffer? = nil,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> SIMD3<Float>? {
        // 可靠融合路径不允许固定深度回退；有效深度不足时必须返回 nil。
        let observation = Observation.capture(
            id: detection.id,
            frameID: detection.observation?.frameID ?? FrameID(),
            category: detection.category,
            boundingBox: detection.boundingBox,
            confidence: detection.confidence,
            timestamp: detection.timestamp,
            cameraTransform: detection.cameraTransform ?? cameraTransform,
            cameraIntrinsics: detection.cameraIntrinsics ?? cameraIntrinsics,
            imageSize: detection.imageSize ?? imageSize,
            depthMap: depthMap,
            depthConfidenceMap: depthConfidenceMap,
            depthConfidenceProvenance: detection.depthConfidenceProvenance
        )
        return ObservationProjection.projectObservationTo3D(
            detection: observation,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize,
            fallbackDepth: nil
        )
    }

}

extension DetectionDepthCandidateBuilder {
    /// 为每个二维检测框构造带深度支持的三维候选；失败的框直接留在诊断链路。
    static func makeCandidates(
        from detections: [DetectedFruit],
        clusterConfig: ClusterConfig
    ) -> [FruitCandidate] {
        // 每个候选必须来自检测框内的同帧深度和相机位姿。
        makeCandidates(from: detections.map { $0.resolvedObservation() }, clusterConfig: clusterConfig)
    }

}
