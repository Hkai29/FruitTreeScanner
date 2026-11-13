// TagEditView.swift
// 标签编辑页面 - 创建和编辑 GroupTag 对象。
//
// 草稿语义：表单只改本地草稿；保存提交并关闭，取消丢弃草稿。

import SwiftUI

struct TagEditView: View {
    @Environment(\.dismiss) var dismiss

    private let tag: GroupTag?
    private let onSave: ((GroupTag) -> Void)?

    @State private var name: String = ""
    @State private var selectedColor: String = "#6F8F63"

    private var isEditing: Bool {
        tag != nil
    }

    private var isSaveEnabled: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    init(tag: GroupTag? = nil, onSave: ((GroupTag) -> Void)? = nil) {
        self.tag = tag
        self.onSave = onSave
        _name = State(initialValue: tag?.name ?? "")
        _selectedColor = State(initialValue: tag?.colorHex ?? "#6F8F63")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                TagEntityEditForm(
                    name: $name,
                    selectedColor: $selectedColor,
                    namePlaceholder: L10n.TagManagement.tagPlaceholder
                )
            }
            .workspacePage()
            .safeAreaInset(edge: .bottom, spacing: 0) {
                saveBand
            }
            .navigationTitle(isEditing ? L10n.TagManagement.editTag : L10n.TagManagement.addTag)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.TagManagement.cancel) {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.Workspace.accent)
                }
            }
        }
    }

    // MARK: - 底部主操作

    private var saveBand: some View {
        VStack(spacing: 0) {
            Button(action: saveTag) {
                Label(L10n.TagManagement.save, systemImage: "checkmark")
            }
            .buttonStyle(WorkspacePrimaryButtonStyle())
            .disabled(!isSaveEnabled)
            .opacity(isSaveEnabled ? 1 : 0.5)
            .accessibilityLabel(L10n.TagManagement.save)
            .accessibilityIdentifier("tagManagement.save")
        }
        .padding(.horizontal, 20)
        .padding(.top, 10)
        .padding(.bottom, 8)
        .frame(maxWidth: 1080)
        .frame(maxWidth: .infinity)
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .top) {
            Rectangle()
                .fill(Design.Colors.Workspace.line)
                .frame(height: 0.5)
                .accessibilityHidden(true)
        }
    }

    // MARK: - Save
    private func saveTag() {
        let trimmedName = name.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmedName.isEmpty else { return }

        if var existingTag = tag {
            existingTag.name = trimmedName
            existingTag.colorHex = selectedColor
            onSave?(existingTag)
        } else {
            let newTag = GroupTag(name: trimmedName, colorHex: selectedColor)
            onSave?(newTag)
        }

        dismiss()
    }
}
