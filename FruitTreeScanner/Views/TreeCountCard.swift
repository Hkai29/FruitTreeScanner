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
        let presentation = OrchardMapPresentation(bundle: bundle)
        let locale = bundle.preferredLocalizations.first.map(Locale.init(identifier:)) ?? .current
        self.init(summary: summary, presentation: presentation, locale: locale)
    }

    init(summary: TreeYieldSummary, presentation: OrchardMapPresentation, locale: Locale) {
        title = presentation.orchardTrees
        totalCountText = presentation.summaryTreeCountText(summary.totalCount, locale: locale)
        high = Self.levelPresentation(.high, summary: summary, presentation: presentation, locale: locale)
        medium = Self.levelPresentation(.medium, summary: summary, presentation: presentation, locale: locale)
        low = Self.levelPresentation(.low, summary: summary, presentation: presentation, locale: locale)
    }

    private static func levelPresentation(
        _ level: YieldLevel,
        summary: TreeYieldSummary,
        presentation: OrchardMapPresentation,
        locale: Locale
    ) -> OrchardYieldLevelCountPresentation {
        OrchardYieldLevelCountPresentation(
            label: presentation.summaryYieldLevelLabel(level),
            countText: presentation.summaryTreeCountText(summary.count(for: level), locale: locale)
        )
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
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.orchardMapPresentation) private var presentation
    private let summary: TreeYieldSummary

    init(filteredTrees: [TreeAnnotation]) {
        self.summary = TreeYieldSummary(trees: filteredTrees)
    }

    var body: some View {
        let countPresentation = OrchardTreeCountPresentation(
            summary: summary,
            presentation: presentation,
            locale: locale
        )

        Group {
            if OrchardTreeCountLayout(dynamicTypeSize: dynamicTypeSize) == .stacked {
                VStack(alignment: .leading, spacing: Design.Space.md) {
                    identity(countPresentation)
                    summaryStats(countPresentation)
                }
            } else {
                HStack(spacing: Design.Space.md) {
                    identity(countPresentation)
                    Spacer()
                    HStack(spacing: Design.Space.lg) {
                        summaryStats(countPresentation)
                    }
                }
            }
        }
        .padding(Design.Space.md)
        .background(orchardFloatingSurface)
    }

    private func identity(_ countPresentation: OrchardTreeCountPresentation) -> some View {
        VStack(alignment: .leading, spacing: Design.Space.xs) {
            Text(countPresentation.title)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(countPresentation.totalCountText)
                .font(.title2.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
    }

    private func summaryStats(_ countPresentation: OrchardTreeCountPresentation) -> some View {
        Group {
            YieldStatMini(level: .high, presentation: countPresentation.high)
            YieldStatMini(level: .medium, presentation: countPresentation.medium)
            YieldStatMini(level: .low, presentation: countPresentation.low)
        }
    }
}
