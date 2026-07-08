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
