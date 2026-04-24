// SettingsStore.swift
// 统一管理所有扫描参数，通过 UserDefaults 持久化

import Foundation
import Combine
import SwiftUI

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    // MARK: - Keys
    private enum Keys {
        static let fruitType = "fruitType"
        static let season = "season"
        static let clusterMinPoints = "clusterMinPoints"
        static let clusterMinDiameter = "clusterMinDiameter"
        static let clusterMaxDiameter = "clusterMaxDiameter"
        static let clusterBaseEps = "clusterBaseEps"
        static let detectionInterval = "detectionInterval"
        static let minConfidence = "minConfidence"
        static let sphericityThreshold = "sphericityThreshold"
        static let depthRangeMin = "depthRangeMin"
        static let depthRangeMax = "depthRangeMax"
        static let rgbRadius = "rgbRadius"
        static let confidenceThreshold = "confidenceThreshold"
        static let enableLidar = "enableLidar"
        static let gpsUpdateRate = "gpsUpdateRate"
        static let autoSavePLY = "autoSavePLY"
        static let maxStorageMB = "maxStorageMB"
        static let enableCloudSync = "enableCloudSync"
        static let wifiOnlyUpload = "wifiOnlyUpload"
        static let autoExportCSV = "autoExportCSV"
        static let cameraResolution = "cameraResolution"
        static let cameraFrameRate = "cameraFrameRate"
        static let exportFormat = "exportFormat"
        static let qualityPreset = "qualityPreset"
        static let maxPointCount = "maxPointCount"
        static let scanPrecision = "scanPrecision"
        static let sensorCalibrationDone = "sensorCalibrationDone"
    }

    private init() {
        // 初始化所有 @Published 属性
        cloudSyncEnabled = (defaults.object(forKey: Keys.enableCloudSync) as? Bool) ?? false
        wifiOnlyUpload = (defaults.object(forKey: Keys.wifiOnlyUpload) as? Bool) ?? true
        autoExportCSV = (defaults.object(forKey: Keys.autoExportCSV) as? Bool) ?? false
        cameraResolution = defaults.string(forKey: Keys.cameraResolution) ?? "1080p"
        cameraFrameRate = defaults.string(forKey: Keys.cameraFrameRate) ?? "60fps"
        exportFormat = defaults.string(forKey: Keys.exportFormat) ?? "PLY"
        qualityPreset = defaults.string(forKey: Keys.qualityPreset) ?? "高"
        maxPointCount = (defaults.object(forKey: Keys.maxPointCount) as? Int) ?? 1000000
        scanPrecision = (defaults.object(forKey: Keys.scanPrecision) as? Double) ?? 0.01
        sensorCalibrationDone = (defaults.object(forKey: Keys.sensorCalibrationDone) as? Bool) ?? false
    }

    // MARK: - 水果参数
    var fruitType: String {
        get { defaults.string(forKey: Keys.fruitType) ?? "apple" }
        set { defaults.set(newValue, forKey: Keys.fruitType) }
    }

    var season: String {
        get { defaults.string(forKey: Keys.season) ?? "mature" }
        set { defaults.set(newValue, forKey: Keys.season) }
    }

    // MARK: - 聚类参数
    var clusterMinPoints: Int {
        get { defaults.object(forKey: Keys.clusterMinPoints) as? Int ?? 5 }
        set { defaults.set(newValue, forKey: Keys.clusterMinPoints) }
    }

    var clusterMinDiameter: Double {
        get { defaults.object(forKey: Keys.clusterMinDiameter) as? Double ?? 0.02 }
        set { defaults.set(newValue, forKey: Keys.clusterMinDiameter) }
    }

    var clusterMaxDiameter: Double {
        get { defaults.object(forKey: Keys.clusterMaxDiameter) as? Double ?? 0.15 }
        set { defaults.set(newValue, forKey: Keys.clusterMaxDiameter) }
    }

    var clusterBaseEps: Double {
        get { defaults.object(forKey: Keys.clusterBaseEps) as? Double ?? 0.1 }
        set { defaults.set(newValue, forKey: Keys.clusterBaseEps) }
    }

    // MARK: - 检测参数
    var detectionInterval: Int {
        get { defaults.object(forKey: Keys.detectionInterval) as? Int ?? 10 }
        set { defaults.set(newValue, forKey: Keys.detectionInterval) }
    }

    var minConfidence: Double {
        get { defaults.object(forKey: Keys.minConfidence) as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: Keys.minConfidence) }
    }

    var sphericityThreshold: Double {
        get { defaults.object(forKey: Keys.sphericityThreshold) as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: Keys.sphericityThreshold) }
    }

    // MARK: - 深度范围
    var depthRangeMin: Double {
        get { defaults.object(forKey: Keys.depthRangeMin) as? Double ?? 0.5 }
        set { defaults.set(newValue, forKey: Keys.depthRangeMin) }
    }

    var depthRangeMax: Double {
        get { defaults.object(forKey: Keys.depthRangeMax) as? Double ?? 5.0 }
        set { defaults.set(newValue, forKey: Keys.depthRangeMax) }
    }

    // MARK: - 设备参数
    var rgbRadius: Double {
        get { defaults.object(forKey: Keys.rgbRadius) as? Double ?? 3.0 }
        set { defaults.set(newValue, forKey: Keys.rgbRadius) }
    }

    var confidenceThreshold: Int {
        get { defaults.object(forKey: Keys.confidenceThreshold) as? Int ?? 1 }
        set { defaults.set(newValue, forKey: Keys.confidenceThreshold) }
    }

    var enableLidar: Bool {
        get { defaults.object(forKey: Keys.enableLidar) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.enableLidar) }
    }

    var gpsUpdateRate: Double {
        get { defaults.object(forKey: Keys.gpsUpdateRate) as? Double ?? 1.0 }
        set { defaults.set(newValue, forKey: Keys.gpsUpdateRate) }
    }

    // MARK: - 数据参数
    var autoSavePLY: Bool {
        get { defaults.object(forKey: Keys.autoSavePLY) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.autoSavePLY) }
    }

    var maxStorageMB: Int {
        get { defaults.object(forKey: Keys.maxStorageMB) as? Int ?? 500 }
        set { defaults.set(newValue, forKey: Keys.maxStorageMB) }
    }

    // MARK: - 设置页面 @Published 属性（支持 $ 绑定）
    @Published var cloudSyncEnabled: Bool
    @Published var wifiOnlyUpload: Bool
    @Published var autoExportCSV: Bool
    @Published var cameraResolution: String
    @Published var cameraFrameRate: String
    @Published var exportFormat: String
    @Published var qualityPreset: String
    @Published var maxPointCount: Int
    @Published var scanPrecision: Double
    @Published var sensorCalibrationDone: Bool

    // MARK: - Binding 访问器（供 SwiftUI $ 绑定语法使用）
    var cameraResolutionBinding: Binding<String> { Binding(
        get: { self.cameraResolution },
        set: { self.cameraResolution = $0 }
    ) }
    var cameraFrameRateBinding: Binding<String> { Binding(
        get: { self.cameraFrameRate },
        set: { self.cameraFrameRate = $0 }
    ) }
    var cloudSyncEnabledBinding: Binding<Bool> { Binding(
        get: { self.cloudSyncEnabled },
        set: { self.cloudSyncEnabled = $0 }
    ) }
    var wifiOnlyUploadBinding: Binding<Bool> { Binding(
        get: { self.wifiOnlyUpload },
        set: { self.wifiOnlyUpload = $0 }
    ) }
    var autoExportCSVBinding: Binding<Bool> { Binding(
        get: { self.autoExportCSV },
        set: { self.autoExportCSV = $0 }
    ) }
    var exportFormatBinding: Binding<String> { Binding(
        get: { self.exportFormat },
        set: { self.exportFormat = $0 }
    ) }
    var qualityPresetBinding: Binding<String> { Binding(
        get: { self.qualityPreset },
        set: { self.qualityPreset = $0 }
    ) }
    var maxPointCountBinding: Binding<Int> { Binding(
        get: { self.maxPointCount },
        set: { self.maxPointCount = $0 }
    ) }
    var scanPrecisionBinding: Binding<Double> { Binding(
        get: { self.scanPrecision },
        set: { self.scanPrecision = $0 }
    ) }
    var sensorCalibrationDoneBinding: Binding<Bool> { Binding(
        get: { self.sensorCalibrationDone },
        set: { self.sensorCalibrationDone = $0 }
    ) }

    // MARK: - 派生配置（融合 qualityPreset 和 scanPrecision）
    var fruitScanConfig: FruitScanConfig {
        // 基础参数可被用户调整，但受 qualityPreset 上下限约束
        let baseInterval = detectionInterval
        let baseConfidence = Float(minConfidence)
        let baseSphericity = Float(sphericityThreshold)

        // qualityPreset 覆盖：预设优先级最高
        let (presetInterval, presetConfidence, presetSphericity): (Int, Float, Float)
        switch qualityPreset {
        case "高":
            presetInterval = min(baseInterval, 5)
            presetConfidence = max(baseConfidence, 0.7)
            presetSphericity = max(baseSphericity, 0.6)
        case "中":
            presetInterval = baseInterval
            presetConfidence = baseConfidence
            presetSphericity = baseSphericity
        case "低":
            presetInterval = max(baseInterval, 20)
            presetConfidence = min(baseConfidence, 0.3)
            presetSphericity = min(baseSphericity, 0.4)
        default:
            presetInterval = baseInterval
            presetConfidence = baseConfidence
            presetSphericity = baseSphericity
        }

        return FruitScanConfig(
            imageDetectionInterval: presetInterval,
            minConfidence: presetConfidence,
            sizeTolerance: 0.2,
            sphericityThreshold: presetSphericity
        )
    }

    var clusterConfig: ClusterConfig {
        // scanPrecision 直接映射到 baseEps（精度越高 eps 越小）
        // scanPrecision 范围 0.001~0.05，对应精细~粗糙
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
}
