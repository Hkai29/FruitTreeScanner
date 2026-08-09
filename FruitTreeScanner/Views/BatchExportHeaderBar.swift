import SwiftUI

struct BatchExportHeaderBar: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let selectedCount: Int
    let totalCount: Int
    let unavailableCount: Int
    let totalYield: Float?
    let totalFruitCount: Int?

    var body: some View {
        VStack(spacing: Design.Space.sm) {
            heroHeader

            HStack {
                VStack(alignment: .leading, spacing: 4) {
                    Text(selectionSummaryText)
                        .font(.headline)
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)

                    if selectedCount > 0 {
                        if let totalYield, let totalFruitCount {
                            Text(selectedMetricsText(totalYield: totalYield, totalFruitCount: totalFruitCount))
                                .font(.subheadline)
                                .foregroundColor(Design.Colors.Dark.textSecondary)
                                .fixedSize(horizontal: false, vertical: true)
                        } else {
                            Text("汇总数值超出支持范围")
                                .font(Design.Typography.caption)
                                .foregroundColor(Design.Colors.warning)
                        }
                    }
                }

                Spacer()
            }
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(selectionAccessibilityLabel)

            if unavailableCount > 0 {
                Label(
                    unavailableSummaryText,
                    systemImage: "exclamationmark.triangle.fill"
                )
                .font(.subheadline)
                .foregroundColor(Design.Colors.warning)
                .frame(maxWidth: .infinity, alignment: .leading)
                .fixedSize(horizontal: false, vertical: true)
                .accessibilityElement(children: .ignore)
                .accessibilityLabel(L10n.Export.unavailableSummary(count: unavailableCount))
            }

            if totalCount > 0 {
                ProgressView(value: Double(selectedCount), total: Double(totalCount))
                    .tint(Design.Colors.harvest)
                    .accessibilityLabel(L10n.Export.selectionProgress)
                    .accessibilityValue(
                        L10n.Export.selectionSummary(
                            selectedCount: selectedCount,
                            totalCount: totalCount
                        )
                    )
            }
        }
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
    }

    @ViewBuilder
    private var heroHeader: some View {
        if dynamicTypeSize.isAccessibilitySize {
            Label {
                Text(L10n.Export.headerTitle)
                    .font(.headline)
            } icon: {
                Image(systemName: "doc.richtext")
                    .foregroundColor(Design.Colors.harvest)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
            .accessibilityAddTraits(.isHeader)
        } else {
            HStack(alignment: .center, spacing: Design.Space.sm) {
                DashboardFeatureImage(name: "FeatureBatchExport", accent: Design.Colors.harvest)
                    .frame(width: 86, height: 66)
                    .accessibilityHidden(true)

                VStack(alignment: .leading, spacing: 5) {
                    Label {
                        Text(L10n.Export.headerTitle)
                            .font(.headline)
                    } icon: {
                        Image(systemName: "doc.richtext")
                            .foregroundColor(Design.Colors.harvest)
                    }

                    Text(L10n.Export.headerSubtitle)
                        .font(.subheadline)
                        .foregroundColor(Design.Colors.Dark.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }

                Spacer(minLength: 0)
            }
            .padding(Design.Space.sm)
            .frame(maxWidth: .infinity, alignment: .leading)
            .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel(heroAccessibilityLabel)
            .accessibilityAddTraits(.isHeader)
        }
    }

    private var selectionSummaryText: String {
        if dynamicTypeSize.isAccessibilitySize {
            return L10n.Export.compactSelectionSummary(
                selectedCount: selectedCount,
                totalCount: totalCount
            )
        }
        return L10n.Export.selectionSummary(
            selectedCount: selectedCount,
            totalCount: totalCount
        )
    }

    private var unavailableSummaryText: String {
        if dynamicTypeSize.isAccessibilitySize {
            return L10n.Export.compactUnavailableSummary(count: unavailableCount)
        }
        return L10n.Export.unavailableSummary(count: unavailableCount)
    }

    private func selectedMetricsText(totalYield: Float, totalFruitCount: Int) -> String {
        if dynamicTypeSize.isAccessibilitySize {
            return L10n.Export.compactSelectedMetrics(
                totalYield: totalYield,
                totalFruitCount: totalFruitCount
            )
        }
        return L10n.Export.selectedMetrics(
            totalYield: totalYield,
            totalFruitCount: totalFruitCount
        )
    }

    private var heroAccessibilityLabel: String {
        "\(L10n.Export.headerTitle). \(L10n.Export.headerSubtitle)"
    }

    private var selectionAccessibilityLabel: String {
        let selection = L10n.Export.selectionSummary(
            selectedCount: selectedCount,
            totalCount: totalCount
        )
        guard selectedCount > 0 else { return selection }
        guard let totalYield, let totalFruitCount else { return selection }
        return "\(selection). \(L10n.Export.selectedMetrics(totalYield: totalYield, totalFruitCount: totalFruitCount))"
    }
}
