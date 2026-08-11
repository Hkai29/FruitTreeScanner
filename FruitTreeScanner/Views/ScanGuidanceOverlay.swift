import SwiftUI

struct ScanGuidanceOverlay: View {
    @ObservedObject var hudState: ScanHUDState
    let isRecording: Bool

    @State private var showHint = false
    @State private var lastHint: ScanGuidanceHint = .none

    var body: some View {
        VStack {
            if isRecording {
                guidanceBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
            Spacer()
        }
        .onChange(of: hudState.guidanceHint) { newHint in
            handleHintChange(newHint)
        }
    }

    @ViewBuilder
    private var guidanceBanner: some View {
        if showHint, lastHint != .none {
            HStack(spacing: 10) {
                Image(systemName: lastHint.icon)
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(lastHint.iconColor)

                VStack(alignment: .leading, spacing: 2) {
                    Text(lastHint.title)
                        .font(.system(size: 14, weight: .semibold))
                        .foregroundColor(.white)
                    Text(lastHint.subtitle)
                        .font(.system(size: 11))
                        .foregroundColor(.white.opacity(0.7))
                }

                Spacer()

                // 速度指示条
                if lastHint == .tooFast || lastHint == .goodPace {
                    SpeedIndicator(speed: hudState.cameraSpeed)
                }
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 10)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                    .fill(lastHint.backgroundColor)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                    .stroke(lastHint.borderColor, lineWidth: 1)
            )
            .padding(.horizontal, Design.Space.md)
            .padding(.top, 80)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(lastHint.title)
            .accessibilityValue(lastHint.subtitle)
            .onAppear {
                ScanTransientAccessibility.announce(lastHint.accessibilityAnnouncement)
            }
            .onChange(of: lastHint) { newHint in
                ScanTransientAccessibility.announce(newHint.accessibilityAnnouncement)
            }
        }
    }

    private func handleHintChange(_ newHint: ScanGuidanceHint) {
        guard newHint != .none else {
            withAnimation(.easeOut(duration: 0.3)) {
                showHint = false
            }
            return
        }
        // 避免 goodPace 频繁闪烁
        if newHint == .goodPace && lastHint == .goodPace && showHint { return }

        lastHint = newHint
        withAnimation(.easeOut(duration: 0.25)) {
            showHint = true
        }

        // goodPace 自动消失
        if newHint == .goodPace {
            DispatchQueue.main.asyncAfter(deadline: .now() + 2.0) {
                if lastHint == .goodPace {
                    withAnimation(.easeOut(duration: 0.3)) {
                        showHint = false
                    }
                }
            }
        }
    }
}

// MARK: - Speed Indicator

private struct SpeedIndicator: View {
    let speed: Float

    private var normalizedSpeed: CGFloat {
        CGFloat(min(speed / 0.8, 1.0))
    }

    private var barColor: Color {
        if speed > 0.6 { return Design.Colors.apple }
        if speed > 0.35 { return Design.Colors.harvest }
        return Design.Colors.forest
    }

    var body: some View {
        VStack(spacing: 2) {
            GeometryReader { geo in
                ZStack(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 2)
                        .fill(Color.white.opacity(0.15))

                    RoundedRectangle(cornerRadius: 2)
                        .fill(barColor)
                        .frame(width: geo.size.width * normalizedSpeed)
                        .animation(.easeOut(duration: 0.2), value: normalizedSpeed)
                }
            }
            .frame(width: 40, height: 4)

            Text(String(format: "%.1fm/s", speed))
                .font(.system(size: 9, weight: .medium, design: .monospaced))
                .foregroundColor(.white.opacity(0.6))
        }
    }
}

// MARK: - Hint Properties

extension ScanGuidanceHint {
    var icon: String {
        switch self {
        case .none: return ""
        case .tooFast: return "speedometer"
        case .tooClose: return "arrow.up.backward.and.arrow.down.forward"
        case .tooFar: return "arrow.down.forward.and.arrow.up.backward"
        case .trackingLost: return "exclamationmark.triangle.fill"
        case .lowLight: return "sun.min.fill"
        case .sparseDepth: return "viewfinder.trianglebadge.exclamationmark"
        case .goodPace: return "checkmark.circle.fill"
        }
    }

    var iconColor: Color {
        switch self {
        case .none: return .clear
        case .tooFast: return Design.Colors.apple
        case .tooClose, .tooFar, .sparseDepth: return Design.Colors.harvest
        case .trackingLost: return Design.Colors.apple
        case .lowLight: return Design.Colors.harvest
        case .goodPace: return Design.Colors.forest
        }
    }

    var title: String {
        L10n.ScanGuidance.title(for: self)
    }

    var subtitle: String {
        L10n.ScanGuidance.message(for: self)
    }

    var accessibilityAnnouncement: String {
        L10n.ScanGuidance.announcement(for: self)
    }

    var backgroundColor: Color {
        switch self {
        case .none: return .clear
        case .tooFast, .trackingLost: return Design.Colors.apple.opacity(0.24)
        case .tooClose, .tooFar, .lowLight, .sparseDepth: return Design.Colors.harvest.opacity(0.20)
        case .goodPace: return Design.Colors.forest.opacity(0.16)
        }
    }

    var borderColor: Color {
        switch self {
        case .none: return .clear
        case .tooFast, .trackingLost: return Design.Colors.apple.opacity(0.42)
        case .tooClose, .tooFar, .lowLight, .sparseDepth: return Design.Colors.harvest.opacity(0.34)
        case .goodPace: return Design.Colors.forest.opacity(0.30)
        }
    }
}
