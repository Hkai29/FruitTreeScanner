// DashboardAnalyticsComponents.swift
// 首页分析 sheet 的通用组件

import SwiftUI

struct DashboardAnalyticsRecordPresentation: Equatable {
    let treeID: String
    let dateText: String
    let shortDateText: String
    let yieldValueText: String
    let yieldText: String
    let fruitCountText: String
    let rowAccessibilityLabel: String
    let trendAccessibilityLabel: String

    init(
        record: ScanFileRecord,
        bundle: Bundle = .main,
        locale: Locale = .current,
        timeZone: TimeZone = .current
    ) {
        let localizedDate = Self.formattedDate(
            record.scanDate,
            template: "yMMMd",
            locale: locale,
            timeZone: timeZone
        )
        let localizedShortDate = Self.formattedDate(
            record.scanDate,
            template: "Md",
            locale: locale,
            timeZone: timeZone
        )
        let localizedYieldValue = Self.formattedYield(record.yieldKg, locale: locale)
        let localizedFruitCount = L10n.Dashboard.fruitCountLabel(record.fruitCount, in: bundle)

        let yieldFormat = bundle.localizedString(
            forKey: "dashboard.analytics.yield_format",
            value: "%@ kg",
            table: nil
        )
        let localizedYield = String(format: yieldFormat, locale: locale, localizedYieldValue)

        let rowFormat = bundle.localizedString(
            forKey: "dashboard.analytics.record_accessibility",
            value: "树体 %@，%@，%@，%@",
            table: nil
        )
        let localizedRowAccessibilityLabel = String(
            format: rowFormat,
            locale: locale,
            record.treeID,
            localizedDate,
            localizedYield,
            localizedFruitCount
        )

        let trendFormat = bundle.localizedString(
            forKey: "dashboard.analytics.trend_accessibility",
            value: "%@，产量%@",
            table: nil
        )
        let localizedTrendAccessibilityLabel = String(
            format: trendFormat,
            locale: locale,
            localizedDate,
            localizedYield
        )

        treeID = record.treeID
        dateText = localizedDate
        shortDateText = localizedShortDate
        yieldValueText = localizedYieldValue
        yieldText = localizedYield
        fruitCountText = localizedFruitCount
        rowAccessibilityLabel = localizedRowAccessibilityLabel
        trendAccessibilityLabel = localizedTrendAccessibilityLabel
    }

    private static func formattedDate(
        _ date: Date,
        template: String,
        locale: Locale,
        timeZone: TimeZone
    ) -> String {
        let formatter = DateFormatter()
        formatter.locale = locale
        formatter.timeZone = timeZone
        formatter.setLocalizedDateFormatFromTemplate(template)
        return formatter.string(from: date)
    }

    private static func formattedYield(_ yieldKg: Float, locale: Locale) -> String {
        let formatter = NumberFormatter()
        formatter.locale = locale
        formatter.numberStyle = .decimal
        formatter.minimumFractionDigits = 1
        formatter.maximumFractionDigits = 1
        return formatter.string(from: NSNumber(value: yieldKg)) ?? "0.0"
    }
}

enum DashboardAnalyticsRecordLayout: Equatable {
    case horizontal
    case stacked

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize.isAccessibilitySize ? .stacked : .horizontal
    }
}

struct DashboardSheetMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
}

struct DashboardSheetMetricGrid: View {
    let items: [DashboardSheetMetric]

    var body: some View {
        LazyVGrid(
            columns: [
                GridItem(.flexible(), spacing: 8),
                GridItem(.flexible(), spacing: 8)
            ],
            spacing: 8
        ) {
            ForEach(items) { item in
                DashboardSheetMetricCell(item: item)
            }
        }
    }
}

private struct DashboardSheetMetricCell: View {
    let item: DashboardSheetMetric

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(item.title)
                .font(.system(size: 12, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(item.value)
                    .font(.system(size: 18, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(item.unit)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(Design.Colors.Dark.bgElevated)
        .cornerRadius(8)
    }
}

struct YieldRecordRow: View {
    let record: ScanFileRecord

    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let layout = DashboardAnalyticsRecordLayout(dynamicTypeSize: dynamicTypeSize)
        let presentation = DashboardAnalyticsRecordPresentation(
            record: record,
            locale: locale,
            timeZone: timeZone
        )

        Group {
            switch layout {
            case .horizontal:
                HStack(spacing: 12) {
                    identity(presentation)
                    Spacer()
                    metrics(presentation, alignment: .trailing)
                }
            case .stacked:
                VStack(alignment: .leading, spacing: 8) {
                    identity(presentation)
                    metrics(presentation, alignment: .leading)
                }
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.rowAccessibilityLabel)
    }

    private func identity(_ presentation: DashboardAnalyticsRecordPresentation) -> some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.treeID)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text(presentation.dateText)
                .font(.caption.weight(.medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private func metrics(
        _ presentation: DashboardAnalyticsRecordPresentation,
        alignment: HorizontalAlignment
    ) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(presentation.yieldText)
                .font(.system(.subheadline, design: .monospaced).weight(.semibold))
                .foregroundColor(Design.Colors.harvest)

            Text(presentation.fruitCountText)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }
}

struct TrendBar: View {
    let record: ScanFileRecord
    let maxYield: Float
    let color: Color

    @ScaledMetric(relativeTo: .caption2) private var barWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var columnWidth: CGFloat = 42
    @ScaledMetric(relativeTo: .caption2) private var minimumBarHeight: CGFloat = 6
    @ScaledMetric(relativeTo: .caption2) private var maximumBarHeight: CGFloat = 120
    @Environment(\.locale) private var locale
    @Environment(\.timeZone) private var timeZone

    var body: some View {
        let presentation = DashboardAnalyticsRecordPresentation(
            record: record,
            locale: locale,
            timeZone: timeZone
        )

        VStack(spacing: 5) {
            Text(presentation.yieldValueText)
                .font(.caption2.weight(.medium))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Dark.textSecondary)

            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(
                    width: barWidth,
                    height: max(
                        minimumBarHeight,
                        CGFloat(record.yieldKg / maxYield) * maximumBarHeight
                    )
                )

            Text(presentation.shortDateText)
                .font(.caption2)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
        .frame(width: columnWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(presentation.trendAccessibilityLabel)
    }
}
