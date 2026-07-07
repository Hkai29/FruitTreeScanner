// SettingsStore.swift
// 统一管理所有扫描参数，通过 UserDefaults 持久化

import Foundation
import Combine

final class SettingsStore: ObservableObject {
    static let shared = SettingsStore()
    private let defaults = UserDefaults.standard

    private init() {
        // 初始化所有 @Published 属性
        autoExportCSV = (defaults.object(forKey: SettingsStoreKey.autoExportCSV) as? Bool) ?? false
        cameraResolution = Self.validOption(
            defaults.string(forKey: SettingsStoreKey.cameraResolution),
            in: Self.cameraResolutionOptions,
            fallback: "1080p"
        )
        cameraFrameRate = Self.validOption(
            defaults.string(forKey: SettingsStoreKey.cameraFrameRate),
            in: Self.cameraFrameRateOptions,
            fallback: "60fps"
        )
        qualityPreset = Self.validOption(
            defaults.string(forKey: SettingsStoreKey.qualityPreset),
            in: Self.qualityPresetOptions,
            fallback: "高"
        )
        maxPointCount = Self.clamp(
            (defaults.object(forKey: SettingsStoreKey.maxPointCount) as? Int) ?? 1000000,
            min: 100000,
            max: 3000000
        )
        scanPrecision = Self.clamp(
            (defaults.object(forKey: SettingsStoreKey.scanPrecision) as? Double) ?? 0.01,
            min: 0.001,
            max: 0.05
        )
        hsvHMin = Self.normalizedHue((defaults.object(forKey: SettingsStoreKey.hsvHMin) as? Float) ?? 330, fallback: 330)
        hsvHMax = Self.normalizedHue((defaults.object(forKey: SettingsStoreKey.hsvHMax) as? Float) ?? 25, fallback: 25)
        hsvSMin = Self.normalizedUnit((defaults.object(forKey: SettingsStoreKey.hsvSMin) as? Float) ?? 0.3, fallback: 0.3)
        hsvVMin = Self.normalizedUnit((defaults.object(forKey: SettingsStoreKey.hsvVMin) as? Float) ?? 0.3, fallback: 0.3)
        persistHSVSettings()
    }

    // MARK: - 水果参数
    var fruitType: String {
        get { defaults.string(forKey: SettingsStoreKey.fruitType) ?? "apple" }
        set {
            let normalized = FruitCategory(rawValue: newValue)?.rawValue ?? FruitCategory.apple.rawValue
            setIfChanged(normalized, forKey: SettingsStoreKey.fruitType)
        }
    }

    // MARK: - 聚类参数
    var clusterMinPoints: Int {
        get { Self.clamp((defaults.object(forKey: SettingsStoreKey.clusterMinPoints) as? Int) ?? 5, min: 3, max: 150) }
        set { setIfChanged(Self.clamp(newValue, min: 3, max: 150), forKey: SettingsStoreKey.clusterMinPoints) }
    }

    var clusterMinDiameter: Double {
        get {
            Self.clampFinite((defaults.object(forKey: SettingsStoreKey.clusterMinDiameter) as? Double) ?? 0.02, min: 0.005, max: clusterMaxDiameter, fallback: 0.02)
        }
        set {
            let normalized = Self.clampFinite(newValue, min: 0.005, max: clusterMaxDiameter, fallback: 0.02)
            setIfChanged(normalized, forKey: SettingsStoreKey.clusterMinDiameter)
        }
    }

    var clusterMaxDiameter: Double {
        get { Self.clampFinite((defaults.object(forKey: SettingsStoreKey.clusterMaxDiameter) as? Double) ?? 0.15, min: 0.04, max: 0.40, fallback: 0.15) }
        set {
            let normalized = Self.clampFinite(newValue, min: 0.04, max: 0.40, fallback: 0.15)
            setIfChanged(normalized, forKey: SettingsStoreKey.clusterMaxDiameter)
            if clusterMinDiameter > normalized {
                setIfChanged(normalized, forKey: SettingsStoreKey.clusterMinDiameter)
            }
        }
    }

    // MARK: - 检测参数
    var minConfidence: Double {
        get { Self.clampFinite((defaults.object(forKey: SettingsStoreKey.minConfidence) as? Double) ?? 0.5, min: 0, max: 1, fallback: 0.5) }
        set { setIfChanged(Self.clampFinite(newValue, min: 0, max: 1, fallback: 0.5), forKey: SettingsStoreKey.minConfidence) }
    }

    var sphericityThreshold: Double {
        get { Self.clampFinite((defaults.object(forKey: SettingsStoreKey.sphericityThreshold) as? Double) ?? 0.5, min: 0, max: 1, fallback: 0.5) }
        set { setIfChanged(Self.clampFinite(newValue, min: 0, max: 1, fallback: 0.5), forKey: SettingsStoreKey.sphericityThreshold) }
    }

    // MARK: - 深度范围
    var depthRangeMin: Double {
        get { Self.clampFinite((defaults.object(forKey: SettingsStoreKey.depthRangeMin) as? Double) ?? 0.5, min: 0.1, max: depthRangeMax, fallback: 0.5) }
        set {
            let normalized = Self.clampFinite(newValue, min: 0.1, max: depthRangeMax, fallback: 0.5)
            setIfChanged(normalized, forKey: SettingsStoreKey.depthRangeMin)
        }
    }

