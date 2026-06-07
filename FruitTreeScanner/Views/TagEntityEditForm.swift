import SwiftUI

struct TagEntityEditForm: View {
    @Binding var name: String
    @Binding var selectedColor: String

    let namePlaceholder: String

    private let colorOptions = [
        "#6F8F63", "#B8843A", "#4D7588", "#B8564B",
        "#8A7657", "#6C7B58", "#7E8580", "#34362F"
    ]

    var body: some View {
        ScrollView {
            VStack(spacing: 14) {
                nameSection
                colorSection
            }
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.lg)
        }
    }

    private var nameSection: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text("名称")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            TextField(namePlaceholder, text: $name)
                .font(.system(size: 16, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, 14)
                .frame(height: 48)
                .background(Design.Colors.Dark.bgElevated)
                .clipShape(RoundedRectangle(cornerRadius: 10))
                .overlay(
                    RoundedRectangle(cornerRadius: 10)
                        .stroke(nameBorderColor, lineWidth: 1)
                )
                .textInputAutocapitalization(.words)
                .autocorrectionDisabled(true)
        }
        .padding(16)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    private var colorSection: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("颜色")
                .font(.system(size: 13, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 4), spacing: 12) {
                ForEach(colorOptions, id: \.self) { colorHex in
                    colorSwatch(colorHex)
                }
            }
        }
        .padding(16)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }

    private var nameBorderColor: Color {
        name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
            ? Design.Colors.Dark.glassBorder
            : Design.Colors.forest.opacity(0.5)
    }

    private func colorSwatch(_ colorHex: String) -> some View {
        Button {
            selectedColor = colorHex
        } label: {
            RoundedRectangle(cornerRadius: 8)
                .fill(Color(hex: colorHex))
                .frame(height: 34)
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(selectedColor == colorHex ? Color.white : Color.clear, lineWidth: 2)
                )
                .overlay(
                    RoundedRectangle(cornerRadius: 8)
                        .stroke(Design.Colors.Dark.glassBorder.opacity(0.35), lineWidth: 1)
                )
        }
        .buttonStyle(.plain)
        .accessibilityLabel("颜色 \(colorHex)")
    }
}
