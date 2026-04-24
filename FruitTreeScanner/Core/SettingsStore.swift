// SettingsStore.swift
// 统一管理所有扫描参数，通过 UserDefaults 持久化

import Foundation

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    private init() {}

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

    var enableCloudSync: Bool {
        get { defaults.object(forKey: Keys.enableCloudSync) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.enableCloudSync) }
    }

    var wifiOnlyUpload: Bool {
        get { defaults.object(forKey: Keys.wifiOnlyUpload) as? Bool ?? true }
        set { defaults.set(newValue, forKey: Keys.wifiOnlyUpload) }
    }

    var autoExportCSV: Bool {
        get { defaults.object(forKey: Keys.autoExportCSV) as? Bool ?? false }
        set { defaults.set(newValue, forKey: Keys.autoExportCSV) }
    }

    // MARK: - 派生配置
    var fruitScanConfig: FruitScanConfig {
        FruitScanConfig(
            imageDetectionInterval: detectionInterval,
            minConfidence: Float(minConfidence),
            sizeTolerance: 0.2,
            sphericityThreshold: Float(sphericityThreshold)
        )
    }

    var clusterConfig: ClusterConfig {
        ClusterConfig(
            minPoints: clusterMinPoints,
            minDiameter: Float(clusterMinDiameter),
            maxDiameter: Float(clusterMaxDiameter),
            baseEps: Float(clusterBaseEps)
        )
    }
}
