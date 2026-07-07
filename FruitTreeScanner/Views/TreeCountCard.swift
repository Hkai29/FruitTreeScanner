import SwiftUI

struct TreeCountCard: View {
    private let summary: TreeYieldSummary

    init(filteredTrees: [TreeAnnotation]) {
        self.summary = TreeYieldSummary(trees: filteredTrees)
    }

    var body: some View {
        HStack(spacing: Design.Space.md) {
            VStack(alignment: .leading, spacing: Design.Space.xs) {
                Text("园区树木")
                    .font(Design.Typography.subheadline)
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                Text("\(summary.totalCount) 棵")
                    .font(Design.Typography.title2)
                    .foregroundColor(Design.Colors.Dark.textPrimary)
            }

            Spacer()

            HStack(spacing: Design.Space.lg) {
                YieldStatMini(level: .high, count: summary.count(for: .high))
                YieldStatMini(level: .medium, count: summary.count(for: .medium))
                YieldStatMini(level: .low, count: summary.count(for: .low))
            }
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }
}
