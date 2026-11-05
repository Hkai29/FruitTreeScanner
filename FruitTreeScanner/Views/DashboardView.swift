// DashboardView.swift
// 果园工作台：果园空间 / 档案 / 分析

import SwiftUI

struct DashboardView: View {
    @ObservedObject var router: NavigationRouter
    @EnvironmentObject private var appDependencies: AppDependencies
    @Environment(\.scenePhase) private var scenePhase
    @State var destination: DashboardDestination?
    @State var scanLaunchPresentationState = ScanLaunchPresentationState<ScanLaunchRequest>()
    @State var activeScanRequest: ScanLaunchRequest?
    @State var postScanNavigationState = PostScanNavigationState()
    @State var sheetScanHandoffState = DashboardSheetScanHandoffState()
    @ObservedObject var historyStore: ScanHistoryStore

    @MainActor
    init(router: NavigationRouter, historyStore: ScanHistoryStore? = nil) {
        self.router = router
        self.historyStore = historyStore ?? .shared
    }

    var scanImportOperations: ScanImportOperations {
        appDependencies.importOperations()
    }

    var batchExportOperations: BatchExportOperations {
        appDependencies.batchExportOperations()
    }

    var calibrationScanSource: CalibrationScanSource {
        appDependencies.calibrationScanSource()
    }

    var settingsStore: SettingsStore {
        appDependencies.settings
    }

    var parametersStore: FruitParametersStore {
        appDependencies.parametersStore
    }

    var tagStore: TagStore {
        appDependencies.tagStore
    }

    func rescanRequest(treeID: String) -> ScanLaunchRequest? {
        appDependencies.rescanRequest(treeID: treeID)
    }

    func activateScan(_ request: ScanLaunchRequest) {
        activeScanRequest = appDependencies.activateScanRequest(request)
    }

    var body: some View {
        DashboardHomeLayoutView(
            aggregation: historyStore.dashboardAggregation,
            onSettingsTap: showSettings,
            onHistoryTap: showHistory,
            onStartScan: showStartScan,
            onQuickScan: showQuickScan,
            onQuickAction: handleQuickAction,
            onScanTap: openPointCloud
        )
        .sheet(item: sheetDestination, onDismiss: handleSheetDismissal) { destination in
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
                appDependencies: appDependencies,
                onScanNextTree: requestNextTreeScan,
                classification: request.classification
            )
        }
        .onChange(of: router.pendingDestination) { nav in
            guard nav != nil else { return }
            presentPendingNavigationIfPossible()
        }
        .onAppear {
            historyStore.dashboardAggregation.refreshTimeContext()
            historyStore.loadRecords()
            router.consumePendingUserDefaults()
            presentPendingNavigationIfPossible()
        }
        .onChange(of: scenePhase) { phase in
            if phase == .active { historyStore.dashboardAggregation.refreshTimeContext() }
        }
    }
}