    var depthRangeMax: Double {
        get { Self.clampFinite((defaults.object(forKey: SettingsStoreKey.depthRangeMax) as? Double) ?? 5.0, min: 0.5, max: 8.0, fallback: 5.0) }
        set {
            let normalized = Self.clampFinite(newValue, min: 0.5, max: 8.0, fallback: 5.0)
            setIfChanged(normalized, forKey: SettingsStoreKey.depthRangeMax)
            if depthRangeMin > normalized {
                setIfChanged(normalized, forKey: SettingsStoreKey.depthRangeMin)
            }
        }
    }

    // MARK: - 设备参数
    var rgbRadius: Double {
        get { Self.clampFinite((defaults.object(forKey: SettingsStoreKey.rgbRadius) as? Double) ?? 3.0, min: 0, max: 12.0, fallback: 3.0) }
        set { setIfChanged(Self.clampFinite(newValue, min: 0, max: 12.0, fallback: 3.0), forKey: SettingsStoreKey.rgbRadius) }
    }

    var confidenceThreshold: Int {
        get { Self.clamp((defaults.object(forKey: SettingsStoreKey.confidenceThreshold) as? Int) ?? 1, min: 0, max: 2) }
        set { setIfChanged(Self.clamp(newValue, min: 0, max: 2), forKey: SettingsStoreKey.confidenceThreshold) }
    }

    // MARK: - 设置页面 @Published 属性（支持 $ 绑定）
    @Published var autoExportCSV: Bool { didSet { defaults.set(autoExportCSV, forKey: SettingsStoreKey.autoExportCSV) } }
    @Published var cameraResolution: String {
        didSet {
            let normalized = Self.validOption(cameraResolution, in: Self.cameraResolutionOptions, fallback: "1080p")
            if cameraResolution != normalized {
                cameraResolution = normalized
                return
            }
            defaults.set(cameraResolution, forKey: SettingsStoreKey.cameraResolution)
        }
    }
    @Published var cameraFrameRate: String {
        didSet {
            let normalized = Self.validOption(cameraFrameRate, in: Self.cameraFrameRateOptions, fallback: "60fps")
            if cameraFrameRate != normalized {
                cameraFrameRate = normalized
                return
            }
            defaults.set(cameraFrameRate, forKey: SettingsStoreKey.cameraFrameRate)
        }
    }
    @Published var qualityPreset: String {
        didSet {
            let normalized = Self.validOption(qualityPreset, in: Self.qualityPresetOptions, fallback: "高")
            if qualityPreset != normalized {
                qualityPreset = normalized
                return
            }
            defaults.set(qualityPreset, forKey: SettingsStoreKey.qualityPreset)
        }
    }
    @Published var maxPointCount: Int {
        didSet {
            let normalized = Self.clamp(maxPointCount, min: 100000, max: 3000000)
            if maxPointCount != normalized {
                maxPointCount = normalized
                return
            }
            defaults.set(maxPointCount, forKey: SettingsStoreKey.maxPointCount)
        }
    }
    @Published var scanPrecision: Double {
        didSet {
            let normalized = Self.clamp(scanPrecision, min: 0.001, max: 0.05)
            if scanPrecision != normalized {
                scanPrecision = normalized
                return
            }
            defaults.set(scanPrecision, forKey: SettingsStoreKey.scanPrecision)
        }
    }
    @Published var hsvHMin: Float {
        didSet {
            let normalized = Self.normalizedHue(hsvHMin, fallback: 330)
            if hsvHMin != normalized {
                defaults.set(normalized, forKey: SettingsStoreKey.hsvHMin)
                hsvHMin = normalized
                return
            }
            defaults.set(hsvHMin, forKey: SettingsStoreKey.hsvHMin)
        }
    }
    @Published var hsvHMax: Float {
        didSet {
            let normalized = Self.normalizedHue(hsvHMax, fallback: 25)
            if hsvHMax != normalized {
                defaults.set(normalized, forKey: SettingsStoreKey.hsvHMax)
                hsvHMax = normalized
                return
            }
            defaults.set(hsvHMax, forKey: SettingsStoreKey.hsvHMax)
        }
    }
    @Published var hsvSMin: Float {
        didSet {
            let normalized = Self.normalizedUnit(hsvSMin, fallback: 0.3)
            if hsvSMin != normalized {
                defaults.set(normalized, forKey: SettingsStoreKey.hsvSMin)
                hsvSMin = normalized
                return
            }
            defaults.set(hsvSMin, forKey: SettingsStoreKey.hsvSMin)
        }
    }
    @Published var hsvVMin: Float {
        didSet {
            let normalized = Self.normalizedUnit(hsvVMin, fallback: 0.3)
            if hsvVMin != normalized {
                defaults.set(normalized, forKey: SettingsStoreKey.hsvVMin)
                hsvVMin = normalized
                return
            }
            defaults.set(hsvVMin, forKey: SettingsStoreKey.hsvVMin)
        }
    }

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

    private func persistHSVSettings() {
        defaults.set(hsvHMin, forKey: SettingsStoreKey.hsvHMin)
        defaults.set(hsvHMax, forKey: SettingsStoreKey.hsvHMax)
        defaults.set(hsvSMin, forKey: SettingsStoreKey.hsvSMin)
        defaults.set(hsvVMin, forKey: SettingsStoreKey.hsvVMin)
    }

    private func setIfChanged<T: Equatable>(_ value: T, forKey key: String) {
        if let current = defaults.object(forKey: key) as? T, current == value {
            return
        }
        defaults.set(value, forKey: key)
    }

    static func normalizedHue(_ value: Float, fallback: Float) -> Float {
        clampFinite(value, min: 0, max: 360, fallback: fallback)
    }

    static func normalizedUnit(_ value: Float, fallback: Float) -> Float {
        clampFinite(value, min: 0, max: 1, fallback: fallback)
    }
}
