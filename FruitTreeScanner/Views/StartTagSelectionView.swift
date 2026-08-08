// StartTagSelectionView.swift
// 标签选择步骤

import SwiftUI

struct Step4_TagSelection: View {
    let tags: [GroupTag]
    @Binding var selectedTagIds: Set<UUID>
    let onAddTag: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            StartStepHeader(
                step: 4,
                totalSteps: 5,
                title: L10n.StartSetup.text(.tagsTitle),
                subtitle: L10n.StartSetup.text(.tagsSubtitle)
            )

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
        VStack(alignment: .leading, spacing: Design.Space.md) {
            FlowLayout(spacing: Design.Space.sm) {
                ForEach(tags) { tag in
                    TagChip(tag: tag, isSelected: selectedTagIds.contains(tag.id)) {
                        toggle(tag)
                    }
                }

                Button(action: onAddTag) {
                    HStack(spacing: 4) {
                        Image(systemName: "plus")
                        Text(L10n.StartSetup.text(.tagsAdd))
                    }
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                    .background(
                        Capsule()
                            .strokeBorder(Design.Colors.Dark.glassBorder, lineWidth: 1)
                    )
                }
            }

            if !selectedTagIds.isEmpty {
                Text(L10n.StartSetup.selectedTagCount(selectedTagIds.count))
                    .font(.system(size: 12, weight: .semibold))
                    .foregroundColor(Design.Colors.forest)
            }
        }
        .padding(Design.Space.md)
        .startSurface(cornerRadius: 10)
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
        Button(action: action) {
            HStack(spacing: Design.Space.xs) {
                Circle()
                    .fill(Color(hex: tag.colorHex))
                    .frame(width: 10, height: 10)

                Text(tag.name)
                    .font(.system(size: 13, weight: .medium))

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.system(size: 12, weight: .bold))
                }
            }
            .foregroundColor(isSelected ? .white : Design.Colors.Dark.textPrimary)
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm)
            .background(
                Capsule()
                    .fill(isSelected ? Design.Colors.forest : Design.Colors.Dark.bgElevated)
            )
        }
        .buttonStyle(ScaleButtonStyle())
    }
}
