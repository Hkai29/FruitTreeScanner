import SwiftUI

struct ScanGuidanceOverlay: View {
    @ObservedObject var hudState: ScanHUDState
    let isRecording: Bool

    @StateObject private var presentationController = ScanGuidancePresentationController()

    var body: some View {
        VStack(spacing: 0) {
            if isRecording {
                guidanceBanner
                    .transition(.move(edge: .top).combined(with: .opacity))
            }
        }
        .onChange(of: hudState.guidanceHint) { newHint in
            presentationController.update(hint: newHint, isRecording: isRecording)
        }
        .onChange(of: isRecording) { newValue in
            presentationController.update(
                hint: hudState.guidanceHint,
                isRecording: newValue
            )
        }
        .onAppear {
            presentationController.update(
                hint: hudState.guidanceHint,
                isRecording: isRecording
            )
        }
        .onDisappear {
            presentationController.invalidate()
        }
    }

    @ViewBuilder
    private var guidanceBanner: some View {
        if let visibleHint = presentationController.visibleHint {
            ScanGuidanceBannerCard(hint: visibleHint, speed: hudState.cameraSpeed)
            .frame(maxWidth: 760)
            .padding(.horizontal, 24)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(visibleHint.title)
            .accessibilityValue(visibleHint.subtitle)
            .onAppear {
                ScanTransientAccessibility.announce(visibleHint.accessibilityAnnouncement)
            }
            .onChange(of: visibleHint) { newHint in
                ScanTransientAccessibility.announce(newHint.accessibilityAnnouncement)
            }
        }
    }
}

struct ScanGuidanceBannerCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let hint: ScanGuidanceHint
    let speed: Float

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: hint.icon)
                .font(.title3.weight(.medium))
                .foregroundColor(hint.iconColor)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 2) {
                Text(hint.title)
                    .font(.headline)
                    .foregroundColor(.white)
                    .fixedSize(horizontal: false, vertical: true)
                Text(hint.subtitle)
                    .font(.footnote)
                    .foregroundColor(.white.opacity(0.7))
                    .fixedSize(horizontal: false, vertical: true)
                if dynamicTypeSize.isAccessibilitySize, hint == .tooFast || hint == .goodPace {
                    SpeedIndicator(speed: speed)
                }
            }
            .layoutPriority(1)

            Spacer(minLength: 4)

            if !dynamicTypeSize.isAccessibilitySize, hint == .tooFast || hint == .goodPace {
                SpeedIndicator(speed: speed)
            }
        }
        .padding(16)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .fill(Design.Colors.Dark.controlSurface)
        )
        .overlay(alignment: .leading) {
            RoundedRectangle(cornerRadius: 1).fill(hint.iconColor)
                .frame(width: 2).padding(.vertical, 16).accessibilityHidden(true)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(hint.title)
        .accessibilityValue(hint.subtitle)
    }
}

@MainActor
final class ScanGuidancePresentationController: ObservableObject {
    typealias DismissDelay = @Sendable () async -> Void

    @Published private(set) var visibleHint: ScanGuidanceHint?

    private let dismissDelay: DismissDelay
    private var dismissTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        dismissDelay: @escaping DismissDelay = {
            do {
                try await Task.sleep(nanoseconds: 2_000_000_000)
            } catch {
                return
            }
        }
    ) {
        self.dismissDelay = dismissDelay
    }

    @discardableResult
    func update(
        hint: ScanGuidanceHint,
        isRecording: Bool
    ) -> Task<Void, Never>? {
        generation &+= 1
        let operationGeneration = generation
        dismissTask?.cancel()
        dismissTask = nil

        guard isRecording, hint != .none else {
            setVisibleHint(nil)
            return nil
        }

        setVisibleHint(hint)
        guard hint == .goodPace else { return nil }

        let dismissDelay = dismissDelay
        let task = Task { [weak self] in
            await dismissDelay()
            guard !Task.isCancelled, let self else { return }
            guard self.generation == operationGeneration else { return }
            self.setVisibleHint(nil)
            self.dismissTask = nil
        }
        dismissTask = task
        return task
    }

    func invalidate() {
        generation &+= 1
        dismissTask?.cancel()
        dismissTask = nil
        setVisibleHint(nil)
    }

    private func setVisibleHint(_ hint: ScanGuidanceHint?) {
        guard visibleHint != hint else { return }
        withAnimation(.easeOut(duration: hint == nil ? 0.3 : 0.25)) {
            visibleHint = hint
        }
    }
}

// MARK: - Speed Indicator

private struct SpeedIndicator: View {
    @ScaledMetric(relativeTo: .caption) private var barWidth: CGFloat = 48
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
            .frame(width: barWidth, height: 4)

            Text(L10n.ScanGuidance.speed(speed))
                .font(.caption).monospacedDigit()
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
        case .tooFast: return Design.Colors.Dark.error
        case .tooClose, .tooFar, .sparseDepth: return Design.Colors.Dark.warning
        case .trackingLost: return Design.Colors.Dark.error
        case .lowLight: return Design.Colors.Dark.warning
        case .goodPace: return Design.Colors.Dark.success
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
