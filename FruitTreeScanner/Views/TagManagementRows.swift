// TagManagementRows.swift
// 地块 / 标签行：色块 + 名称 + 真实树数 + 编辑与删除动作。
//
// 树数直接来自 TagStore 的真实分配关系，删除仍走原有确认流程。

import SwiftUI

struct PlotRowView: View {
    let plot: Plot
    let treeCount: Int
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        TagManagementRow(
            colorHex: plot.colorHex,
            title: plot.name,
            detail: L10n.TagManagement.treeCount(treeCount),
            editAccessibilityHint: L10n.TagManagement.editPlotHint,
            deleteAccessibilityLabel: L10n.TagManagement.deletePlotAction,
            onEdit: onEdit,
            onDelete: onDelete
        )
    }
}

struct TagRowView: View {
    let tag: GroupTag
    let treeCount: Int
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        TagManagementRow(
            colorHex: tag.colorHex,
            title: tag.name,
            detail: L10n.TagManagement.treeCount(treeCount),
            editAccessibilityHint: L10n.TagManagement.editTagHint,
            deleteAccessibilityLabel: L10n.TagManagement.deleteTagAction,
            onEdit: onEdit,
            onDelete: onDelete
        )
    }
}

/// 地块与标签共用的行：左侧色块标识，右侧编辑与删除。
struct TagManagementRow: View {
    let colorHex: String
    let title: String
    let detail: String
    var editAccessibilityHint: String? = nil
    var deleteAccessibilityLabel: String? = nil
    var onEdit: (() -> Void)? = nil
    var onDelete: (() -> Void)? = nil

    var body: some View {
        HStack(spacing: 0) {
            Button(action: { onEdit?() }) {
                HStack(spacing: 10) {
                    RoundedRectangle(cornerRadius: 5, style: .continuous)
                        .fill(Color(hex: colorHex))
                        .frame(width: 16, height: 16)
                        .accessibilityHidden(true)

                    VStack(alignment: .leading, spacing: 2) {
                        Text(title)
                            .font(.subheadline.weight(.medium))
                            .foregroundColor(Design.Colors.Workspace.ink)
                            .fixedSize(horizontal: false, vertical: true)

                        Text(detail)
                            .font(.caption)
                            .foregroundColor(Design.Colors.Workspace.muted)
                            .fixedSize(horizontal: false, vertical: true)
                    }

                    Spacer(minLength: 8)

                    InstrumentChevron()
                }
                .padding(.vertical, 12)
                .frame(maxWidth: .infinity, minHeight: Design.Touch.minimumHeight, alignment: .leading)
                .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel(title)
            .accessibilityValue(detail)
            .accessibilityHint(editAccessibilityHint ?? "")
            .accessibilityAction(named: Text(deleteAccessibilityLabel ?? L10n.Common.delete)) {
                onDelete?()
            }

            if let onDelete {
                Button(action: { onDelete() }) {
                    Image(systemName: "trash")
                        .font(.system(size: 13, weight: .medium))
                        .foregroundColor(Design.Colors.Workspace.secondary)
                        .frame(width: Design.Touch.minimumWidth, height: Design.Touch.minimumHeight)
                        .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
                .accessibilityLabel(deleteAccessibilityLabel ?? L10n.Common.delete)
            }
        }
    }
}
