import SwiftUI
import UIKit

@MainActor
enum ScanTransientAccessibility {
    typealias AnnouncementPoster = (String) -> Void

    static func announce(_ message: String) {
        announce(
            message,
            isVoiceOverRunning: UIAccessibility.isVoiceOverRunning,
            poster: { message in
                UIAccessibility.post(notification: .announcement, argument: message)
            }
        )
    }

    static func announce(
        _ message: String,
        isVoiceOverRunning: Bool,
        poster: AnnouncementPoster
    ) {
        guard isVoiceOverRunning, !message.isEmpty else { return }
        poster(message)
    }
}

struct ScanPostCapturePanel: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let pointCount: Int
    let coveragePercent: Int
    let completion: ScanCompletion
    let canFinish: Bool
    let onResume: () -> Void
    let onFinish: () -> Void
    var showsActions = true

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            adaptiveLayout(spacing: 10) {
                Image(systemName: "cube.transparent")
                    .font(.system(size: 18, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.glow)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 2) {
                    Text(L10n.ScanPostCapture.title)
                        .font(.headline)
                        .foregroundColor(.white)
                        .fixedSize(horizontal: false, vertical: true)
                    Text(nextStepText)
                        .font(.footnote)
                        .foregroundColor(.white.opacity(0.68))
                        .fixedSize(horizontal: false, vertical: true)
                }
                .accessibilityElement(children: .combine)
                .frame(maxWidth: .infinity, alignment: .leading)

                Text("\(coveragePercent)%")
                    .font(.title3.weight(.medium)).monospacedDigit()
                    .foregroundColor(statusColor)
                    .accessibilityLabel(L10n.ScanPostCapture.coverage)
                    .accessibilityValue("\(coveragePercent)%")
            }

            adaptiveLayout(spacing: 8) {
                ScanPostCaptureMetric(
                    label: L10n.ScanPostCapture.metricPointCloud,
                    value: ScanHUDValueFormatter.pointCount(pointCount)
                )
                ScanPostCaptureMetric(
                    label: L10n.ScanPostCapture.metricDuration,
                    value: completion.formattedDuration
                )
                ScanPostCaptureMetric(
                    label: L10n.ScanPostCapture.metricStatus,
                    value: L10n.ScanPostCapture.statusTitle(for: completion.coverageStatus)
                )
            }

            if showsActions {
                adaptiveLayout(spacing: 8) {
                Button(action: onResume) {
                    Label(L10n.ScanPostCapture.resumeAction, systemImage: "plus.viewfinder")
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(.white)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .frame(minHeight: 54)
                        .background(Color.white.opacity(0.06))
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
                        )
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
                }
                .buttonStyle(.plain)
                .accessibilityHint(L10n.ScanPostCapture.resumeAccessibilityHint)

                Button(action: onFinish) {
                    Label(
                        canFinish ? L10n.ScanPostCapture.finishAction : L10n.ScanExport.requirementsAction,
                        systemImage: canFinish ? "checkmark" : "info.circle"
                    )
                        .font(.subheadline.weight(.semibold))
                        .foregroundColor(canFinish ? Design.Colors.Dark.bgDeep : Design.Colors.Dark.textPrimary)
                        .frame(maxWidth: .infinity)
                        .padding(.vertical, 10)
                        .frame(minHeight: 54)
                        .background(canFinish ? Design.Colors.Dark.glow : Color.white.opacity(0.06))
                        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                                .stroke(canFinish ? Color.clear : Design.Colors.Dark.glassBorder, lineWidth: 1)
                        )
                }
                .buttonStyle(.plain)
                .disabled(!canFinish)
                .opacity(canFinish ? 1 : 0.55)
                .accessibilityHint(
                    canFinish
                        ? L10n.ScanPostCapture.finishAccessibilityHint(canFinish: true)
                        : L10n.ScanExport.requirementsHint
                )
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Dark.bgSurface.opacity(0.94))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .frame(maxWidth: 760)
        .padding(.horizontal, 16)
        .padding(.bottom, Design.Space.sm)
    }

    private var nextStepText: String {
        L10n.ScanPostCapture.guidance(for: completion.coverageStatus)
    }

    private func adaptiveLayout<Content: View>(spacing: CGFloat, @ViewBuilder content: () -> Content) -> some View {
        let layout = dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: spacing))
            : AnyLayout(HStackLayout(spacing: spacing))
        return layout { content() }
    }

    private var statusColor: Color {
        switch completion.coverageStatus {
        case .complete, .good: return Design.Colors.Dark.success
        case .continueScanning, .insufficient: return Design.Colors.Dark.warning
        }
    }
}

