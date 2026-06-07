import SwiftUI

struct ScanStatusBar: View {
    let treeID: String
    let isRecording: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor

    var body: some View {
        VStack(spacing: 8) {
            HStack(spacing: 8) {
                ScanPrimaryStatusMetric(label: "树号", value: treeID, accentColor: Design.Colors.harvest)
                ScanPrimaryStatusMetric(label: "覆盖", value: "\(hudState.coveragePercent)%", accentColor: Design.Colors.harvest)
                ScanPrimaryStatusMetric(label: "果数", value: "\(hudState.detectedFruitCount)", accentColor: hudState.detectedFruitCount > 0 ? Design.Colors.harvest : Design.Colors.warning)
                ScanPrimaryStatusMetric(label: "质量", value: qualityMonitor.getQualityStatus(), accentColor: qualityColor)
                StatusIndicator(status: isRecording ? .recording : .ready)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    HUDPill(label: "点数", value: ScanHUDValueFormatter.pointCount(hudState.pointCount), accentColor: Design.Colors.harvest)
                    HUDPill(label: "图像", value: visionStatusText, accentColor: visionStatusColor)
                    HUDPill(label: "模型", value: visionDetailText, accentColor: visionStatusColor)
                    HUDPill(label: "深度", value: depthStatusText, accentColor: depthStatusColor)
                    HUDPill(label: "点云", value: pointCloudStatusText, accentColor: pointCloudStatusColor)
                    HUDPill(label: "帧数", value: hudState.processedImageFrames > 0 ? "\(hudState.processedImageFrames)" : "--", accentColor: hudState.processedImageFrames > 0 ? Design.Colors.harvest : Design.Colors.warning)
                    HUDPill(label: "融合", value: fusionStatusText, accentColor: fusionStatusColor)
                    HUDPill(label: "密度", value: ScanHUDValueFormatter.pointDensity(qualityMonitor.pointDensity), accentColor: qualityMonitor.pointDensity > 100 ? Design.Colors.harvest : Design.Colors.warning)
                    HUDPill(label: "光照", value: qualityMonitor.lightLevel.description, accentColor: qualityMonitor.lightLevel.color)
                }
            }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 10)
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

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textMuted)
                .lineLimit(1)

            Text(value)
                .font(.system(size: 12, weight: .semibold, design: .monospaced))
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

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            HStack(spacing: Design.Space.sm) {
                ScanUtilityControlButton(
                    title: "引导",
                    icon: "questionmark.circle",
                    isActive: false,
                    action: onToggleGuide
                )

                ScanUtilityControlButton(
                    title: "测量",
                    icon: "ruler",
                    isActive: measurementController.isActive,
                    action: onToggleMeasurement
                )

            #if DEBUG
                ScanUtilityControlButton(
                    title: "调试",
                    icon: "wrench.and.screwdriver",
                    isActive: false,
                    action: onDebug
                )
            #endif
            }

            HStack(spacing: Design.Space.sm) {
                ScanPrimaryControlButton(
                    title: "取消",
                    icon: "xmark",
                    role: .secondary,
                    isLoading: false,
                    action: onCancel
                )

                ScanPrimaryControlButton(
                    title: isRecording ? "停止录制" : "开始录制",
                    icon: isRecording ? "stop.fill" : "record.circle",
                    role: isRecording ? .recording : .primary,
                    isLoading: false,
                    action: onToggleRecording
                )

                ScanPrimaryControlButton(
                    title: "完成",
                    icon: "checkmark",
                    role: .finish,
                    isLoading: isEstimating,
                    action: onFinish
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
        isEstimating || hudState.pointCount == 0
    }
}

private struct ScanUtilityControlButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(isActive ? Design.Colors.harvest : Design.Colors.Dark.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(height: 38)
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

    var body: some View {
        Button(action: action) {
            HStack(spacing: 6) {
                if isLoading {
                    ProgressView()
                        .tint(foregroundColor)
                        .scaleEffect(0.75)
                } else {
                    Image(systemName: icon)
                        .font(.system(size: 13, weight: .bold))
                }

                Text(isLoading ? "处理中" : title)
                    .font(.system(size: 14, weight: .semibold))
            }
            .foregroundColor(foregroundColor)
            .lineLimit(1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .frame(height: 46)
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
