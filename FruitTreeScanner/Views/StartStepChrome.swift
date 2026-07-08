import SwiftUI

struct StartStepHeader: View {
    let step: Int
    let totalSteps: Int
    let title: String
    let subtitle: String

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            HStack(spacing: Design.Space.xs) {
                Text("步骤 \(step)/\(totalSteps)")
                    .font(.system(size: 12, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.harvest)

                Capsule()
                    .fill(Design.Colors.Dark.glassBorder)
                    .frame(width: 4, height: 4)

                Text(title)
                    .font(.system(size: 20, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)
            }

            Text(subtitle)
                .font(.system(size: 13))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}

struct StartNoteRow: View {
    let icon: String
    let text: String
    var tint: Color = Design.Colors.Dark.info

    var body: some View {
        HStack(alignment: .top, spacing: Design.Space.xs) {
            Image(systemName: icon)
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(tint)
                .frame(width: 16, height: 16)

            Text(text)
                .font(.system(size: 12))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}

struct StartEmptyAction: View {
    let icon: String
    let title: String
    let message: String
    let buttonTitle: String
    let action: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            HStack(spacing: Design.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Text(message)
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                }
            }

            Button(action: action) {
                HStack(spacing: Design.Space.xs) {
                    Image(systemName: "plus")
                    Text(buttonTitle)
                }
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
            }
        }
        .padding(Design.Space.md)
        .startSurface(cornerRadius: 10)
    }
}

struct StartSelectionRow<Accessory: View>: View {
    let title: String
    let subtitle: String
    let icon: String
    let tint: Color
    let isSelected: Bool
    let action: () -> Void
    @ViewBuilder let accessory: () -> Accessory

    var body: some View {
        Button(action: action) {
            HStack(spacing: Design.Space.sm) {
                Image(systemName: icon)
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundColor(tint)
                    .frame(width: 28, height: 28)

                VStack(alignment: .leading, spacing: 3) {
                    Text(title)
                        .font(.system(size: 15, weight: .semibold))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                    Text(subtitle)
                        .font(.system(size: 12))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .lineLimit(2)
                }

                Spacer(minLength: Design.Space.sm)

                accessory()

                Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 17, weight: .semibold))
                    .foregroundColor(isSelected ? Design.Colors.harvest : Design.Colors.Dark.textMuted)
            }
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, 13)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
    }
}

extension View {
    func startSurface(cornerRadius: CGFloat) -> some View {
        self
            .background(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .fill(Design.Colors.Dark.glassFill)
            )
            .overlay(
                RoundedRectangle(cornerRadius: cornerRadius)
                    .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
            )
    }
}
