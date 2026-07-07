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
        visionStatusColor = hudState.visionModelStatus == "CoreML" ? Design.Colors.forest : Design.Colors.warning
        depthStatusText = Self.depthStatusText(for: hudState.depthRuntimeStatus)
        depthStatusColor = Self.depthStatusColor(for: hudState.depthRuntimeStatus)
        pointCloudStatusText = Self.pointCloudStatusText(for: hudState.exportablePointStatus)
        pointCloudStatusColor = hudState.exportablePointStatus == "Ready" ? Design.Colors.forest : Design.Colors.warning
        fusionStatusText = Self.fusionStatusText(for: hudState.fusionStatus)
        fusionStatusColor = hudState.fusionStatus == "OK" ? Design.Colors.forest : Design.Colors.warning
        processedFrameText = hudState.processedImageFrames > 0 ? "\(hudState.processedImageFrames)" : "--"
        processedFrameColor = hudState.processedImageFrames > 0 ? Design.Colors.harvest : Design.Colors.warning
        pointDensityColor = qualityMonitor.pointDensity > 100 ? Design.Colors.harvest : Design.Colors.warning
    }

    private static func qualityColor(for score: Float) -> Color {
        switch score {
        case 0..<30: return Design.Colors.apple
        case 30..<50: return Design.Colors.harvestDark
        case 50..<70: return Design.Colors.harvest
        case 70..<90: return Design.Colors.forest
        default: return Design.Colors.earth
        }
    }

    private static func coverageColor(for percent: Int) -> Color {
        if percent >= 85 { return Design.Colors.harvest }
        if percent >= 60 { return Design.Colors.forest }
        if percent >= 30 { return Design.Colors.warning }
        return Design.Colors.apple
    }

    private static func recordingRouteHint(for trend: VoxelDiscoveryTrend) -> String {
        switch trend {
        case .collecting:
            return "从主干开始，慢速绕树一圈"
        case .increasing:
            return "正在发现新区域，继续保持树冠在画面中"
        case .decreasing:
            return "接近完成，补树冠背面和下层枝条"
        case .stable:
            return "覆盖稳定，可以停止录制并进入粗预览"
        }
    }

    private static func visionStatusText(for status: String) -> String {
        switch status {
        case "CoreML": return "本机"
        case "Fallback": return "备用"
        case "--": return "--"
        default: return status
        }
    }

    private static func visionDetailText(for detail: String) -> String {
        switch detail {
        case "No model": return "未载入"
        case "--": return "--"
        default: return "已载入"
        }
    }

    private static func depthStatusText(for status: String) -> String {
        switch status {
        case "LiDAR": return "可用"
        case "Wait": return "等待"
        case "NoDepth": return "无深度"
        case "NoAR": return "不可用"
        case "--": return "--"
        default: return status
        }
    }

    private static func depthStatusColor(for status: String) -> Color {
        switch status {
        case "LiDAR": return Design.Colors.forest
        case "Wait": return Design.Colors.harvest
        default: return Design.Colors.warning
        }
    }

    private static func pointCloudStatusText(for status: String) -> String {
        switch status {
        case "Ready": return "可导出"
        case "NoCloud": return "等待"
        case "--": return "--"
        default: return status
        }
    }

    private static func fusionStatusText(for status: String) -> String {
        switch status {
        case "OK": return "已融合"
        case "Wait": return "等待"
        case "0kg": return "低置信"
        default: return status
        }
    }
}
