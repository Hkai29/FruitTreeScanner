import SwiftUI

struct ResultSummaryLayoutPolicy: Equatable, Sendable {
    enum Arrangement: Equatable, Sendable {
        case horizontal
        case vertical
    }

    let headerArrangement: Arrangement
    let primaryMetricArrangement: Arrangement
    let summaryColumnCount: Int
    let allowsPillValueWrapping: Bool

    init(isAccessibilitySize: Bool) {
        headerArrangement = isAccessibilitySize ? .vertical : .horizontal
        primaryMetricArrangement = isAccessibilitySize ? .vertical : .horizontal
        summaryColumnCount = isAccessibilitySize ? 1 : 3
        allowsPillValueWrapping = isAccessibilitySize
    }
}

struct ResultSummaryHeader: View {
    let treeID: String
    let result: YieldResult

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ScaledMetric(relativeTo: .headline) private var titleFontSize: CGFloat = 15
    @ScaledMetric(relativeTo: .title2) private var treeIDFontSize: CGFloat = 22
    @ScaledMetric(relativeTo: .caption) private var noteFontSize: CGFloat = 12

    private var confidencePresentation: ResultConfidencePresentation {
        ResultConfidencePresentation(result.confidence)
    }

    private var algorithmPresentation: ResultAlgorithmParametersPresentation {
        ResultAlgorithmParametersPresentation(result: result)
    }

    private var reliabilityPresentation: ResultReliabilityPresentation {
        ResultReliabilityPresentation(result: result)
    }

    private var layoutPolicy: ResultSummaryLayoutPolicy {
        ResultSummaryLayoutPolicy(isAccessibilitySize: dynamicTypeSize.isAccessibilitySize)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            headerContent

            ResultPrimaryMetric(
                title: L10n.Result.yieldTitle,
                value: ResultValueFormatter.finalYieldKg(result.yieldFinalKg),
                unit: "kg",
                color: confidencePresentation.color,
                arrangement: layoutPolicy.primaryMetricArrangement
            )

            ResultReliabilitySummaryCard(presentation: reliabilityPresentation)

            LazyVGrid(
                columns: Array(
                    repeating: GridItem(.flexible(), spacing: 8),
                    count: layoutPolicy.summaryColumnCount
                ),
                spacing: 8
            ) {
                ResultSummaryPill(
                    label: L10n.Result.fruit,
                    value: "\(result.nLidar)",
                    allowsValueWrapping: layoutPolicy.allowsPillValueWrapping
                )
                ResultSummaryPill(
                    label: L10n.Result.pointCloud,
                    value: result.pointCloudSize > 0 ? "\(result.pointCloudSize)" : "--",
                    allowsValueWrapping: layoutPolicy.allowsPillValueWrapping
                )
                ResultSummaryPill(
                    label: L10n.Result.methodLabel,
                    value: algorithmPresentation.methodDisplayName,
                    allowsValueWrapping: layoutPolicy.allowsPillValueWrapping
                )
            }

            if !result.note.isEmpty {
                Text(result.note)
                    .font(.system(size: noteFontSize))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .resultSurface(cornerRadius: 10)
        .padding(.horizontal, 18)
    }

    @ViewBuilder
    private var headerContent: some View {
        switch layoutPolicy.headerArrangement {
        case .horizontal:
            HStack(alignment: .center, spacing: 12) {
                titleContent
                Spacer()
                confidenceBadge
            }
        case .vertical:
            VStack(alignment: .leading, spacing: 10) {
                titleContent
                confidenceBadge
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleContent: some View {
        VStack(alignment: .leading, spacing: 5) {
            Text(L10n.Result.scanResult)
                .font(.system(size: titleFontSize, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(treeID)
                .font(.system(size: treeIDFontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var confidenceBadge: some View {
        ConfidenceBadge(
            label: confidencePresentation.label,
            color: confidencePresentation.color
        )
    }
}

private struct ResultReliabilitySummaryCard: View {
    let presentation: ResultReliabilityPresentation

    @ScaledMetric(relativeTo: .subheadline) private var titleFontSize: CGFloat = 13
    @ScaledMetric(relativeTo: .caption) private var actionFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption) private var summaryFontSize: CGFloat = 12
    @ScaledMetric(relativeTo: .caption2) private var hintFontSize: CGFloat = 11

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(presentation.tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.title)
                    .font(.system(size: titleFontSize, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.recommendedAction)
                    .font(.system(size: actionFontSize, weight: .medium))
                    .foregroundColor(presentation.tint)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.summary)
                    .font(.system(size: summaryFontSize))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let diagnosticHint = presentation.diagnosticHint {
                    Text(diagnosticHint)
                        .font(.system(size: hintFontSize))
                        .foregroundColor(Design.Colors.Dark.textMuted)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }

            Spacer(minLength: 0)
        }
        .padding(12)
        .background(presentation.tint.opacity(0.10))
        .cornerRadius(8)
    }
}

private struct ResultPrimaryMetric: View {
    let title: String
    let value: String
    let unit: String
    let color: Color

    let arrangement: ResultSummaryLayoutPolicy.Arrangement

    @ScaledMetric(relativeTo: .subheadline) private var titleFontSize: CGFloat = 13
    @ScaledMetric(relativeTo: .largeTitle) private var valueFontSize: CGFloat = 36
    @ScaledMetric(relativeTo: .subheadline) private var unitFontSize: CGFloat = 14

    @ViewBuilder
    var body: some View {
        switch arrangement {
        case .horizontal:
            HStack(alignment: .lastTextBaseline, spacing: 8) {
                titleText
                Spacer()
                valueContent
            }
        case .vertical:
            VStack(alignment: .leading, spacing: 6) {
                titleText
                verticalValueContent
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    private var titleText: some View {
        Text(title)
            .font(.system(size: titleFontSize, weight: .medium))
            .foregroundColor(Design.Colors.Dark.textSecondary)
    }

    private var valueContent: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            valueText
            unitText
        }
        .accessibilityElement(children: .combine)
    }

    private var verticalValueContent: some View {
        VStack(alignment: .leading, spacing: 2) {
            valueText
            unitText
        }
        .accessibilityElement(children: .combine)
    }

    private var valueText: some View {
        Text(value)
            .font(.system(size: valueFontSize, weight: .semibold, design: .monospaced))
            .foregroundColor(color)
            .fixedSize(horizontal: false, vertical: true)
    }

    private var unitText: some View {
        Text(unit)
            .font(.system(size: unitFontSize, weight: .semibold))
            .foregroundColor(Design.Colors.Dark.textSecondary)
    }
}
