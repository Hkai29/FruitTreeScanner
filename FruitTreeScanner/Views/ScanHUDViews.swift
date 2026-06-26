import SwiftUI

struct ScanStatusBar: View {
    let treeID: String
    let isRecording: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPad: Bool { horizontalSizeClass == .regular }

    private var metricFontSize: CGFloat { isPad ? 14 : 12 }
    private var metricLabelSize: CGFloat { isPad ? 11 : 9 }
    private var pillLabelSize: CGFloat { isPad ? 12 : 10 }
    private var pillValueSize: CGFloat { isPad ? 16 : 14 }
    private var statusIconSize: CGFloat { isPad ? 12 : 10 }
    private var statusLabelSize: CGFloat { isPad ? 13 : 12 }

    var body: some View {
        Group {
            if isRecording {
                recordingHUD
            } else {
                detailedHUD
            }
        }
        .padding(.horizontal, isPad ? 14 : 10)
        .padding(.vertical, isPad ? 14 : 10)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, Design.Space.md)
        .padding(.top, Design.Space.md)
    }

    private var recordingHUD: some View {
        VStack(spacing: isPad ? 10 : 8) {
            HStack(spacing: 8) {
                Label("果树全株", systemImage: "viewfinder")
                    .font(.system(size: isPad ? 14 : 12, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Design.Colors.harvest.opacity(0.14))
                    .clipShape(Capsule())

                Text("树号 \(treeID)")
                    .font(.system(size: isPad ? 13 : 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                StatusIndicator(
                    status: .recording,
                    iconSize: statusIconSize,
                    labelSize: statusLabelSize
                )
            }

            HStack(spacing: isPad ? 10 : 8) {
                ScanPrimaryStatusMetric(
                    label: "覆盖",
                    value: "\(hudState.coveragePercent)%",
                    accentColor: coverageColor,
                    valueFontSize: metricFontSize,
                    labelFontSize: metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "果数",
                    value: "\(hudState.detectedFruitCount)",
                    accentColor: hudState.detectedFruitCount > 0 ? Design.Colors.harvest : Design.Colors.warning,
                    valueFontSize: metricFontSize,
                    labelFontSize: metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "质量",
                    value: qualityMonitor.getQualityStatus(),
                    accentColor: qualityColor,
                    valueFontSize: metricFontSize,
                    labelFontSize: metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "深度",
                    value: depthStatusText,
                    accentColor: depthStatusColor,
                    valueFontSize: metricFontSize,
                    labelFontSize: metricLabelSize
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                Text(recordingRouteHint)
                    .font(.system(size: isPad ? 12 : 10, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Design.Colors.Dark.bgElevated.opacity(0.64))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }

    private var detailedHUD: some View {
        VStack(spacing: isPad ? 10 : 8) {
            HStack(spacing: isPad ? 10 : 8) {
                ScanPrimaryStatusMetric(
                    label: "树号",
                    value: treeID,
                    accentColor: Design.Colors.harvest,
                    valueFontSize: metricFontSize,
                    labelFontSize: metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "覆盖",
                    value: "\(hudState.coveragePercent)%",
                    accentColor: coverageColor,
                    valueFontSize: metricFontSize,
                    labelFontSize: metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "果数",
                    value: "\(hudState.detectedFruitCount)",
                    accentColor: hudState.detectedFruitCount > 0 ? Design.Colors.harvest : Design.Colors.warning,
                    valueFontSize: metricFontSize,
                    labelFontSize: metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "质量",
                    value: qualityMonitor.getQualityStatus(),
                    accentColor: qualityColor,
                    valueFontSize: metricFontSize,
                    labelFontSize: metricLabelSize
                )
                StatusIndicator(
                    status: isRecording ? .recording : .ready,
                    iconSize: statusIconSize,
                    labelSize: statusLabelSize
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: isPad ? 10 : 8) {
                    HUDPill(label: "点数", value: ScanHUDValueFormatter.pointCount(hudState.pointCount), accentColor: Design.Colors.harvest, labelSize: pillLabelSize, valueSize: pillValueSize)
                    HUDPill(label: "图像", value: visionStatusText, accentColor: visionStatusColor, labelSize: pillLabelSize, valueSize: pillValueSize)
                    HUDPill(label: "模型", value: visionDetailText, accentColor: visionStatusColor, labelSize: pillLabelSize, valueSize: pillValueSize)
                    HUDPill(label: "深度", value: depthStatusText, accentColor: depthStatusColor, labelSize: pillLabelSize, valueSize: pillValueSize)
                    HUDPill(label: "点云", value: pointCloudStatusText, accentColor: pointCloudStatusColor, labelSize: pillLabelSize, valueSize: pillValueSize)
                    HUDPill(label: "帧数", value: hudState.processedImageFrames > 0 ? "\(hudState.processedImageFrames)" : "--", accentColor: hudState.processedImageFrames > 0 ? Design.Colors.harvest : Design.Colors.warning, labelSize: pillLabelSize, valueSize: pillValueSize)
                    HUDPill(label: "融合", value: fusionStatusText, accentColor: fusionStatusColor, labelSize: pillLabelSize, valueSize: pillValueSize)
                    HUDPill(label: "密度", value: ScanHUDValueFormatter.pointDensity(qualityMonitor.pointDensity), accentColor: qualityMonitor.pointDensity > 100 ? Design.Colors.harvest : Design.Colors.warning, labelSize: pillLabelSize, valueSize: pillValueSize)
                    HUDPill(label: "光照", value: qualityMonitor.lightLevel.description, accentColor: qualityMonitor.lightLevel.color, labelSize: pillLabelSize, valueSize: pillValueSize)
                }
            }
        }
    }

    private var qualityColor: Color {
        let score = qualityMonitor.qualityScore
        switch score {
        case 0..<30: return Design.Colors.apple
        case 30..<50: return Design.Colors.harvestDark
        case 50..<70: return Design.Colors.harvest
        case 70..<90: return Design.Colors.forest
        default: return Design.Colors.earth
        }
    }

    private var coverageColor: Color {
        if hudState.coveragePercent >= 85 { return Design.Colors.harvest }
        if hudState.coveragePercent >= 60 { return Design.Colors.forest }
        if hudState.coveragePercent >= 30 { return Design.Colors.warning }
        return Design.Colors.apple
    }

    private var recordingRouteHint: String {
        switch hudState.scanCompletion.discoveryTrend {
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

    private var visionStatusText: String {
        switch hudState.visionModelStatus {
        case "CoreML": return "本机"
        case "Fallback": return "备用"
        case "--": return "--"
        default: return hudState.visionModelStatus
        }
    }

    private var visionDetailText: String {
        switch hudState.visionModelDetail {
        case "No model": return "未载入"
        case "--": return "--"
        default: return "已载入"
        }
    }

    private var visionStatusColor: Color {
        hudState.visionModelStatus == "CoreML" ? Design.Colors.forest : Design.Colors.warning
    }

    private var depthStatusText: String {
        switch hudState.depthRuntimeStatus {
        case "LiDAR": return "可用"
        case "Wait": return "等待"
        case "NoDepth": return "无深度"
        case "NoAR": return "不可用"
        case "--": return "--"
        default: return hudState.depthRuntimeStatus
        }
    }

    private var pointCloudStatusText: String {
        switch hudState.exportablePointStatus {
        case "Ready": return "可导出"
        case "NoCloud": return "等待"
        case "--": return "--"
        default: return hudState.exportablePointStatus
        }
    }

    private var pointCloudStatusColor: Color {
        hudState.exportablePointStatus == "Ready" ? Design.Colors.forest : Design.Colors.warning
    }

    private var fusionStatusText: String {
        switch hudState.fusionStatus {
        case "OK": return "已融合"
        case "Wait": return "等待"
        case "0kg": return "低置信"
        default: return hudState.fusionStatus
        }
    }

    private var fusionStatusColor: Color {
        hudState.fusionStatus == "OK" ? Design.Colors.forest : Design.Colors.warning
    }

    private var depthStatusColor: Color {
        switch hudState.depthRuntimeStatus {
        case "LiDAR": return Design.Colors.forest
        case "Wait": return Design.Colors.harvest
        default: return Design.Colors.warning
        }
    }
}

private struct ScanPrimaryStatusMetric: View {
    let label: String
    let value: String
    let accentColor: Color
    var valueFontSize: CGFloat = 12
    var labelFontSize: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textMuted)
                .lineLimit(1)

            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Design.Colors.Dark.bgElevated.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}

struct ScanCoverageHintBar: View {
    @ObservedObject var hudState: ScanHUDState

    var body: some View {
        CoverageMapView(completion: hudState.scanCompletion)
            .padding(.horizontal, Design.Space.lg)
            .padding(.bottom, Design.Space.sm)
    }
}

struct ScanBottomControlBar: View {
    let isRecording: Bool
    let isEstimating: Bool
    let canFinish: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var measurementController: MetalMeasurementController
    let onToggleGuide: () -> Void
    let onToggleRecording: () -> Void
    let onToggleMeasurement: () -> Void
    let onCancel: () -> Void
    let onFinish: () -> Void
    #if DEBUG
    let onDebug: () -> Void
    #endif

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPad: Bool { horizontalSizeClass == .regular }

    private var utilityHeight: CGFloat { isPad ? 48 : 38 }
    private var utilityFontSize: CGFloat { isPad ? 15 : 13 }
    private var primaryHeight: CGFloat { isPad ? 56 : 46 }
    private var primaryFontSize: CGFloat { isPad ? 16 : 14 }
    private var primaryIconSize: CGFloat { isPad ? 15 : 13 }

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            HStack(spacing: Design.Space.sm) {
                ScanUtilityControlButton(
                    title: "引导",
                    icon: "questionmark.circle",
                    isActive: false,
                    action: onToggleGuide,
                    height: utilityHeight,
                    fontSize: utilityFontSize
                )

                ScanUtilityControlButton(
                    title: "测量",
                    icon: "ruler",
                    isActive: measurementController.isActive,
                    action: onToggleMeasurement,
                    height: utilityHeight,
                    fontSize: utilityFontSize
                )

            #if DEBUG
                ScanUtilityControlButton(
                    title: "调试",
                    icon: "wrench.and.screwdriver",
                    isActive: false,
                    action: onDebug,
                    height: utilityHeight,
                    fontSize: utilityFontSize
                )
            #endif
            }

            HStack(spacing: Design.Space.sm) {
                ScanPrimaryControlButton(
                    title: "取消",
                    icon: "xmark",
                    role: .secondary,
                    isLoading: false,
                    action: onCancel,
                    height: primaryHeight,
                    fontSize: primaryFontSize,
                    iconSize: primaryIconSize
                )

                ScanPrimaryControlButton(
                    title: recordingButtonTitle,
                    icon: isRecording ? "stop.fill" : "record.circle",
                    role: isRecording ? .recording : .primary,
                    isLoading: false,
                    action: onToggleRecording,
                    height: primaryHeight,
                    fontSize: primaryFontSize,
                    iconSize: primaryIconSize
                )

                ScanPrimaryControlButton(
                    title: "完成",
                    icon: "checkmark",
                    role: .finish,
                    isLoading: isEstimating,
                    action: onFinish,
                    height: primaryHeight,
                    fontSize: primaryFontSize,
                    iconSize: primaryIconSize
                )
                .disabled(isFinishDisabled)
                .opacity(isFinishDisabled ? 0.5 : 1)
            }
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.large)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.large)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, Design.Space.md)
        .padding(.bottom, Design.Space.lg)
    }

    private var isFinishDisabled: Bool {
        isEstimating || !canFinish
    }

    private var recordingButtonTitle: String {
        if isRecording { return "停止录制" }
        if hudState.pointCount > 0 { return "重新录制" }
        return "开始录制"
    }
}

private struct ScanUtilityControlButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void
    var height: CGFloat = 38
    var fontSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: fontSize, weight: .semibold))
                .foregroundColor(isActive ? Design.Colors.harvest : Design.Colors.Dark.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: height)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .fill(isActive ? Design.Colors.harvest.opacity(0.16) : Color.white.opacity(0.07))
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(isActive ? Design.Colors.harvest.opacity(0.7) : Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
        }
        .buttonStyle(ScanControlButtonStyle())
    }
}

private struct ScanPrimaryControlButton: View {
    enum Role {
        case primary
        case secondary
        case recording
        case finish
    }

    let title: String
    let icon: String
    let role: Role
    let isLoading: Bool
    let action: () -> Void
    var height: CGFloat = 46
    var fontSize: CGFloat = 14
    var iconSize: CGFloat = 13

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: iconSize, weight: .bold))
                }

                Text(isLoading ? "处理中" : title)
                    .font(.system(size: fontSize, weight: .semibold))
            }
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .frame(height: height)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(ScanControlButtonStyle())
    }

    private var backgroundColor: Color {
        switch role {
        case .primary: return Design.Colors.harvest
        case .secondary: return Color.white.opacity(0.08)
        case .recording: return Design.Colors.apple
        case .finish: return Design.Colors.forest
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .secondary: return Design.Colors.Dark.textPrimary
        default: return .white
        }
    }

    private var borderColor: Color {
        switch role {
        case .secondary: return Design.Colors.Dark.glassBorder
        default: return Color.white.opacity(0.12)
        }
    }
}

private struct ScanControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}
