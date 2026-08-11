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
    @StateObject private var coverageCompletionPresentation = ScanCoverageCompletionPresentationController()
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
                showCoverageComplete: coverageCompletionPresentation.isPresented,
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
            .alert("取消本次扫描？", isPresented: $showCancelConfirmation) {
                Button("继续扫描", role: .cancel) {}
                Button("放弃", role: .destructive) {
                    cancelScan()
                }
            } message: {
                Text("已采集的点云不会保存。若要保留本次采集，请点击完成。")
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

    func beginCoverageCompletionForNewScan() {
        coverageCompletionPresentation.beginNewScan()
    }

    func presentCoverageCompletionIfNeeded() {
        coverageCompletionPresentation.presentIfNeeded()
    }

    func pauseCoverageCompletion() {
        coverageCompletionPresentation.pauseCurrentScan()
    }

    func invalidateCoverageCompletion() {
        coverageCompletionPresentation.invalidate()
    }
}

@MainActor
final class ScanCoverageCompletionPresentationController: ObservableObject {
    typealias DismissDelay = @Sendable () async -> Void

    @Published private(set) var isPresented = false

    private let dismissDelay: DismissDelay
    private var hasPresentedForCurrentScan = false
    private var dismissTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        dismissDelay: @escaping DismissDelay = {
            do {
                try await Task.sleep(nanoseconds: 3_000_000_000)
            } catch {
                return
            }
        }
    ) {
        self.dismissDelay = dismissDelay
    }

    func beginNewScan() {
        hasPresentedForCurrentScan = false
        cancelPendingDismissalAndHide()
    }

    @discardableResult
    func presentIfNeeded() -> Task<Void, Never>? {
        guard !hasPresentedForCurrentScan else { return nil }
        hasPresentedForCurrentScan = true
        generation &+= 1
        let operationGeneration = generation
        dismissTask?.cancel()

        setPresented(true)

        let dismissDelay = dismissDelay
        let task = Task { [weak self] in
            await dismissDelay()
            guard !Task.isCancelled, let self else { return }
            guard self.generation == operationGeneration else { return }
            self.setPresented(false)
            self.dismissTask = nil
        }
        dismissTask = task
        return task
    }

    func pauseCurrentScan() {
        cancelPendingDismissalAndHide()
    }

    func invalidate() {
        cancelPendingDismissalAndHide()
    }

    private func cancelPendingDismissalAndHide() {
        generation &+= 1
        dismissTask?.cancel()
        dismissTask = nil
        setPresented(false)
    }

    private func setPresented(_ presented: Bool) {
        guard isPresented != presented else { return }
        if presented {
            isPresented = true
        } else {
            withAnimation {
                isPresented = false
            }
        }
    }
}
