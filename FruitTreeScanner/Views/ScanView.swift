// ScanView.swift
// 扫描主界面 + 产量估算（扫描停止后自动触发）

import SwiftUI

struct ScanView: View {
    let treeID: String
    @ObservedObject var gps: GPSRecorder
    let season: Season

    @State private var coordinator = ScanCoordinator()
    @StateObject private var hudState = ScanHUDState()
    @StateObject private var qualityMonitor = ScanQualityMonitor()
    @StateObject private var measurementController = MetalMeasurementController()
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State private var isRecording = false
    @State private var showGuide = true
    @State private var savedFilename = ""
    @State private var yieldResult: YieldResult? = nil
    @State private var showResult = false
    @State private var isEstimating = false
    @State private var showCoverageComplete = false
    @State private var hasShownCoverageComplete = false
    #if DEBUG
    @State private var showDebugView = false
    @State private var detectionDebugState = DetectionDebugState(
        currentThreshold: DetectionDebugConfiguration.defaultThreshold
    )
    #endif
    @State private var measuredDistance: Float?
    @State private var scanNotice: String?
    @State private var isViewActive = false
    @State private var scanReadiness: ScanReadiness = .checking
    @State private var isCheckingScanReadiness = false
    @State private var showCancelConfirmation = false

    var body: some View {
        ZStack {
            renderLayer
            scannerInterfaceLayer
            readinessLayer
            noticeLayer
        }
        .onAppear {
            isViewActive = true
            refreshScanReadiness()
            coordinator.hudState = hudState
            coordinator.onCoveragePercentChange = handleCoveragePercentChange
            #if DEBUG
            coordinator.onDetectionDebugStateChange = { state in
                detectionDebugState = state
            }
            #endif
            coordinator.onMeasurementReady = { renderer in
                measurementController.renderer = renderer
            }
        }
        .onDisappear {
            isViewActive = false
            isEstimating = false
            measurementController.deactivate()
            measurementController.renderer = nil
            coordinator.teardown()
        }
        .onChange(of: scenePhase) { phase in
            refreshScanReadinessWhenActive(phase)
        }
        #if DEBUG
            .sheet(isPresented: $showDebugView) {
                DetectionDebugView(
                    state: detectionDebugState,
                    onExport: { try coordinator.imageDetector.exportFailureSamplesFile() }
                )
            }
        #endif
            .alert("取消本次扫描？", isPresented: $showCancelConfirmation) {
                Button("继续扫描", role: .cancel) {}
                Button("放弃", role: .destructive) {
                    cancelScan()
                }
            } message: {
                Text("已采集的点云不会保存。若要保留本次采集，请点击完成。")
            }
    }

    @ViewBuilder
    private var scannerInterfaceLayer: some View {
        if !scanReadiness.blocksScanning {
            #if DEBUG
            detectionDebugOverlayLayer
            #endif
            statusLayer
            guidanceLayer
            measurementLayer
            controlLayer
            guideLayer
            resultLayer
            estimatingLayer
            coverageCompleteLayer
        }
    }

    @ViewBuilder
    private var renderLayer: some View {
        if scanReadiness == .ready {
            MetalView(coordinator: coordinator)
                .ignoresSafeArea()
                .onAppear {
                    coordinator.onQualitySampleUpdate = { sample in
                        DispatchQueue.main.async {
                            qualityMonitor.update(with: sample)
                        }
                    }
                }
        } else {
            Color.black.ignoresSafeArea()
        }
    }

    #if DEBUG
    private var detectionDebugOverlayLayer: some View {
        DetectionDebugOverlayView(state: detectionDebugState)
            .ignoresSafeArea()
            .allowsHitTesting(false)
    }
    #endif

    @ViewBuilder
    private var guideLayer: some View {
        if showGuide {
            ScanFieldGuideOverlay(
                onClose: { showGuide = false },
                onStartScan: startRecording
            )
        }
    }

    private var statusLayer: some View {
        VStack {
            ScanStatusBar(
                treeID: treeID,
                isRecording: isRecording,
                hudState: hudState,
                qualityMonitor: qualityMonitor
            )
            Spacer()
        }
    }

    private var guidanceLayer: some View {
        ScanGuidanceOverlay(hudState: hudState, isRecording: isRecording)
    }

    @ViewBuilder
    private var measurementLayer: some View {
        if measurementController.isActive {
            MetalMeasurementOverlay(
                controller: measurementController,
                measuredDistance: $measuredDistance,
                onClose: {
                    measurementController.deactivate()
                }
            )
        }
    }

