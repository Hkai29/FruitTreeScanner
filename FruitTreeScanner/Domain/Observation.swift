import CoreGraphics
import Foundation
import simd

enum DepthConfidenceProvenance: String, Sendable {
    case available
    case unavailable
    case copyFailed

    static let copyFailureReason = "Depth confidence unavailable because buffer copy failed"
}

struct FrameID: Hashable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

enum ObservationCoordinateConvention: String, Sendable {
    /// Vision normalized image coordinates: origin at lower-left, x right, y up.
    case visionNormalizedLowerLeft
    /// Camera space uses right, up, and backward as positive axes after projection.
    case arKitCameraRightUpBack
}

enum ObservationRejectionReason: String, Sendable {
    case missingDepthMap
    case missingCameraPose
    case missingCameraIntrinsics
    case invalidImageGeometry
    case invalidDepthBuffer
    case confidenceCopyFailed
    case noReliableDepthSamples
}

struct ObservationDepthSample: Sendable, Equatable {
    let normalizedImageX: Float
    let normalizedImageY: Float
    let depthMeters: Float
    let row: Int
    let column: Int
}

/// Checked, buffer-free evidence captured from one RGB/depth/pose frame.
/// The dense pixel buffers remain owned by FramePacket and are released after
/// inference has reduced the detection ROIs to these bounded samples.
struct Observation: Identifiable, Sendable {
    let id: UUID
    let frameID: FrameID
    let category: FruitCategory
    let boundingBox: CGRect
    let confidence: Float
    let timestamp: TimeInterval
    let cameraTransform: simd_float4x4?
    let cameraIntrinsics: simd_float3x3?
    let imageSize: CGSize?
    let coordinateConvention: ObservationCoordinateConvention
    let depthConfidenceProvenance: DepthConfidenceProvenance
    let hasDepthMap: Bool
    let roiDepthSamples: [ObservationDepthSample]
    let projectionDepthSamples: [Float]
    let rejectionReasons: [ObservationRejectionReason]

    var hasAlignedDepthContext: Bool {
        hasDepthMap
            && cameraTransform != nil
            && cameraIntrinsics != nil
            && imageSize != nil
            && depthConfidenceProvenance != .copyFailed
    }
}
