// DashboardAnalyticsSheets.swift
// 首页分析类 sheet

import SwiftUI

struct YieldReportData {
    let completeRecords: [ScanFileRecord]
    let totalYield: Float
    let totalFruit: Int

    var totalScans: Int { completeRecords.count }
    var averageYield: Float { totalScans > 0 ? totalYield / Float(totalScans) : 0 }
    var visibleRecords: [ScanFileRecord] { Array(completeRecords.prefix(20)) }
    var isEmpty: Bool { completeRecords.isEmpty }

    init(records: [ScanFileRecord]) {
        let completeRecords = records.filter { $0.persistenceState == .complete }
        self.completeRecords = completeRecords
        totalYield = completeRecords.reduce(0) { $0 + $1.yieldKg }
        totalFruit = completeRecords.reduce(0) { $0 + $1.fruitCount }
    }
}

struct YieldReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var historyStore = ScanHistoryStore.shared
    var onStartScan: (() -> Void)? = nil

    private var reportData: YieldReportData {
        YieldReportData(records: historyStore.scanFiles)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if reportData.isEmpty {
                    DashboardSheetEmptyState(
                        icon: "chart.pie",
                        imageName: "FeatureYieldReport",
                        title: "暂无可靠产量数据",
                        message: "完成扫描并保存完整结果后，这里会按树体汇总产量、果数和平均值。",
                        primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan)
                    )
                } else {
                    reportContent
                }
            }
            .navigationTitle("产量报告")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button("完成") { dismiss() }
                        .foregroundColor(Design.Colors.harvest)
                }
            }
        }
    }

    private var reportContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashboardToolHeader(
                    imageName: "FeatureYieldReport",
                    title: "产量报告",
                    subtitle: "汇总果数、重量和每棵树的扫描结果，适合采收后复核。",
                    icon: "chart.pie",
                    accent: Design.Colors.harvest
                )

                DashboardSheetMetricGrid(items: [
                    .init(title: "扫描", value: "\(reportData.totalScans)", unit: "次"),
                    .init(title: "总产量", value: String(format: "%.1f", reportData.totalYield), unit: "kg"),
                    .init(title: "平均", value: String(format: "%.1f", reportData.averageYield), unit: "kg"),
                    .init(title: "果实", value: "\(reportData.totalFruit)", unit: "个")
                ])

                perTreeBreakdown
            }
            .padding(Design.Space.lg)
        }
    }

    private var perTreeBreakdown: some View {
        let visibleRecords = reportData.visibleRecords

        return VStack(alignment: .leading, spacing: 0) {
            Text("树体明细")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                YieldRecordRow(record: record)
                if index < visibleRecords.count - 1 {
                    Divider()
                        .background(Design.Colors.Dark.glassBorder)
                        .padding(.leading, 14)
                }
            }
        }
        .darkSurface(cornerRadius: 10)
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

struct TrendsData {
    let records: [ScanFileRecord]
    let maxYield: Float

    var isEmpty: Bool { records.isEmpty }

    init(records: [ScanFileRecord]) {
        self.records = records
            .filter { $0.persistenceState == .complete }
            .sorted { $0.scanDate < $1.scanDate }
        maxYield = max(self.records.map(\.yieldKg).max() ?? 1, 1)
    }
}

struct TrendsRecordPresentation: Equatable {
    let treeID: String
    let chartDate: String
    let recordDate: String
    let yieldValue: String
    let yieldText: String
    let fruitText: String

    var chartAccessibilityValue: String {
        "\(chartDate), \(yieldText)"
    }
}

struct TrendsPresentation {
    let title: String
    let done: String
    let doneHint: String
    let emptyTitle: String
    let emptyMessage: String
    let startScan: String
    let headerSubtitle: String
    let chartTitle: String
    let recordsTitle: String

    private let fruitUnitOne: String
    private let fruitUnitOther: String
    private let kilogramsUnit: String

