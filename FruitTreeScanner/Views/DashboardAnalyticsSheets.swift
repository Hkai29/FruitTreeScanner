// DashboardAnalyticsSheets.swift
// 首页分析类 sheet

import SwiftUI

struct YieldReportSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var historyStore = ScanHistoryStore.shared
    var onStartScan: (() -> Void)? = nil

    private var completeRecords: [ScanFileRecord] { historyStore.scanFiles.filter { $0.persistenceState == .complete } }
    private var totalScans: Int { completeRecords.count }
    private var totalYield: Float { completeRecords.reduce(0) { $0 + $1.yieldKg } }
    private var avgYield: Float { totalScans > 0 ? totalYield / Float(totalScans) : 0 }
    private var totalFruit: Int { completeRecords.reduce(0) { $0 + $1.fruitCount } }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    DashboardSheetEmptyState(
                        icon: "chart.pie",
                        imageName: "FeatureYieldReport",
                        title: "暂无产量数据",
                        message: "完成扫描后，这里会按树体汇总产量、果数和平均值。",
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
                    .init(title: "扫描", value: "\(totalScans)", unit: "次"),
                    .init(title: "总产量", value: String(format: "%.1f", totalYield), unit: "kg"),
                    .init(title: "平均", value: String(format: "%.1f", avgYield), unit: "kg"),
                    .init(title: "果实", value: "\(totalFruit)", unit: "个")
                ])

                perTreeBreakdown
            }
            .padding(Design.Space.lg)
        }
    }

    private var perTreeBreakdown: some View {
        VStack(alignment: .leading, spacing: 0) {
            Text("树体明细")
                .font(.system(size: 15, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .padding(.horizontal, 14)
                .padding(.top, 14)
                .padding(.bottom, 8)

            ForEach(Array(historyStore.scanFiles.prefix(20).enumerated()), id: \.element.id) { index, record in
                YieldRecordRow(record: record)
                if index < min(historyStore.scanFiles.count, 20) - 1 {
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

struct TrendsSheet: View {
    @Environment(\.dismiss) private var dismiss
    @ObservedObject private var historyStore = ScanHistoryStore.shared
    var onStartScan: (() -> Void)? = nil

    private var sortedRecords: [ScanFileRecord] {
        historyStore.scanFiles.sorted { $0.scanDate < $1.scanDate }
    }

    private var maxYield: Float {
        max(sortedRecords.map(\.yieldKg).max() ?? 1, 1)
    }

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                if historyStore.scanFiles.isEmpty {
                    DashboardSheetEmptyState(
                        icon: "chart.xyaxis.line",
                        imageName: "FeatureTrends",
                        title: "暂无趋势数据",
                        message: "至少完成一次扫描后，才能显示产量随时间变化。",
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
                    ForEach(sortedRecords) { record in
                        TrendBar(
                            record: record,
                            maxYield: maxYield,
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

            ForEach(Array(sortedRecords.enumerated()), id: \.element.id) { index, record in
                YieldRecordRow(record: record)
                if index < sortedRecords.count - 1 {
                    Divider()
                        .background(Design.Colors.Dark.glassBorder)
                        .padding(.leading, 14)
                }
            }
        }
        .darkSurface(cornerRadius: 10)
    }

    private func barColor(for yield: Float) -> Color {
        let ratio = yield / maxYield
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
