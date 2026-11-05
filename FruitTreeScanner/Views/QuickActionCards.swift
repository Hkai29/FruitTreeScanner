// QuickActionCards.swift
// 工具条目：面板内的发丝分隔条目。不用带插图的磁贴。

import SwiftUI

struct QuickActionCard: View {
    let action: QuickAction
    var compactLandscape: Bool = false
    var onTap: (() -> Void)? = nil

    var body: some View {
        Button { onTap?() } label: {
            if compactLandscape {
                compactLabel
            } else {
                fullLabel
            }
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.Dashboard.quickActionAccessibilityLabel(title: action.title, description: action.description))
        .accessibilityIdentifier("dashboard.action.\(action.kind.rawValue)")
    }

    private var fullLabel: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: action.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(action.color)
                .frame(width: 22, height: 22)
                .background(
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(action.color.opacity(0.10))
                )
                .accessibilityHidden(true)
            VStack(alignment: .leading, spacing: 2) {
                Text(action.title)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)
                Text(action.description)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 12)
        .padding(.horizontal, 12)
        .frame(maxWidth: .infinity, minHeight: 48, alignment: .leading)
        .contentShape(Rectangle())
    }

    private var compactLabel: some View {
        VStack(alignment: .leading, spacing: 4) {
            Image(systemName: action.icon)
                .font(.system(size: 14, weight: .medium))
                .foregroundColor(action.color)
            Text(action.title)
                .font(.caption.weight(.medium))
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.8)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(9)
        .background(Design.Colors.Workspace.surfaceQuiet, in: RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }
}

/// 工具分组：带标签条的白底面板，组内以发丝线分隔。
struct DashboardToolGroup: View {
    let title: String
    let icon: String
    let actions: [QuickAction]
    var compactLandscape: Bool = false
    var showsHeader: Bool = true
    var onAction: ((QuickAction) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if showsHeader {
                HStack(spacing: 6) {
                    Image(systemName: icon)
                        .font(.system(size: 11, weight: .semibold))
                        .foregroundColor(Design.Colors.Workspace.accent)
                        .accessibilityHidden(true)
                    Text(title)
                        .instrumentLabel()
                }
                .padding(.horizontal, 12)
                .padding(.vertical, 9)
                .background(Design.Colors.Workspace.inset.opacity(0.5))
                .overlay(alignment: .bottom) {
                    Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
                }
            }

            if actions.isEmpty {
                Text(L10n.Dashboard.noToolsInGroup)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.muted)
                    .padding(12)
            } else {
                ForEach(Array(actions.enumerated()), id: \.element.id) { index, action in
                    QuickActionCard(action: action, compactLandscape: compactLandscape) { onAction?(action) }
                    if index < actions.count - 1 {
                        Rectangle().fill(Design.Colors.Workspace.line).frame(height: 0.5)
                    }
                }
            }
        }
        .background(Design.Colors.Workspace.surface, in: RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous))
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Workspace.line, lineWidth: 1)
        )
    }
}

struct QuickActionTile: View {
    let action: QuickAction
    var onTap: (() -> Void)? = nil
    var body: some View { QuickActionCard(action: action, compactLandscape: true, onTap: onTap) }
}
