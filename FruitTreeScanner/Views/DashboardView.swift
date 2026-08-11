// DashboardView.swift
// 全新主界面 - 自然有机风格

import SwiftUI

struct DashboardView: View {
    @ObservedObject var router: NavigationRouter
    @State var destination: DashboardDestination?
    @State var pendingScanRequest: ScanLaunchRequest?
    @State var activeScanRequest: ScanLaunchRequest?
    @State var isScanActivationPending = false
    @State var postScanNavigationState = PostScanNavigationState()
    @ObservedObject var historyStore = ScanHistoryStore.shared

    init(router: NavigationRouter) {
        self.router = router
    }

    private var recentScans: [ScanFileRecord] {
        Array(historyStore.scanFiles.prefix(3))
    }

    var body: some View {
        DashboardHomeLayoutView(
            records: historyStore.scanFiles,
            recentScans: recentScans,
            onSettingsTap: showSettings,
            onHistoryTap: showHistory,
            onStartScan: showStartScan,
            onQuickScan: showQuickScan,
            onQuickAction: handleQuickAction,
            onScanTap: openPointCloud
        )
        .sheet(item: sheetDestination, onDismiss: presentPendingNavigationIfPossible) { destination in
            sheetView(for: destination)
        }
        .fullScreenCover(item: fullScreenDestination, onDismiss: handleDestinationDismissal) { destination in
            fullScreenView(for: destination)
        }
        .fullScreenCover(item: $activeScanRequest, onDismiss: handleActiveScanDismissal) { request in
            ScanView(
                treeID: request.treeID,
                gps: request.gps,
                season: request.season,
                selectedFruitCategory: request.selectedFruitCategory,
                onScanNextTree: requestNextTreeScan
            )
        }
        .onChange(of: router.pendingDestination) { nav in
            guard nav != nil else { return }
            presentPendingNavigationIfPossible()
        }
        .onAppear {
            historyStore.loadRecords()
            router.consumePendingUserDefaults()
            presentPendingNavigationIfPossible()
        }
    }
}
