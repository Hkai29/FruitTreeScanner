import SwiftUI

enum PostScanNavigationEvent {
    case nextTreeRequested
    case activeScanDismissed
}

struct PostScanNavigationState {
    private enum PendingIntent {
        case nextTree
    }

    private var pendingIntent: PendingIntent?

    mutating func transition(for event: PostScanNavigationEvent) -> DashboardDestination? {
        switch event {
        case .nextTreeRequested:
            pendingIntent = .nextTree
            return nil
        case .activeScanDismissed:
            defer { pendingIntent = nil }
            switch pendingIntent {
            case .nextTree:
                return .startScan
            case nil:
                return nil
            }
        }
    }
}

extension DashboardView {
    var sheetDestination: Binding<DashboardDestination?> {
        Binding(
            get: {
                guard let destination, !destination.isFullScreen else { return nil }
                return destination
            },
            set: { destination = $0 }
        )
    }

    var fullScreenDestination: Binding<DashboardDestination?> {
        Binding(
            get: {
                guard let destination, destination.isFullScreen else { return nil }
                return destination
            },
            set: { destination = $0 }
        )
    }

    func showSettings() {
        destination = .settings
    }

    func showHistory() {
        destination = .scanHistory
    }

    func showStartScan() {
        destination = .startScan
    }

    func showQuickScan() {
        destination = .quickScan
    }

    func refreshScanHistory() {
        historyStore.loadRecords()
    }

    func requestNextTreeScan() {
        guard activeScanRequest != nil else { return }
        _ = postScanNavigationState.transition(for: .nextTreeRequested)
        activeScanRequest = nil
    }

    func handleActiveScanDismissal() {
        refreshScanHistory()
        guard let nextDestination = postScanNavigationState.transition(for: .activeScanDismissed) else {
            return
        }
        destination = nextDestination
    }

    func openPointCloud(_ record: ScanFileRecord) {
        destination = .pointCloud(record.fileURL)
    }

    func applyNavigation(_ nav: AppNavigation) {
        switch nav {
        case .scanner: destination = .startScan
        case .history: destination = .scanHistory
        case .batchExport: destination = .batchExport
        case .map: destination = .map
        }
    }

    func handleQuickAction(_ action: QuickAction) {
        switch action.kind {
        case .startScan: destination = .startScan
        case .quickScan: destination = .quickScan
        case .calibration: destination = .calibration
        case .scanHistory: destination = .scanHistory
        case .pointCloud: destination = .pointCloud(nil)
        case .tagManagement: destination = .tagManagement
        case .yieldReport: destination = .yieldReport
        case .compare: destination = .compare
        case .trends: destination = .trends
        case .map: destination = .map
        case .importFile: destination = .importFile
        case .batchExport: destination = .batchExport
        }
    }

    func presentPendingScanIfNeeded() {
        guard let request = pendingScanRequest else { return }
        pendingScanRequest = nil
        launchScan(request)
    }

    @ViewBuilder
    func fullScreenView(for destination: DashboardDestination) -> some View {
        switch destination {
        case .startScan:
            StartView { request in
                pendingScanRequest = request
                self.destination = nil
            }
        case .quickScan:
            QuickScanView { request in
                pendingScanRequest = request
                self.destination = nil
            }
        default:
            EmptyView()
        }
    }

    @ViewBuilder
    func sheetView(for destination: DashboardDestination) -> some View {
        switch destination {
        case .settings:
            SettingsView()
        case .calibration:
            CalibrationView()
        case .scanHistory:
            HistorySheetView(
                onStartScan: showStartScan,
                onRescanTree: launchRescan,
                onImportFile: { self.destination = .importFile }
            )
        case .pointCloud(let initialFileURL):
            PointCloudSheet(
                initialFileURL: initialFileURL,
                onStartScan: showStartScan,
                onImportFile: { self.destination = .importFile }
            )
        case .tagManagement:
            TagManagementView(onStartScan: showStartScan)
        case .yieldReport:
            YieldReportSheet(onStartScan: showStartScan)
        case .compare:
            HistoricalCompareView(onStartScan: showStartScan)
        case .trends:
            TrendsSheet(onStartScan: showStartScan)
        case .map:
            if #available(iOS 17, *) {
                MapSheet(onStartScan: showStartScan)
            } else {
                Text("地图功能需要 iOS 17")
            }
        case .importFile:
            ImportFileView()
        case .batchExport:
            BatchExportView(
                onStartScan: showStartScan,
                onImportFile: { self.destination = .importFile }
            )
        case .startScan, .quickScan:
            EmptyView()
        }
    }

    func launchRescan(treeID: String) {
        let normalizedTreeID = TreeIdentifierPolicy.normalized(treeID)
        guard TreeIdentifierPolicy.isValid(normalizedTreeID) else {
            destination = .startScan
            return
        }
        destination = nil
        let existing = TagStore.shared.getAssignment(treeId: normalizedTreeID)
        let request = ScanLaunchRequest(
            treeID: normalizedTreeID,
            selectedFruitCategory: FruitCategory.scanCategory(for: SettingsStore.shared.fruitType),
            season: .mature,
            gps: GPSRecorder(),
            plotId: existing?.plotId,
            tagIds: existing?.tagIds ?? []
        )
        launchScan(request)
    }

    private func launchScan(_ request: ScanLaunchRequest) {
        let existing = TagStore.shared.getAssignment(treeId: request.treeID)
        TagStore.shared.createOrUpdateAssignment(
            treeId: request.treeID,
            plotId: request.plotId,
            tagIds: request.tagIds,
            status: existing?.status ?? .notScanned
        )
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.25) {
            activeScanRequest = request
        }
    }
}
