// TreeFilterContentView.swift
// 果树档案浏览：筛选条 + 筛选结果。
//
// 筛选规则完全交给 `TagStore.filteredAssignments`，这里只负责呈现。

import SwiftUI

struct TreeFilterContentView: View {
    @ObservedObject var tagStore: TagStore
    @ObservedObject var historyStore: ScanHistoryStore

    @Binding var selectedPlotId: UUID?
    @Binding var selectedTagIds: Set<UUID>
    @Binding var selectedStatus: ScanStatus?

    private var filteredAssignments: [TreeAssignment] {
        tagStore.filteredAssignments(
            plotId: selectedPlotId,
            tagIds: Array(selectedTagIds),
            status: selectedStatus
        )
    }

    var body: some View {
        VStack(spacing: 0) {
            TreeFilterBar(
                tagStore: tagStore,
                selectedPlotId: $selectedPlotId,
                selectedTagIds: $selectedTagIds,
                selectedStatus: $selectedStatus
            )
            .padding(.horizontal, 20)
            .padding(.top, 10)
            .padding(.bottom, 12)
            .frame(maxWidth: 1080)

            DividerLine()

            TreeFilterListView(
                assignments: filteredAssignments,
                tagStore: tagStore,
                latestScan: latestScan(for:)
            )
        }
    }

    private func latestScan(for treeId: String) -> ScanFileRecord? {
        historyStore.scanFiles.first { $0.treeID == treeId }
    }
}
