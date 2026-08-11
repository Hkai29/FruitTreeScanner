// DashboardView.swift
// 全新主界面 - 自然有机风格

import SwiftUI

struct DashboardView: View {
    @ObservedObject var router: NavigationRouter
    @State var destination: DashboardDestination?
    @State var scanLaunchPresentationState = ScanLaunchPresentationState<ScanLaunchRequest>()
    @State var activeScanRequest: ScanLaunchRequest?
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
        .sheet(item: sheetDestination, onDismiss: presentPendingScanIfNeeded) { destination in
            sheetView(for: destination)
        }
        .fullScreenCover(item: fullScreenDestination, onDismiss: presentPendingScanIfNeeded) { destination in
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
        .onReceive(router.$pendingDestination) { nav in
            guard let nav else { return }
            applyNavigation(nav)
            router.clear()
        }
        .onAppear {
            historyStore.loadRecords()
            router.consumePendingUserDefaults()
            if let nav = router.pendingDestination {
                applyNavigation(nav)
                router.clear()
            }
        }
    }
}