    init(bundle: Bundle = .main) {
        func localized(_ key: String, fallback: String) -> String {
            bundle.localizedString(forKey: key, value: fallback, table: nil)
        }

        title = localized("trends.title", fallback: "趋势")
        done = localized("trends.done", fallback: "完成")
        doneHint = localized("trends.done_hint", fallback: "关闭趋势视图。")
        emptyTitle = localized("trends.empty_title", fallback: "暂无可靠趋势数据")
        emptyMessage = localized(
            "trends.empty_message",
            fallback: "至少完成一次扫描并保存完整结果后，才能显示产量随时间变化。"
        )
        startScan = localized("trends.start_scan", fallback: "开始扫描")
        headerSubtitle = localized(
            "trends.header_subtitle",
            fallback: "按时间查看产量和果数变化，辅助判断采收节奏。"
        )
        chartTitle = localized("trends.chart_title", fallback: "产量趋势")
        recordsTitle = localized("trends.records_title", fallback: "记录")
        fruitUnitOne = localized("trends.unit.fruit_one", fallback: "个")
        fruitUnitOther = localized("trends.unit.fruit_other", fallback: "个")
        kilogramsUnit = localized("trends.unit.kilograms", fallback: "kg")
    }

    func recordPresentation(
        for record: ScanFileRecord,
        locale: Locale
    ) -> TrendsRecordPresentation {
        let yieldValue = Self.formattedDecimal(record.yieldKg, locale: locale)
        let chartDate = record.scanDate.formatted(
            .dateTime
                .locale(locale)
                .month(.twoDigits)
                .day(.twoDigits)
        )

        return TrendsRecordPresentation(
            treeID: record.treeID,
            chartDate: chartDate,
            recordDate: record.scanDate.formatted(
                .dateTime
                    .locale(locale)
                    .year()
                    .month(.twoDigits)
                    .day(.twoDigits)
            ),
            yieldValue: yieldValue,
            yieldText: "\(yieldValue) \(kilogramsUnit)",
            fruitText: "\(Self.formattedInteger(record.fruitCount, locale: locale)) \(record.fruitCount == 1 ? fruitUnitOne : fruitUnitOther)"
        )
    }

    private static func formattedInteger(_ value: Int, locale: Locale) -> String {
        value.formatted(.number.locale(locale).grouping(.automatic))
    }

    private static func formattedDecimal(_ value: Float, locale: Locale) -> String {
        Double(value).formatted(
            .number
                .locale(locale)
                .grouping(.automatic)
                .precision(.fractionLength(1))
        )
    }
}

struct TrendsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject private var historyStore = ScanHistoryStore.shared
    private let onStartScan: (() -> Void)?
    private let bundle: Bundle

    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main) {
        self.onStartScan = onStartScan
        self.bundle = bundle
    }

    private var trendsData: TrendsData { TrendsData(records: historyStore.scanFiles) }

    private var presentation: TrendsPresentation {
        TrendsPresentation(bundle: bundle)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if trendsData.isEmpty {
                    DashboardSheetEmptyState(
                        icon: "chart.xyaxis.line",
                        imageName: "FeatureTrends",
                        title: presentation.emptyTitle,
                        message: presentation.emptyMessage,
                        accent: Design.Colors.Dark.info,
                        primaryAction: action(
                            title: presentation.startScan,
                            icon: "viewfinder",
                            handler: onStartScan
                        )
                    )
                } else {
                    trendsContent
                }
            }
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(presentation.done) { dismiss() }
                        .foregroundColor(Design.Colors.harvest)
                        .accessibilityHint(Text(presentation.doneHint))
                }
            }
        }
    }

    private var trendsContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashboardToolHeader(
                    imageName: "FeatureTrends",
                    title: presentation.title,
                    subtitle: presentation.headerSubtitle,
                    icon: "chart.xyaxis.line",
                    accent: Design.Colors.Dark.info
                )

                trendChart
                trendsTable
            }
            .padding(Design.Space.lg)
        }
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }

    private var trendChart: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text(presentation.chartTitle)
                .font(.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .accessibilityAddTraits(.isHeader)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(trendsData.records) { record in
                        let recordPresentation = presentation.recordPresentation(
                            for: record,
                            locale: locale
                        )
                        TrendsChartPoint(
                            presentation: recordPresentation,
                            yieldRatio: CGFloat(record.yieldKg / trendsData.maxYield),
                            color: barColor(for: record.yieldKg)
                        )
                    }
                }
                .padding(.vertical, 6)
            }
        }
        .padding(14)
        .darkSurface(cornerRadius: 10)
    }

    private var trendsTable: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text(presentation.recordsTitle)
                .font(.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(trendsData.records.enumerated()), id: \.element.id) { index, record in
                TrendsRecordRow(
                    presentation: presentation.recordPresentation(for: record, locale: locale)
                )
                if index < trendsData.records.count - 1 {
                    Divider()
                        .background(Design.Colors.Dark.glassBorder)
                        .padding(.leading, 14)
                }
            }
        }
        .darkSurface(cornerRadius: 10)
    }

    private func barColor(for yield: Float) -> Color {
        let ratio = yield / trendsData.maxYield
        if ratio > 0.7 { return Design.Colors.harvest }
        if ratio > 0.4 { return Design.Colors.Dark.info }
        return Design.Colors.Dark.textMuted
    }
}

