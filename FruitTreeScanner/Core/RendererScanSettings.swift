import Foundation

struct RendererScanSettings {
    let maxPoints: Int
    let rgbRadius: Float
    let minDepth: Float
    let maxDepth: Float
    let confidenceThreshold: Int
    let depthEdgeThreshold: Float
    let minimumStableDepthNeighborCount: Int
    let snapshotVoxelSize: Float

    @MainActor
    init(store: SettingsStore, particleCapacity: Int) {
        maxPoints = min(store.maxPointCount, particleCapacity)
        rgbRadius = Float(store.rgbRadius)
        minDepth = Float(store.depthRangeMin)
        maxDepth = Float(store.depthRangeMax)
        snapshotVoxelSize = Self.exportVoxelSize(
            scanPrecision: Float(store.scanPrecision),
            qualityPreset: store.qualityPreset
        )
        let depthConfig = FruitScanExperimentConfig.default.depth
        confidenceThreshold = Self.reliableConfidenceThreshold(
            storedThreshold: store.confidenceThreshold,
            minimumReliableConfidence: depthConfig.minimumReliableConfidence
        )
        minimumStableDepthNeighborCount = min(
            max(depthConfig.minimumStableDepthNeighborCount, 0),
            4
        )

        switch store.qualityPreset {
        case "高":
            depthEdgeThreshold = 0.08
        case "低":
            depthEdgeThreshold = 0.16
        default:
            depthEdgeThreshold = 0.12
        }
    }

    static func reliableConfidenceThreshold(
        storedThreshold: Int,
        minimumReliableConfidence: UInt8 = FruitScanExperimentConfig.default.depth.minimumReliableConfidence
    ) -> Int {
        max(storedThreshold, Int(minimumReliableConfidence))
    }

    private static func exportVoxelSize(scanPrecision: Float, qualityPreset: String) -> Float {
        let clamped = min(max(scanPrecision, 0.001), 0.05)
        switch qualityPreset {
        case "高":
            return max(clamped * 0.7, 0.001)
        case "低":
            return min(clamped * 1.5, 0.06)
        default:
            return clamped
        }
    }
}
