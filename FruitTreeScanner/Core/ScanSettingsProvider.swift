// ScanSettingsProvider.swift
// 扫描流水线所需设置的抽象协议，支持测试注入

import Foundation

protocol ScanSettingsProviding: AnyObject {
    var fruitType: String { get }
    var fruitScanConfig: FruitScanConfig { get }
    var autoExportCSV: Bool { get }
    var hsvFilter: HSVFilter { get }
    var currentCameraResolutionDisplay: String { get set }
    func clusterConfig(for params: FruitVarietyParams) -> ClusterConfig
    func colorFilter(for category: FruitCategory) -> ColorFilter
}

extension SettingsStore: ScanSettingsProviding {}
