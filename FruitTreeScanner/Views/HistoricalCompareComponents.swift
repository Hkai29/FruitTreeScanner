import SwiftUI

struct HistoricalCompareEmptyState: View {
    @Environment(\.locale) private var locale
    @Environment(\.historicalComparePresentation) private var presentation
    let scanCount: Int
    var onStartScan: (() -> Void)? = nil

    var body: some View {
        DashboardSheetEmptyState(
            icon: "arrow.left.arrow.right",
            imageName: "FeatureCompare",
            title: presentation.emptyTitle,
            message: presentation.emptyMessage(scanCount: scanCount, locale: locale),
            accent: Design.Colors.harvest,
            primaryAction: action(
                title: presentation.startScan,
                icon: "viewfinder",
                handler: onStartScan
            ),
            outerPadding: false
        )
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

struct HistoricalComparePrompt: View {
    @Environment(\.historicalComparePresentation) private var presentation

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            Image(systemName: "hand.tap")
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.forest)
                .frame(width: 24, height: 24)
                .accessibilityHidden(true)

            Text(presentation.prompt)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(maxWidth: .infinity, alignment: .leading)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
    }
}

struct ScanSelectionCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.historicalComparePresentation) private var presentation
    let scan: ScanItem?
    let label: String
    let onTap: () -> Void

    var body: some View {
        Button(action: onTap) {
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                Text(label)
                    .font(.caption.weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textSecondary)

                if let scan {
                    selectedContent(scan)
                } else {
                    emptyContent
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.vertical, Design.Space.md)
            .padding(.horizontal, Design.Space.sm)
            .background(Design.Colors.Dark.bgSurface)
            .cornerRadius(10)
            .overlay(border)
        }
        .buttonStyle(.plain)
        .accessibilityLabel(Text(label))
        .accessibilityValue(Text(presentation.selectionValue(scan: scan, locale: locale)))
        .accessibilityHint(Text(presentation.selectionHint(slot: label)))
    }

    private func selectedContent(_ scan: ScanItem) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.treeTitle(scan.treeID))
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)

            Text(presentation.dateText(scan.scanDate, locale: locale))
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)

            Text(presentation.yieldText(scan.yieldKg, locale: locale))
                .font(.title2.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.glow)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private var emptyContent: some View {
        Label(presentation.selectScan, systemImage: "plus")
            .font(.subheadline.weight(.semibold))
            .foregroundColor(Design.Colors.Dark.textSecondary)
            .frame(minHeight: 54)
    }

    private var border: some View {
        RoundedRectangle(cornerRadius: 10)
            .stroke(scan != nil ? Design.Colors.Dark.glow.opacity(0.3) : Design.Colors.sand, lineWidth: 1.5)
    }
}

struct HistoricalYieldComparisonCard: View {
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.historicalComparePresentation) private var presentation
    let scan1: ScanItem
    let scan2: ScanItem
    let proportionalChange: Double?

    private var trend: TrendDirection {
        HistoricalCompareMetrics.trend(for: proportionalChange)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.sm) {
            Text(presentation.yieldChange)
                .font(.subheadline.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: Design.Space.md) {
                    scanValue(scan1, slot: presentation.scanA, alignment: .leading)
                    changeIndicator
                    scanValue(scan2, slot: presentation.scanB, alignment: .leading)
                }
            } else {
                HStack(alignment: .center, spacing: Design.Space.sm) {
                    scanValue(scan1, slot: presentation.scanA, alignment: .leading)
                    Spacer()
                    changeIndicator
                    Spacer()
                    scanValue(scan2, slot: presentation.scanB, alignment: .trailing)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(Design.Space.md)
        .darkSurface(cornerRadius: 10, fill: Design.Colors.Dark.bgSurface)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.yieldChange))
        .accessibilityValue(
            Text(
                presentation.yieldComparisonValue(
                    scan1: scan1,
                    scan2: scan2,
                    proportionalChange: proportionalChange,
                    locale: locale
                )
            )
        )
    }

    private func scanValue(
        _ scan: ScanItem,
        slot: String,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(slot)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(presentation.yieldText(scan.yieldKg, locale: locale))
                .font(.title2.weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Text(presentation.treeTitle(scan.treeID))
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .frame(maxWidth: .infinity, alignment: alignment == .trailing ? .trailing : .leading)
    }

    private var changeIndicator: some View {
        HStack(spacing: Design.Space.xs) {
            Image(systemName: trend.icon)
                .font(.subheadline.weight(.bold))
                .accessibilityHidden(true)

            Text(presentation.percentageText(proportionalChange, locale: locale))
                .font(.subheadline.weight(.semibold))
        }
        .foregroundColor(trend.color)
        .frame(minWidth: 64, alignment: .leading)
    }
}

struct StatCompareCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.historicalComparePresentation) private var presentation
    let title: String
    let value1: String
    let value2: String
    let icon: String
    let trend: TrendDirection?

    var body: some View {
        VStack(alignment: .leading, spacing: Design.Space.md) {
            header
            values
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(Design.Space.md)
        .background(Design.Colors.Dark.bgSurface)
        .cornerRadius(10)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(title))
        .accessibilityValue(Text(presentation.comparisonValue(value1: value1, value2: value2, trend: trend)))
    }

    private var header: some View {
        HStack(alignment: .top) {
            Image(systemName: icon)
                .font(.subheadline.weight(.medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .accessibilityHidden(true)

            Text(title)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .layoutPriority(1)
        }
    }

    @ViewBuilder
    private var values: some View {
        if dynamicTypeSize.isAccessibilitySize {
            VStack(alignment: .leading, spacing: Design.Space.sm) {
                CompareValueColumn(slot: presentation.scanA, value: value1, alignment: .leading)
                if let trend { trendIndicator(trend) }
                CompareValueColumn(slot: presentation.scanB, value: value2, alignment: .leading)
            }
        } else {
            HStack {
                CompareValueColumn(slot: presentation.scanA, value: value1, alignment: .leading)
                Spacer()
                if let trend {
                    trendIndicator(trend)
                    Spacer()
                }
                CompareValueColumn(slot: presentation.scanB, value: value2, alignment: .trailing)
            }
        }
    }

    private func trendIndicator(_ trend: TrendDirection) -> some View {
        Label(presentation.trendText(trend), systemImage: trend.icon)
            .labelStyle(.iconOnly)
            .font(.caption.weight(.bold))
            .foregroundColor(trend.color)
            .accessibilityHidden(true)
    }
}

private struct CompareValueColumn: View {
    let slot: String
    let value: String
    let alignment: HorizontalAlignment

    var body: some View {
        VStack(alignment: alignment, spacing: 2) {
            Text(slot)
                .font(.caption2)
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Text(value)
                .font(.subheadline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }
}
