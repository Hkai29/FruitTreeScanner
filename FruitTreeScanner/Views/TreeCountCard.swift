import SwiftUI

struct TreeCountCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orchardMapPresentation) private var presentation
    private let summary: TreeYieldSummary

    init(filteredTrees: [TreeAnnotation]) {
        self.summary = TreeYieldSummary(trees: filteredTrees)
    }

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Design.Space.md) {
                    identity
                    summaryStats
                }
            } else {
                HStack(spacing: Design.Space.md) {
                    identity
                    Spacer()
                    HStack(spacing: Design.Space.lg) {
                        summaryStats
                    }
                }
            }
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    private var identity: some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(presentation.orchardTrees)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(presentation.treeCountText(summary.totalCount, locale: locale))
                .font(.title2.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }

    private var summaryStats: some View {
        Group {
            YieldStatMini(level: .high, count: summary.count(for: .high))
            YieldStatMini(level: .medium, count: summary.count(for: .medium))
            YieldStatMini(level: .low, count: summary.count(for: .low))
        }
    }
}
