// DashboardAnalyticsSheets.swift
// 产量报告 / 趋势：采收后的复核页。
//
// 数据全部来自 `DashboardAggregationStore` 的真实聚合
// （`YieldReportData` / `TrendsData`），界面不发明任何指标。

import SwiftUI

// MARK: - 产量报告

struct YieldReportMetricPresentation: Equatable {
    let title: String
    let value: String
    let unit: String
}

struct YieldReportRecordPresentation: Equatable {
    let treeID: String
    let date: String
    let yield: String
    let fruit: String
}

struct YieldReportPresentation {
    let title: String
    let done: String
    let doneHint: String
    let emptyTitle: String
    let emptyMessage: String
    let startScan: String
    let headerSubtitle: String
    let treeDetailsTitle: String

    private let scansMetricTitle: String
    private let totalYieldMetricTitle: String
    private let averageYieldMetricTitle: String
    private let fruitMetricTitle: String
    private let scanUnitOne: String
    private let scanUnitOther: String
    private let fruitUnitOne: String
    private let fruitUnitOther: String
    private let kilogramsUnit: String
    private let outOfRangeText: String

    init(bundle: Bundle = .main) {
        func localized(_ key: String, fallback: String) -> String {
            bundle.localizedString(forKey: key, value: fallback, table: nil)
        }

        title = localized("yield_report.title", fallback: "产量报告")
        done = localized("yield_report.done", fallback: "完成")
        doneHint = localized("yield_report.done_hint", fallback: "关闭产量报告。")
        emptyTitle = localized("yield_report.empty_title", fallback: "暂无可靠产量数据")
        emptyMessage = localized(
            "yield_report.empty_message",
            fallback: "完成扫描并保存完整结果后，这里会按树体汇总产量、果数和平均值。"
        )
        startScan = localized("yield_report.start_scan", fallback: "开始扫描")
        headerSubtitle = localized(
            "yield_report.header_subtitle",
            fallback: "汇总果数、重量和每棵树的扫描结果，适合采收后复核。"
        )
        treeDetailsTitle = localized("yield_report.tree_details", fallback: "树体明细")
        scansMetricTitle = localized("yield_report.metric.scans", fallback: "扫描")
        totalYieldMetricTitle = localized("yield_report.metric.total_yield", fallback: "总产量")
        averageYieldMetricTitle = localized("yield_report.metric.average_yield", fallback: "平均")
        fruitMetricTitle = localized("yield_report.metric.fruit", fallback: "果实")
        outOfRangeText = localized("yield_report.metric.out_of_range", fallback: "超出范围")
        scanUnitOne = localized("yield_report.unit.scan_one", fallback: "次")
        scanUnitOther = localized("yield_report.unit.scan_other", fallback: "次")
        fruitUnitOne = localized("yield_report.unit.fruit_one", fallback: "个")
        fruitUnitOther = localized("yield_report.unit.fruit_other", fallback: "个")
        kilogramsUnit = localized("yield_report.unit.kilograms", fallback: "kg")
    }

    func metricPresentations(
        totalScans: Int,
        totalYield: Float?,
        averageYield: Float?,
        totalFruit: Int?,
        locale: Locale
    ) -> [YieldReportMetricPresentation] {
        [
            YieldReportMetricPresentation(
                title: scansMetricTitle,
                value: Self.formattedInteger(totalScans, locale: locale),
                unit: totalScans == 1 ? scanUnitOne : scanUnitOther
            ),
            YieldReportMetricPresentation(
                title: totalYieldMetricTitle,
                value: totalYield.map { Self.formattedDecimal($0, locale: locale) } ?? outOfRangeText,
                unit: totalYield == nil ? "" : kilogramsUnit
            ),
            YieldReportMetricPresentation(
                title: averageYieldMetricTitle,
                value: averageYield.map { Self.formattedDecimal($0, locale: locale) } ?? outOfRangeText,
                unit: averageYield == nil ? "" : kilogramsUnit
            ),
            YieldReportMetricPresentation(
                title: fruitMetricTitle,
                value: totalFruit.map { Self.formattedInteger($0, locale: locale) } ?? outOfRangeText,
                unit: totalFruit.map { $0 == 1 ? fruitUnitOne : fruitUnitOther } ?? ""
            )
        ]
    }

