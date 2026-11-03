import Foundation
import ARKit
import MetalKit

extension SettingsStore {
    @MainActor
    func rendererScanSettings() -> RendererScanSettings {
        RendererScanSettings(store: self, particleCapacity: maxPointCount)
    }
}

// Compatibility defaults stay at the mutable-settings boundary. Production
// MetalView passes the root provider's captured values to the designated init.
extension Renderer {
    @MainActor
    convenience init(session: ARSession, metalDevice: MTLDevice, renderDestination: MTKView) {
        self.init(session: session, metalDevice: metalDevice, renderDestination: renderDestination,
                  initialSettings: SettingsStore.shared.rendererScanSettings())
    }

    @MainActor
    func applyScanQualitySettings() {
        applyScanQualitySettings(SettingsStore.shared.rendererScanSettings())
    }
}

// Capture mutable application settings before constructing the immutable plan value.
extension RendererScanSettings {
    @MainActor
    init(store: SettingsStore, particleCapacity: Int, depthConfiguration: DepthExperimentConfig = .default) {
        let maxPoints = min(store.maxPointCount, particleCapacity)
        let rgbRadius = Float(store.rgbRadius)
        let minDepth = Float(store.depthRangeMin)
        let maxDepth = Float(store.depthRangeMax)
        let snapshotVoxelSize = Self.exportVoxelSize(
            scanPrecision: Float(store.scanPrecision),
            qualityPreset: store.qualityPreset
        )
        let depthConfig = depthConfiguration
        let confidenceThreshold = Self.reliableConfidenceThreshold(
            storedThreshold: store.confidenceThreshold,
            minimumReliableConfidence: depthConfig.reliableConfidence
        )
        let minimumStableDepthNeighborCount = min(
            max(depthConfig.minimumStableDepthNeighborCount, 0),
            4
        )

        let depthEdgeThreshold: Float
        switch store.qualityPreset {
        case "高":
            depthEdgeThreshold = 0.08
        case "低":
            depthEdgeThreshold = 0.16
        default:
            depthEdgeThreshold = 0.12
        }
        self.init(
            maxPoints: maxPoints,
            rgbRadius: rgbRadius,
            minDepth: minDepth,
            maxDepth: maxDepth,
            confidenceThreshold: confidenceThreshold,
            depthEdgeThreshold: depthEdgeThreshold,
            minimumStableDepthNeighborCount: minimumStableDepthNeighborCount,
            snapshotVoxelSize: snapshotVoxelSize,
            depthConfiguration: depthConfiguration
        )
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
