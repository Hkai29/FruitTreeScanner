// DashboardRecentAndStats.swift
// 最近扫描与今日/累计读数。所有数值来自真实归档记录。

import SwiftUI

struct RecentScansSection: View {
    var scans: [ScanFileRecord]
    var onViewAll: (() -> Void)? = nil
    var onScanTap: ((ScanFileRecord) -> Void)? = nil
    var onStartScan: (() -> Void)? = nil
    var compactLandscape: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: compactLandscape ? 10 : 16) {
            DashboardSectionHeader(
                title: L10n.Dashboard.recentScans,
                actionTitle: L10n.Dashboard.viewAll,
                onAction: onViewAll
            )

            if scans.isEmpty {
                emptyRecentScans
            } else {
                InstrumentRowGroup {
                    ForEach(scans) { record in
                        Button {
                            onScanTap?(record)
                        } label: {
                            InstrumentScanRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel(
                            L10n.Dashboard.viewPointCloudAccessibilityLabel(treeID: record.treeID)
                        )
                        .accessibilityValue(ScanHistoryRecordPresentation(record: record).accessibilityValue)
                        .accessibilityIdentifier("dashboard.recentScan.\(record.treeID)")
                    }
                }
            }

            Spacer(minLength: 0)
        }
        .padding(.vertical, compactLandscape ? 10 : 16)
    }

    private var emptyRecentScans: some View {
        InstrumentEmptyState(
            systemImage: "square.stack.3d.up",
            title: L10n.Dashboard.noScans,
            message: L10n.Dashboard.emptyDescription
        ) {
            if let onStartScan {
                Button(action: onStartScan) {
                    Label(L10n.Dashboard.startFirstScan, systemImage: "viewfinder")
                }
                .buttonStyle(WorkspacePrimaryButtonStyle())
                .padding(.top, 4)
            }
        }
    }
}

struct RecentScanCard: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let record: ScanFileRecord
    var compactLandscape: Bool = false

    private var presentation: ScanHistoryRecordPresentation {
        ScanHistoryRecordPresentation(record: record)
    }

    var body: some View {
        InstrumentScanRow(record: record)
    }
}

