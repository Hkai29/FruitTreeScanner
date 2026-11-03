// DashboardHomeLayoutView.swift
// 果园工作台：果园空间 / 档案 / 分析 三个视图共用同一套骨架。

import SwiftUI

struct DashboardHomeLayoutView: View {
    @ObservedObject var aggregation: DashboardAggregationStore
    let onSettingsTap: () -> Void
    let onHistoryTap: () -> Void
    let onStartScan: () -> Void
    let onQuickScan: () -> Void
    let onQuickAction: (QuickAction) -> Void
    let onScanTap: (ScanFileRecord) -> Void
    @State private var mode: AppMode = .scan
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.locale) private var locale
    /// 读数随系统辅助字号缩放：用户把字放大时，这个数也要跟着长。
    @ScaledMetric(relativeTo: .largeTitle) private var todayYieldDatumSize: CGFloat = 38
    @Environment(\.verticalSizeClass) private var verticalSizeClass

    private var contentWidth: CGFloat { 1080 }

    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                VStack(alignment: .leading, spacing: 22) {
                    TopNavigationBar(
                        onSettingsTap: onSettingsTap,
                        onHistoryTap: onHistoryTap,
                        historyCount: aggregation.snapshot.records.count
                    )

                    switch mode {
                    case .scan:
                        orchardSection(width: proxy.size.width, height: proxy.size.height)
                    case .history:
                        archiveSection
                    case .analytics:
                        analysisSection
                    }
                }
                .frame(maxWidth: contentWidth)
                .padding(.horizontal, 20)
                .padding(.top, 10)
                .padding(.bottom, 24)
                .frame(maxWidth: .infinity)
            }
            .id(mode)
            .safeAreaInset(edge: .bottom, spacing: 0) {
                bottomDock
            }
            .workspacePage()
        }
    }

    // MARK: - 果园空间

    private func orchardSection(width: CGFloat, height: CGFloat) -> some View {
        VStack(alignment: .leading, spacing: 14) {
            // 今日概览始终可见：没有记录时显示真实的 0，而不是整段消失。
            dailyStrip

            InstrumentSectionLabel(
                title: workspaceTitle,
                actionTitle: hasLocatedTrees ? WorkspaceText.openMap : nil,
                onAction: hasLocatedTrees ? { openMap() } : nil
            )

            DashboardOrchardWorkspace(
                records: aggregation.snapshot.records,
                wideLayout: width >= 780 && !dynamicTypeSize.isAccessibilitySize,
                mapHeight: max(180, min(240, height * 0.26)),
                onOpenMap: openMap,
                onScanTap: onScanTap
            )

            toolSection(mode: .scan)

            // 辅助大字号 + 横屏时底部动作带会收起，主操作必须在这里仍然可达。
            if usesScrollableScanActions {
                actionBand
                    .padding(.top, 4)
            }
        }
    }

    // MARK: - 档案

    private var archiveSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            InstrumentSectionLabel(
                title: workspaceTitle,
                actionTitle: L10n.Dashboard.viewAll,
                onAction: onHistoryTap
            )

            if aggregation.snapshot.recentRecords.isEmpty {
                InstrumentEmptyState(
                    systemImage: "square.stack.3d.up",
                    title: L10n.Dashboard.noScans,
                    message: L10n.Dashboard.emptyDescription
                )
            } else {
                InstrumentRowGroup {
                    ForEach(aggregation.snapshot.recentRecords) { record in
                        Button { onScanTap(record) } label: {
                            InstrumentScanRow(record: record)
                        }
                        .buttonStyle(.plain)
                        .accessibilityIdentifier("dashboard.recentScan.\(record.treeID)")
                        if record.id != aggregation.snapshot.recentRecords.last?.id {
                            DividerLine(inset: 0)
                        }
                    }
                }
            }

            toolSection(mode: .history)
        }
    }

    // MARK: - 分析

    private var analysisSection: some View {
        VStack(alignment: .leading, spacing: 14) {
            InstrumentSectionLabel(title: workspaceTitle)

            StatsOverviewSection(
                snapshot: aggregation.snapshot,
                emptyActionTitle: aggregation.snapshot.records.isEmpty ? L10n.Dashboard.startScan : WorkspaceText.openArchives,
                onEmptyAction: aggregation.snapshot.records.isEmpty ? onStartScan : { mode = .history }
            )

            toolSection(mode: .analytics)
        }
    }

    // MARK: - 今日读数

    /// 今日概览。**只统计当天**，因此面板标题与每个指标都写明"今日"，
    /// 避免被误读成全档案累计值。
    ///
    /// 辅助大字号下改成纵排：横排会把"35.0 kg"和"2 次"挤在一起，标签也会碰撞。
    private var dailyStrip: some View {
        InstrumentPanel(label: L10n.Dashboard.todayOverview) {
            if dynamicTypeSize.isAccessibilitySize {
                VStack(alignment: .leading, spacing: 12) {
                    todayYieldDatum
                    InstrumentInlineDatum(
                        label: L10n.Dashboard.todayScanCount,
                        value: "\(aggregation.snapshot.daily.scanCount)"
                    )
                    InstrumentInlineDatum(
                        label: L10n.Dashboard.todayTreeCount,
                        value: "\(aggregation.snapshot.daily.treeCount)"
                    )
                }
            } else {
                HStack(alignment: .top, spacing: 18) {
                    todayYieldDatum

                    Spacer(minLength: 8)

                    VStack(alignment: .trailing, spacing: 8) {
                        InstrumentInlineDatum(
                            label: L10n.Dashboard.todayScanCount,
                            value: "\(aggregation.snapshot.daily.scanCount)"
                        )
                        InstrumentInlineDatum(
                            label: L10n.Dashboard.todayTreeCount,
                            value: "\(aggregation.snapshot.daily.treeCount)"
                        )
                    }
                    .padding(.top, 2)
                }
            }
        }
    }

    private var todayYieldDatum: some View {
        VStack(alignment: .leading, spacing: 3) {
            Text(L10n.Dashboard.todayYield)
                .instrumentLabel()
            HStack(alignment: .lastTextBaseline, spacing: 4) {
                Text(YieldNumberFormatting.text(aggregation.snapshot.daily.yieldKg, locale: locale))
                    .font(.system(size: todayYieldDatumSize, weight: .semibold))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Workspace.ink)
                Text("kg")
                    .font(.footnote.weight(.medium))
                    .foregroundColor(Design.Colors.Workspace.secondary)
            }
            .lineLimit(1)
            .minimumScaleFactor(0.6)
        }
    }

    // MARK: - 工具

    private func toolSection(mode: AppMode) -> some View {
        VStack(alignment: .leading, spacing: 10) {
            InstrumentSectionLabel(title: L10n.Dashboard.tools)
            QuickActionsGrid(mode: mode, onAction: onQuickAction)
        }
    }

    // MARK: - 底部

    private var bottomDock: some View {
        VStack(spacing: 0) {
            if mode == .scan && !usesScrollableScanActions {
                actionBand
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
            }
            WorkspaceTabBar(selection: mode) { mode = $0 }
        }
        .background(Design.Colors.Workspace.surface)
        .overlay(alignment: .top) {
            if mode == .scan && !usesScrollableScanActions {
                Design.Colors.Workspace.line.frame(height: 0.5)
            }
        }
    }

    private var actionBand: some View {
        actionLayout {
            Button(action: onStartScan) {
                Label(L10n.Dashboard.startScan, systemImage: "viewfinder")
            }
            .buttonStyle(WorkspacePrimaryButtonStyle())
            .accessibilityIdentifier("dashboard.action.startScan")

            Button(action: onQuickScan) {
                Label(L10n.Dashboard.quickCapture, systemImage: "bolt")
            }
            .buttonStyle(WorkspaceSecondaryButtonStyle())
            .accessibilityIdentifier("dashboard.action.quickScan")
            .frame(maxWidth: dynamicTypeSize.isAccessibilitySize ? .infinity : 150)
        }
        .frame(maxWidth: contentWidth)
    }

    /// 辅助大字号时两个动作改为竖排，避免按钮文字被挤成两行。
    private var actionLayout: AnyLayout {
        dynamicTypeSize.isAccessibilitySize
            ? AnyLayout(VStackLayout(spacing: 8))
            : AnyLayout(HStackLayout(spacing: 10))
    }

    private var usesScrollableScanActions: Bool {
        dynamicTypeSize.isAccessibilitySize && verticalSizeClass == .compact
    }

    // MARK: - 辅助

    private var hasLocatedTrees: Bool {
        !OrchardMapData(records: aggregation.snapshot.records).trees.isEmpty
    }

    private var workspaceTitle: String {
        switch mode {
        case .scan: return WorkspaceText.orchard
        case .history: return WorkspaceText.archive
        case .analytics: return WorkspaceText.analysis
        }
    }


    private func openMap() {
        onQuickAction(
            QuickAction(
                kind: .map,
                title: L10n.Dashboard.mapTitle,
                icon: "map",
                color: Design.Colors.Workspace.accent,
                description: L10n.Dashboard.mapDescription
            )
        )
    }
}
