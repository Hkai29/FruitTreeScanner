import ARKit
import MetalKit
import os
import UIKit

enum ScanSessionFailureClassifier {
    static func reason(for error: Error) -> ScanFailureReason {
        let error = error as NSError
        guard error.domain == ARErrorDomain,
              error.code == ARError.Code.cameraUnauthorized.rawValue else {
            return .sessionFailed(error.localizedDescription)
        }
        return .cameraUnavailable(error.localizedDescription)
    }
}

struct ScanCameraTrackingStatus: Equatable, Sendable {
    let acceptsReliableCapture: Bool
    let guidanceHint: ScanGuidanceHint

    static func make(from trackingState: ARCamera.TrackingState) -> ScanCameraTrackingStatus {
        let acceptsReliableCapture: Bool
        switch trackingState {
        case .normal:
            acceptsReliableCapture = true
        case .notAvailable, .limited:
            acceptsReliableCapture = false
        @unknown default:
            acceptsReliableCapture = false
        }
        return ScanCameraTrackingStatus(
            acceptsReliableCapture: acceptsReliableCapture,
            guidanceHint: ScanGuidanceHelper.trackingHint(
                for: trackingState,
                lightIntensity: nil
            ) ?? .none
        )
    }
}

// MARK: - ScanCoordinator
enum ScanDepthRuntimeStatus: String {
    case unsupportedAR = "NoAR"
    case unsupportedSceneDepth = "NoDepth"
    case waitingForDepth = "Wait"
    case activeDepth = "LiDAR"
}

struct ScanSessionRuntime {
    let isWorldTrackingSupported: () -> Bool
    let run: (ARSession, ARWorldTrackingConfiguration, ARSession.RunOptions) -> Void
    var preferredVideoFormat: (ScanCameraRequest) -> ARConfiguration.VideoFormat? = {
        ScanSessionConfiguration.preferredVideoFormat(request: $0)
    }

    static let live = ScanSessionRuntime(
        isWorldTrackingSupported: { ARWorldTrackingConfiguration.isSupported },
        run: { session, configuration, options in
            session.run(configuration, options: options)
        }
    )
}

typealias ScanCalibrationRecordsLoader = () throws -> [CalibrationRecord]

/// 协调 AR 会话、点云采集、图像检测与产量估算的扫描级生命周期。
class ScanCoordinator: NSObject {
    let settings: ScanSettingsProviding
    private let sessionRuntime: ScanSessionRuntime
    let calibrationRecordsLoader: ScanCalibrationRecordsLoader
    let scanSession: ScanSession
    private let captureAdmissionGate: CaptureAdmissionGate
    var scanLifecycle: ScanLifecycleController { scanSession }

    var renderer: Renderer?
    var session: ARSession?
    weak var mtkView: MTKView?

    init(
        settings: ScanSettingsProviding = SettingsStore.shared,
        sessionRuntime: ScanSessionRuntime = .live,
        calibrationRecordsLoader: @escaping ScanCalibrationRecordsLoader = {
            try CalibrationRecordPersistence.load()
        }
    ) {
        self.settings = settings
        self.sessionRuntime = sessionRuntime
        self.calibrationRecordsLoader = calibrationRecordsLoader
        let scanSession = ScanSession()
        self.scanSession = scanSession
        self.captureAdmissionGate = CaptureAdmissionGate(
            bindingID: scanSession.sessionSnapshot().bindingID
        )
        super.init()
    }

    var pointCount: Int = 0
    var scannedRegionCount: Int = 0
    var coveragePercent: Int = 0
    var coverageVoxelCount: Int = 0

    // 扫描完成度相关
    var scanCompletion: ScanCompletion = ScanCompletion()

    var detectedFruits: [Observation] = []
    var archivedFusionEvidenceDetections: [Observation] = []
    @MainActor var evidenceArchiveRevision: UInt64 = 0
    var activeScanPlan: ScanPlan? { scanSession.activePlan }
    var activeFruitConfiguration: ScanFruitConfiguration? {
        scanSession.activeFruitConfiguration
    }
    var hasPublishedCategoryMismatch = false

