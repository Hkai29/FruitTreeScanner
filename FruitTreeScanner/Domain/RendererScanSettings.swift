import Foundation

struct RendererScanSettings: Equatable, Sendable {
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
