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
        scanUnitOne = localized("yield_report.unit.scan_one", fallback: "次")
        scanUnitOther = localized("yield_report.unit.scan_other", fallback: "次")
        fruitUnitOne = localized("yield_report.unit.fruit_one", fallback: "个")
        fruitUnitOther = localized("yield_report.unit.fruit_other", fallback: "个")
        kilogramsUnit = localized("yield_report.unit.kilograms", fallback: "kg")
    }

    func metricPresentations(
        totalScans: Int,
        totalYield: Float,
        averageYield: Float,
        totalFruit: Int,
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
                value: Self.formattedDecimal(totalYield, locale: locale),
                unit: kilogramsUnit
            ),
            YieldReportMetricPresentation(
                title: averageYieldMetricTitle,
                value: Self.formattedDecimal(averageYield, locale: locale),
                unit: kilogramsUnit
            ),
            YieldReportMetricPresentation(
                title: fruitMetricTitle,
                value: Self.formattedInteger(totalFruit, locale: locale),
                unit: totalFruit == 1 ? fruitUnitOne : fruitUnitOther
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

struct YieldReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.locale) private var locale
    @ObservedObject private var historyStore = ScanHistoryStore.shared
    private let onStartScan: (() -> Void)?
    private let bundle: Bundle

    init(onStartScan: (() -> Void)? = nil, bundle: Bundle = .main) {
        self.onStartScan = onStartScan
        self.bundle = bundle
    }

    private var reportData: YieldReportData {
        YieldReportData(records: historyStore.scanFiles)
    }

    private var presentation: YieldReportPresentation {
        YieldReportPresentation(bundle: bundle)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if reportData.isEmpty {
                    DashboardSheetEmptyState(
                        icon: "chart.pie",
                        imageName: "FeatureYieldReport",
                        title: presentation.emptyTitle,
                        message: presentation.emptyMessage,
                        primaryAction: action(
                            title: presentation.startScan,
                            icon: "viewfinder",
                            handler: onStartScan
                        )
                    )
                } else {
                    reportContent
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

    private var reportContent: some View {
        let metrics = presentation.metricPresentations(
            totalScans: reportData.totalScans,
            totalYield: reportData.totalYield,
            averageYield: reportData.averageYield,
            totalFruit: reportData.totalFruit,
            locale: locale
        )

        return ScrollView {
            VStack(spacing: 14) {
                DashboardToolHeader(
                    imageName: "FeatureYieldReport",
                    title: presentation.title,
                    subtitle: presentation.headerSubtitle,
                    icon: "chart.pie",
                    accent: Design.Colors.harvest
                )

                DashboardSheetMetricGrid(
                    items: metrics.map {
                        DashboardSheetMetric(title: $0.title, value: $0.value, unit: $0.unit)
                    }
                )

                perTreeBreakdown
            }
            .padding(Design.Space.lg)
        }
    }

    private var perTreeBreakdown: some View {
        let visibleRecords = reportData.visibleRecords

        return VStack(alignment: .leading, spacing: 0) {
            Text(presentation.treeDetailsTitle)
                .font(.headline)
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)
                .accessibilityAddTraits(.isHeader)

            ForEach(Array(visibleRecords.enumerated()), id: \.element.id) { index, record in
                YieldReportRecordRow(
                    presentation: presentation.recordPresentation(for: record, locale: locale)
                )
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

private struct YieldReportRecordRow: View {
    let presentation: YieldReportRecordPresentation

    var body: some View {
        HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 4) {
                Text(presentation.treeID)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)

                Text(presentation.date)
                    .font(.system(size: 11, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }

            Spacer()

            VStack(alignment: .trailing, spacing: 4) {
                Text(presentation.yield)
                    .font(.system(size: 14, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.harvest)

                Text(presentation.fruit)
                    .font(.system(size: 11))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .accessibilityElement(children: .combine)
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

struct TrendsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var historyStore = ScanHistoryStore.shared
    var onStartScan: (() -> Void)? = nil

    private var trendsData: TrendsData { TrendsData(records: historyStore.scanFiles) }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if trendsData.isEmpty {
                    DashboardSheetEmptyState(
                        icon: "chart.xyaxis.line",
                        imageName: "FeatureTrends",
                        title: "暂无可靠趋势数据",
                        message: "至少完成一次扫描并保存完整结果后，才能显示产量随时间变化。",
                        accent: Design.Colors.Dark.info,
                        primaryAction: action(title: "开始扫描", icon: "viewfinder", handler: onStartScan)
                    )
                } else {
                    trendsContent
                }
            }
            .navigationTitle("趋势")
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

    private var trendsContent: some View {
        ScrollView {
            VStack(spacing: 14) {
                DashboardToolHeader(
                    imageName: "FeatureTrends",
                    title: "趋势",
                    subtitle: "按时间查看产量和果数变化，辅助判断采收节奏。",
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
            Text("产量趋势")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(alignment: .bottom, spacing: 10) {
                    ForEach(trendsData.records) { record in
                        TrendBar(
                            record: record,
                            maxYield: trendsData.maxYield,
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
            Text("记录")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(trendsData.records.enumerated()), id: \.element.id) { index, record in
                YieldRecordRow(record: record)
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