    var onMeasurementReady: ((Renderer) -> Void)?
    var onQualitySampleUpdate: ((ScanQualitySample) -> Void)?
    var onCoveragePercentChange: ((Int) -> Void)?
    var onFruitCategoryMismatch: ((FruitCategoryMismatch) -> Void)?
    var onCalibrationWarning: ((ScanCalibrationWarning) -> Void)?
    var onLifecycleStateChange: ((ScanLifecycleSnapshot) -> Void)?
    #if DEBUG
    var onDetectionDebugStateChange: ((DetectionDebugState) -> Void)?
    #endif
    var hudState: ScanHUDState?

    #if DEBUG
        func debugSnapshot() -> [DetectedFruit] {
            detectedFruits.map(DetectedFruit.init(observation:))
        }

        func detectionDebugSnapshot() -> DetectionDebugState {
            imageDetector.detectionDebugSnapshot()
        }

        func detectionFailureSamplesSnapshot() -> [DetectionFailureSample] {
            imageDetector.detectionFailureSamplesSnapshot()
        }
    #endif

    private var displayLink: CADisplayLink?
    var lastHUDUpdateTime: TimeInterval = 0
    var lastCompletionUpdateTime: TimeInterval = 0
    var lastQualitySampleTime: TimeInterval = 0
    var hasPublishedCameraResolution = false
    var requestedSceneDepth = false
    private var configuredCameraRequest: ScanCameraRequest?
    private var depthRuntimeStatus: ScanDepthRuntimeStatus?
    var isTornDown = false
    let activeHUDUpdateInterval: TimeInterval = 0.1
    let idleHUDUpdateInterval: TimeInterval = 0.25
    let activeCompletionUpdateInterval: TimeInterval = 0.25
    let idleCompletionUpdateInterval: TimeInterval = 0.5
    let qualitySampleInterval: TimeInterval = 0.25
    let completionEvaluator = ScanCompletionEvaluator()
    let detectionProcessingLock = NSLock()
    var isDetectionProcessing = false
    private let cameraTrackingLock = NSLock()
    // Unbound coordinators are treated as an already-running session so unit
    // workflows remain deterministic. bind/reset always moves production to
    // notAvailable until ARKit reports normal tracking.
    private var cameraTrackingStatus = ScanCameraTrackingStatus.make(from: .normal)
    private var trackingSuspendedScanIdentity: UUID?

    // MARK: - 相机速度追踪
    var lastCameraPosition: SIMD3<Float>?
    var lastCameraSpeedTime: TimeInterval = 0
    var smoothedCameraSpeed: Float = 0

    // MARK: - 多模态融合组件
    lazy var imageDetector: ImageDetector = {
        var config = FruitScanConfig(
            imageDetectionInterval: 10,
            minConfidence: 0.85,
            sizeTolerance: 0.2,
            minimumStableDetectionsForYield: 2,
            stableDetectionTimeWindow: 4.0
        )
        let detector = ImageDetector(config: config)
        return detector
    }()
    var detectionTask: Task<Void, Never>?
    let yieldEstimationController = ScanYieldEstimationController()

    func bind(session: ARSession, renderer: Renderer, mtkView: MTKView) {
        Log.scan.info("Binding scan session")
        resetRuntimeState()
        self.session = session
        self.renderer = renderer
        self.mtkView = mtkView

        publishPendingCameraResolution(
            session: session,
            renderer: renderer,
            mtkView: mtkView
        )

        // ARKit may report an interruption or failure as soon as a run starts.
        // Install the observer first so initial sessions cannot lose the callback
        // that closes reliable-evidence capture.
        session.delegate = self
        let depthStatus = configureAndRunSession(session, cameraRequest: activeScanPlan?.cameraRequest ?? currentCameraRequest())
        publishDepthRuntimeStatus(depthStatus)

        publishImageDetectorStatus()

        // 启动定期处理队列的定时器
        startDetectionTimer()

        scheduleDeferredSettingsLoad(
            session: session,
            renderer: renderer,
            mtkView: mtkView
        )
        startHUDDisplayLink()
        UIApplication.shared.isIdleTimerDisabled = true

        DispatchQueue.main.async { [weak self, weak session, weak renderer, weak mtkView] in
            guard let self, let session, let renderer, let mtkView,
                  self.acceptsBindingCallback(
                      from: session,
                      renderer: renderer,
                      mtkView: mtkView
                  ) else { return }
            self.onMeasurementReady?(renderer)
        }
    }

