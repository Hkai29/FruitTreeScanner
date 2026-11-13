import Foundation

struct RendererScanSettings: Equatable, Sendable, Codable {
    /// Matches the existing application capture limit; invalid explicit values
    /// must not overflow Metal allocation sizes or create an empty ring buffer.
    static func boundedParticleCapacity(_ requested: Int) -> Int {
        min(max(requested, 1), 3_000_000)
    }

    let maxPoints: Int
    let rgbRadius: Float
    let minDepth: Float
    let maxDepth: Float
    let confidenceThreshold: Int
    let depthEdgeThreshold: Float
    let minimumStableDepthNeighborCount: Int
    let snapshotVoxelSize: Float
    let depthConfiguration: DepthExperimentConfig

    static func reliableConfidenceThreshold(
        storedThreshold: Int,
        minimumReliableConfidence: UInt8 = FruitScanExperimentConfig.default.depth.minimumReliableConfidence
    ) -> Int {
        max(storedThreshold, max(Int(minimumReliableConfidence), 1))
    }
}
