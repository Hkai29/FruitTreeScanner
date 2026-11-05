// DashboardHeroPanel.swift
// 工作台主读数面板。没有照片、没有渐变封面 —— 用真实读数和测绘网格表达身份。

import SwiftUI

struct DashboardHeroPanel: View {
    let summary: DashboardDailySummary
    let onStartScan: () -> Void
    let onQuickScan: () -> Void
    var compactLandscape: Bool = false

    private var panelHeight: CGFloat { compactLandscape ? 260 : 214 }

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
        VStack(alignment: .leading, spacing: 0) {
            header
                .padding(.horizontal, 16)
                .padding(.top, 14)
                .padding(.bottom, 12)
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
                }

            HStack(spacing: 0) {
                DashboardHeroMetric(title: L10n.Dashboard.today, value: "\(summary.scanCount)", suffix: L10n.Dashboard.scanCountUnit(summary.scanCount))
                metricDivider
                DashboardHeroMetric(title: L10n.Dashboard.yield, value: String(format: "%.1f", summary.yieldKg), suffix: "kg")
                metricDivider
                DashboardHeroMetric(title: L10n.Dashboard.trees, value: "\(summary.treeCount)", suffix: L10n.Dashboard.treeCountUnit(summary.treeCount))
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 14)

            HStack(spacing: 10) {
                DashboardHeroButton(
                    title: L10n.Dashboard.startScan,
                    icon: "viewfinder",
                    isPrimary: true,
                    compactLandscape: compactLandscape,
                    action: onStartScan
                )
                DashboardHeroButton(
                    title: L10n.Dashboard.quickCapture,
                    icon: "bolt",
                    isPrimary: false,
                    compactLandscape: compactLandscape,
                    action: onQuickScan
                )
            }
            .padding(.horizontal, 16)
            .padding(.bottom, 16)

            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity)
        .frame(height: height, alignment: .top)
        .background {
            Canvas { context, size in
                var path = Path()
                var x: CGFloat = 22
                while x < size.width {
                    path.move(to: CGPoint(x: x, y: 0))
                    path.addLine(to: CGPoint(x: x, y: size.height))
                    x += 22
                }
                var y: CGFloat = 22
                while y < size.height {
                    path.move(to: CGPoint(x: 0, y: y))
                    path.addLine(to: CGPoint(x: size.width, y: y))
                    y += 22
                }
                context.stroke(path, with: .color(Design.Colors.Workspace.line.opacity(0.45)), lineWidth: 0.5)
            }
            .opacity(0.55)
        }
        .background(Design.Colors.Workspace.surface)
        .clipShape(RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }

    private var metricDivider: some View {
        Rectangle()
            .fill(Design.Colors.Workspace.line)
            .frame(width: 0.5, height: 30)
            .accessibilityHidden(true)
    }

    private var header: some View {
        HStack(alignment: .top) {
            VStack(alignment: .leading, spacing: 3) {
                Text(L10n.Dashboard.workbenchTitle)
                    .font(.system(.headline, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                Text(L10n.Dashboard.workbenchSubtitle)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.secondary)
            }

            Spacer(minLength: 8)

            HStack(spacing: 5) {
                Image(systemName: "location.viewfinder")
                    .font(.system(size: 10, weight: .semibold))
                Text(L10n.Dashboard.fieldMode)
                    .font(.system(.caption2, design: .default).weight(.semibold))
            }
            .foregroundColor(Design.Colors.Workspace.accent)
            .padding(.horizontal, 8)
            .padding(.vertical, 5)
            .background(Design.Colors.Workspace.accentSoft, in: RoundedRectangle(cornerRadius: 4, style: .continuous))
        }
    }
}

private struct DashboardHeroMetric: View {
    let title: String
    let value: String
    let suffix: String

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(alignment: .firstTextBaseline, spacing: 4) {
                titleLabel.fixedSize()
                Spacer(minLength: 4)
                reading.fixedSize()
            }
            VStack(alignment: .leading, spacing: 4) {
                titleLabel
                reading
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
        .frame(maxWidth: .infinity)
    }

    private var titleLabel: some View {
        Text(title)
            .font(.system(.caption2, design: .default).weight(.semibold))
            .tracking(0.5)
            .foregroundColor(Design.Colors.Workspace.muted)
            .lineLimit(1)
    }

    private var reading: some View {
        HStack(alignment: .firstTextBaseline, spacing: 3) {
            Text(value)
                .font(.system(.title3, design: .default).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
            Text(suffix)
                .font(.system(.caption2, design: .default).weight(.medium))
                .foregroundColor(Design.Colors.Workspace.secondary)
                .lineLimit(1)
                .fixedSize()
        }
    }
}

private struct DashboardHeroButton: View {
    let title: String
    let icon: String
    let isPrimary: Bool
    var compactLandscape: Bool = false
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 7) {
                Image(systemName: icon)
                    .font(.system(size: 12, weight: .semibold))
                Text(title)
                    .font(.system(size: compactLandscape ? 13 : 14, weight: .semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.85)
            }
            .foregroundColor(isPrimary ? .white : Design.Colors.Workspace.ink)
            .frame(maxWidth: .infinity, minHeight: 44)
            .background(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(isPrimary ? Design.Colors.Workspace.accent : Design.Colors.Workspace.surface)
            )
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(isPrimary ? Color.clear : Design.Colors.Workspace.line, lineWidth: 1)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityIdentifier(isPrimary ? "dashboard.hero.startScan" : "dashboard.hero.quickScan")
    }
}
