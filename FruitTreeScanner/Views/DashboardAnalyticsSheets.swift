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
