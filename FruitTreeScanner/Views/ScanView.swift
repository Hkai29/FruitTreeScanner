// ScanView.swift
// 扫描主界面 + 产量估算（扫描停止后自动触发）

import SwiftUI

struct ScanView: View {
    let treeID: String
    @ObservedObject var gps: GPSRecorder
    let season: Season
    let selectedFruitCategory: FruitCategory
    let classification: ScanClassificationSnapshot
    let appDependencies: AppDependencies
    let onScanNextTree: () -> Void

    @State var coordinator: ScanCoordinator
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
    @StateObject var lifecycleRecoveryPresentation = ScanLifecycleRecoveryPresentationController()

    @MainActor
    init(treeID: String, gps: GPSRecorder, season: Season, selectedFruitCategory: FruitCategory,
         appDependencies: AppDependencies, onScanNextTree: @escaping () -> Void,
         classification: ScanClassificationSnapshot = .empty,
         coordinator: ScanCoordinator? = nil, showGuide: Bool = true, yieldResult: YieldResult? = nil,
         showResult: Bool = false, readinessRequestController: ScanReadinessRequestController? = nil,
         categoryMismatchPresentation: ScanCategoryMismatchPresentationController? = nil,
         finalizationWorkflow: ScanFinalizationWorkflow? = nil,
         lifecycleRecoveryPresentation: ScanLifecycleRecoveryPresentationController? = nil) {
        self.treeID = treeID
        self.gps = gps
        self.season = season
        self.selectedFruitCategory = selectedFruitCategory
        self.classification = classification
        self.appDependencies = appDependencies
        self.onScanNextTree = onScanNextTree
        _coordinator = State(initialValue: coordinator ?? ScanCoordinator(settings: appDependencies.settings))
        _showGuide = State(initialValue: showGuide)
        _yieldResult = State(initialValue: yieldResult)
        _showResult = State(initialValue: showResult)
        _readinessRequestController = StateObject(wrappedValue: readinessRequestController ?? ScanReadinessRequestController())
        _categoryMismatchPresentation = StateObject(wrappedValue: categoryMismatchPresentation ?? ScanCategoryMismatchPresentationController())
        _finalizationWorkflow = StateObject(wrappedValue: finalizationWorkflow ?? ScanFinalizationWorkflow())
        _lifecycleRecoveryPresentation = StateObject(wrappedValue: lifecycleRecoveryPresentation ?? ScanLifecycleRecoveryPresentationController())
    }

    var lifecycleSnapshot: ScanLifecycleSnapshot { sessionModel.lifecycleSnapshot }
    var isRecording: Bool {
        sessionModel.isRecording && scanReadiness == .ready && !showLifecycleRecovery
    }
    var isEstimating: Bool { finalizationWorkflow.isWorking }
    var showLifecycleRecovery: Bool { lifecycleRecoveryPresentation.presentation != nil }

    var body: some View {
        let recoveryPresentationID = lifecycleRecoveryPresentation.presentation?.id
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
                actions: scannerInterfaceActions,
                tagStore: appDependencies.tagStore,
                notice: scanNoticePresentation.visibleNotice
            )

            ScanReadinessOverlay(
                scanReadiness: scanReadiness,
                onOpenSettings: openAppSettings,
                onDismiss: requestCancelScan,
                notice: scanNoticePresentation.visibleNotice
            )
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
        .accessibilityIdentifier("scan.session.\(treeID)")
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
            .alert(lifecycleAlertTitle, isPresented: Binding(
                get: { lifecycleRecoveryPresentation.presentation != nil },
                set: { if !$0, let recoveryPresentationID {
                    lifecycleRecoveryPresentation.dismissFromSystem(presentationID: recoveryPresentationID)
                } }
            ), presenting: lifecycleRecoveryPresentation.presentation) { presentation in
                Button(L10n.Scan.restartAfterInterruption) {
                    lifecycleRecoveryPresentation.restart(presentationID: presentation.id)
                }
                .accessibilityHint(L10n.Scan.interruptionAccessibilityHint)
                Button(L10n.Scan.discardAfterInterruption, role: .destructive) {
                    lifecycleRecoveryPresentation.discard(presentationID: presentation.id)
                }
                .accessibilityHint(L10n.Scan.interruptionAccessibilityHint)
            } message: { _ in
                Text(lifecycleAlertMessage)
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
final class ScanLifecycleRecoveryPresentationController: ObservableObject {
    struct Presentation: Identifiable {
        let id = UUID()
        let snapshot: ScanLifecycleSnapshot
        var scanIdentity: UUID { snapshot.scanIdentity }
    }

    @Published var presentation: Presentation?
    private var activeChoice: Presentation?
    private var acceptsRecovery: ((UUID) -> Bool)?
    private var onRestart: ((UUID) -> Void)?
    private var onDiscard: ((UUID) -> Void)?
    private var bindingIdentity = UUID()
    private var isHandlingChoice = false

    var scanIdentity: UUID? { activeChoice?.scanIdentity }

    func bind(acceptsRecovery: @escaping (UUID) -> Bool,
              onRestart: @escaping (UUID) -> Void, onDiscard: @escaping (UUID) -> Void) {
        bindingIdentity = UUID()
        activeChoice = nil
        self.acceptsRecovery = acceptsRecovery
        self.onRestart = onRestart
        self.onDiscard = onDiscard
        presentation = nil
    }

    func present(_ snapshot: ScanLifecycleSnapshot) {
        guard !isHandlingChoice, acceptsRecovery?(snapshot.scanIdentity) == true else { return }
        if presentation?.snapshot == snapshot { return }
        let choice = Presentation(snapshot: snapshot)
        activeChoice = choice
        presentation = choice
    }

    func restart(presentationID: UUID) {
        handleChoice(presentationID: presentationID, action: onRestart)
    }

    func discard(presentationID: UUID) {
        handleChoice(presentationID: presentationID, action: onDiscard)
    }

    private func handleChoice(presentationID: UUID, action: ((UUID) -> Void)?) {
        guard !isHandlingChoice, let choice = activeChoice, choice.id == presentationID,
              acceptsRecovery?(choice.scanIdentity) == true, let action else { return }
        let binding = bindingIdentity
        isHandlingChoice = true
        activeChoice = nil
        presentation = nil
        // Dismissal may synchronously replace the page binding or scan owner.
        let accepted = binding == bindingIdentity && acceptsRecovery?(choice.scanIdentity) == true
        isHandlingChoice = false
        guard accepted else { return }
        // A failed restart can now present a new choice; the old one stays consumed.
        action(choice.scanIdentity)
    }

    func dismiss() {
        activeChoice = nil
        presentation = nil
    }

    func dismissFromSystem(presentationID: UUID) {
        // SwiftUI can write the alert binding during a view update. Publish on
        // the next main-queue turn and never hide a replacement presentation.
        DispatchQueue.main.async { [weak self] in
            guard let self, self.presentation?.id == presentationID else { return }
            self.dismiss()
        }
    }

    func invalidate() {
        bindingIdentity = UUID()
        activeChoice = nil
        acceptsRecovery = nil
        onRestart = nil
        onDiscard = nil
        presentation = nil
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
