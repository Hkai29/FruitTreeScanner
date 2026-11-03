// ScanControlBar.swift
// 采集底部控制条：工具行 + 主操作行。
// 语义色来自 Design.Colors.Dark（信号青=可执行，锈红=记录中/危险）。

import SwiftUI

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
    var onResume: (() -> Void)? = nil
    #if DEBUG
    let onDebug: () -> Void
    #endif

    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @Environment(\.verticalSizeClass) private var verticalSizeClass
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private var isPad: Bool { horizontalSizeClass == .regular }
    // 触达区域不得小于 44pt：野外戴手套操作。
    private var utilityHeight: CGFloat { isPad ? 48 : 44 }
    private var primaryHeight: CGFloat { isPad ? 58 : 54 }

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            if !isRecording {
                HStack(spacing: Design.Space.sm) {
                    ScanUtilityControlButton(
                        title: L10n.ScanControls.text(.guide),
                        icon: "questionmark.circle",
                        isActive: false,
                        action: onToggleGuide,
                        height: utilityHeight,
                        accessibilityIdentifier: "scan.guide"
                    )

                    ScanUtilityControlButton(
                        title: L10n.ScanControls.text(.measure),
                        icon: "ruler",
                        isActive: measurementController.isActive,
                        action: onToggleMeasurement,
                        height: utilityHeight,
                        accessibilityIdentifier: "scan.measure"
                    )

                    if onResume != nil {
                        ScanUtilityControlButton(
                            title: L10n.ScanControls.text(.rerecord),
                            icon: "arrow.counterclockwise",
                            isActive: false,
                            action: onToggleRecording,
                            height: utilityHeight,
                            accessibilityIdentifier: "scan.rerecord"
                        )
                    }
                }
            }

            primaryLayout {
                ScanPrimaryControlButton(
                    title: L10n.ScanControls.text(.cancel),
                    icon: "xmark",
                    role: .cancel,
                    isLoading: false,
                    action: onCancel,
                    height: primaryHeight,
                    accessibilityIdentifier: "scan.cancel"
                )

                ScanPrimaryControlButton(
                    title: onResume != nil ? L10n.ScanPostCapture.resumeAction : recordingButtonTitle,
                    icon: onResume != nil ? "plus.viewfinder" : (isRecording ? "stop.fill" : "record.circle"),
                    role: isRecording ? .recording : (onResume != nil ? .secondary : .primary),
                    isLoading: false,
                    action: onResume ?? onToggleRecording,
                    height: primaryHeight,
                    accessibilityIdentifier: onResume != nil ? "scan.resume" : "scan.record"
                )

                ScanPrimaryControlButton(
                    title: canFinish ? L10n.ScanControls.text(.finish) : L10n.ScanExport.requirementsAction,
                    icon: canFinish ? "checkmark" : "info.circle",
                    role: canFinish && onResume != nil ? .finish : .secondary,
                    isLoading: isEstimating,
                    action: onFinish,
                    height: primaryHeight,
                    accessibilityIdentifier: "scan.finish"
                )
                .disabled(ScanExportReadiness.finishControlIsDisabled(isEstimating: isEstimating))
                .opacity(isEstimating ? 0.5 : 1)
                .accessibilityHint(canFinish ? "" : L10n.ScanExport.requirementsHint)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .fill(Design.Colors.Dark.bgSurface.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .frame(maxWidth: 760)
        .padding(.horizontal, 16)
        .padding(.bottom, 10)
    }

    private var recordingButtonTitle: String {
        if isRecording { return L10n.ScanControls.text(.stopRecording) }
        if hudState.pointCount > 0 { return L10n.ScanControls.text(.rerecord) }
        return L10n.ScanControls.text(.startRecording)
    }

    private var primaryLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize && verticalSizeClass != .compact
            ? AnyLayout(VStackLayout(spacing: Design.Space.sm))
            : AnyLayout(HStackLayout(spacing: Design.Space.sm))
    }
}

private struct ScanUtilityControlButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void
    var height: CGFloat = 42
    var accessibilityIdentifier: String?

    var body: some View {
        Button(action: action) {
            Label(title, systemImage: icon)
                .labelStyle(ScanUtilityLabelStyle(usesTextOnly: dynamicTypeSize.isAccessibilitySize))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(isActive ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
                .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                .minimumScaleFactor(0.85)
                .frame(maxWidth: .infinity)
                .frame(minHeight: height)
                .contentShape(Rectangle())
                .background(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .fill(isActive ? Design.Colors.Dark.glow : Color.clear)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                        .stroke(
                            isActive ? Color.clear : Design.Colors.Dark.glassBorder,
                            lineWidth: 1
                        )
                )
        }
        .buttonStyle(ScanControlButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier ?? "scan.utility.\(title)")
    }
}

private struct ScanUtilityLabelStyle: LabelStyle {
    let usesTextOnly: Bool

    func makeBody(configuration: Configuration) -> some View {
        if usesTextOnly {
            configuration.title
        } else {
            HStack(spacing: 6) {
                configuration.icon
                configuration.title
            }
        }
    }
}

private struct ScanPrimaryControlButton: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    enum Role {
        case primary
        case secondary
        case recording
        case finish
        case cancel
    }

    let title: String
    let icon: String
    let role: Role
    let isLoading: Bool
    let action: () -> Void
    var height: CGFloat = 52
    var accessibilityIdentifier: String?

    var body: some View {
        Button(action: action) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: 6) {
                    if isLoading {
                        ProgressView()
                            .tint(foregroundColor)
                            .scaleEffect(0.75)
                    } else {
                        Image(systemName: icon)
                            .font(.system(.subheadline, design: .default).weight(.bold))
                    }

                    Text(displayTitle)
                }

                Text(displayTitle)
            }
            .font(.subheadline.weight(.semibold))
            .foregroundColor(foregroundColor)
            .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
            .minimumScaleFactor(0.82)
            .frame(maxWidth: .infinity)
            .padding(.vertical, dynamicTypeSize.isAccessibilitySize ? 8 : 0)
            .frame(minHeight: height)
            .contentShape(Rectangle())
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(borderColor, lineWidth: 1)
            )
        }
        .buttonStyle(ScanControlButtonStyle())
        .accessibilityIdentifier(accessibilityIdentifier ?? "scan.primary.\(title)")
    }

    private var displayTitle: String {
        isLoading ? L10n.ScanControls.text(.processing) : title
    }

    private var backgroundColor: Color {
        switch role {
        case .primary, .finish: return Design.Colors.Dark.glow
        case .secondary: return Color.white.opacity(0.04)
        case .recording: return Design.Colors.Dark.error
        case .cancel: return .clear
        }
    }

    private var foregroundColor: Color {
        switch role {
        case .secondary: return Design.Colors.Dark.textPrimary
        case .primary, .finish: return Design.Colors.Dark.bgDeep
        case .cancel: return Design.Colors.Dark.textSecondary
        // 深色画布上的实心按钮一律"亮底 + 墨字"：浅锈红 #E58B7B 配白字只有 2.6:1，不达标。
        case .recording: return Design.Colors.Dark.bgDeep
        }
    }

    private var borderColor: Color {
        switch role {
        case .secondary: return Design.Colors.Dark.glassBorder
        default: return .clear
        }
    }
}

private struct ScanControlButtonStyle: ButtonStyle {
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed && !reduceMotion ? 0.97 : 1)
            .opacity(configuration.isPressed ? 0.85 : 1)
            .animation(reduceMotion ? nil : .easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}