    private func configureAndRunSession(
        _ session: ARSession,
        cameraRequest: ScanCameraRequest,
        options: ARSession.RunOptions = []
    ) -> ScanDepthRuntimeStatus {
        requestedSceneDepth = false

        guard sessionRuntime.isWorldTrackingSupported() else {
            return .unsupportedAR
        }

        let config = ARWorldTrackingConfiguration()
        if let depthSemantics = ScanSessionConfiguration.preferredDepthSemantics() {
            config.frameSemantics = depthSemantics
            requestedSceneDepth = true
        }
        if let videoFormat = sessionRuntime.preferredVideoFormat(cameraRequest) {
            config.videoFormat = videoFormat
        }
        configuredCameraRequest = cameraRequest
        hasPublishedCameraResolution = false
        // 实时产量估计依赖 sceneDepth 点云，避免开启高负载的 ARKit mesh 重建。
        sessionRuntime.run(session, config, options)

        return requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth
    }

    @MainActor
    func restartBoundSessionWithResetTracking(cameraRequest: ScanCameraRequest? = nil) -> Bool {
        guard !isTornDown, let session else { return false }
        // Reassert ownership before starting a replacement run as well.
        session.delegate = self
        resetCameraTrackingForSessionRun()
        let depthStatus = configureAndRunSession(
            session,
            cameraRequest: cameraRequest ?? activeScanPlan?.cameraRequest ?? currentCameraRequest(),
            options: [.resetTracking, .removeExistingAnchors]
        )
        publishDepthRuntimeStatus(depthStatus)
        return depthStatus != .unsupportedAR
    }

    func currentCameraRequest() -> ScanCameraRequest {
        ScanCameraRequest(resolution: settings.cameraResolution, frameRate: settings.cameraFrameRate)
    }

    @MainActor
    func applyCameraRequestForNewScan(_ request: ScanCameraRequest) -> Bool {
        // Unbound algorithm/test workflows have no physical session to configure.
        guard let session else { return true }
        guard configuredCameraRequest != request else { return true }
        session.delegate = self
        resetCameraTrackingForSessionRun()
        let status = configureAndRunSession(session, cameraRequest: request)
        publishDepthRuntimeStatus(status)
        return status != .unsupportedAR
    }

