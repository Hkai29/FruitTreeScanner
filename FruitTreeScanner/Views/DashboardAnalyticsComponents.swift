// DashboardAnalyticsComponents.swift
// 分析 sheet 的共享读数与栅格。
//
// 档案行统一由 `InstrumentScanRow` 承担（Design/InstrumentRecords.swift），
// 本文件只保留跨页复用的读数模型与统计栅格。

import SwiftUI

/// 一条分析记录的可读性文案。
///
/// 供档案行以外的读数复用：树号、日期、产量、果数与朗读顺序。
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
        YieldNumberFormatting.text(yieldKg, locale: locale)
    }
}

/// 记录行的版式：辅助字号横排，辅助字号竖排。
enum DashboardAnalyticsRecordLayout: Equatable {
    case horizontal
    case stacked

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize.isAccessibilitySize ? .stacked : .horizontal
    }
}

// MARK: - 统计栅格

struct DashboardSheetMetric: Identifiable {
    let id = UUID()
    let title: String
    let value: String
    let unit: String
}

enum DashboardSheetMetricGridLayout: Equatable {
    case twoColumns
    case singleColumn

    init(dynamicTypeSize: DynamicTypeSize) {
        self = dynamicTypeSize.isAccessibilitySize ? .singleColumn : .twoColumns
    }

    var columnCount: Int {
        switch self {
        case .twoColumns: return 2
        case .singleColumn: return 1
        }
    }
}

/// 读数栅格。两栏，辅助字号下改为单栏，避免数字被挤压。
struct DashboardSheetMetricGrid: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    let items: [DashboardSheetMetric]

    private var layout: DashboardSheetMetricGridLayout {
        DashboardSheetMetricGridLayout(dynamicTypeSize: dynamicTypeSize)
    }

    private var columns: [GridItem] {
        Array(
            repeating: GridItem(.flexible(), spacing: Design.Space.xs),
            count: layout.columnCount
        )
    }

    var body: some View {
        LazyVGrid(
            columns: columns,
            spacing: Design.Space.xs
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
                .font(.subheadline.weight(.medium))
                .foregroundColor(Design.Colors.Workspace.secondary)

            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(item.value)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.ink)

                Text(item.unit)
                    .font(.caption.weight(.medium))
                    .foregroundColor(Design.Colors.Workspace.muted)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }
}