struct StatsOverviewSection: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    let snapshot: DashboardAggregationSnapshot
    var compactLandscape: Bool = false
    var emptyActionTitle: String = WorkspaceText.openArchives
    var onEmptyAction: (() -> Void)? = nil

    private var summary: DashboardDailySummary { snapshot.daily }
    private var report: YieldReportData { snapshot.report }

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            overviewHeaderLayout {
                DashboardSectionHeader(title: L10n.Dashboard.todayOverview)
                Text(
                    snapshot.context.dayStart,
                    format: Date.FormatStyle(
                        date: .abbreviated,
                        time: .omitted,
                        locale: locale,
                        calendar: snapshot.context.calendar,
                        timeZone: snapshot.context.calendar.timeZone
                    )
                )
                .font(.caption)
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.muted)
            }

            if summary.scanCount == 0 {
                InstrumentEmptyState(
                    systemImage: "chart.xyaxis.line",
                    title: WorkspaceText.noScansToday,
                    message: WorkspaceText.analysisExplanation
                ) {
                    if let onEmptyAction {
                        Button(action: onEmptyAction) {
                            Text(emptyActionTitle)
                        }
                        .buttonStyle(WorkspaceSecondaryButtonStyle())
                        .padding(.top, 4)
                        .accessibilityIdentifier("dashboard.analysis.emptyAction")
                    }
                }
            } else {
                dailyStrip
                archiveTotals
                trendBlock
            }
        }
        .padding(.vertical, compactLandscape ? 14 : 20)
    }

    private var overviewHeaderLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(alignment: .leading, spacing: 8))
            : AnyLayout(HStackLayout(alignment: .firstTextBaseline))
    }

    /// 今日三项统计。辅助大字号下改成纵排：
    /// 横排会把"35.0 kg"和"2 次"挤在一起，标签也会碰撞。
    private var dailyStrip: some View {
        InstrumentStatStrip {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 10) {
                    InstrumentDatum(
                        label: L10n.Dashboard.yield,
                        value: String(format: "%.1f", summary.yieldKg),
                        unit: "kg"
                    )
                    horizontalDivider
                    InstrumentDatum(
                        label: L10n.Dashboard.todayScans,
                        value: "\(summary.scanCount)",
                        unit: "次"
                    )
                    horizontalDivider
                    InstrumentDatum(
                        label: L10n.Dashboard.treeIDs,
                        value: "\(summary.treeCount)",
                        unit: "棵"
                    )
                }
                // 纵排时数字离卡片边缘要和其他面板一样是 18pt，
                // 不能贴着 stat 条自己的 4pt 内边距。
                .padding(.horizontal, 14)
            } else {
                HStack(spacing: 0) {
                    InstrumentDatum(
                        label: L10n.Dashboard.yield,
                        value: String(format: "%.1f", summary.yieldKg),
                        unit: "kg"
                    )
                    divider
                    InstrumentDatum(
                        label: L10n.Dashboard.todayScans,
                        value: "\(summary.scanCount)",
                        unit: "次"
                    )
                    divider
                    InstrumentDatum(
                        label: L10n.Dashboard.treeIDs,
                        value: "\(summary.treeCount)",
                        unit: "棵"
                    )
                }
            }
        }
    }

    private var archiveTotals: some View {
        InstrumentPanel(label: L10n.Dashboard.archiveTotals) {
            VStack(alignment: .leading, spacing: 12) {
                InstrumentInlineDatum(
                    label: L10n.Dashboard.totalYield,
                    value: report.totalYield.map { String(format: "%.1f kg", $0) } ?? "—"
                )
                InstrumentInlineDatum(
                    label: L10n.Dashboard.treeIDs,
                    value: "\(report.totalTrees) 棵"
                )
                InstrumentInlineDatum(
                    label: L10n.Dashboard.averagePerTree,
                    value: report.averageYield.map { String(format: "%.1f kg", $0) } ?? "—"
                )
                InstrumentInlineDatum(
                    label: L10n.Dashboard.totalScans,
                    value: "\(report.totalScans) 次"
                )
            }
        }
    }

    @ViewBuilder private var trendBlock: some View {
        let points = trendPoints
        if points.count > 1 {
            InstrumentPanel(label: L10n.Dashboard.trendsTitle) {
                InstrumentTrendChart(points: points)
            }
        }
    }

    private var trendPoints: [InstrumentTrendChart.Point] {
        let grouped = Dictionary(grouping: snapshot.trends.records) { record in
            Calendar.current.startOfDay(for: record.scanDate)
        }
        return grouped
            .map { day, records in
                InstrumentTrendChart.Point(
                    id: Int(day.timeIntervalSince1970),
                    label: day.formatted(.dateTime.month(.abbreviated).day()),
                    value: Double(records.reduce(Float(0)) { $0 + $1.yieldKg })
                )
            }
            .sorted { $0.id < $1.id }
    }

    private var divider: some View {
        Rectangle()
            .fill(Design.Colors.Workspace.line)
            .frame(width: 0.5, height: 34)
            .accessibilityHidden(true)
    }

    /// 纵排时的横向发丝线。
    private var horizontalDivider: some View {
        Rectangle()
            .fill(Design.Colors.Workspace.line)
            .frame(height: 0.5)
            .accessibilityHidden(true)
    }
}

struct StatCard: View {
    let value: String
    let label: String
    let icon: String
    var compactLandscape: Bool = false

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(value)
                .font((compactLandscape ? Font.title3 : .title2).weight(.semibold))
                .monospacedDigit()
                .foregroundColor(Design.Colors.Workspace.ink)
            Text(label)
                .font(.caption)
                .foregroundColor(Design.Colors.Workspace.secondary)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 8)
    }
}
