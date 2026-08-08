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
                    .font(.body.weight(.semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .padding(.horizontal, Design.Space.md)
                    .padding(.vertical, Design.Space.sm)
                    .frame(minHeight: Design.Touch.minimumHeight)
                    .background(
                        Capsule()
                            .strokeBorder(Design.Colors.Dark.glassBorder, lineWidth: 1)
                    )
                }
            }

            if !selectedTagIds.isEmpty {
                Text(L10n.StartSetup.selectedTagCount(selectedTagIds.count))
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Design.Colors.forest)
                    .fixedSize(horizontal: false, vertical: true)
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
                    .accessibilityHidden(true)

                Text(tag.name)
                    .font(.body.weight(.medium))
                    .fixedSize(horizontal: false, vertical: true)

                if isSelected {
                    Image(systemName: "checkmark")
                        .font(.body.weight(.bold))
                        .accessibilityHidden(true)
                }
            }
            .foregroundColor(isSelected ? .white : Design.Colors.Dark.textPrimary)
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm)
            .frame(minHeight: Design.Touch.minimumHeight)
            .background(
                Capsule()
                    .fill(isSelected ? Design.Colors.forest : Design.Colors.Dark.bgElevated)
            )
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel(tag.name)
        .accessibilityValue(L10n.QuickTagging.selectionValue(isSelected: isSelected))
        .accessibilityHint(L10n.QuickTagging.tagHint)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}
