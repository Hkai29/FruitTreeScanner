import Foundation

/// Value identity only; no dependency on Metal buffers or renderer lifetime.
/// The existing name remains source-compatible with renderer callers.
struct RendererSnapshotSignature: Equatable, Hashable, Sendable {
    let pointCount: Int
    let pointIndex: Int
    let voxelSize: Float
    let confidenceThreshold: Int
    let pointBufferRevision: UInt64
    let analysisInputSampleLimit: Int?

    init(pointCount: Int, pointIndex: Int, voxelSize: Float, confidenceThreshold: Int,
         pointBufferRevision: UInt64 = 0, analysisInputSampleLimit: Int? = nil) {
        self.pointCount = pointCount
        self.pointIndex = pointIndex
        self.voxelSize = voxelSize
        self.confidenceThreshold = confidenceThreshold
        self.pointBufferRevision = pointBufferRevision
        self.analysisInputSampleLimit = analysisInputSampleLimit
    }
}

struct ScanContext: Equatable, Sendable {
    let scanID: UUID
    let planID: UUID
}

/// Recorded when the point cloud is written, before observations are drained.
struct ScanCaptureIdentity: Equatable, Sendable {
    let context: ScanContext
    let pointCloud: RendererSnapshotSignature
}

/// An in-memory input identity. This does not replace the historical scanID
/// (file basename) stored in archive schemas 1–3.
struct ScanEvidenceIdentity: Equatable, Sendable {
    let capture: ScanCaptureIdentity
    let snapshotID: UUID
    let sourceOwnershipID: UUID
    let sourceSHA256: String
}

enum ScanEvidenceError: LocalizedError {
    case mismatchedInput

    var errorDescription: String? {
        "扫描、计划或冻结证据不匹配，不能保存当前估算结果。"
    }
}

struct ScanEstimate: Sendable {
    let evidenceIdentity: ScanEvidenceIdentity
    let result: YieldResult
}