    @MainActor
    func teardown() {
        Log.scan.info("Tearing down scan session")
        isTornDown = true
        invalidateReliableEvidenceGate()
        stopRuntimeServices()
        clearRuntimeReferences()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @MainActor
    func teardownForReadinessBlock() {
        Log.scan.info("Tearing down scan runtime for readiness block")
        let state = scanSession.snapshot().state
        switch state {
        case .recording, .userPaused, .finishing:
            _ = scanSession.fail(.cameraUnavailable("Scan readiness became unavailable"))
        default:
            break
        }
        isTornDown = true
        invalidateReliableEvidenceGate()
        stopRuntimeServices()
        clearBindingReferences()
        clearScanReferences()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    @MainActor
    func teardownBinding(for candidateView: MTKView) {
        guard mtkView === candidateView else { return }
        Log.scan.info("Tearing down scan view binding")
        isTornDown = true
        invalidateReliableEvidenceGate()
        stopRuntimeServices()
        clearBindingReferences()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func resetRuntimeState() {
        isTornDown = false
        configuredCameraRequest = nil
        hasPublishedCameraResolution = false
        let bindingID = scanSession.beginBinding()
        captureAdmissionGate.bind(to: bindingID)
        resetCameraTrackingForSessionRun()
    }

    private func publishPendingCameraResolution(
        session: ARSession,
        renderer: Renderer,
        mtkView: MTKView
    ) {
        // 延后发布，避免 UIViewRepresentable 创建期触发 SwiftUI 状态警告。
        DispatchQueue.main.async { [weak self, weak session, weak renderer, weak mtkView] in
            guard let self, let session, let renderer, let mtkView,
                  self.acceptsBindingCallback(
                      from: session,
                      renderer: renderer,
                      mtkView: mtkView
                  ) else { return }
            settings.currentCameraResolutionDisplay = L10n.Scan.detecting
        }
    }

    private func scheduleDeferredSettingsLoad(
        session: ARSession,
        renderer: Renderer,
        mtkView: MTKView
    ) {
        // 等 session 初始化完成后再下发 Metal/检测参数。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            [weak self, weak session, weak renderer, weak mtkView] in
            guard let self, let session, let renderer, let mtkView,
                  self.acceptsBindingCallback(
                      from: session,
                      renderer: renderer,
                      mtkView: mtkView
                  ) else { return }
            self.loadSettings()
        }
    }

    private func startHUDDisplayLink() {
        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(updatePointCount))
        displayLink?.add(to: .main, forMode: .common)
    }

    @MainActor
    private func stopRuntimeServices() {
        detectionTask?.cancel()
        detectionTask = nil
        yieldEstimationController.cancel()
        displayLink?.invalidate()
        displayLink = nil
        detectionTimer?.invalidate()
        detectionTimer = nil
        imageDetector.clearQueue()
        session?.pause()
        session?.delegate = nil
        mtkView?.delegate = nil
    }

    private func clearBindingReferences() {
        mtkView = nil
        renderer = nil
        session = nil
        depthRuntimeStatus = nil
        requestedSceneDepth = false
        configuredCameraRequest = nil
        resetCameraTrackingForSessionRun()
    }

    private func clearRuntimeReferences() {
        // 同时释放回调和大对象引用，避免已退出页面继续接收扫描结果。
        clearBindingReferences()
        clearPresentationReferences()
        clearScanReferences()
    }

    private func clearPresentationReferences() {
        hudState = nil
        onMeasurementReady = nil
        onQualitySampleUpdate = nil
        onCoveragePercentChange = nil
        onFruitCategoryMismatch = nil
        onCalibrationWarning = nil
        onLifecycleStateChange = nil
        #if DEBUG
        onDetectionDebugStateChange = nil
        #endif
    }

    private func clearScanReferences() {
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()
        scanSession.clearConfiguration()
        hasPublishedCategoryMismatch = false
    }

    func lifecycleSnapshot() -> ScanLifecycleSnapshot {
        scanSession.snapshot()
    }

    // A coordinator can outlive the UIView that created its ARSession. Reject
    // callbacks still draining from that replaced session.
    func acceptsDelegateCallback(from candidateSession: ARSession) -> Bool {
        guard !isTornDown, let activeSession = session else { return false }
        return activeSession === candidateSession
    }

    func acceptsBindingCallback(
        from candidateSession: ARSession,
        renderer candidateRenderer: Renderer,
        mtkView candidateView: MTKView
    ) -> Bool {
        acceptsDelegateCallback(from: candidateSession)
            && renderer === candidateRenderer
            && mtkView === candidateView
    }

    func resetCameraTrackingForSessionRun() {
        cameraTrackingLock.lock()
        cameraTrackingStatus = ScanCameraTrackingStatus.make(from: .notAvailable)
        trackingSuspendedScanIdentity = nil
        cameraTrackingLock.unlock()
    }

    func cameraTrackingStatusSnapshot() -> ScanCameraTrackingStatus {
        cameraTrackingLock.lock()
        defer { cameraTrackingLock.unlock() }
        return cameraTrackingStatus
    }

    func isCaptureSuspendedForCameraTracking(scanIdentity: UUID? = nil) -> Bool {
        cameraTrackingLock.lock()
        defer { cameraTrackingLock.unlock() }
        guard let suspendedIdentity = trackingSuspendedScanIdentity else { return false }
        return scanIdentity.map { $0 == suspendedIdentity } ?? true
    }

    func clearCameraTrackingSuspension() {
        cameraTrackingLock.lock()
        trackingSuspendedScanIdentity = nil
        cameraTrackingLock.unlock()
    }

    @MainActor
    @discardableResult
    func activateCaptureWhenCameraTrackingAllows(
        lifecycle: ScanLifecycleSnapshot,
        resetPointCloud: Bool
    ) -> Bool {
        guard lifecycle.state == .recording else { return false }

        cameraTrackingLock.lock()
        let status = cameraTrackingStatus
        guard status.acceptsReliableCapture else {
            trackingSuspendedScanIdentity = lifecycle.scanIdentity
            suspendReliableEvidenceCaptureImmediately()
            if resetPointCloud {
                renderer?.resetPointCloudCapture()
            }
            cameraTrackingLock.unlock()
            hudState?.update(guidanceHint: status.guidanceHint)
            return false
        }

        trackingSuspendedScanIdentity = nil
        _ = setReliableEvidenceAcceptance(true)
        if resetPointCloud {
            renderer?.isRecording = true
        } else {
            renderer?.resumeRecordingPreservingPointCloud()
        }
        cameraTrackingLock.unlock()
        hudState?.update(guidanceHint: ScanGuidanceHint.none)
        return true
    }

    func handleCameraTrackingState(
        _ trackingState: ARCamera.TrackingState,
        originatingFrom originatingSession: ARSession? = nil
    ) {
        guard !isTornDown else { return }
        let nextStatus = ScanCameraTrackingStatus.make(from: trackingState)
        let lifecycle = lifecycleSnapshot()
        var suspendedIdentityToResume: UUID?

        cameraTrackingLock.lock()
        guard nextStatus != cameraTrackingStatus else {
            cameraTrackingLock.unlock()
            return
        }
        cameraTrackingStatus = nextStatus

        if lifecycle.state == .recording {
            // A limited tracking state is recoverable and keeps the same scan
            // identity. ARSession interruption/failure callbacks remain the
            // only paths that hard-invalidate the logical scan.
            if nextStatus.acceptsReliableCapture {
                suspendedIdentityToResume = trackingSuspendedScanIdentity
            } else if trackingSuspendedScanIdentity != lifecycle.scanIdentity {
                trackingSuspendedScanIdentity = lifecycle.scanIdentity
                // Close the evidence gate on ARSession's callback queue before
                // any UI work can observe the tracking transition.
                suspendReliableEvidenceCaptureImmediately()
            }
        }
        cameraTrackingLock.unlock()

        Task { @MainActor [weak self] in
            guard let self,
                  originatingSession.map(self.acceptsDelegateCallback(from:)) ?? true,
                  self.cameraTrackingStatusSnapshot() == nextStatus else { return }
            self.hudState?.update(guidanceHint: nextStatus.guidanceHint)
            if let suspendedIdentityToResume {
                self.resumeCaptureAfterCameraTrackingRecovery(
                    scanIdentity: suspendedIdentityToResume
                )
            }
        }
    }

    @MainActor
    private func resumeCaptureAfterCameraTrackingRecovery(scanIdentity: UUID) {
        let lifecycle = lifecycleSnapshot()

        cameraTrackingLock.lock()
        guard cameraTrackingStatus.acceptsReliableCapture,
              trackingSuspendedScanIdentity == scanIdentity,
              lifecycle.state == .recording,
              lifecycle.scanIdentity == scanIdentity else {
            if trackingSuspendedScanIdentity == scanIdentity,
               (lifecycle.state != .recording || lifecycle.scanIdentity != scanIdentity) {
                trackingSuspendedScanIdentity = nil
            }
            cameraTrackingLock.unlock()
            return
        }

        trackingSuspendedScanIdentity = nil
        _ = setReliableEvidenceAcceptance(true)
        renderer?.resumeRecordingPreservingPointCloud()
        cameraTrackingLock.unlock()
        hudState?.update(guidanceHint: ScanGuidanceHint.none)
    }

    func evidenceGenerationSnapshot() -> Int {
        captureAdmissionGate.snapshot().generation
    }

    func acceptsReliableEvidence(generation: Int? = nil) -> Bool {
        captureAdmissionGate.accepts(generation: generation)
    }

    @discardableResult
    func setReliableEvidenceAcceptance(_ accepted: Bool) -> Int {
        // 每次开关证据门都推进代次，使已在途的任务自然失效。
        captureAdmissionGate.setOpen(accepted)
    }

    func capturedEvidenceToken() -> ScanCapturedEvidenceToken? {
        let sessionSnapshot = scanSession.sessionSnapshot()
        guard sessionSnapshot.lifecycle.state == .recording else { return nil }
        return captureAdmissionGate.makeToken(
            scanIdentity: sessionSnapshot.lifecycle.scanIdentity,
            bindingID: sessionSnapshot.bindingID
        )
    }

    @MainActor
    func acceptsCapturedEvidence(_ token: ScanCapturedEvidenceToken) -> Bool {
        guard !isTornDown else { return false }
        let sessionSnapshot = scanSession.sessionSnapshot()
        let lifecycle = sessionSnapshot.lifecycle
        guard lifecycle.scanIdentity == token.scanIdentity,
              sessionSnapshot.bindingID == token.bindingID else { return false }

        let admission = captureAdmissionGate.snapshot()
        let invalidationEpochMatches = token.invalidationEpoch == admission.invalidationEpoch
            && token.bindingID == admission.bindingID
        guard invalidationEpochMatches else { return false }
        let acceptsTrackingSuspendedEvidence =
            isCaptureSuspendedForCameraTracking(
                scanIdentity: lifecycle.scanIdentity
            )

        switch lifecycle.state {
        case .recording:
            // A frame captured while tracking was normal remains valid if its
            // inference finishes during a transient tracking pause. No new
            // token can be issued while the capture gate is closed.
            return admission.isOpen || acceptsTrackingSuspendedEvidence
        case .userPaused, .finishing:
            return true
        default:
            return false
        }
    }

    func invalidateReliableEvidenceGate() {
        captureAdmissionGate.invalidate()
    }

    func publishLifecycleSnapshot(_ snapshot: ScanLifecycleSnapshot) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTornDown else { return }
            self.onLifecycleStateChange?(snapshot)
        }
    }

    /// This is safe to call from ARSession's callback queue. It closes the
    /// evidence gate before the MainActor updates presentation state.
    func suspendReliableEvidenceCaptureImmediately() {
        _ = setReliableEvidenceAcceptance(false)
        renderer?.isRecording = false
    }

    /// Hard invalidation additionally rejects already captured work. Use this
    /// for session interruption, failure, teardown, and scan replacement.
    func invalidateReliableEvidenceImmediately() {
        invalidateReliableEvidenceGate()
        renderer?.isRecording = false
        imageDetector.clearQueue()
        detectionTask?.cancel()
        Task { @MainActor [weak self] in
            self?.yieldEstimationController.cancel()
        }
    }

    // MARK: - 图像检测定时器
    var detectionTimer: Timer?

    func publishDepthRuntimeStatus(_ status: ScanDepthRuntimeStatus) {
        guard depthRuntimeStatus != status else { return }
        depthRuntimeStatus = status
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTornDown else { return }
            self.hudState?.update(depthRuntimeStatus: status.rawValue)
        }
    }

}
