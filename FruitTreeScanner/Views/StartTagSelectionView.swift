// StartTagSelectionView.swift
// 第 4 步：标签。
//
// 标签片来自 TagStore 的真实数据；"不加标签"是显式选项，
// 便于把"不分组"和"还没决定"区分开。

import SwiftUI

struct Step4_TagSelection: View {
    let tags: [GroupTag]
    @Binding var selectedTagIds: Set<UUID>
    let onAddTag: () -> Void

    private static let noTagTitle = NSLocalizedString(
        "start.setup.tags.no_tag",
        value: "不加标签",
        comment: "Chip that clears the current tag selection"
    )

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            InstrumentSectionLabel(title: L10n.StartSetup.text(.tagsTitle))

            if !selectedTagIds.isEmpty {
                Text(L10n.StartSetup.selectedTagCount(selectedTagIds.count))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Design.Colors.Workspace.accent)
                    .fixedSize(horizontal: false, vertical: true)
            }

            if tags.isEmpty {
                StartEmptyAction(
                    icon: "tag",
                    title: L10n.StartSetup.text(.tagsEmptyTitle),
                    message: L10n.StartSetup.text(.tagsEmptyMessage),
                    buttonTitle: L10n.StartSetup.text(.tagsCreate),
                    action: onAddTag
                )
            } else {
                tagPanel
            }
        }
    }

    private var tagPanel: some View {
        FlowLayout(spacing: 8) {
            ForEach(tags) { tag in
                TagChip(tag: tag, isSelected: selectedTagIds.contains(tag.id)) {
                    toggle(tag)
                }
            }

            noTagChip

            addTagChip
        }
    }

    private var noTagChip: some View {
        InstrumentChip(title: Self.noTagTitle, isSelected: selectedTagIds.isEmpty) {
            selectedTagIds.removeAll()
        }
        .accessibilityValue(L10n.QuickTagging.selectionValue(isSelected: selectedTagIds.isEmpty))
    }

    private var addTagChip: some View {
        Button(action: onAddTag) {
            HStack(spacing: 4) {
                Image(systemName: "plus")
                    .font(.system(size: 11, weight: .semibold))
                Text(L10n.StartSetup.text(.tagsAdd))
                    .font(.footnote.weight(.semibold))
            }
            .foregroundColor(Design.Colors.Workspace.accent)
            .padding(.horizontal, 11)
            .padding(.vertical, 7)
            .frame(minHeight: 32)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(Design.Colors.Workspace.line, lineWidth: 1)
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.StartSetup.text(.tagsAdd))
    }

    private func toggle(_ tag: GroupTag) {
        if selectedTagIds.contains(tag.id) {
            selectedTagIds.remove(tag.id)
        } else {
            selectedTagIds.insert(tag.id)
        }
    }
}

struct TagChip: View {
    let tag: GroupTag
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        HStack(spacing: 5) {
            Circle()
                .fill(Color(hex: tag.colorHex))
                .frame(width: 8, height: 8)
                .accessibilityHidden(true)

            InstrumentChip(title: tag.name, isSelected: isSelected, action: action)
                .accessibilityValue(L10n.QuickTagging.selectionValue(isSelected: isSelected))
                .accessibilityHint(L10n.QuickTagging.tagHint)
        }
    }
}