    private var controlLayer: some View {
        VStack {
            Spacer()
            if isRecording {
                ScanCoverageHintBar(hudState: hudState)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            if shouldShowPostCapturePanel {
                ScanPostCapturePanel(
                    pointCount: hudState.pointCount,
                    coveragePercent: hudState.coveragePercent,
                    completion: hudState.scanCompletion,
                    canFinish: canExportScan,
                    onResume: resumeRecording,
                    onFinish: finishScan
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }
            #if DEBUG
                ScanBottomControlBar(
                    isRecording: isRecording,
                    isEstimating: isEstimating,
                    canFinish: canExportScan,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: { showGuide.toggle() },
                    onToggleRecording: toggleRecording,
                    onToggleMeasurement: toggleMeasurement,
                    onCancel: requestCancelScan,
                    onFinish: finishScan,
                    onDebug: showDebugSnapshot
                )
            #else
                ScanBottomControlBar(
                    isRecording: isRecording,
                    isEstimating: isEstimating,
                    canFinish: canExportScan,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: { showGuide.toggle() },
                    onToggleRecording: toggleRecording,
                    onToggleMeasurement: toggleMeasurement,
                    onCancel: requestCancelScan,
                    onFinish: finishScan
                )
            #endif
        }
    }

    @ViewBuilder
    private var resultLayer: some View {
        if showResult, let result = yieldResult {
            ResultView(treeID: treeID, result: result) {
                withAnimation(.easeInOut(duration: 0.25)) { showResult = false }
            } onDismissToHome: {
                showResult = false
                dismiss()
            }
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var estimatingLayer: some View {
        if isEstimating {
            Color.black.opacity(0.5)
                .transition(.opacity)
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                    .tint(Design.Colors.harvest)
                Text(L10n.Scan.estimating)
                    .font(.system(size: 15, weight: .medium))
                    .foregroundColor(.white)
            }
            .transition(.scale(scale: 0.9).combined(with: .opacity))
        }
    }

    @ViewBuilder
    private var coverageCompleteLayer: some View {
        if showCoverageComplete {
            ScanCoverageCompleteToast()
            .animation(.easeInOut(duration: 0.3), value: showCoverageComplete)
        }
    }

    @ViewBuilder
    private var readinessLayer: some View {
        ScanReadinessOverlay(
            scanReadiness: scanReadiness,
            onOpenSettings: openAppSettings,
            onDismiss: requestCancelScan
        )
    }

    @ViewBuilder
    private var noticeLayer: some View {
        if let scanNotice {
            ScanNoticeToast(message: scanNotice)
        }
    }

    private var shouldShowPostCapturePanel: Bool {
        !isRecording && !isEstimating && !showResult && hudState.pointCount > 0
    }

    private func handleCoveragePercentChange(_ newValue: Int) {
        if newValue >= 85 && !hasShownCoverageComplete && isRecording {
            showCoverageComplete = true
            hasShownCoverageComplete = true
            DispatchQueue.main.asyncAfter(deadline: .now() + 3) {
                guard isViewActive else { return }
                withAnimation { showCoverageComplete = false }
            }
        }
    }

    private func toggleMeasurement() {
        if hudState.pointCount == 0 && !measurementController.isActive {
            showTemporaryNotice(L10n.Scan.noPointCloud)
            return
        }
        if measurementController.isActive {
            measurementController.deactivate()
        } else {
            measurementController.activate()
        }
    }

    #if DEBUG
        private func showDebugSnapshot() {
            detectionDebugState = coordinator.detectionDebugSnapshot()
            showDebugView = true
        }
    #endif

    // MARK: - 录制切换
    private func toggleRecording() {
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    private func startRecording() {
        guard scanReadiness == .ready else {
            showTemporaryNotice(scanReadiness.title)
            return
        }
        createDirectory(folder: "scans")
        coordinator.startRecording()
        isRecording = true
        showGuide = false
    }

    private func resumeRecording() {
        guard scanReadiness == .ready else {
            showTemporaryNotice(scanReadiness.title)
            return
        }
        guard coordinator.pointCount > 0 || hudState.pointCount > 0 else {
            startRecording()
            return
        }
        createDirectory(folder: "scans")
        coordinator.resumeRecordingPreservingCapture()
        isRecording = true
        showGuide = false
    }

    private func stopRecording() {
        coordinator.stopRecording()
        isRecording = false
    }

    private func requestCancelScan() {
        if isRecording || coordinator.pointCount > 0 || hudState.pointCount > 0 {
            showCancelConfirmation = true
        } else {
            cancelScan()
        }
    }

    private func cancelScan() {
        isEstimating = false
        if isRecording {
            stopRecording()
        }
        measurementController.deactivate()
        coordinator.teardown()
        dismiss()
    }

    private func finishScan() {
        guard !isEstimating else { return }
        if isRecording {
            stopRecording()
        }
        exportAndEstimate()
    }

    // MARK: - 导出 + 估算
    private func exportAndEstimate() {
        guard !isEstimating else { return }
        guard canExportScan else {
            showTemporaryNotice(exportBlockedReason)
            return
        }

        withAnimation(.easeInOut(duration: 0.2)) { isEstimating = true }
        coordinator.exportPLY(treeID: treeID, lat: gps.latitude, lon: gps.longitude) { filename in
            guard self.isViewActive else { return }
            guard let filename else {
                self.isEstimating = false
                self.showTemporaryNotice(L10n.Scan.exportFailed)
                return
            }
            self.savedFilename = filename

            self.coordinator.runMultiModalYieldEstimate(season: season) { result, _ in
                Task { @MainActor in
                    guard self.isViewActive else { return }
                    let didPersist = await self.persistScanResult(result: result, filename: filename)
                    if !didPersist {
                        ScanHistoryStore.shared.notifyRecordsUpdated()
                        self.showTemporaryNotice("结果文件保存失败，请保留点云后重试导出")
                    }

                    self.isEstimating = false
                    self.yieldResult = result
                    withAnimation(.easeInOut(duration: 0.3)) { self.showResult = true }
                }
            }
        }
    }

    private var exportBlockedReason: String {
        ScanExportReadiness.blockedReason(
            scanIsReady: scanReadiness == .ready,
            scanBlockedTitle: scanReadiness.title,
            depthRuntimeStatus: hudState.depthRuntimeStatus,
            pointCount: hudState.pointCount,
            exportablePointStatus: hudState.exportablePointStatus
        )
    }

    private var canExportScan: Bool {
        ScanExportReadiness.canExport(
            scanIsReady: scanReadiness == .ready,
            depthRuntimeStatus: hudState.depthRuntimeStatus,
            exportablePointStatus: hudState.exportablePointStatus,
            pointCount: hudState.pointCount
        )
    }

    private func showTemporaryNotice(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            scanNotice = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard isViewActive else { return }
            guard scanNotice == message else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                scanNotice = nil
            }
        }
    }

    private func refreshScanReadiness() {
        guard !isCheckingScanReadiness else { return }
        isCheckingScanReadiness = true
        scanReadiness = .checking
        Task {
            let next = await ScanReadiness.determine()
            await MainActor.run {
                isCheckingScanReadiness = false
                guard isViewActive else { return }
                scanReadiness = next
                if next != .ready {
                    isRecording = false
                    measurementController.deactivate()
                    measurementController.renderer = nil
                    coordinator.teardown()
                }
            }
        }
    }

    private func refreshScanReadinessWhenActive(_ phase: ScenePhase) {
        guard phase == .active else { return }
        guard scanReadiness.blocksScanning || !isRecording else { return }
        refreshScanReadiness()
    }

    private func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }

    @MainActor
    private func persistScanResult(result: YieldResult, filename: String) async -> Bool {
        let includeCSV = SettingsStore.shared.autoExportCSV
        let scanMetadata = savedScanMetadata(for: filename)
        let request = ScanResultExportService.ExportRequest(
            treeID: treeID,
            fruitType: SettingsStore.shared.fruitType,
            scanDate: scanMetadata.scanDate,
            gpsLat: scanMetadata.gpsLat,
            gpsLon: scanMetadata.gpsLon,
            sourceFilename: filename,
            result: result,
            includeCSV: includeCSV
        )

        do {
            _ = try await Task.detached(priority: .utility) {
                try ScanResultExportService.shared.exportIfNeeded(request)
            }.value
            ScanHistoryStore.shared.notifyRecordsUpdated()
            if let existing = TagStore.shared.getAssignment(treeId: treeID) {
                TagStore.shared.createOrUpdateAssignment(
                    treeId: treeID,
                    plotId: existing.plotId,
                    tagIds: existing.tagIds,
                    status: .scanned
                )
            } else {
                TagStore.shared.createOrUpdateAssignment(
                    treeId: treeID,
                    plotId: nil,
                    tagIds: [],
                    status: .scanned
                )
            }
            return true
        } catch {
            Log.export.error("Failed to persist scan result: \(error.localizedDescription)")
            return false
        }
    }

    private func savedScanMetadata(for filename: String) -> (scanDate: Date, gpsLat: Double, gpsLon: Double) {
        let fileURL = getDocumentsDirectory()
            .appendingPathComponent("scans", isDirectory: true)
            .appendingPathComponent(filename)
        guard let parsed = PLYParserHelper.parsePLYFile(at: fileURL) else {
            return (Date(), gps.latitude, gps.longitude)
        }
        return (parsed.scanDate, parsed.gpsLat, parsed.gpsLon)
    }
}
