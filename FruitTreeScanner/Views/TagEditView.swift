// TagEditView.swift
// 标签编辑页面 - 创建和编辑 GroupTag 对象

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
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                TagEntityEditForm(
                    name: $name,
                    selectedColor: $selectedColor,
                    namePlaceholder: L10n.TagManagement.tagPlaceholder
                )
            }
            .navigationTitle(isEditing ? L10n.TagManagement.editTag : L10n.TagManagement.addTag)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.Colors.Dark.bgDeep, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button(L10n.TagManagement.cancel) {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.forest)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.TagManagement.save) {
                        saveTag()
                    }
                    .foregroundColor(Design.Colors.forest)
                    .fontWeight(.semibold)
                    .disabled(!isSaveEnabled)
                }
            }
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
