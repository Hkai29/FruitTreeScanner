import SwiftUI

struct DashboardHeroPanel: View {
    let records: [ScanFileRecord]
    let onStartScan: () -> Void
    let onQuickScan: () -> Void
    var compactLandscape: Bool = false

    private var summary: DashboardDailySummary {
        DashboardDailySummary(records: records)
    }

    private var panelHeight: CGFloat { compactLandscape ? 260 : 226 }

    var body: some View {
        if compactLandscape {
            GeometryReader { proxy in
                heroPanel(height: max(220, proxy.size.height))
            }
        } else {
            heroPanel(height: panelHeight)
        }
    }

    private func heroPanel(height: CGFloat) -> some View {
        ZStack(alignment: .bottomLeading) {
            LinearGradient(
                colors: [
                    Color.black.opacity(0.74),
                    Color.black.opacity(0.40),
                    Color.black.opacity(0.08)
                ],
                startPoint: .leading,
                endPoint: .trailing
            )

            LinearGradient(
                colors: [
                    Color.black.opacity(0.0),
                    Color.black.opacity(0.66)
                ],
                startPoint: .top,
                endPoint: .bottom
            )

            VStack(alignment: .leading, spacing: 16) {
                header

                Spacer(minLength: 0)

                HStack(spacing: 8) {
                    DashboardHeroMetric(title: L10n.Dashboard.today, value: "\(summary.scanCount)", suffix: L10n.Dashboard.scanCountUnit(summary.scanCount))
                    DashboardHeroMetric(title: L10n.Dashboard.yield, value: String(format: "%.1f", summary.yieldKg), suffix: "kg")
                    DashboardHeroMetric(title: L10n.Dashboard.trees, value: "\(summary.treeCount)", suffix: L10n.Dashboard.treeCountUnit(summary.treeCount))
                }

                HStack(spacing: 10) {
                    DashboardHeroButton(
                        title: L10n.Dashboard.startScan,
                        icon: "viewfinder",
                        imageName: "FeatureStartScan",
                        isPrimary: true,
                        compactLandscape: compactLandscape,
                        action: onStartScan
                    )

                    DashboardHeroButton(
                        title: L10n.Dashboard.quickCapture,
                        icon: "bolt.fill",
                        imageName: "FeatureQuickScan",
                        isPrimary: false,
                        compactLandscape: compactLandscape,
                        action: onQuickScan
                    )
                }
            }
            .padding(16)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height)
        .background {
            GeometryReader { proxy in
                Image("DashboardHero")
                    .resizable()
                    .scaledToFill()
                    .frame(width: proxy.size.width, height: proxy.size.height)
                    .clipped()
                    .accessibilityHidden(true)
            }
        }
        .clipShape(RoundedRectangle(cornerRadius: 14))
        .shadow(
            color: Color.black.opacity(0.22),
            radius: 12,
            y: 5
        )
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 4) {
                Text(L10n.Dashboard.workbenchTitle)
                    .font(.system(size: 21, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                Text(L10n.Dashboard.workbenchSubtitle)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            HStack(spacing: 6) {
                DashboardMiniIcon(icon: "leaf.fill", size: 20)
                    .accessibilityHidden(true)
                Text(L10n.Dashboard.fieldMode)
                    .font(.system(size: 11, weight: .semibold))
            }
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Color.black.opacity(0.32))
            .overlay(
                RoundedRectangle(cornerRadius: 999)
                    .stroke(Design.Colors.harvest.opacity(0.22), lineWidth: 1)
            )
            .clipShape(Capsule())
        }
    }
}

private struct DashboardHeroMetric: View {
    let title: String
    let value: String
    let suffix: String

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 4) {
            Text(title)
                .font(.system(size: 10, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer(minLength: 4)

            Text(value)
                .font(.system(size: 16, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text(suffix)
                .font(.system(size: 9, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 8)
        .frame(maxWidth: .infinity)
        .background(Color.black.opacity(0.30))
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .stroke(Color.black.opacity(0.22), lineWidth: 1)
        )
    }
}

private struct DashboardHeroButton: View {
    let title: String
    let icon: String
    let imageName: String
    let isPrimary: Bool
    var compactLandscape: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 8) {
                if !compactLandscape {
                    DashboardFeatureImage(
                        name: imageName,
                        accent: isPrimary ? Design.Colors.harvestDark : Design.Colors.Dark.info,
                        cornerRadius: 7
                    )
                    .frame(width: 34, height: 30)
                }

                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))

                Text(title)
                    .font(.system(size: compactLandscape ? 13 : 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isPrimary ? Color(hex: "171B14") : Design.Colors.Dark.textPrimary)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: 9)
                    .fill(isPrimary ? Design.Colors.harvestLight : Color.black.opacity(0.34))
            )
            .overlay(
                RoundedRectangle(cornerRadius: 9)
                    .stroke(isPrimary ? Design.Colors.harvest.opacity(0.55) : Color.white.opacity(0.10), lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityIdentifier(isPrimary ? "dashboard.hero.startScan" : "dashboard.hero.quickScan")
    }
}
