import SwiftUI

struct ResultSummaryHeader: View {
    let treeID: String
    let result: YieldResult

    private var confidencePresentation: ResultConfidencePresentation {
        ResultConfidencePresentation(result.confidence)
    }

    private var algorithmPresentation: ResultAlgorithmParametersPresentation {
        ResultAlgorithmParametersPresentation(result: result)
    }

    private var reliabilityPresentation: ResultReliabilityPresentation {
        ResultReliabilityPresentation(result: result)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            HStack(alignment: .center, spacing: 12) {
                VStack(alignment: .leading, spacing: 5) {
                    Text(L10n.Result.scanResult)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                    Text(treeID)
                        .font(.system(size: 22, weight: .semibold, design: .monospaced))
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }

                Spacer()

                ConfidenceBadge(label: confidencePresentation.label, color: confidencePresentation.color)
            }

            ResultPrimaryMetric(
                title: L10n.Result.yieldTitle,
                value: ResultValueFormatter.finalYieldKg(result.yieldFinalKg),
                unit: "kg",
                color: confidencePresentation.color
            )

            ResultReliabilitySummaryCard(presentation: reliabilityPresentation)

            LazyVGrid(
                columns: [
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8),
                    GridItem(.flexible(), spacing: 8)
                ],
                spacing: 8
            ) {
                ResultSummaryPill(label: L10n.Result.fruit, value: "\(result.nLidar)")
                ResultSummaryPill(label: L10n.Result.pointCloud, value: result.pointCloudSize > 0 ? "\(result.pointCloudSize)" : "--")
                ResultSummaryPill(label: L10n.Result.methodLabel, value: algorithmPresentation.methodDisplayName)
            }

            if !result.note.isEmpty {
                Text(result.note)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .resultSurface(cornerRadius: 10)
        .padding(.horizontal, 18)
    }
}

private struct ResultReliabilitySummaryCard: View {
    let presentation: ResultReliabilityPresentation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: presentation.iconName)
                .font(.system(size: 16, weight: .semibold))
                .foregroundColor(presentation.tint)
                .frame(width: 22, height: 22)

            VStack(alignment: .leading, spacing: 5) {
                Text(presentation.title)
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.recommendedAction)
                    .font(.system(size: 12, weight: .medium))
                    .foregroundColor(presentation.tint)
                    .fixedSize(horizontal: false, vertical: true)

                Text(presentation.summary)
                    .font(.system(size: 12))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)

                if let diagnosticHint = presentation.diagnosticHint {
                    Text(diagnosticHint)
                        .font(.system(size: 11))
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

    var body: some View {
        HStack(alignment: .lastTextBaseline, spacing: 8) {
            Text(title)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Spacer()

            Text(value)
                .font(.system(size: 36, weight: .semibold, design: .monospaced))
                .foregroundColor(color)
                .lineLimit(1)
                .minimumScaleFactor(0.75)

            Text(unit)
                .font(.system(size: 14, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }
}
