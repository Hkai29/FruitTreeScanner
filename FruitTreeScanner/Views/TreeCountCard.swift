import Foundation
import SwiftUI

struct OrchardYieldLevelCountPresentation: Equatable {
    let label: String
    let countText: String
}

struct OrchardTreeCountPresentation: Equatable {
    let title: String
    let totalCountText: String
    let high: OrchardYieldLevelCountPresentation
    let medium: OrchardYieldLevelCountPresentation
    let low: OrchardYieldLevelCountPresentation

    init(summary: TreeYieldSummary, bundle: Bundle = .main) {
        title = Self.localized(
            "orchard_map.summary.title",
            fallback: "园区树木",
            bundle: bundle
        )
        totalCountText = Self.treeCountText(summary.totalCount, bundle: bundle)
        high = Self.levelPresentation(for: .high, count: summary.count(for: .high), bundle: bundle)
        medium = Self.levelPresentation(for: .medium, count: summary.count(for: .medium), bundle: bundle)
        low = Self.levelPresentation(for: .low, count: summary.count(for: .low), bundle: bundle)
    }

    private static func levelPresentation(
        for level: YieldLevel,
        count: Int,
        bundle: Bundle
    ) -> OrchardYieldLevelCountPresentation {
        let key: String
        let fallback: String

        switch level {
        case .high:
            key = "orchard_map.summary.level_high"
            fallback = "高产"
        case .medium:
            key = "orchard_map.summary.level_medium"
            fallback = "中产"
        case .low:
            key = "orchard_map.summary.level_low"
            fallback = "低产"
        }

        return OrchardYieldLevelCountPresentation(
            label: localized(key, fallback: fallback, bundle: bundle),
            countText: treeCountText(count, bundle: bundle)
        )
    }

    private static func treeCountText(_ count: Int, bundle: Bundle) -> String {
        let key = count == 1
            ? "orchard_map.summary.tree_count_one"
            : "orchard_map.summary.tree_count_other"
        let format = localized(key, fallback: "%d 棵果树", bundle: bundle)
        let locale = bundle.preferredLocalizations.first.map(Locale.init(identifier:)) ?? .current
        return String(format: format, locale: locale, arguments: [count])
    }

    private static func localized(_ key: String, fallback: String, bundle: Bundle) -> String {
        bundle.localizedString(forKey: key, value: fallback, table: nil)
    }
}

enum OrchardTreeCountLayout: Equatable {
    case horizontal
    case stacked

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize.isAccessibilitySize ? .stacked : .horizontal
    }
}

struct TreeCountCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    private let summary: TreeYieldSummary

    init(filteredTrees: [TreeAnnotation]) {
        self.summary = TreeYieldSummary(trees: filteredTrees)
    }

    var body: some View {
        let presentation = OrchardTreeCountPresentation(summary: summary)

        Group {
            switch OrchardTreeCountLayout(dynamicTypeSize: dynamicTypeSize) {
            case .horizontal:
                ViewThatFits(in: .horizontal) {
                    horizontalContent(presentation)
                    stackedContent(presentation)
                }
            case .stacked:
                stackedContent(presentation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    private func horizontalContent(_ presentation: OrchardTreeCountPresentation) -> some View {
        HStack(spacing: Design.Space.lg) {
            summaryHeader(presentation)
                .fixedSize(horizontal: true, vertical: false)

            Spacer(minLength: Design.Space.md)

            HStack(spacing: Design.Space.lg) {
                yieldStats(presentation)
            }
            .fixedSize(horizontal: true, vertical: false)
        }
    }

    private func stackedContent(_ presentation: OrchardTreeCountPresentation) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            summaryHeader(presentation)

            VStack(alignment: .leading, spacing: Design.Space.sm) {
                yieldStats(presentation)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    private func summaryHeader(_ presentation: OrchardTreeCountPresentation) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(presentation.title)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(presentation.totalCountText)
                .font(.title2.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .accessibilityElement(children: .combine)
    }

    @ViewBuilder
    private func yieldStats(_ presentation: OrchardTreeCountPresentation) -> some View {
        YieldStatMini(level: .high, presentation: presentation.high)
        YieldStatMini(level: .medium, presentation: presentation.medium)
        YieldStatMini(level: .low, presentation: presentation.low)
    }
}
