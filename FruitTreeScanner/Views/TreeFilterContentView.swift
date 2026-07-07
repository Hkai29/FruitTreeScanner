// TreeFilterContentView.swift
// Coordinates tree filtering controls and filtered results.

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
        TreeFilterBar(
            tagStore: tagStore,
            selectedPlotId: $selectedPlotId,
            selectedTagIds: $selectedTagIds,
            selectedStatus: $selectedStatus
        )
        .padding(.horizontal, Design.Space.md)
        .padding(.vertical, Design.Space.sm)

        TreeFilterListView(
            assignments: filteredAssignments,
            tagStore: tagStore,
            latestScan: latestScan(for:)
        )
    }

    private func latestScan(for treeId: String) -> ScanFileRecord? {
        historyStore.scanFiles.first { $0.treeID == treeId }
    }
}
