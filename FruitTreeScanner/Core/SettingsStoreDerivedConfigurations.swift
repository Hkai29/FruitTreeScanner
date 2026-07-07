// SettingsStoreDerivedConfigurations.swift
// Derived scanner and clustering configs backed by SettingsStore values.

import Foundation

extension SettingsStore {
    var fruitScanConfig: FruitScanConfig {
        let baseConfidence = Float(minConfidence)
        let baseSphericity = Float(sphericityThreshold)

        let (presetConfidence, presetSphericity): (Float, Float)
        switch qualityPreset {
        case "高":
            presetConfidence = max(baseConfidence, 0.7)
            presetSphericity = max(baseSphericity, 0.6)
        case "中":
            presetConfidence = baseConfidence
            presetSphericity = baseSphericity
        case "低":
            presetConfidence = min(baseConfidence, 0.3)
            presetSphericity = min(baseSphericity, 0.4)
        default:
            presetConfidence = baseConfidence
            presetSphericity = baseSphericity
        }

        let detectionIntervalFromFps: Int
        switch cameraFrameRate {
        case "30fps": detectionIntervalFromFps = 8
        case "120fps": detectionIntervalFromFps = 24
        default: detectionIntervalFromFps = 12
        }

        return FruitScanConfig(
            imageDetectionInterval: detectionIntervalFromFps,
            minConfidence: presetConfidence,
            sizeTolerance: 0.2,
            sphericityThreshold: presetSphericity
        )
    }

    var clusterConfig: ClusterConfig {
        let mappedBaseEps = Float(scanPrecision)

        let (presetMinPoints, presetMaxDiameter): (Int, Float)
        switch qualityPreset {
        case "高":
            presetMinPoints = max(clusterMinPoints - 2, 3)
            presetMaxDiameter = Float(clusterMaxDiameter)
        case "中":
            presetMinPoints = clusterMinPoints
            presetMaxDiameter = Float(clusterMaxDiameter)
        case "低":
            presetMinPoints = clusterMinPoints + 3
            presetMaxDiameter = Float(clusterMaxDiameter) * 1.2
        default:
            presetMinPoints = clusterMinPoints
            presetMaxDiameter = Float(clusterMaxDiameter)
        }

        return ClusterConfig(
            minPoints: presetMinPoints,
            minDiameter: Float(clusterMinDiameter),
            maxDiameter: presetMaxDiameter,
            baseEps: max(mappedBaseEps, 0.001)
        )
    }

    func clusterConfig(for params: FruitVarietyParams) -> ClusterConfig {
        let precisionScale = Float(scanPrecision / 0.01)
        let baseEps = Self.clampFinite(
            Double(params.clusterEps * precisionScale),
            min: 0.001,
            max: 0.50,
            fallback: Double(params.clusterEps)
        )

        let (presetMinPoints, maxDiameterScale, sphericity): (Int, Float, Float)
        switch qualityPreset {
        case "高":
            presetMinPoints = max(clusterMinPoints - 2, 3)
            maxDiameterScale = 1.0
            sphericity = max(params.sphericityThreshold, 0.6)
        case "低":
            presetMinPoints = clusterMinPoints + 3
            maxDiameterScale = 1.2
            sphericity = min(params.sphericityThreshold, 0.4)
        default:
            presetMinPoints = clusterMinPoints
            maxDiameterScale = 1.0
            sphericity = params.sphericityThreshold
        }

        return ClusterConfig(
            minPoints: presetMinPoints,
            minDiameter: params.diamMin,
            maxDiameter: params.diamMax * maxDiameterScale,
            baseEps: Float(baseEps),
            sphericityThreshold: sphericity
        )
    }
}
