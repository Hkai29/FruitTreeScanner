import Foundation

/// Bounded, immutable scan input, independent of hardware buffers and files.
struct FinalPointCloud: Sendable {
    let identity: RendererSnapshotSignature
    let points: [ColoredPoint]
    let inputSampleCount: Int
    let retainedSampleCount: Int
    let buildDuration: TimeInterval
    let estimatedPeakPayloadBytes: Int
}
