import Foundation
import SwiftUI

struct OrchardTreePinPresentation: Equatable {
    let symbolName: String
    let accessibilityLabel: String
    let accessibilityValue: String

    init(tree: TreeAnnotation, isSelected: Bool, bundle: Bundle = .main) {
        symbolName = tree.yieldLevel.icon

        let treeLabelFormat = Self.localized(
            "orchard_map.pin.tree_label",
            fallback: "果树 %@",
            bundle: bundle
        )
        accessibilityLabel = Self.formatted(
            treeLabelFormat,
            arguments: [tree.treeID],
            bundle: bundle
        )

        let level = Self.yieldLevelText(tree.yieldLevel, bundle: bundle)
        if isSelected {
            let selectedFormat = Self.localized(
                "orchard_map.pin.selected_value",
                fallback: "%@，已选中",
                bundle: bundle
            )
            accessibilityValue = Self.formatted(
                selectedFormat,
                arguments: [level],
                bundle: bundle
            )
        } else {
            accessibilityValue = level
        }
    }

    private static func yieldLevelText(_ level: YieldLevel, bundle: Bundle) -> String {
        switch level {
        case .high:
            return localized("orchard_map.pin.level_high", fallback: "高产", bundle: bundle)
        case .medium:
            return localized("orchard_map.pin.level_medium", fallback: "中产", bundle: bundle)
        case .low:
            return localized("orchard_map.pin.level_low", fallback: "低产", bundle: bundle)
        }
    }

    private static func localized(_ key: String, fallback: String, bundle: Bundle) -> String {
        bundle.localizedString(forKey: key, value: fallback, table: nil)
    }

    private static func formatted(
        _ format: String,
        arguments: [CVarArg],
        bundle: Bundle
    ) -> String {
        let locale = bundle.preferredLocalizations.first.map(Locale.init(identifier:)) ?? .current
        return String(format: format, locale: locale, arguments: arguments)
    }
}

struct TreeMapPin: View {
    let tree: TreeAnnotation
    let isSelected: Bool

    var body: some View {
        let presentation = OrchardTreePinPresentation(tree: tree, isSelected: isSelected)

        VStack(spacing: 0) {
            ZStack {
                Circle()
                    .fill(tree.yieldLevel.color)
                    .frame(width: isSelected ? 36 : 28, height: isSelected ? 36 : 28)
                    .shadow(color: tree.yieldLevel.color.opacity(0.4), radius: isSelected ? 8 : 4, y: 2)

                Image(systemName: presentation.symbolName)
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
        .accessibilityLabel(presentation.accessibilityLabel)
        .accessibilityValue(presentation.accessibilityValue)
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
    let count: Int

    var body: some View {
        HStack(spacing: Design.Space.xs) {
            Circle().fill(level.color).frame(width: 8, height: 8)
            Text("\(count)")
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }
}

struct TreeStatItem: View {
    let label: String
    let value: String
    let color: Color

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(Design.Typography.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(value)
                .font(Design.Typography.subheadlineMedium)
                .foregroundColor(color)
        }
    }
}
