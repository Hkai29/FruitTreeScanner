// TreeFilterView.swift
// 果树档案浏览器：果园 → 地块 → 树 → 标签 → 状态。
//
// 页面只展示库里真实存在的数据：地块、标签、状态与扫描记录都来自
// `TagStore` 与 `ScanHistoryStore`，没有任何演示数据。

import SwiftUI

struct TreeFilterView: View {
    @ObservedObject private var tagStore = TagStore.shared
    @ObservedObject var historyStore: ScanHistoryStore

    @State private var selectedPlotId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedStatus: ScanStatus?

    var body: some View {
        NavigationStack {
            TreeFilterContentView(
                tagStore: tagStore,
                historyStore: historyStore,
                selectedPlotId: $selectedPlotId,
                selectedTagIds: $selectedTagIds,
                selectedStatus: $selectedStatus
            )
            .navigationTitle(TreeFilterText.title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.Colors.Workspace.background, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
        }
        .workspacePage()
    }
}

/// 果树档案页的本地化文案。
enum TreeFilterText {
    static let title = localized("tree_filter.title", "果树列表")
    static let allPlots = L10n.History.allPlots
    static let allStatuses = L10n.History.allStatuses
    static let allTags = localized("tree_filter.all_tags", "全部标签")
    static let unassigned = localized("tree_filter.plot.unassigned", "未分配")
    static let emptyTitle = localized("tree_filter.empty.title", "没有符合筛选的果树")
    static let emptyMessage = localized(
        "tree_filter.empty.message",
        "调整地块、标签或状态筛选后再查看。"
    )
    static let metricsUnavailable = localized(
        "history.row.metrics_unavailable",
        "Metrics Unavailable"
    )
    static let treesLabel = localized("tree_filter.trees_label", "果树")

    static func selectedTagsFormat(_ count: Int) -> String {
        String(
            format: localized("tree_filter.selected_tags_format", "%d 个标签"),
            count
        )
    }

    static func localized(_ key: String, _ value: String) -> String {
        NSLocalizedString(key, value: value, comment: "")
    }
}
