import SwiftUI

struct ScanFieldGuideOverlay: View {
    let onClose: () -> Void
    let onStartScan: () -> Void

    private var tips: [(icon: String, title: String, message: String)] {
        [
            (
                "figure.walk.motion",
                L10n.ScanGuidance.text(.slowCircleTitle),
                L10n.ScanGuidance.text(.slowCircleMessage)
            ),
            (
                "scope",
                L10n.ScanGuidance.text(.outlineFirstTitle),
                L10n.ScanGuidance.text(.outlineFirstMessage)
            ),
            (
                "square.3.layers.3d",
                L10n.ScanGuidance.text(.blindSpotsTitle),
                L10n.ScanGuidance.text(.blindSpotsMessage)
            ),
            (
                "ruler",
                L10n.ScanGuidance.text(.measureTitle),
                L10n.ScanGuidance.text(.measureMessage)
            ),
        ]
    }

    var body: some View {
        ZStack {
            Color.black.opacity(0.72)
                .ignoresSafeArea()

            VStack(spacing: 16) {
                HStack(alignment: .top) {
                    VStack(alignment: .leading, spacing: 6) {
                        Text(L10n.ScanGuidance.text(.guideTitle))
                            .font(.system(size: 22, weight: .bold))
                            .foregroundColor(.white)
                        Text(L10n.ScanGuidance.text(.guideSubtitle))
                            .font(.system(size: 13))
                            .foregroundColor(.white.opacity(0.72))
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer()

                    Button(action: onClose) {
                        Image(systemName: "xmark.circle.fill")
                            .font(.system(size: 26, weight: .semibold))
                            .foregroundColor(.white.opacity(0.9))
                    }
                    .buttonStyle(.plain)
                    .accessibilityLabel(L10n.ScanGuidance.text(.closeGuideAccessibility))
                }

                VStack(spacing: 10) {
                    ForEach(tips, id: \.title) { tip in
                        ScanFieldGuideTipRow(icon: tip.icon, title: tip.title, message: tip.message)
                    }
                }

                HStack(spacing: 10) {
                    Label(L10n.ScanGuidance.text(.defaultMode), systemImage: "viewfinder")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.harvest)
                        .padding(.horizontal, 10)
                        .padding(.vertical, 7)
                        .background(Design.Colors.harvest.opacity(0.14))
                        .clipShape(Capsule())

                    Text(L10n.ScanGuidance.text(.wholeTree))
                        .font(.system(size: 12, weight: .medium))
                        .foregroundColor(.white.opacity(0.72))

                    Spacer()
                }

                Button(action: onStartScan) {
                    Text(L10n.ScanGuidance.text(.start))
                        .font(.system(size: 16, weight: .semibold))
                        .foregroundColor(.black)
                        .frame(maxWidth: .infinity)
                        .frame(height: 48)
                        .background(Design.Colors.harvest)
                        .clipShape(RoundedRectangle(cornerRadius: 10))
                }
                .buttonStyle(.plain)
            }
            .padding(18)
            .frame(maxWidth: 420)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.large)
                    .fill(Design.Colors.Dark.hudBackground)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.Glass.large)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
            .padding(.horizontal, 20)
        }
        .transition(.opacity)
    }
}

private struct ScanFieldGuideTipRow: View {
    let icon: String
    let title: String
    let message: String

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: icon)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(width: 26, height: 26)
                .background(Design.Colors.harvest.opacity(0.12))
                .clipShape(RoundedRectangle(cornerRadius: 7))

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(.white)
                Text(message)
                    .font(.system(size: 12))
                    .foregroundColor(.white.opacity(0.68))
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer(minLength: 0)
        }
        .padding(10)
        .background(Color.white.opacity(0.06))
        .clipShape(RoundedRectangle(cornerRadius: 9))
    }
}
