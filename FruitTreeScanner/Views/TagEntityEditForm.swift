// TagEntityEditForm.swift
// 地块 / 标签共用的编辑表单：名称 + 颜色。
//
// 名称用仪器表单行与输入框；颜色为固定调色板。表单只改草稿，
// 是否提交由外层决定（取消即丢弃草稿）。

import SwiftUI

struct TagEntityEditForm: View {
    @Binding var name: String
    @Binding var selectedColor: String

    let namePlaceholder: String

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    private let colorOptions = [
        "#6F8F63", "#B8843A", "#4D7588", "#B8564B",
        "#8A7657", "#6C7B58", "#7E8580", "#34362F"
    ]

    private let contentWidth: CGFloat = 1080

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                namePanel
                colorPanel
            }
            .frame(maxWidth: contentWidth, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 14)
            .padding(.bottom, 24)
            .frame(maxWidth: .infinity)
        }
    }

    // MARK: - 名称

    private var namePanel: some View {
        InstrumentPanel {
            nameControl
        }
    }

    @ViewBuilder
    private var nameControl: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: 6) {
                Text(L10n.TagManagement.nameLabel)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Workspace.ink)
                InstrumentTextField(placeholder: namePlaceholder, text: $name)
            }
            .padding(.vertical, 10)
            .padding(.horizontal, 14)
        } else {
            InstrumentFormRow(label: L10n.TagManagement.nameLabel) {
                InstrumentTextField(placeholder: namePlaceholder, text: $name)
                    .frame(maxWidth: 260)
            }
        }
    }

    // MARK: - 颜色

    private var colorPanel: some View {
        InstrumentPanel {
            VStack(alignment: .leading, spacing: 12) {
                Text(L10n.TagManagement.colorLabel)
                    .instrumentLabel()
                    .accessibilityAddTraits(.isHeader)

                LazyVGrid(
                    columns: [GridItem(.adaptive(minimum: 56), spacing: 12)],
                    spacing: 12
                ) {
                    ForEach(colorOptions, id: \.self) { colorHex in
                        colorSwatch(colorHex)
                    }
                }
            }
        }
    }

    private func colorSwatch(_ colorHex: String) -> some View {
        Button {
            selectedColor = colorHex
        } label: {
            ZStack {
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .fill(Color(hex: colorHex))

                if selectedColor == colorHex {
                    Image(systemName: "checkmark")
                        .font(.system(size: 14, weight: .bold))
                        .foregroundStyle(.white)
                        .accessibilityHidden(true)
                }
            }
            .frame(maxWidth: .infinity)
            .frame(minHeight: Design.Touch.minimumHeight)
            .overlay(
                RoundedRectangle(cornerRadius: Design.Radius.control, style: .continuous)
                    .stroke(
                        selectedColor == colorHex
                            ? Design.Colors.Workspace.ink
                            : Design.Colors.Workspace.line,
                        lineWidth: selectedColor == colorHex ? 2 : 1
                    )
            )
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .accessibilityLabel(L10n.TagManagement.colorAccessibilityLabel(for: colorHex))
        .accessibilityValue(
            L10n.TagManagement.selectionValue(isSelected: selectedColor == colorHex)
        )
        .accessibilityAddTraits(selectedColor == colorHex ? .isSelected : [])
    }
}
