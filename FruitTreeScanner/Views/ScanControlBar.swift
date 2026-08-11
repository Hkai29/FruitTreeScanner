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
            if !isRecording {
                HStack(spacing: Design.Space.sm) {
                    ScanUtilityControlButton(
                        title: L10n.Scan.guideControl,
                        icon: "questionmark.circle",
                        isActive: false,
                        action: onToggleGuide,
                        height: utilityHeight,
                        fontSize: utilityFontSize,
                        accessibilityIdentifier: "scan.guide"
                    )

                    ScanUtilityControlButton(
                        title: L10n.Scan.measureControl,
                        icon: "ruler",
                        isActive: measurementController.isActive,
                        action: onToggleMeasurement,
                        height: utilityHeight,
                        fontSize: utilityFontSize,
                        accessibilityIdentifier: "scan.measure"
                    )
                }
            }

            HStack(spacing: Design.Space.sm) {
                ScanPrimaryControlButton(
                    title: L10n.Scan.cancelControl,
                    icon: "xmark",
                    role: .secondary,
                    isLoading: false,
                    action: onCancel,
                    height: primaryHeight,
                    fontSize: primaryFontSize,
                    iconSize: primaryIconSize,
                    accessibilityIdentifier: "scan.cancel"
                )

                ScanPrimaryControlButton(
                    title: recordingButtonTitle,
                    icon: isRecording ? "stop.fill" : "record.circle",
                    role: isRecording ? .recording : .primary,
                    isLoading: false,
                    action: onToggleRecording,
                    height: primaryHeight,
                    fontSize: primaryFontSize,
                    iconSize: primaryIconSize,
                    accessibilityIdentifier: "scan.record"
                )

                ScanPrimaryControlButton(
                    title: L10n.Scan.finishControl,
                    icon: "checkmark",
                    role: .finish,
                    isLoading: isEstimating,
                    action: onFinish,
                    height: primaryHeight,
                    fontSize: primaryFontSize,
                    iconSize: primaryIconSize,
                    accessibilityIdentifier: "scan.finish"
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
        if isRecording { return L10n.Scan.stopRecording }
        if hudState.pointCount > 0 { return L10n.Scan.recordAgain }
        return L10n.Scan.startRecording
    }
}

private struct ScanUtilityControlButton: View {
    let title: String
    let icon: String
    let isActive: Bool
    let action: () -> Void
    var height: CGFloat = 38
    var fontSize: CGFloat = 13
    var accessibilityIdentifier: String?

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
        .accessibilityIdentifier(accessibilityIdentifier ?? "scan.utility.\(title)")
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
    var accessibilityIdentifier: String?

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

                Text(isLoading ? L10n.Scan.processing : title)
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
        .accessibilityIdentifier(accessibilityIdentifier ?? "scan.primary.\(title)")
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