private struct ScanPostCaptureMetric: View {
    let label: String
    let value: String

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textMuted)
            Text(value)
                .font(.subheadline.weight(.medium)).monospacedDigit()
                .foregroundColor(.white)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 7)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

struct ScanCoverageCompleteToast: View {
    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            Image(systemName: "checkmark.circle").font(.title3)
                .foregroundColor(Design.Colors.Dark.glow).accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Scan.coverageComplete).font(.headline)
                Text(L10n.Scan.coverageCompleteHint)
                    .font(.footnote).foregroundColor(Design.Colors.Dark.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .foregroundColor(Design.Colors.Dark.textPrimary)
        .padding(14)
        .background(Design.Colors.Dark.bgSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .frame(maxWidth: 760)
        .padding(.horizontal, 16)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(L10n.Scan.coverageComplete)
        .accessibilityValue(L10n.Scan.coverageCompleteHint)
        .onAppear {
            ScanTransientAccessibility.announce(
                L10n.Scan.transientAnnouncement(title: L10n.Scan.coverageComplete,
                                               message: L10n.Scan.coverageCompleteHint)
            )
        }
        .transition(.opacity)
    }
}

struct ScanReadinessOverlay: View {
    let scanReadiness: ScanReadiness
    let onOpenSettings: () -> Void
    let onDismiss: () -> Void
    var notice: String? = nil

    var body: some View {
        if scanReadiness.blocksScanning {
            GeometryReader { geometry in
                if geometry.size.height < 500 {
                    VStack(spacing: 16) {
                        ScrollView { information }
                        HStack(spacing: 16) { actions }
                    }
                    .padding(24)
                    .frame(maxWidth: 520, maxHeight: max(0, geometry.size.height - 32))
                    .background(Design.Colors.Dark.bgSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous))
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                            .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
                    )
                    .padding(.horizontal, 20)
                    .frame(maxWidth: .infinity, maxHeight: .infinity)
                } else {
                    ScrollView {
                        VStack(spacing: 20) {
                            information
                            VStack(spacing: 12) { actions }
                        }
                        .padding(24)
                        .frame(maxWidth: 420)
                        .background(Design.Colors.Dark.bgSurface.opacity(0.96), in: RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous))
                        .overlay(
                            RoundedRectangle(cornerRadius: Design.Radius.xl, style: .continuous)
                                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
                        )
                        .padding(.horizontal, 20)
                        .frame(maxWidth: .infinity, minHeight: geometry.size.height, alignment: .center)
                    }
                }
            }
            .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }

    private var information: some View {
        VStack(spacing: 20) {
            if scanReadiness == .checking {
                ProgressView().tint(Design.Colors.Dark.glow)
            }
            VStack(spacing: 12) {
                Text(scanReadiness.title).font(.title2.weight(.semibold))
                Text(scanReadiness.message)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
            .fixedSize(horizontal: false, vertical: true)
            .multilineTextAlignment(.center)
            if let notice { ScanNoticeToast(message: notice) }
        }
    }

    @ViewBuilder
    private var actions: some View {
        if scanReadiness == .cameraDenied {
            Button(action: onOpenSettings) {
                Text(L10n.ScanReadiness.openSettings)
                    .font(.headline)
                    .foregroundColor(Design.Colors.Dark.bgDeep)
                    .frame(maxWidth: .infinity, minHeight: 44)
                    .padding(.vertical, 8)
                    .background(Design.Colors.Dark.glow, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
        }
        Button(action: onDismiss) {
            Text(L10n.ScanReadiness.back).font(.subheadline)
                .frame(maxWidth: .infinity, minHeight: 44)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
    }
}

struct ScanNoticeToast: View {
    let message: String

    var body: some View {
        Text(message)
            .font(.footnote)
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .fixedSize(horizontal: false, vertical: true)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(14)
            .background(Design.Colors.Dark.bgSurface.opacity(0.94), in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .frame(maxWidth: 760)
            .padding(.horizontal, 16)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(message)
            .onAppear { ScanTransientAccessibility.announce(message) }
            .onChange(of: message) { ScanTransientAccessibility.announce($0) }
            .transition(.opacity)
    }
}
