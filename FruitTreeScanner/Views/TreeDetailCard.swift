import SwiftUI

struct TreeDetailCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orchardMapPresentation) private var presentation
    let tree: TreeAnnotation
    let onClose: () -> Void

    private var confidenceColor: Color {
        switch tree.confidence.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() {
        case "high": return Design.Colors.Dark.success
        case "medium": return Design.Colors.Dark.warning
        case "low": return Design.Colors.Dark.error
        default: return Design.Colors.Dark.textSecondary
        }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            header
            DividerLine()
            statsRow
            yieldBadgeRow
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    private var header: some View {
        HStack {
            HStack(spacing: Design.Space.sm) {
                Image(systemName: tree.yieldLevel.icon)
                    .font(.title3.weight(.medium))
                    .foregroundColor(tree.yieldLevel.color)
                    .accessibilityHidden(true)

                Text(presentation.treeTitle(tree.treeID))
                    .font(.headline)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }

            Spacer()

            Button(action: onClose) {
                Image(systemName: "xmark")
                    .font(.system(size: 14, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(width: 44, height: 44)
                    .background(Design.Colors.Dark.bgSurface)
                    .clipShape(Circle())
            }
            .accessibilityLabel(Text(presentation.closeDetails))
            .accessibilityHint(Text(presentation.closeDetailsHint))
        }
    }

    @ViewBuilder
    private var statsRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                stats
            }
        } else {
            HStack(spacing: Design.Space.xl) {
                stats
            }
        }
    }

    private var stats: some View {
        Group {
            TreeStatItem(
                label: presentation.estimatedYield,
                value: presentation.yieldText(tree.weight, locale: locale),
                color: Design.Colors.Dark.glow
            )
            TreeStatItem(
                label: presentation.fruitCount,
                value: presentation.fruitCountText(tree.fruitCount, locale: locale),
                color: Design.Colors.Dark.glow
            )
            TreeStatItem(
                label: presentation.confidence,
                value: presentation.confidenceLabel(tree.confidence),
                color: confidenceColor
            )
            TreeStatItem(
                label: presentation.scanDate,
                value: presentation.scanDateText(tree.scanDate, locale: locale),
                color: Design.Colors.Dark.textSecondary
            )
        }
    }

    @ViewBuilder
    private var yieldBadgeRow: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                yieldLevelLabel
                yieldLevelBadge
            }
        } else {
            HStack {
                yieldLevelLabel
                Spacer()
                yieldLevelBadge
            }
        }
    }

    private var yieldLevelLabel: some View {
        Text(presentation.yieldLevelTitle)
            .font(.caption)
            .foregroundColor(Design.Colors.Dark.textSecondary)
    }

    private var yieldLevelBadge: some View {
        HStack(spacing: Design.Space.xs) {
            Image(systemName: tree.yieldLevel.icon)
                .font(.caption)
                .foregroundColor(tree.yieldLevel.color)

            Text(presentation.yieldLevelLabel(tree.yieldLevel))
                .font(.caption.weight(.medium))
                .foregroundColor(tree.yieldLevel.color)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(.horizontal, Design.Space.sm)
        .padding(.vertical, Design.Space.xs)
        .background(tree.yieldLevel.color.opacity(0.1))
        .cornerRadius(Design.Radius.full)
    }

}
