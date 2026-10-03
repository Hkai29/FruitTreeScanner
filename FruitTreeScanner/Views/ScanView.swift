// ScanView.swift
// 扫描主界面 + 产量估算（扫描停止后自动触发）

import SwiftUI

struct ScanView: View {
    let treeID: String
    @ObservedObject var gps: GPSRecorder
    let season: Season
    let selectedFruitCategory: FruitCategory
    let appDependencies: AppDependencies
    let onScanNextTree: () -> Void

    @State var coordinator = ScanCoordinator()
    @StateObject var sessionModel = ScanFeatureModel()
    @StateObject var finalizationWorkflow = ScanFinalizationWorkflow()
    @StateObject var hudState = ScanHUDState()
    @StateObject var qualityMonitor = ScanQualityMonitor()
    @StateObject var measurementController = MetalMeasurementController()
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State var showGuide = true
    @State var yieldResult: YieldResult? = nil
    @State var resultPersistenceState: ScanResultPersistenceState = .idle
    @State var showResult = false
    @StateObject private var coverageCompletionPresentation = ScanCoverageCompletionPresentationController()
    #if DEBUG
    @State var showDebugView = false
    @State var detectionDebugState = DetectionDebugState(
        currentThreshold: DetectionDebugConfiguration.defaultThreshold
    )
    #endif
    @State var measuredDistance: Float?
    @StateObject private var scanNoticePresentation = ScanNoticePresentationController()
    @State var isViewActive = false
    @State var scanReadiness: ScanReadiness = .checking
    @State var pendingLifecycleRecoveryAfterReadiness = false
    @StateObject var readinessRequestController = ScanReadinessRequestController()
    @State var showCancelConfirmation = false
    @StateObject var categoryMismatchPresentation = ScanCategoryMismatchPresentationController()
    @State var showLifecycleRecovery = false

    var lifecycleSnapshot: ScanLifecycleSnapshot { sessionModel.lifecycleSnapshot }
    var isRecording: Bool {
        sessionModel.isRecording && scanReadiness == .ready && !showLifecycleRecovery
    }
    var isEstimating: Bool { finalizationWorkflow.isWorking }

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
                resultPersistenceState: resultPersistenceState,
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

            if let scanNotice = scanNoticePresentation.visibleNotice {
                ScanNoticeToast(message: scanNotice)
            }
            if isEstimating {
                VStack {
                    Spacer()
                    Button("取消本次估算") { showCancelConfirmation = true }
                        .buttonStyle(.bordered)
                        .accessibilityIdentifier("scan.cancelEstimation")
                        .padding(.bottom, 24)
                }
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
            .alert(L10n.ScanCancellation.text(.title), isPresented: $showCancelConfirmation) {
                Button(L10n.ScanCancellation.text(.continueAction), role: .cancel) {}
                Button(L10n.ScanCancellation.text(.discard), role: .destructive) {
                    cancelScan()
                }
            } message: {
                Text(L10n.ScanCancellation.text(.message))
            }
            .alert(item: $categoryMismatchPresentation.presentation) { presentation in
                let mismatch = presentation.mismatch
                return Alert(
                    title: Text(L10n.FruitCategoryVerification.mismatchTitle),
                    message: Text(L10n.FruitCategoryVerification.mismatchMessage(
                        selected: mismatch.selectedCategory,
                        detected: mismatch.dominantDetectedCategory
                    )),
                    primaryButton: .default(Text(L10n.FruitCategoryVerification.continueAction)) {
                        categoryMismatchPresentation.continueScan(presentationID: presentation.id)
                    },
                    secondaryButton: .destructive(Text(L10n.FruitCategoryVerification.stopAndSwitchAction)) {
                        categoryMismatchPresentation.stopAndSwitch(presentationID: presentation.id)
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

    func showTemporaryNotice(_ message: String) {
        scanNoticePresentation.present(message)
    }

    func invalidateTemporaryNotice() {
        scanNoticePresentation.invalidate()
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
final class ScanCategoryMismatchPresentationController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let mismatch: FruitCategoryMismatch
        let scanIdentity: UUID
    }

    @Published var presentation: Presentation?
    private var activeChoice: Presentation?
    private var settings: SettingsStore?
    private var currentScanIdentity: (() -> UUID?)?
    private var onStop: (() -> Void)?
    private var bindingIdentity = UUID()
    private var isHandlingChoice = false

    func bind(settings: SettingsStore, currentScanIdentity: @escaping () -> UUID?, onStop: @escaping () -> Void) {
        bindingIdentity = UUID()
        activeChoice = nil
        self.settings = settings
        self.currentScanIdentity = currentScanIdentity
        self.onStop = onStop
        presentation = nil
    }

    func present(_ mismatch: FruitCategoryMismatch, scanIdentity: UUID) {
        guard !isHandlingChoice, settings != nil, onStop != nil,
              currentScanIdentity?() == scanIdentity else { return }
        let choice = Presentation(mismatch: mismatch, scanIdentity: scanIdentity)
        activeChoice = choice
        presentation = choice
    }

    func continueScan(presentationID: UUID) {
        guard !isHandlingChoice, let current = activeChoice, current.id == presentationID,
              current.scanIdentity == currentScanIdentity?() else { return }
        isHandlingChoice = true
        defer { isHandlingChoice = false }
        activeChoice = nil
        presentation = nil
    }

    func stopAndSwitch(presentationID: UUID) {
        guard !isHandlingChoice, let current = activeChoice, current.id == presentationID,
              current.scanIdentity == currentScanIdentity?(),
              let settings, let onStop else { return }
        let binding = bindingIdentity
        isHandlingChoice = true
        defer { isHandlingChoice = false }
        activeChoice = nil
        presentation = nil
        // Publishing the dismissal or preference can synchronously replace the scan or page binding.
        guard binding == bindingIdentity, current.scanIdentity == currentScanIdentity?() else { return }
        settings.fruitType = current.mismatch.dominantDetectedCategory.rawValue
        guard binding == bindingIdentity, current.scanIdentity == currentScanIdentity?() else { return }
        onStop()
    }

    func invalidate() {
        bindingIdentity = UUID()
        activeChoice = nil
        settings = nil
        currentScanIdentity = nil
        onStop = nil
        presentation = nil
    }
}

@MainActor
final class ScanNoticePresentationController: ObservableObject {
    typealias DismissDelay = @Sendable () async -> Void

    @Published private(set) var visibleNotice: String?

    private let dismissDelay: DismissDelay
    private var dismissTask: Task<Void, Never>?
    private var generation: UInt64 = 0

    init(
        dismissDelay: @escaping DismissDelay = {
            do {
                try await Task.sleep(nanoseconds: 2_200_000_000)
            } catch {
                return
            }
        }
    ) {
        self.dismissDelay = dismissDelay
    }

    @discardableResult
    func present(_ message: String) -> Task<Void, Never> {
        generation &+= 1
        let operationGeneration = generation
        dismissTask?.cancel()

        setVisibleNotice(message)

        let dismissDelay = dismissDelay
        let task = Task { [weak self] in
            await dismissDelay()
            guard !Task.isCancelled, let self else { return }
            guard self.generation == operationGeneration else { return }
            self.setVisibleNotice(nil)
            self.dismissTask = nil
        }
        dismissTask = task
        return task
    }

    func invalidate() {
        generation &+= 1
        dismissTask?.cancel()
        dismissTask = nil
        setVisibleNotice(nil)
    }

    private func setVisibleNotice(_ notice: String?) {
        guard visibleNotice != notice else { return }
        withAnimation(.easeInOut(duration: 0.2)) {
            visibleNotice = notice
        }
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
