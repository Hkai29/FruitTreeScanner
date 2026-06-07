import Foundation

struct RendererScanSettings {
    let maxPoints: Int
    let rgbRadius: Float
    let minDepth: Float
    let maxDepth: Float
    let confidenceThreshold: Int
    let depthEdgeThreshold: Float
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

        switch store.qualityPreset {
        case "高":
            confidenceThreshold = max(store.confidenceThreshold, 2)
            depthEdgeThreshold = 0.08
        case "低":
            confidenceThreshold = max(store.confidenceThreshold, 1)
            depthEdgeThreshold = 0.16
        default:
            confidenceThreshold = max(store.confidenceThreshold, 1)
            depthEdgeThreshold = 0.12
        }
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
