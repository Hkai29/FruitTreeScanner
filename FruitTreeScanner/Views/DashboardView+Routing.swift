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

enum ScanLaunchPresentationEvent<Request> {
    case requestQueued(Request)
    case sourceDismissed
}

struct ScanLaunchPresentationState<Request> {
    private var pendingRequest: Request?

    var hasPendingRequest: Bool {
        pendingRequest != nil
    }

    mutating func transition(for event: ScanLaunchPresentationEvent<Request>) -> Request? {
        switch event {
        case .requestQueued(let request):
            pendingRequest = request
            return nil
        case .sourceDismissed:
            defer { pendingRequest = nil }
            return pendingRequest
        }
    }
}

enum DashboardSheetScanHandoffEvent {
    case startScanRequested
    case sheetDismissed
}

struct DashboardSheetScanHandoffState {
    private var hasPendingStartScan = false

    mutating func transition(for event: DashboardSheetScanHandoffEvent) -> DashboardDestination? {
        switch event {
        case .startScanRequested:
            hasPendingStartScan = true
            return nil
        case .sheetDismissed:
            guard hasPendingStartScan else { return nil }
            hasPendingStartScan = false
            return .startScan
        }
    }
}

enum DashboardExternalNavigationDisposition: Equatable {
    case present
    case deferUntilIdle
    case alreadySatisfied
}

struct DashboardExternalNavigationPolicy {
    static func disposition(
        for navigation: AppNavigation,
        destination currentDestination: DashboardDestination?,
        hasPendingScanRequest: Bool,
        hasActiveScanRequest: Bool
    ) -> DashboardExternalNavigationDisposition {
        if currentDestination == destination(for: navigation) {
            return .alreadySatisfied
        }
        if navigation == .scanner, hasPendingScanRequest || hasActiveScanRequest {
            return .alreadySatisfied
        }
        if currentDestination != nil || hasPendingScanRequest || hasActiveScanRequest {
            return .deferUntilIdle
        }
        return .present
    }

    static func destination(for navigation: AppNavigation) -> DashboardDestination {
        switch navigation {
        case .scanner: return .startScan
        case .history: return .scanHistory
        case .batchExport: return .batchExport
        case .map: return .map
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

    func showStartScanAfterDismissingSheet() {
        _ = sheetScanHandoffState.transition(for: .startScanRequested)
        destination = nil
    }

    func handleSheetDismissal() {
        if let nextDestination = sheetScanHandoffState.transition(for: .sheetDismissed) {
            destination = nextDestination
            presentPendingNavigationIfPossible()
            return
        }
        presentPendingScanIfNeeded()
        presentPendingNavigationIfPossible()
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
        if let nextDestination = postScanNavigationState.transition(for: .activeScanDismissed) {
            destination = nextDestination
            presentPendingNavigationIfPossible()
            return
        }
        presentPendingNavigationIfPossible()
    }

    func openPointCloud(_ record: ScanFileRecord) {
        destination = .pointCloud(record.fileURL)
    }

    func applyNavigation(_ nav: AppNavigation) {
        destination = DashboardExternalNavigationPolicy.destination(for: nav)
    }

    func presentPendingNavigationIfPossible() {
        guard let navigation = router.pendingDestination else { return }
        let disposition = DashboardExternalNavigationPolicy.disposition(
            for: navigation,
            destination: destination,
            hasPendingScanRequest: scanLaunchPresentationState.hasPendingRequest,
            hasActiveScanRequest: activeScanRequest != nil
        )
        guard disposition != .deferUntilIdle else { return }
        guard let consumedNavigation = router.takePendingDestination(if: true) else { return }
        if disposition == .present {
            applyNavigation(consumedNavigation)
        }
    }

    func handleDestinationDismissal() {
        presentPendingScanIfNeeded()
        presentPendingNavigationIfPossible()
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
        guard let request = scanLaunchPresentationState.transition(for: .sourceDismissed) else {
            return
        }
        activateScan(request)
    }

    func queueScanAfterSourceDismissal(_ request: ScanLaunchRequest) {
        _ = scanLaunchPresentationState.transition(for: .requestQueued(request))
        destination = nil
    }

    @ViewBuilder
    func fullScreenView(for destination: DashboardDestination) -> some View {
        switch destination {
        case .startScan:
            StartView { request in
                queueScanAfterSourceDismissal(request)
            }
        case .quickScan:
            QuickScanView { request in
                queueScanAfterSourceDismissal(request)
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
                onStartScan: showStartScanAfterDismissingSheet,
                onRescanTree: launchRescan,
                onImportFile: { self.destination = .importFile }
            )
        case .pointCloud(let initialFileURL):
            PointCloudSheet(
                initialFileURL: initialFileURL,
                onStartScan: showStartScanAfterDismissingSheet,
                onImportFile: { self.destination = .importFile }
            )
        case .tagManagement:
            TagManagementView(onStartScan: showStartScanAfterDismissingSheet)
        case .yieldReport:
            YieldReportSheet(onStartScan: showStartScanAfterDismissingSheet)
        case .compare:
            HistoricalCompareView(onStartScan: showStartScanAfterDismissingSheet)
        case .trends:
            TrendsSheet(onStartScan: showStartScanAfterDismissingSheet)
        case .map:
            if #available(iOS 17, *) {
                MapSheet(onStartScan: showStartScanAfterDismissingSheet)
            } else {
                Text(OrchardMapPresentation().requiresIOS17)
            }
        case .importFile:
            ImportFileView()
        case .batchExport:
            BatchExportView(
                onStartScan: showStartScanAfterDismissingSheet,
                onImportFile: { self.destination = .importFile }
            )
        case .startScan, .quickScan:
            EmptyView()
        }
    }

    func launchRescan(treeID: String) {
        let normalizedTreeID = TreeIdentifierPolicy.normalized(treeID)
        guard TreeIdentifierPolicy.isValid(normalizedTreeID) else {
            showStartScanAfterDismissingSheet()
            return
        }
        let existing = TagStore.shared.getAssignment(treeId: normalizedTreeID)
        let request = ScanLaunchRequest(
            treeID: normalizedTreeID,
            selectedFruitCategory: FruitCategory.scanCategory(for: SettingsStore.shared.fruitType),
            season: .mature,
            gps: GPSRecorder(),
            plotId: existing?.plotId,
            tagIds: existing?.tagIds ?? []
        )
        queueScanAfterSourceDismissal(request)
    }

    private func activateScan(_ request: ScanLaunchRequest) {
        let existing = TagStore.shared.getAssignment(treeId: request.treeID)
        TagStore.shared.createOrUpdateAssignment(
            treeId: request.treeID,
            plotId: request.plotId,
            tagIds: request.tagIds,
            status: existing?.status ?? .notScanned
        )
        activeScanRequest = request
    }
}
