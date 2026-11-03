// ScanStatusBarPresentation.swift
// 采集状态的颜色与文案映射。
//
// 颜色只有三档：可靠(绿) / 注意(琥珀) / 失败(锈红)。
// 连续量（覆盖度、质量分）用分段电平表表达连续信息，
// 颜色只做三档强化，避免彩虹色阶。

import SwiftUI

@MainActor
struct ScanStatusBarPresentation {
    let qualityColor: Color
    let coverageColor: Color
    let recordingRouteHint: String
    let visionStatusText: String
    let visionDetailText: String
    let visionStatusColor: Color
    let depthStatusText: String
    let depthStatusColor: Color
    let pointCloudStatusText: String
    let pointCloudStatusColor: Color
    let fusionStatusText: String
    let fusionStatusColor: Color
    let processedFrameText: String
    let processedFrameColor: Color
    let pointDensityColor: Color

    init(hudState: ScanHUDState, qualityMonitor: ScanQualityMonitor) {
        qualityColor = Self.qualityColor(for: qualityMonitor.qualityScore)
        coverageColor = Self.coverageColor(for: hudState.coveragePercent)
        recordingRouteHint = Self.recordingRouteHint(for: hudState.scanCompletion.discoveryTrend)
        visionStatusText = Self.visionStatusText(for: hudState.visionModelStatus)
        visionDetailText = Self.visionDetailText(for: hudState.visionModelDetail)
        visionStatusColor = hudState.visionModelStatus == "CoreML" ? Design.Colors.Dark.success : Design.Colors.Dark.warning
        depthStatusText = Self.depthStatusText(for: hudState.depthRuntimeStatus)
        depthStatusColor = Self.depthStatusColor(for: hudState.depthRuntimeStatus)
        pointCloudStatusText = Self.pointCloudStatusText(for: hudState.exportablePointStatus)
        pointCloudStatusColor = hudState.exportablePointStatus == "Ready" ? Design.Colors.Dark.success : Design.Colors.Dark.warning
        fusionStatusText = Self.fusionStatusText(for: hudState.fusionStatus)
        fusionStatusColor = hudState.fusionStatus == "OK" ? Design.Colors.Dark.success : Design.Colors.Dark.warning
        processedFrameText = hudState.processedImageFrames > 0 ? "\(hudState.processedImageFrames)" : "--"
        processedFrameColor = hudState.processedImageFrames > 0 ? Design.Colors.Dark.glow : Design.Colors.Dark.warning
        pointDensityColor = qualityMonitor.pointDensity > 100 ? Design.Colors.Dark.glow : Design.Colors.Dark.warning
    }

    /// 三档色阶：差 / 一般 / 好。连续分值由电平表承担。
    private static func qualityColor(for score: Float) -> Color {
        switch score {
        case 0..<40: return Design.Colors.Dark.error
        case 40..<70: return Design.Colors.Dark.warning
        default: return Design.Colors.Dark.success
        }
    }

    private static func coverageColor(for percent: Int) -> Color {
        if percent >= 85 { return Design.Colors.Dark.success }
        if percent >= 50 { return Design.Colors.Dark.warning }
        return Design.Colors.Dark.error
    }

    private static func recordingRouteHint(for trend: VoxelDiscoveryTrend) -> String {
        switch trend {
        case .collecting:
            return L10n.ScanHUD.routeTrunk
        case .increasing:
            return L10n.ScanHUD.routeDiscovering
        case .decreasing:
            return L10n.ScanHUD.routeFinishing
        case .stable:
            return L10n.ScanHUD.routeStable
        }
    }

    private static func visionStatusText(for status: String) -> String {
        switch status {
        case "CoreML": return L10n.ScanHUD.onDevice
        case "Fallback": return L10n.ScanHUD.fallback
        case "--": return "--"
        default: return status
        }
    }

    private static func visionDetailText(for detail: String) -> String {
        switch detail {
        case "No model": return L10n.ScanHUD.modelNotLoaded
        case "--": return "--"
        default: return L10n.ScanHUD.modelLoaded
        }
    }

    private static func depthStatusText(for status: String) -> String {
        switch status {
        case "LiDAR": return L10n.ScanHUD.available
        case "Wait": return L10n.ScanHUD.waiting
        case "NoDepth": return L10n.ScanHUD.noDepth
        case "NoAR": return L10n.ScanHUD.unavailable
        case "--": return "--"
        default: return status
        }
    }

    private static func depthStatusColor(for status: String) -> Color {
        switch status {
        case "LiDAR": return Design.Colors.Dark.success
        case "Wait": return Design.Colors.Dark.warning
        case "NoDepth", "NoAR": return Design.Colors.Dark.error
        default: return Design.Colors.Dark.warning
        }
    }

    private static func pointCloudStatusText(for status: String) -> String {
        switch status {
        case "Ready": return L10n.ScanHUD.exportable
        case "NoCloud": return L10n.ScanHUD.waiting
        case "--": return "--"
        default: return status
        }
    }

    private static func fusionStatusText(for status: String) -> String {
        switch status {
        case "OK": return L10n.ScanHUD.fused
        case "Wait", "等待扫描": return L10n.ScanHUD.waiting
        case "扫描中": return L10n.ScanHUD.scanning
        case "补扫中": return L10n.ScanHUD.rescanning
        case "Interrupted": return L10n.ScanHUD.interrupted
        case "Failed": return L10n.ScanHUD.failed
        case "0kg": return L10n.ScanHUD.lowConfidence
        default: return status
        }
    }
}
