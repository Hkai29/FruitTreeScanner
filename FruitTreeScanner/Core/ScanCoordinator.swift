import ARKit
import MetalKit
import os
import UIKit

enum ScanInterruptionReason: String, Equatable, Sendable {
    case appInactive, appBackgrounded, arSessionInterrupted, trackingFailure, cameraUnavailable
}

enum ScanFailureReason: Equatable, Sendable {
    case sessionFailed(String)
}

enum ScanLifecycleState: Equatable, Sendable {
    case idle, recording, userPaused, systemInterrupted(ScanInterruptionReason)
    case recovering, finishing, completed, failed(ScanFailureReason), cancelled
}

struct ScanLifecycleSnapshot: Equatable, Sendable {
    let state: ScanLifecycleState
    let scanIdentity: UUID
    let generation: Int
    let interruptionCount: Int
    let lastInterruptionTimestamp: Date?
    var acceptsReliableEvidence: Bool { state == .recording }
}

struct ScanCapturedEvidenceToken: Equatable, Sendable {
    let scanIdentity: UUID
    let invalidationEpoch: UInt64
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

/// Serializes scan-local lifecycle transitions and deliberately never resumes
/// a system-interrupted scan without a new identity.
final class ScanLifecycleController {
    private let lock = NSLock()
    private var state: ScanLifecycleState = .idle
    private var scanIdentity = UUID()
    private var generation = 0
    private var interruptionCount = 0
    private var lastInterruptionTimestamp: Date?

    func snapshot() -> ScanLifecycleSnapshot { withLock { makeSnapshot() } }
    func startNewScan() -> ScanLifecycleSnapshot {
        withLock { generation &+= 1; scanIdentity = UUID(); state = .recording; interruptionCount = 0; lastInterruptionTimestamp = nil; return makeSnapshot() }
    }
    func userPaused() -> ScanLifecycleSnapshot {
        withLock { if state == .recording { generation &+= 1; state = .userPaused }; return makeSnapshot() }
    }
    func resumeUserPaused() -> ScanLifecycleSnapshot {
        withLock { if state == .userPaused { generation &+= 1; state = .recording }; return makeSnapshot() }
    }
    func interrupt(_ reason: ScanInterruptionReason) -> ScanLifecycleSnapshot {
        withLock {
            switch state {
            case .recording, .userPaused, .finishing:
                generation &+= 1; interruptionCount += 1; lastInterruptionTimestamp = Date(); state = .systemInterrupted(reason)
            default: break
            }
            return makeSnapshot()
        }
    }
    func interruptionEnded() -> ScanLifecycleSnapshot {
        withLock { if case .systemInterrupted = state { state = .recovering }; return makeSnapshot() }
    }
    func beginFinishing() -> ScanLifecycleSnapshot {
        withLock { if state == .recording || state == .userPaused { generation &+= 1; state = .finishing }; return makeSnapshot() }
    }
    func complete() -> ScanLifecycleSnapshot {
        withLock { if state == .finishing { state = .completed }; return makeSnapshot() }
    }
    func fail(_ reason: ScanFailureReason) -> ScanLifecycleSnapshot {
        withLock { if state != .completed && state != .cancelled { generation &+= 1; state = .failed(reason) }; return makeSnapshot() }
    }
    func cancel() -> ScanLifecycleSnapshot {
        withLock { if state != .completed { generation &+= 1; state = .cancelled }; return makeSnapshot() }
    }
    private func withLock<T>(_ body: () -> T) -> T { lock.lock(); defer { lock.unlock() }; return body() }
    private func makeSnapshot() -> ScanLifecycleSnapshot {
        ScanLifecycleSnapshot(state: state, scanIdentity: scanIdentity, generation: generation, interruptionCount: interruptionCount, lastInterruptionTimestamp: lastInterruptionTimestamp)
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

    static let live = ScanSessionRuntime(
        isWorldTrackingSupported: { ARWorldTrackingConfiguration.isSupported },
        run: { session, configuration, options in
            session.run(configuration, options: options)
        }
    )
}

struct ScanFruitConfiguration {
    let selectedCategory: FruitCategory
    let parametersSnapshot: [String: FruitVarietyParams]
    let defaultParams: FruitVarietyParams
    let clusterConfig: ClusterConfig
    let fusionConfig: FruitScanConfig
    let colorFilter: ColorFilter
    let calibrationCorrection: YieldCalibrationCorrection
    let calibrationWarning: ScanCalibrationWarning?

