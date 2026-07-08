// SettingsStoreSupport.swift
// Keys, option lists, and value normalization for SettingsStore.

import Foundation

enum SettingsStoreKey {
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

private enum SettingsStoreOptions {
    static let cameraFrameRates = ["30fps", "60fps", "120fps"]
    static let cameraResolutions = ["720p", "1080p", "4K"]
    static let qualityPresets = ["高", "中", "低"]
}

extension SettingsStore {
    static var cameraFrameRateOptions: [String] { SettingsStoreOptions.cameraFrameRates }
    static var cameraResolutionOptions: [String] { SettingsStoreOptions.cameraResolutions }
    static var qualityPresetOptions: [String] { SettingsStoreOptions.qualityPresets }

    static func validOption(_ value: String?, in options: [String], fallback: String) -> String {
        guard let value, options.contains(value) else { return fallback }
        return value
    }

    static func clamp<T: Comparable>(_ value: T, min: T, max: T) -> T {
        Swift.max(min, Swift.min(value, max))
    }

    static func clampFinite(_ value: Double, min: Double, max: Double, fallback: Double) -> Double {
        guard value.isFinite else { return fallback }
        return Swift.max(min, Swift.min(value, max))
    }

    static func clampFinite(_ value: Float, min: Float, max: Float, fallback: Float) -> Float {
        guard value.isFinite else { return fallback }
        return Swift.max(min, Swift.min(value, max))
    }
}
