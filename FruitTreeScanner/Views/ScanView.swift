// ScanView.swift
// 扫描主界面 + 产量估算（扫描停止后自动触发）

import SwiftUI

struct ScanView: View {
    let treeID: String
    @ObservedObject var gps: GPSRecorder
    let season: Season
    let selectedFruitCategory: FruitCategory
    let onScanNextTree: () -> Void

    @State var coordinator = ScanCoordinator()
    @StateObject var hudState = ScanHUDState()
    @StateObject var qualityMonitor = ScanQualityMonitor()
    @StateObject var measurementController = MetalMeasurementController()
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State var isRecording = false
    @State var showGuide = true
    @State var savedFilename = ""
    @State var yieldResult: YieldResult? = nil
    @State var showResult = false
    @State var isEstimating = false
    @State var showCoverageComplete = false
    @State var hasShownCoverageComplete = false
    #if DEBUG
    @State var showDebugView = false
    @State var detectionDebugState = DetectionDebugState(
        currentThreshold: DetectionDebugConfiguration.defaultThreshold
    )
    #endif
    @State var measuredDistance: Float?
    @State var scanNotice: String?
    @State var isViewActive = false
    @State var scanReadiness: ScanReadiness = .checking
    @State var isCheckingScanReadiness = false
    @State var showCancelConfirmation = false
    @State var categoryMismatch: FruitCategoryMismatch?
    @State var lifecycleSnapshot = ScanLifecycleSnapshot(
        state: .idle,
        scanIdentity: UUID(),
        generation: 0,
        interruptionCount: 0,
        lastInterruptionTimestamp: nil
    )
    @State var showLifecycleRecovery = false

    var body: some View {
        ZStack {
            ScanRenderLayer(
                scanReadiness: scanReadiness,
                coordinator: coordinator,
                qualityMonitor: qualityMonitor
            )

            ScanScannerInterfaceLayer(
                treeID: treeID,
                scanReadiness: scanReadiness,
                isRecording: isRecording,
                isEstimating: isEstimating,
                canExportScan: canExportScan,
                shouldShowPostCapturePanel: shouldShowPostCapturePanel,
                showGuide: showGuide,
                showResult: showResult,
                showCoverageComplete: showCoverageComplete,
                yieldResult: yieldResult,
                detectionDebugState: currentDetectionDebugState,
                hudState: hudState,
                qualityMonitor: qualityMonitor,
                measurementController: measurementController,
                measuredDistance: $measuredDistance,
                actions: scannerInterfaceActions
            )

            ScanReadinessOverlay(
                scanReadiness: scanReadiness,
                onOpenSettings: openAppSettings,
                onDismiss: requestCancelScan
            )

            if let scanNotice {
                ScanNoticeToast(message: scanNotice)
            }
        }
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
        .onChange(of: scenePhase) { phase in
            handleScenePhaseChange(phase)
        }
        #if DEBUG
            .sheet(isPresented: $showDebugView) {
                DetectionDebugView(
                    state: detectionDebugState,
                    onExport: { try coordinator.imageDetector.exportFailureSamplesFile() }
                )
            }
        #endif
            .alert(L10n.Scan.cancelConfirmationTitle, isPresented: $showCancelConfirmation) {
                Button(L10n.Scan.continueScanning, role: .cancel) {}
                Button(L10n.Scan.discardScan, role: .destructive) {
                    cancelScan()
                }
            } message: {
                Text(L10n.Scan.cancelConfirmationMessage)
            }
            .alert(item: $categoryMismatch) { mismatch in
                Alert(
                    title: Text(L10n.FruitCategoryVerification.mismatchTitle),
                    message: Text(L10n.FruitCategoryVerification.mismatchMessage(
                        selected: mismatch.selectedCategory,
                        detected: mismatch.dominantDetectedCategory
                    )),
                    primaryButton: .default(Text(L10n.FruitCategoryVerification.continueAction)),
                    secondaryButton: .destructive(Text(L10n.FruitCategoryVerification.stopAndSwitchAction)) {
                        SettingsStore.shared.fruitType = mismatch.dominantDetectedCategory.rawValue
                        cancelScan()
                    }
                )
            }
            .alert(lifecycleAlertTitle, isPresented: $showLifecycleRecovery) {
                Button(L10n.Scan.restartAfterInterruption) {
                    restartAfterInterruption()
                }
                .accessibilityHint(L10n.Scan.interruptionAccessibilityHint)
                Button(L10n.Scan.discardAfterInterruption, role: .destructive) {
                    discardAfterInterruption()
                }
                .accessibilityHint(L10n.Scan.interruptionAccessibilityHint)
            } message: {
                Text(L10n.Scan.interruptionMessage)
            }
    }

}