    func recordPresentation(
        for record: ScanFileRecord,
        locale: Locale
    ) -> YieldReportRecordPresentation {
        YieldReportRecordPresentation(
            treeID: record.treeID,
            date: record.scanDate.formatted(
                .dateTime
                    .locale(locale)
                    .year()
                    .month(.twoDigits)
                    .day(.twoDigits)
            ),
            yield: "\(Self.formattedDecimal(record.yieldKg, locale: locale)) \(kilogramsUnit)",
            fruit: "\(Self.formattedInteger(record.fruitCount, locale: locale)) \(record.fruitCount == 1 ? fruitUnitOne : fruitUnitOther)"
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

/// 产量报告：采收后的复核页。
///
/// 三个关键数字（扫描次数、总产量、单株均值）占据最大视觉权重，
/// 每棵树的明细在下面按档案行的写法排列。
struct YieldReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var aggregation: DashboardAggregationStore
    private let historyStore: ScanHistoryStore
    private let onStartScan: (() -> Void)?
    private let bundle: Bundle

    @MainActor
    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main, historyStore: ScanHistoryStore? = nil) {
        self.onStartScan = onStartScan
        self.bundle = bundle
        let historyStore = historyStore ?? .shared
        self.historyStore = historyStore
        self.aggregation = historyStore.dashboardAggregation
    }

    private var reportData: YieldReportData {
        aggregation.snapshot.report
    }

    private var presentation: YieldReportPresentation {
        YieldReportPresentation(bundle: bundle)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Workspace.background.ignoresSafeArea()

                if reportData.isEmpty {
                    // 空状态必须可滚动：辅助字号下说明文字会把操作按钮顶出视口。
                    ScrollView {
                        DashboardSheetEmptyState(
                            icon: "chart.pie",
                            title: presentation.emptyTitle,
                            message: presentation.emptyMessage,
                            primaryAction: action(
                                title: presentation.startScan,
                                icon: "viewfinder",
                                handler: onStartScan
                            )
                        )
                    }
                } else {
                    reportContent
                }
            }
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onAppear {
                aggregation.refreshTimeContext()
                historyStore.loadRecords()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { aggregation.refreshTimeContext() }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(presentation.done) { dismiss() }
                        .foregroundColor(Design.Colors.Workspace.accent)
                        .accessibilityHint(Text(presentation.doneHint))
                }
            }
        }
    }

    // MARK: - 内容

    private var reportContent: some View {
        let metrics = presentation.metricPresentations(
            totalScans: reportData.totalScans,
            totalYield: reportData.totalYield,
            averageYield: reportData.averageYield,
            totalFruit: reportData.totalFruit,
            locale: locale
        )

        return ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(presentation.headerSubtitle)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                keyFigures(Array(metrics.prefix(3)))
                secondaryFigures(Array(metrics.dropFirst(3)))
                perTreeChart
                perTreeList            }
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    /// 关键数字：扫描次数、总产量、单株均值。
    ///
    /// 三个数字用 `InstrumentDatum`（大字），是整页视觉权重最高的读数。
    private func keyFigures(_ metrics: [YieldReportMetricPresentation]) -> some View {
        InstrumentPanel {
            Group {
                if dynamicTypeSize.isAccessibilitySize {
                    VStack(alignment: .leading, spacing: 14) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                            if index > 0 { DividerLine() }
                            datum(metric)
                        }
                    }
                } else {
                    HStack(spacing: 0) {
                        ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                            if index > 0 { divider }
                            datum(metric)
                        }
                    }
                }
            }
        }
    }

    /// 次要读数：果实总数与树体数量。比关键数字小一号，不与它争注意力。
    private func secondaryFigures(_ metrics: [YieldReportMetricPresentation]) -> some View {
        InstrumentStatStrip {
            HStack(spacing: 0) {
                ForEach(Array(metrics.enumerated()), id: \.offset) { index, metric in
                    if index > 0 { divider }
                    secondaryDatum(
                        label: metric.title,
                        value: metric.unit.isEmpty ? metric.value : "\(metric.value) \(metric.unit)"
                    )
                }
                divider
                secondaryDatum(
                    label: L10n.Dashboard.treeIDs,
                    value: "\(reportData.totalTrees) \(L10n.Dashboard.treeCountUnit(reportData.totalTrees))"
                )
            }
        }
    }

    private func datum(_ metric: YieldReportMetricPresentation) -> some View {
        InstrumentDatum(
            label: metric.title,
            value: metric.value,
            unit: metric.unit.isEmpty ? nil : metric.unit
        )
    }

    /// 次要读数：标签在上、数字在下，数字比关键读数小一号。
    private func secondaryDatum(label: String, value: String) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .instrumentLabel()
            Text(value)
                .font(.system(.subheadline, design: .default).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.ink)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.Workspace.line)
            .frame(width: 0.5, height: 34)
            .accessibilityHidden(true)
    }

    // MARK: - 每棵树

    private var perTreeChart: some View {
        InstrumentPanel(label: WorkspaceText.estimatedYield, systemImage: "chart.bar") {
            InstrumentBarChart(bars: barEntries)
        }
    }

    private var barEntries: [InstrumentBarChart.Bar] {
        reportData.visibleRecords.map { record in
            let tier = InstrumentRecord.tier(for: record)
            return InstrumentBarChart.Bar(
                id: record.id,
                label: record.treeID,
                value: Double(record.yieldKg),
                displayValue: presentation.recordPresentation(for: record, locale: locale).yield,
                tint: tier == .complete
                    ? Design.Colors.Workspace.accent
                    : tier.tint
            )
        }
    }

    private var perTreeList: some View {
        let visibleRecords = reportData.visibleRecords
        let reviewCount = visibleRecords.filter { InstrumentRecord.tier(for: $0) != .complete }.count

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(presentation.treeDetailsTitle)
                    .instrumentLabel()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                InstrumentInlineDatum(
                    label: L10n.Dashboard.treeIDs,
                    value: "\(visibleRecords.count) / \(reportData.totalTrees)"
                )
                if reviewCount > 0 {
                    InstrumentInlineDatum(
                        label: WorkspaceText.review,
                        value: "\(reviewCount)"
                    )
                }
            }

            InstrumentRowGroup {
                ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                    InstrumentScanRow(record: record)
                    if index < visibleRecords.count - 1 {
                        DividerLine(inset: 0)
                    }
                }
            }
        }
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

