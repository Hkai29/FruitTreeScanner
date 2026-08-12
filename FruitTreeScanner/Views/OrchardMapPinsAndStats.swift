import SwiftUI

struct OrchardTreePinPresentation: Equatable {
    let symbolName: String
    let accessibilityLabel: String
    let accessibilityValue: String

    init(tree: TreeAnnotation, isSelected: Bool, bundle: Bundle = .main) {
        self = OrchardMapPresentation(bundle: bundle).treePinPresentation(
            for: tree,
            isSelected: isSelected
        )
    }

    init(symbolName: String, accessibilityLabel: String, accessibilityValue: String) {
        self.symbolName = symbolName
        self.accessibilityLabel = accessibilityLabel
        self.accessibilityValue = accessibilityValue
    }
}

struct TreeMapPin: View {
    @Environment(\.orchardMapPresentation) private var presentation
    let tree: TreeAnnotation
    let isSelected: Bool

    var body: some View {
        let pinPresentation = presentation.treePinPresentation(
            for: tree,
            isSelected: isSelected
        )

        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(tree.yieldLevel.color)
                    .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                    .shadow(color: tree.yieldLevel.color.opacity(0.4), radius: isSelected ? 8 : 4, y: 2)

                Image(systemName: pinPresentation.symbolName)
                    .font(.system(size: isSelected ? 16 : 12, weight: .medium))
                    .foregroundColor(.white)
            }

            Triangle()
                .fill(tree.yieldLevel.color)
                .frame(width: 10, height: 6)
                .offset(y: -2)
        }
        .frame(width: 44, height: 44, alignment: .bottom)
        .contentShape(Rectangle())
        .animation(.spring(response: 0.3), value: isSelected)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(pinPresentation.accessibilityLabel))
        .accessibilityValue(Text(pinPresentation.accessibilityValue))
        .accessibilityHint(Text(presentation.selectTreeHint))
        .accessibilityAddTraits(.isButton)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }
}

struct Triangle: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.midX, y: rect.maxY))
        path.addLine(to: CGPoint(x: rect.minX, y: rect.minY))
        path.addLine(to: CGPoint(x: rect.maxX, y: rect.minY))
        return path
    }
}

struct YieldStatMini: View {
    let level: YieldLevel
    let presentation: OrchardYieldLevelCountPresentation

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Image(systemName: level.icon)
                .font(.caption)
                .foregroundColor(level.color)
            VStack(alignment: .leading, spacing: 2) {
                Text(presentation.label)
                    .font(.caption)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Text(presentation.countText)
                    .font(.subheadline.weight(.medium))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.label))
        .accessibilityValue(Text(presentation.countText))
    }
}

struct TreeStatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(value)
                .font(.subheadline.weight(.medium))
                .foregroundColor(color)
        }
        .accessibilityElement(children: .combine)
    }
}
