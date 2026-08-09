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
            Text(L10n.TagManagement.nameLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            TextField(namePlaceholder, text: $name)
                .font(.body.weight(.medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, 14)
                .padding(.vertical, 12)
                .frame(minHeight: 48)
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
            Text(L10n.TagManagement.colorLabel)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            LazyVGrid(columns: [GridItem(.adaptive(minimum: 54))], spacing: 12) {
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
            ZStack {
                RoundedRectangle(cornerRadius: 8)
                    .fill(Color(hex: colorHex))

                if selectedColor == colorHex {
                    Image(systemName: "checkmark")
                        .font(.headline.weight(.bold))
                        .foregroundStyle(.white)
                        .shadow(color: .black.opacity(0.45), radius: 1, y: 1)
                        .accessibilityHidden(true)
                }
            }
            .frame(minHeight: 44)
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
        .accessibilityLabel(L10n.TagManagement.colorAccessibilityLabel(for: colorHex))
        .accessibilityValue(
            L10n.TagManagement.selectionValue(isSelected: selectedColor == colorHex)
        )
        .accessibilityAddTraits(selectedColor == colorHex ? .isSelected : [])
    }
}
