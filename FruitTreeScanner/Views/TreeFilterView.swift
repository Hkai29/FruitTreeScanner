// TreeFilterView.swift
// 果树列表筛选视图

import SwiftUI

struct TreeFilterView: View {
    @ObservedObject private var tagStore = TagStore.shared
    @ObservedObject var historyStore: ScanHistoryStore

    @State private var selectedPlotId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedStatus: ScanStatus?

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()

                VStack(spacing: 0) {
                    TreeFilterContentView(
                        tagStore: tagStore,
                        historyStore: historyStore,
                        selectedPlotId: $selectedPlotId,
                        selectedTagIds: $selectedTagIds,
                        selectedStatus: $selectedStatus
                    )
                }
            }
            .navigationTitle("果树列表")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(Design.Colors.Dark.bgDeep, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
        }
    }
}
