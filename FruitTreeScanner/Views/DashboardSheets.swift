// DashboardSheets.swift
// 首页 sheet 容器与轻量报表页

import SwiftUI

struct HistorySheetView: View {
    @Environment(\.dismiss) var dismiss
    var onStartScan: (() -> Void)? = nil
    var onRescanTree: ((String) -> Void)? = nil
    var onImportFile: (() -> Void)? = nil
    @ObservedObject var historyStore = ScanHistoryStore.shared
    @ObservedObject var tagStore = TagStore.shared

    var body: some View {
        NavigationStack {
            ZStack {
                Design.Colors.Workspace.surface.ignoresSafeArea()
                ScanHistoryView(
                    customTitle: L10n.History.navigationTitle,
                    onStartScan: onStartScan,
                    onRescanTree: onRescanTree,
                    onImportFile: onImportFile,
                    historyStore: historyStore,
                    tagStore: tagStore
                )
            }
            .navigationTitle(L10n.History.navigationTitle)
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Workspace.surface, for: .navigationBar)
            .toolbarColorScheme(.light, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.done) { dismiss() }
                        .foregroundColor(Design.Colors.Workspace.accent)
                }
            }
        }
        .workspacePage(background: Design.Colors.Workspace.background)
    }
}
