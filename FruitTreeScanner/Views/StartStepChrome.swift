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
                .font(.caption.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 16, height: 16)
                .accessibilityHidden(true)

            Text(text)
                .font(.caption)
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            emptyStateDescription

            Button(action: action) {
                HStack(spacing: Design.Space.xs) {
                    Image(systemName: "plus")
                    Text(buttonTitle)
                }
                .font(.body.weight(.semibold))
                .foregroundColor(Design.Colors.harvest)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 12)
                .frame(minHeight: layoutPolicy.minimumControlHeight)
                .background(
                    RoundedRectangle(cornerRadius: 8)
                        .strokeBorder(Design.Colors.Dark.glassBorder, lineWidth: 1)
                )
            }
        }
        .padding(Design.Space.md)
        .startSurface(cornerRadius: 10)
    }

    @ViewBuilder
    private var emptyStateDescription: some View {
        switch layoutPolicy.arrangement {
        case .horizontal:
            HStack(alignment: .top, spacing: Design.Space.sm) {
                descriptionIcon
                descriptionCopy
            }
        case .vertical:
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                descriptionIcon
                descriptionCopy
            }
        }
    }

    private var descriptionIcon: some View {
        Image(systemName: icon)
            .font(.body.weight(.semibold))
            .foregroundColor(Design.Colors.harvest)
            .frame(width: 28, height: 28)
            .accessibilityHidden(true)
    }

    private var descriptionCopy: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(title)
                .font(.body.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(message)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var layoutPolicy: StartStepContentLayoutPolicy {
        StartStepContentLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }
}

struct StartStepContentLayoutPolicy: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case horizontal
        case vertical
    }

    let arrangement: Arrangement
    let minimumControlHeight: CGFloat

    init(isAccessibilitySize: Bool) {
        arrangement = isAccessibilitySize ? .vertical : .horizontal
        minimumControlHeight = Design.Touch.minimumHeight
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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Button(action: action) {
            Group {
                switch layoutPolicy.arrangement {
                case .horizontal:
                    HStack(spacing: Design.Space.sm) {
                        selectionDescription
                        Spacer(minLength: Design.Space.sm)
                        selectionStatus
                    }
                case .vertical:
                    VStack(alignment: .leading, spacing: Design.Space.sm) {
                        selectionDescription
                        HStack(spacing: Design.Space.sm) {
                            Spacer(minLength: 0)
                            selectionStatus
                        }
                    }
                }
            }
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, 13)
            .frame(minHeight: layoutPolicy.minimumControlHeight)
            .contentShape(Rectangle())
        }
        .buttonStyle(ScaleButtonStyle())
        .accessibilityLabel("\(title), \(subtitle)")
        .accessibilityValue(L10n.QuickTagging.selectionValue(isSelected: isSelected))
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private var selectionDescription: some View {
        HStack(alignment: .top, spacing: Design.Space.sm) {
            Image(systemName: icon)
                .font(.body.weight(.semibold))
                .foregroundColor(tint)
                .frame(width: 28, height: 28)
                .accessibilityHidden(true)

            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.body.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    private var selectionStatus: some View {
        HStack(spacing: Design.Space.sm) {
            accessory()

            Image(systemName: isSelected ? "checkmark.circle.fill" : "circle")
                .font(.title3.weight(.semibold))
                .foregroundColor(isSelected ? Design.Colors.harvest : Design.Colors.Dark.textMuted)
                .accessibilityHidden(true)
        }
    }

    private var layoutPolicy: StartStepContentLayoutPolicy {
        StartStepContentLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
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