    @MainActor
    /// 固化一次扫描使用的类别、阈值与校准快照，避免扫描途中设置变化污染结果。
    static func capture(
        selectedCategory: FruitCategory,
        settings: ScanSettingsProviding,
        calibrationRecordsLoader: ScanCalibrationRecordsLoader = {
            try CalibrationRecordPersistence.load()
        }
    ) -> ScanFruitConfiguration {
        let parametersSnapshot = FruitParametersStore.shared.parameterSnapshot()
        let defaultParams = parametersSnapshot[selectedCategory.rawValue]
            ?? FruitVarietyParams(category: selectedCategory)
        let calibrationRecords: [CalibrationRecord]
        let calibrationWarning: ScanCalibrationWarning?
        do {
            calibrationRecords = try calibrationRecordsLoader()
            calibrationWarning = nil
        } catch {
            calibrationRecords = []
            calibrationWarning = .recordsUnavailable
            Log.scan.error("Calibration records unavailable at scan start: \(error.localizedDescription)")
        }
        return ScanFruitConfiguration(
            selectedCategory: selectedCategory,
            parametersSnapshot: parametersSnapshot,
            defaultParams: defaultParams,
            clusterConfig: settings.clusterConfig(for: defaultParams),
            fusionConfig: settings.fruitScanConfig,
            colorFilter: settings.colorFilter(for: selectedCategory),
            calibrationCorrection: YieldCalibrationCorrector.correction(
                from: calibrationRecords,
                fruitCategory: selectedCategory,
                fruitType: selectedCategory.rawValue
            ),
            calibrationWarning: calibrationWarning
        )
    }
}

enum ScanCalibrationWarning: Equatable, Sendable {
    case recordsUnavailable
}

typealias ScanCalibrationRecordsLoader = () throws -> [CalibrationRecord]

/// 协调 AR 会话、点云采集、图像检测与产量估算的扫描级生命周期。
class ScanCoordinator: NSObject {
    let settings: ScanSettingsProviding
    private let sessionRuntime: ScanSessionRuntime
    let calibrationRecordsLoader: ScanCalibrationRecordsLoader

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
        super.init()
    }

    var pointCount: Int = 0
    var scannedRegionCount: Int = 0
    var coveragePercent: Int = 0
    var coverageVoxelCount: Int = 0

    // 扫描完成度相关
    var scanCompletion: ScanCompletion = ScanCompletion()

    var detectedFruits: [DetectedFruit] = []
    var archivedFusionEvidenceDetections: [DetectedFruit] = []
    var activeFruitConfiguration: ScanFruitConfiguration?
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
            detectedFruits
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
    let scanLifecycle = ScanLifecycleController()
    private let evidenceGateLock = NSLock()
    private var reliableEvidenceGeneration = 0
    private var acceptsReliableEvidence = false
    private var capturedEvidenceInvalidationEpoch: UInt64 = 0
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
            sphericityThreshold: 0.5,
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

        publishPendingCameraResolution()

        // ARKit may report an interruption or failure as soon as a run starts.
        // Install the observer first so initial sessions cannot lose the callback
        // that closes reliable-evidence capture.
        session.delegate = self
        let depthStatus = configureAndRunSession(session)
        publishDepthRuntimeStatus(depthStatus)

        publishImageDetectorStatus()

        // 启动定期处理队列的定时器
        startDetectionTimer()

        scheduleDeferredSettingsLoad()
        startHUDDisplayLink()
        UIApplication.shared.isIdleTimerDisabled = true

        DispatchQueue.main.async {
            self.onMeasurementReady?(renderer)
        }
    }

    private func configureAndRunSession(
        _ session: ARSession,
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
        if let videoFormat = ScanSessionConfiguration.preferredVideoFormat() {
            config.videoFormat = videoFormat
        }
        // 实时产量估计依赖 sceneDepth 点云，避免开启高负载的 ARKit mesh 重建。
        sessionRuntime.run(session, config, options)

        return requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth
    }