struct TrendsChartPoint: View {
    let presentation: TrendsRecordPresentation
    let yieldRatio: CGFloat
    let color: Color

    @ScaledMetric(relativeTo: .caption2) private var scaledBarWidth: CGFloat = 24
    @ScaledMetric(relativeTo: .caption2) private var scaledColumnWidth: CGFloat = 48

    private var barWidth: CGFloat { min(scaledBarWidth, 36) }
    private var columnWidth: CGFloat { min(max(scaledColumnWidth, 48), 160) }

    var body: some View {
        VStack(spacing: 5) {
            Text(presentation.yieldValue)
                .font(.caption2.monospacedDigit().weight(.medium))
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)

            RoundedRectangle(cornerRadius: 3)
                .fill(color)
                .frame(
                    width: barWidth,
                    height: max(6, min(max(yieldRatio, 0), 1) * 120)
                )

            Text(presentation.chartDate)
                .font(.caption2)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .lineLimit(1)
        }
        .frame(width: columnWidth)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(Text(presentation.treeID))
        .accessibilityValue(Text(presentation.chartAccessibilityValue))
    }
}

struct TrendsRecordRow: View {
    let presentation: TrendsRecordPresentation
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize

    var body: some View {
        Group {
            if dynamicTypeSize.isAccessibilitySize {
                accessibilityLayout
            } else {
                horizontalLayout
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
    }

    private var horizontalLayout: some View {
        HStack(spacing: 12) {
            identityColumn

            Spacer()

            measurementColumn(alignment: .trailing)
        }
    }

    private var accessibilityLayout: some View {
        VStack(alignment: .leading, spacing: 10) {
            identityColumn
            measurementColumn(alignment: .leading)
        }
    }

    private var identityColumn: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(presentation.treeID)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            Text(presentation.recordDate)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }

    private func measurementColumn(alignment: HorizontalAlignment) -> some View {
        VStack(alignment: alignment, spacing: 4) {
            Text(presentation.yieldText)
                .font(.system(.subheadline, design: .monospaced, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)

            Text(presentation.fruitText)
                .font(.caption)
                .foregroundColor(Design.Colors.Dark.textSecondary)
        }
    }
}

@available(iOS 17, *)
struct MapSheet: View {
    @Environment(\.dismiss) private var dismiss
    var onStartScan: (() -> Void)? = nil

    var body: some View {
        ZStack {
            OrchardMapView(onStartScan: onStartScan)

            VStack {
                HStack {
                    Button { dismiss() } label: {
                        Image(systemName: "xmark")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundColor(Design.Colors.Dark.textPrimary)
                            .frame(width: 34, height: 34)
                            .background(Design.Colors.Dark.hudBackground)
                            .clipShape(Circle())
                    }
                    .accessibilityLabel("关闭果园地图")
                    .padding(16)

                    Spacer()
                }
                Spacer()
            }
        }
    }
}
