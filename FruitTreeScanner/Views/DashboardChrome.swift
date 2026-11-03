// DashboardChrome.swift
// 顶部导航：产品标识 + 两个工具入口。

import SwiftUI

struct TopNavigationBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let onSettingsTap: () -> Void
    var onHistoryTap: (() -> Void)? = nil
    var historyCount: Int = 0
    var title: String? = nil
    var subtitle: String? = nil

    private var resolvedTitle: String {
        title ?? NSLocalizedString("workspace.product_name", value: "果树扫描", comment: "")
    }

    private var resolvedSubtitle: String {
        subtitle ?? NSLocalizedString(
            "workspace.product_tagline",
            value: "ORCHARD LIDAR SCANNER",
            comment: "Product mark line under the workspace title"
        )
    }

    var body: some View {
        HStack(alignment: .center, spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                Text(resolvedTitle)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .accessibilityAddTraits(.isHeader)
                    .fixedSize(horizontal: false, vertical: true)
                if !dynamicTypeSize.isAccessibilitySize {
                    Text(resolvedSubtitle)
                        .font(.system(.caption2, design: .default).weight(.semibold))
                        .tracking(0.8)
                        .foregroundColor(Design.Colors.Workspace.muted)
                        .lineLimit(1)
                        .minimumScaleFactor(0.8)
                }
            }

            Spacer(minLength: 8)

            HStack(spacing: 8) {
                if let onHistoryTap {
                    InstrumentToolButton(
                        systemImage: "clock.arrow.circlepath",
                        label: L10n.Dashboard.scanHistoryAccessibilityLabel(recordCount: historyCount),
                        action: onHistoryTap
                    )
                    .accessibilityIdentifier("dashboard.action.history")
                }
                InstrumentToolButton(
                    systemImage: "gearshape",
                    label: L10n.Dashboard.settingsAccessibilityLabel,
                    action: onSettingsTap
                )
                .accessibilityIdentifier("dashboard.action.settings")
            }
        }
        .padding(.bottom, 2)
    }
}

/// 底部工作区分栏：果园空间 / 档案 / 分析。
/// 选中项用一条 2pt 信号青指示线，而不是仅靠变色。
struct WorkspaceTabBar: View {
    let selection: AppMode
    let onSelect: (AppMode) -> Void

    var body: some View {
        HStack(spacing: 0) {
            tab(.scan, title: L10n.Dashboard.scanMode, icon: "map")
            tab(.history, title: WorkspaceText.archive, icon: "square.stack.3d.up")
            tab(.analytics, title: WorkspaceText.analysis, icon: "chart.xyaxis.line")
        }
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .top) {
            Design.Colors.Workspace.line.frame(height: 0.5)
        }
    }

    private func tab(_ mode: AppMode, title: String, icon: String) -> some View {
        Button { onSelect(mode) } label: {
            VStack(spacing: 3) {
                HStack(spacing: 0) {
                    if selection == mode {
                        Rectangle()
                            .fill(Design.Colors.Workspace.accent)
                            .frame(width: 18, height: 2)
                    }
                }
                .frame(height: 2)
                Image(systemName: icon)
                    .font(.system(size: 17, weight: selection == mode ? .semibold : .regular))
                Text(title)
                    .font(.caption.weight(selection == mode ? .semibold : .regular))
                    .fixedSize(horizontal: false, vertical: true)
            }
            .foregroundColor(selection == mode ? Design.Colors.Workspace.accent : Design.Colors.Workspace.muted)
            .frame(maxWidth: .infinity, minHeight: 50)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dashboard.tab.\(mode.rawValue)")
        .accessibilityLabel(title)
        .accessibilityAddTraits(selection == mode ? .isSelected : [])
    }
}
