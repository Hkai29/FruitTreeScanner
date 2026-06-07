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
                title: "标签",
                subtitle: "可选。用于标记品种、试验组或管理状态。"
            )

            if tags.isEmpty {
                StartEmptyAction(
                    icon: "tag",
                    title: "还没有标签",
                    message: "标签可以跳过，不会影响扫描。",
                    buttonTitle: "创建标签",
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
                        Text("添加")
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
                Text("已选 \(selectedTagIds.count) 个标签")
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
