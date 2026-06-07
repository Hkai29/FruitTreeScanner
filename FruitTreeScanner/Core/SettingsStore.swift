// SettingsStore.swift
// 统一管理所有扫描参数，通过 UserDefaults 持久化

import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    static let cameraFrameRateOptions = ["30fps", "60fps", "120fps"]
    static let cameraResolutionOptions = ["720p", "1080p", "4K"]
    static let qualityPresetOptions = ["高", "中", "低"]

    // MARK: - Keys
    private enum Keys {
        static let fruitType = "fruitType"
        static let clusterMinPoints = "clusterMinPoints"
        static let clusterMinDiameter = "clusterMinDiameter"
        static let clusterMaxDiameter = "clusterMaxDiameter"
        static let minConfidence = "minConfidence"
        static let sphericityThreshold = "sphericityThreshold"
        static let depthRangeMin = "depthRangeMin"
        static let depthRangeMax = "depthRangeMax"
        static let rgbRadius = "rgbRadius"
        static let confidenceThreshold = "confidenceThreshold"
        static let autoExportCSV = "autoExportCSV"
        static let cameraResolution = "cameraResolution"
        static let cameraFrameRate = "cameraFrameRate"
        static let qualityPreset = "qualityPreset"
        static let maxPointCount = "maxPointCount"
        static let scanPrecision = "scanPrecision"
        static let hsvHMin = "hsvHMin"
        static let hsvHMax = "hsvHMax"
        static let hsvSMin = "hsvSMin"
        static let hsvVMin = "hsvVMin"
    }

    private init() {
        // 初始化所有 @Published 属性
        autoExportCSV = (defaults.object(forKey: Keys.autoExportCSV) as? Bool) ?? false
        cameraResolution = Self.validOption(
            defaults.string(forKey: Keys.cameraResolution),
            in: Self.cameraResolutionOptions,
            fallback: "1080p"
        )
        cameraFrameRate = Self.validOption(
            defaults.string(forKey: Keys.cameraFrameRate),
            in: Self.cameraFrameRateOptions,
            fallback: "60fps"
        )
        qualityPreset = Self.validOption(
            defaults.string(forKey: Keys.qualityPreset),
            in: Self.qualityPresetOptions,
            fallback: "高"
        )
        maxPointCount = Self.clamp(
            (defaults.object(forKey: Keys.maxPointCount) as? Int) ?? 1000000,
            min: 100000,
            max: 3000000
        )
        scanPrecision = Self.clamp(
            (defaults.object(forKey: Keys.scanPrecision) as? Double) ?? 0.01,
            min: 0.001,
            max: 0.05
        )
        hsvHMin = (defaults.object(forKey: Keys.hsvHMin) as? Float) ?? 330
        hsvHMax = (defaults.object(forKey: Keys.hsvHMax) as? Float) ?? 25
        hsvSMin = (defaults.object(forKey: Keys.hsvSMin) as? Float) ?? 0.3
        hsvVMin = (defaults.object(forKey: Keys.hsvVMin) as? Float) ?? 0.3
    }

    // MARK: - 水果参数
    var fruitType: String {
        get { defaults.string(forKey: Keys.fruitType) ?? "apple" }
        set {
            let normalized = FruitCategory(rawValue: newValue)?.rawValue ?? FruitCategory.apple.rawValue
            setIfChanged(normalized, forKey: Keys.fruitType)
        }
    }

    // MARK: - 聚类参数
    var clusterMinPoints: Int {
        get { Self.clamp((defaults.object(forKey: Keys.clusterMinPoints) as? Int) ?? 5, min: 3, max: 150) }
        set { setIfChanged(Self.clamp(newValue, min: 3, max: 150), forKey: Keys.clusterMinPoints) }
    }

    var clusterMinDiameter: Double {
        get {
            Self.clampFinite((defaults.object(forKey: Keys.clusterMinDiameter) as? Double) ?? 0.02, min: 0.005, max: clusterMaxDiameter, fallback: 0.02)
        }
        set {
            let normalized = Self.clampFinite(newValue, min: 0.005, max: clusterMaxDiameter, fallback: 0.02)
            setIfChanged(normalized, forKey: Keys.clusterMinDiameter)
        }
    }

    var clusterMaxDiameter: Double {
        get { Self.clampFinite((defaults.object(forKey: Keys.clusterMaxDiameter) as? Double) ?? 0.15, min: 0.04, max: 0.40, fallback: 0.15) }
        set {
            let normalized = Self.clampFinite(newValue, min: 0.04, max: 0.40, fallback: 0.15)
            setIfChanged(normalized, forKey: Keys.clusterMaxDiameter)
            if clusterMinDiameter > normalized {
                setIfChanged(normalized, forKey: Keys.clusterMinDiameter)
            }
        }
    }

    // MARK: - 检测参数
    var minConfidence: Double {
        get { Self.clampFinite((defaults.object(forKey: Keys.minConfidence) as? Double) ?? 0.5, min: 0, max: 1, fallback: 0.5) }
        set { setIfChanged(Self.clampFinite(newValue, min: 0, max: 1, fallback: 0.5), forKey: Keys.minConfidence) }
    }

    var sphericityThreshold: Double {
        get { Self.clampFinite((defaults.object(forKey: Keys.sphericityThreshold) as? Double) ?? 0.5, min: 0, max: 1, fallback: 0.5) }
        set { setIfChanged(Self.clampFinite(newValue, min: 0, max: 1, fallback: 0.5), forKey: Keys.sphericityThreshold) }
    }

    // MARK: - 深度范围
    var depthRangeMin: Double {
        get { Self.clampFinite((defaults.object(forKey: Keys.depthRangeMin) as? Double) ?? 0.5, min: 0.1, max: depthRangeMax, fallback: 0.5) }
        set {
            let normalized = Self.clampFinite(newValue, min: 0.1, max: depthRangeMax, fallback: 0.5)
            setIfChanged(normalized, forKey: Keys.depthRangeMin)
        }
    }

    var depthRangeMax: Double {
        get { Self.clampFinite((defaults.object(forKey: Keys.depthRangeMax) as? Double) ?? 5.0, min: 0.5, max: 8.0, fallback: 5.0) }
        set {
            let normalized = Self.clampFinite(newValue, min: 0.5, max: 8.0, fallback: 5.0)
            setIfChanged(normalized, forKey: Keys.depthRangeMax)
            if depthRangeMin > normalized {
                setIfChanged(normalized, forKey: Keys.depthRangeMin)
            }
        }
    }

    // MARK: - 设备参数
    var rgbRadius: Double {
        get { Self.clampFinite((defaults.object(forKey: Keys.rgbRadius) as? Double) ?? 3.0, min: 0, max: 12.0, fallback: 3.0) }
        set { setIfChanged(Self.clampFinite(newValue, min: 0, max: 12.0, fallback: 3.0), forKey: Keys.rgbRadius) }
    }

    var confidenceThreshold: Int {
        get { Self.clamp((defaults.object(forKey: Keys.confidenceThreshold) as? Int) ?? 1, min: 0, max: 2) }
        set { setIfChanged(Self.clamp(newValue, min: 0, max: 2), forKey: Keys.confidenceThreshold) }
    }

    // MARK: - 设置页面 @Published 属性（支持 $ 绑定）
    @Published var autoExportCSV: Bool { didSet { defaults.set(autoExportCSV, forKey: Keys.autoExportCSV) } }
    @Published var cameraResolution: String {
        didSet {
            let normalized = Self.validOption(cameraResolution, in: Self.cameraResolutionOptions, fallback: "1080p")
            if cameraResolution != normalized {
                cameraResolution = normalized
                return
            }
            defaults.set(cameraResolution, forKey: Keys.cameraResolution)
        }
    }
    @Published var cameraFrameRate: String {
        didSet {
            let normalized = Self.validOption(cameraFrameRate, in: Self.cameraFrameRateOptions, fallback: "60fps")
            if cameraFrameRate != normalized {
                cameraFrameRate = normalized
                return
            }
            defaults.set(cameraFrameRate, forKey: Keys.cameraFrameRate)
        }
    }
    @Published var qualityPreset: String {
        didSet {
            let normalized = Self.validOption(qualityPreset, in: Self.qualityPresetOptions, fallback: "高")
            if qualityPreset != normalized {
                qualityPreset = normalized
                return
            }
            defaults.set(qualityPreset, forKey: Keys.qualityPreset)
        }
    }
    @Published var maxPointCount: Int {
        didSet {
            let normalized = Self.clamp(maxPointCount, min: 100000, max: 3000000)
            if maxPointCount != normalized {
                maxPointCount = normalized
                return
            }
            defaults.set(maxPointCount, forKey: Keys.maxPointCount)
        }
    }
    @Published var scanPrecision: Double {
        didSet {
            let normalized = Self.clamp(scanPrecision, min: 0.001, max: 0.05)
            if scanPrecision != normalized {
                scanPrecision = normalized
                return
            }
            defaults.set(scanPrecision, forKey: Keys.scanPrecision)
        }
    }
    @Published var hsvHMin: Float { didSet { defaults.set(hsvHMin, forKey: Keys.hsvHMin) } }
    @Published var hsvHMax: Float { didSet { defaults.set(hsvHMax, forKey: Keys.hsvHMax) } }
    @Published var hsvSMin: Float { didSet { defaults.set(hsvSMin, forKey: Keys.hsvSMin) } }
    @Published var hsvVMin: Float { didSet { defaults.set(hsvVMin, forKey: Keys.hsvVMin) } }

    var hsvFilter: HSVFilter {
        HSVFilter(hMin: hsvHMin, hMax: hsvHMax, sMin: hsvSMin, vMin: hsvVMin)
    }

    func colorFilter(for category: FruitCategory) -> ColorFilter {
        var filter = category.colorFilter
        filter.hsvFilter = hsvFilter
        return filter
    }

    // ARKit 实际分辨率（由 ScanCoordinator 在扫描时更新）
    @Published var currentCameraResolutionDisplay: String = "检测中..."

    private static func validOption(_ value: String?, in options: [String], fallback: String) -> String {
        guard let value, options.contains(value) else { return fallback }
        return value
    }

    private static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.max(min, Swift.min(value, max))
    }

    private static func clampFinite(_ value: Double, min: Double, max: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.max(min, Swift.min(value, max))
    }

    private func setIfChanged<T: Equatable>(_ value: T, forKey key: String) {
        if let current = defaults.object(forKey: key) as? T, current == value {
            return
        }
        defaults.set(value, forKey: key)
    }

    // MARK: - 派生配置（融合 qualityPreset / cameraFrameRate / scanPrecision）
    var fruitScanConfig: FruitScanConfig {
        let baseConfidence = Float(minConfidence)
        let baseSphericity = Float(sphericityThreshold)

        // qualityPreset 影响置信度和球形度阈值
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

        // 视觉检测只需要低频辅助校正，点云采集仍保持实时。
        // 这里先按帧率粗采样，ImageDetector 内部还会做时间节流。
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