    @MainActor
    func restartBoundSessionWithResetTracking() -> Bool {
        guard !isTornDown, let session else { return false }
        // Reassert ownership before starting a replacement run as well.
        session.delegate = self
        resetCameraTrackingForSessionRun()
        let depthStatus = configureAndRunSession(
            session,
            options: [.resetTracking, .removeExistingAnchors]
        )
        publishDepthRuntimeStatus(depthStatus)
        return depthStatus != .unsupportedAR
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

    private func resetRuntimeState() {
        isTornDown = false
        hasPublishedCameraResolution = false
        invalidateReliableEvidenceGate()
        resetCameraTrackingForSessionRun()
    }

    private func publishPendingCameraResolution() {
        // 延后发布，避免 UIViewRepresentable 创建期触发 SwiftUI 状态警告。
        DispatchQueue.main.async { [self] in
            settings.currentCameraResolutionDisplay = L10n.Scan.detecting
        }
    }

    private func scheduleDeferredSettingsLoad() {
        // 等 session 初始化完成后再下发 Metal/检测参数。
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !self.isTornDown else { return }
            self.loadSettings()
            self.renderer?.applyScanQualitySettings()
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

    private func clearRuntimeReferences() {
        // 同时释放回调和大对象引用，避免已退出页面继续接收扫描结果。
        mtkView = nil
        renderer = nil
        session = nil
        hudState = nil
        depthRuntimeStatus = nil
        requestedSceneDepth = false
        onMeasurementReady = nil
        onQualitySampleUpdate = nil
        onCoveragePercentChange = nil
        onFruitCategoryMismatch = nil
        onCalibrationWarning = nil
        onLifecycleStateChange = nil
        #if DEBUG
        onDetectionDebugStateChange = nil
        #endif
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()
        activeFruitConfiguration = nil
        hasPublishedCategoryMismatch = false
        resetCameraTrackingForSessionRun()
    }

    func lifecycleSnapshot() -> ScanLifecycleSnapshot {
        scanLifecycle.snapshot()
    }

    // A coordinator can outlive the UIView that created its ARSession. Reject
    // callbacks still draining from that replaced session.
    func acceptsDelegateCallback(from candidateSession: ARSession) -> Bool {
        guard !isTornDown, let activeSession = session else { return false }
        return activeSession === candidateSession
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
        evidenceGateLock.lock()
        defer { evidenceGateLock.unlock() }
        return reliableEvidenceGeneration
    }

    func acceptsReliableEvidence(generation: Int? = nil) -> Bool {
        evidenceGateLock.lock()
        defer { evidenceGateLock.unlock() }
        guard acceptsReliableEvidence else { return false }
        // generation 可阻止异步推理完成后把旧扫描证据写入新扫描。
        return generation.map { $0 == reliableEvidenceGeneration } ?? true
    }

    @discardableResult
    func setReliableEvidenceAcceptance(_ accepted: Bool) -> Int {
        evidenceGateLock.lock()
        // 每次开关证据门都推进代次，使已在途的任务自然失效。
        reliableEvidenceGeneration &+= 1
        acceptsReliableEvidence = accepted
        let generation = reliableEvidenceGeneration
        evidenceGateLock.unlock()
        return generation
    }

    func capturedEvidenceToken() -> ScanCapturedEvidenceToken? {
        let lifecycle = lifecycleSnapshot()
        guard lifecycle.state == .recording else { return nil }

        evidenceGateLock.lock()
        defer { evidenceGateLock.unlock() }
        guard acceptsReliableEvidence else { return nil }
        return ScanCapturedEvidenceToken(
            scanIdentity: lifecycle.scanIdentity,
            invalidationEpoch: capturedEvidenceInvalidationEpoch
        )
    }

    @MainActor
    func acceptsCapturedEvidence(_ token: ScanCapturedEvidenceToken) -> Bool {
        guard !isTornDown else { return false }
        let lifecycle = lifecycleSnapshot()
        guard lifecycle.scanIdentity == token.scanIdentity else { return false }

        evidenceGateLock.lock()
        let invalidationEpochMatches =
            token.invalidationEpoch == capturedEvidenceInvalidationEpoch
        let acceptsActiveEvidence = acceptsReliableEvidence
        evidenceGateLock.unlock()
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
            return acceptsActiveEvidence || acceptsTrackingSuspendedEvidence
        case .userPaused, .finishing:
            return true
        default:
            return false
        }
    }

    private func invalidateReliableEvidenceGate() {
        evidenceGateLock.lock()
        reliableEvidenceGeneration &+= 1
        acceptsReliableEvidence = false
        capturedEvidenceInvalidationEpoch &+= 1
        evidenceGateLock.unlock()
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