// MARK: - 趋势

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
    private let insufficientDaysFormat: String

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
        insufficientDaysFormat = localized(
            "trends.insufficient_days",
            fallback: "产量趋势至少需要 2 天的完整扫描，当前只有 %d 天。"
        )
    }

    /// 数据不足时的说明：说清缺什么，而不是画一条平线。
    func insufficientDaysMessage(dayCount: Int, locale: Locale) -> String {
        String(format: insufficientDaysFormat, locale: locale, dayCount)
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

/// 趋势：产量随时间的变化。
///
/// 折线由**按天聚合的真实产量**驱动；只有一天数据时说明缺什么，不画平线。
struct TrendsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @Environment(\.scenePhase) private var scenePhase
    @ObservedObject private var aggregation: DashboardAggregationStore
    private let historyStore: ScanHistoryStore
    private let onStartScan: (() -> Void)?
    private let bundle: Bundle

    @MainActor
    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main, historyStore: ScanHistoryStore? = nil) {
        self.onStartScan = onStartScan
        self.bundle = bundle
        let historyStore = historyStore ?? .shared
        self.historyStore = historyStore
        self.aggregation = historyStore.dashboardAggregation
    }

    private var trendsData: TrendsData { aggregation.snapshot.trends }

    private var presentation: TrendsPresentation {
        TrendsPresentation(bundle: bundle)
    }

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Workspace.background.ignoresSafeArea()

                if trendsData.isEmpty {
                    // 空状态必须可滚动：辅助字号下说明文字会把操作按钮顶出视口。
                    ScrollView {
                        DashboardSheetEmptyState(
                            icon: "chart.xyaxis.line",
                            title: presentation.emptyTitle,
                            message: presentation.emptyMessage,
                            accent: Design.Colors.Workspace.information,
                            primaryAction: action(
                                title: presentation.startScan,
                                icon: "viewfinder",
                                handler: onStartScan
                            )
                        )
                    }
                } else {
                    trendsContent
                }
            }
            .navigationTitle(presentation.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .onAppear {
                aggregation.refreshTimeContext()
                historyStore.loadRecords()
            }
            .onChange(of: scenePhase) { phase in
                if phase == .active { aggregation.refreshTimeContext() }
            }
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(presentation.done) { dismiss() }
                        .foregroundColor(Design.Colors.Workspace.accent)
                        .accessibilityHint(Text(presentation.doneHint))
                }
            }
        }
    }

    // MARK: - 内容

    private var trendsContent: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                Text(presentation.headerSubtitle)
                    .font(.footnote)
                    .foregroundColor(Design.Colors.Workspace.secondary)
                    .fixedSize(horizontal: false, vertical: true)

                trendPanel
                recordList
            }
            .frame(maxWidth: 1080, alignment: .leading)
            .frame(maxWidth: .infinity, alignment: .leading)
            .padding(.horizontal, 20)
            .padding(.top, 12)
            .padding(.bottom, 24)
        }
    }

    private var trendPanel: some View {
        InstrumentPanel(label: presentation.chartTitle, systemImage: "chart.xyaxis.line") {
            if dailyPoints.count > 1 {
                VStack(alignment: .leading, spacing: 12) {
                    InstrumentTrendChart(points: chartPoints)
                    endLabels
                }
            } else {
                InstrumentNotice(
                    message: presentation.insufficientDaysMessage(
                        dayCount: dailyPoints.count,
                        locale: locale
                    ),
                    tone: .attention,
                    systemImage: "chart.xyaxis.line"
                )
            }
        }
    }

    /// 端点读数：等宽数字，首尾两天的真实日产量。
    private var endLabels: some View {
        HStack(spacing: 0) {
            if let first = dailyPoints.first {
                InstrumentDatum(
                    label: first.label,
                    value: Self.formatted(first.value, locale: locale),
                    unit: "kg"
                )
            }
            Rectangle()
                .fill(Design.Colors.Workspace.line)
                .frame(width: 0.5, height: 34)
                .accessibilityHidden(true)
            if let last = dailyPoints.last {
                InstrumentDatum(
                    label: last.label,
                    value: Self.formatted(last.value, locale: locale),
                    unit: "kg"
                )
            }
        }
    }

    private var chartPoints: [InstrumentTrendChart.Point] {
        dailyPoints.enumerated().map { index, point in
            InstrumentTrendChart.Point(id: index, label: point.label, value: point.value)
        }
    }

    /// 按天聚合的真实日产量。
    private var dailyPoints: [DailyYield] {
        let calendar = aggregation.snapshot.context.calendar
        let grouped = Dictionary(grouping: trendsData.records) { record in
            calendar.startOfDay(for: record.scanDate)
        }
        return grouped
            .map { day, records in
                DailyYield(
                    day: day,
                    label: day.formatted(.dateTime.month(.abbreviated).day()),
                    value: Double(records.reduce(Float(0)) { $0 + $1.yieldKg })
                )
            }
            .sorted { $0.day < $1.day }
    }

    private var recordList: some View {
        let records = trendsData.records

        return VStack(alignment: .leading, spacing: 8) {
            HStack(alignment: .firstTextBaseline, spacing: 12) {
                Text(presentation.recordsTitle)
                    .instrumentLabel()
                    .accessibilityAddTraits(.isHeader)
                Spacer(minLength: 8)
                InstrumentInlineDatum(
                    label: L10n.Dashboard.totalScans,
                    value: "\(records.count)"
                )
            }

            InstrumentRowGroup {
                ForEach(Array(records.enumerated()), id: \.element.id) { index, record in
                    InstrumentScanRow(record: record)
                    if index < records.count - 1 {
                        DividerLine(inset: 0)
                    }
                }
            }
        }
    }

    private static func formatted(_ value: Double, locale: Locale) -> String {
        value.formatted(
            .number
                .locale(locale)
                .grouping(.automatic)
                .precision(.fractionLength(1))
        )
    }

    private func action(title: String, icon: String, handler: (() -> Void)?) -> DashboardSheetAction? {
        guard let handler else { return nil }
        return DashboardSheetAction(title: title, icon: icon, action: handler)
    }
}

/// 一天的产量聚合。
private struct DailyYield: Identifiable {
    let day: Date
    let label: String
    let value: Double

    var id: Date { day }
}

// MARK: - 地图

@available(iOS 17, *)
struct MapSheet: View {
    private let onStartScan: (() -> Void)?
    /// 「按树复扫」的能力：地图里的档案要能带着**这一棵树**进入扫描。
    private let onRescanTree: ((String) -> Void)?
    private let bundle: Bundle
    private let historyStore: ScanHistoryStore

    @MainActor
    init(
        onStartScan: (() -> Void)? = nil,
        onRescanTree: ((String) -> Void)? = nil,
        bundle: Bundle = .main,
        historyStore: ScanHistoryStore? = nil
    ) {
        self.onStartScan = onStartScan
        self.onRescanTree = onRescanTree
        self.bundle = bundle
        self.historyStore = historyStore ?? .shared
    }

    var body: some View {
        OrchardMapView(
            onStartScan: onStartScan,
            onRescanTree: onRescanTree,
            bundle: bundle,
            historyStore: historyStore
        )
    }
}
