// DashboardSheets.swift
// 首页 sheet 容器与轻量报表页

import SwiftUI

struct HistorySheetView: View {
    @Environment(\.dismiss) var dismiss
    var onStartScan: (() -> Void)? = nil
    var onRescanTree: ((String) -> Void)? = nil
    var onImportFile: (() -> Void)? = nil

    var body: some View {
        NavigationView {
            ZStack {
                Design.Colors.Dark.bgDeep.ignoresSafeArea()
                ScanHistoryView(
                    customTitle: L10n.History.navigationTitle,
                    onStartScan: onStartScan,
                    onRescanTree: onRescanTree,
                    onImportFile: onImportFile
                )
            }
            .navigationTitle("")
            .navigationBarTitleDisplayMode(.inline)
            .toolbarBackground(.visible, for: .navigationBar)
            .toolbarBackground(Design.Colors.Dark.bgSurface, for: .navigationBar)
            .toolbarColorScheme(.dark, for: .navigationBar)
            .toolbar {
                ToolbarItem(placement: .navigationBarTrailing) {
                    Button(L10n.Common.done) { dismiss() }
                        .foregroundColor(Design.Colors.harvest)
                }
            }
        }
    }
}
