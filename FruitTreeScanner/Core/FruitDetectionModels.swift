// FruitDetectionModels.swift
// 图像检测的旧缓冲输入与观测值兼容门面

import CoreGraphics
import Foundation
@preconcurrency import CoreVideo
import simd

// MARK: - 图像检测结果
/// A detection and the AR frame data required to place it in world space.
///
/// `depthMap` and `depthConfidenceMap` are private, copied buffers captured with
/// the RGB frame. Core Video buffers are not formally `Sendable`, but this value
/// never shares ARKit's reusable buffer pool across queues.
struct DetectedFruit: Identifiable, @unchecked Sendable {
    let id: UUID
    let category: FruitCategory
    let boundingBox: CGRect
    let confidence: Float
    let timestamp: TimeInterval
    let cameraTransform: simd_float4x4?
    let cameraIntrinsics: simd_float3x3?
    let imageSize: CGSize?
    private let legacyDepthMap: CVPixelBuffer?
    private let legacyDepthConfidenceMap: CVPixelBuffer?
    let depthConfidenceProvenance: DepthConfidenceProvenance
    let observation: Observation?

    var hasAlignedDepthContext: Bool {
        if let observation { return observation.hasAlignedDepthContext }
        return legacyDepthMap != nil
            && cameraTransform != nil
            && cameraIntrinsics != nil
            && imageSize != nil
            && depthConfidenceProvenance != .copyFailed
    }

    /// Converts the legacy facade into checked value evidence. Production
    /// detections already carry an Observation and do not retain pixel buffers.
    func resolvedObservation(frameID: FrameID = FrameID(), depthConfiguration: DepthExperimentConfig = .default) -> Observation {
        if let observation { return observation }
        return Observation.capture(
            id: id,
            frameID: frameID,
            category: category,
            boundingBox: boundingBox,
            confidence: confidence,
            timestamp: timestamp,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize,
            depthMap: legacyDepthMap,
            depthConfidenceMap: legacyDepthConfidenceMap,
            depthConfidenceProvenance: depthConfidenceProvenance,
            depthConfiguration: depthConfiguration
        )
    }

    init(observation: Observation) {
        self.id = observation.id
        self.category = observation.category
        self.boundingBox = observation.boundingBox
        self.confidence = observation.confidence
        self.timestamp = observation.timestamp
        self.cameraTransform = observation.cameraTransform
        self.cameraIntrinsics = observation.cameraIntrinsics
        self.imageSize = observation.imageSize
        self.legacyDepthMap = nil
        self.legacyDepthConfidenceMap = nil
        self.depthConfidenceProvenance = observation.depthConfidenceProvenance
        self.observation = observation
    }

    init(
        category: FruitCategory,
        boundingBox: CGRect,
        confidence: Float,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        cameraTransform: simd_float4x4? = nil,
        cameraIntrinsics: simd_float3x3? = nil,
        imageSize: CGSize? = nil,
        depthMap: CVPixelBuffer? = nil,
        depthConfidenceMap: CVPixelBuffer? = nil,
        depthConfidenceProvenance: DepthConfidenceProvenance? = nil
    ) {
        self.id = UUID()
        self.category = category
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.timestamp = timestamp
        self.cameraTransform = cameraTransform
        self.cameraIntrinsics = cameraIntrinsics
        self.imageSize = imageSize
        self.legacyDepthMap = depthMap
        self.legacyDepthConfidenceMap = depthConfidenceMap
        self.depthConfidenceProvenance = depthConfidenceProvenance
            ?? (depthConfidenceMap == nil ? .unavailable : .available)
        self.observation = nil
    }
}
