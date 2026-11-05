import SwiftUI

// MARK: - 读数文案

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

// MARK: - 读数面板

/// 果园读数面板：当前范围内的果树总数，以及按产量等级分组的数量。
///
/// 读数用仪器式面板 + 读数条承载，不再用带投影的浮起卡片。
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

        VStack(spacing: Design.Space.sm) {
            InstrumentPanel(
                label: countPresentation.title,
                systemImage: "leaf",
                fill: Design.Colors.Workspace.surfaceQuiet
            ) {
                Text(countPresentation.totalCountText)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.ink)
                    .fixedSize(horizontal: false, vertical: true)
            }

            levelStrip(countPresentation)
        }
    }

    @ViewBuilder
    private func levelStrip(_ countPresentation: OrchardTreeCountPresentation) -> some View {
        switch OrchardTreeCountLayout(dynamicTypeSize: dynamicTypeSize) {
        case .horizontal:
            InstrumentStatStrip {
                HStack(spacing: 0) {
                    ForEach(YieldLevel.allCases, id: \.self) { level in
                        levelDatum(level, countPresentation)
                    }
                }
            }
        case .stacked:
            InstrumentStatStrip {
                VStack(alignment: .leading, spacing: 10) {
                    ForEach(YieldLevel.allCases, id: \.self) { level in
                        levelDatum(level, countPresentation)
                    }
                }
            }
        }
    }

    private func levelDatum(
        _ level: YieldLevel,
        _ countPresentation: OrchardTreeCountPresentation
    ) -> some View {
        let item: OrchardYieldLevelCountPresentation
        switch level {
        case .high: item = countPresentation.high
        case .medium: item = countPresentation.medium
        case .low: item = countPresentation.low
        }
        let count = summary.count(for: level)

        return HStack(spacing: 6) {
            Image(systemName: level.icon)
                .font(.caption)
                .foregroundColor(level.color)
                .accessibilityHidden(true)

            InstrumentDatum(
                label: item.label,
                value: "\(count)",
                unit: L10n.Dashboard.treeCountUnit(count)
            )
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }
}
