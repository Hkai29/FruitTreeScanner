// TagEditView.swift
// 标签编辑页面 - 创建和编辑 GroupTag 对象

import SwiftUI

struct TagEditView: View {
    @Environment(\.dismiss) var dismiss

    private let tag: GroupTag?
    private let onSave: ((GroupTag) -> Void)?

    @State private var name: String = ""
    @State private var selectedColor: String = "#34C759"

    private let colorOptions = [
        "#FF3B30", "#FF9500", "#FFCC00", "#34C759",
        "#007AFF", "#5856D6", "#AF52DE", "#8E8E93"
    ]

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
        _selectedColor = State(initialValue: tag?.colorHex ?? "#34C759")
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.bgBase.ignoresSafeArea()

                ScrollView {
                    VStack(spacing: Design.Space.lg) {
                        // Name Section
                        nameSection

                        // Color Section
                        colorSection
                    }
                    .padding(Design.Space.lg)
                }
            }
            .navigationTitle(isEditing ? "编辑标签" : "添加标签")
            .navigationBarTitleDisplayMode(.large)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Button("取消") {
                        dismiss()
                    }
                    .foregroundColor(Design.Colors.forest)
                }

                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("保存") {
                        saveTag()
                    }
                    .foregroundColor(Design.Colors.forest)
                    .fontWeight(.semibold)
                    .disabled(!isSaveEnabled)
                }
            }
        }
    }

    // MARK: - Name Section
    private var nameSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("名称")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textPrimary)

            TextField("输入标签名称", text: $name)
                .font(Design.Typography.body)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(Design.Space.md)
                .background(Design.Colors.Dark.bgSurface)
                .cornerRadius(Design.Radius.medium)
                .overlay(
                    RoundedRectangle(cornerRadius: Design.Radius.medium)
                        .stroke(
                            name.isEmpty ? Design.Colors.Dark.glassBorder : Design.Colors.forest.opacity(0.5),
                            lineWidth: 1
                        )
                )
        }
        .padding(Design.Space.md)
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.large)
    }

    // MARK: - Color Section
    private var colorSection: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text("颜色")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Color(hex: "3D3A36"))

            LazyVGrid(columns: [
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible()),
                GridItem(.flexible())
            ], spacing: Design.Space.md) {
                ForEach(colorOptions, id: \.self) { colorHex in
                    colorCircle(colorHex: colorHex)
                }
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.bgSurface)
        .cornerRadius(Design.Radius.large)
    }

    // MARK: - Color Circle
    private func colorCircle(colorHex: String) -> some View {
        Button {
            selectedColor = colorHex
        } label: {
            ZStack {
                Circle()
                    .fill(Color(hex: colorHex))
                    .frame(width: 44, height: 44)

                if selectedColor == colorHex {
                    Circle()
                        .strokeBorder(Color.white, lineWidth: 3)
                        .frame(width: 44, height: 44)

                    Circle()
                        .strokeBorder(Color(hex: colorHex).opacity(0.5), lineWidth: 5)
                        .frame(width: 52, height: 52)
                }
            }
        }
        .buttonStyle(.plain)
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

#Preview {
    TagEditView()
}