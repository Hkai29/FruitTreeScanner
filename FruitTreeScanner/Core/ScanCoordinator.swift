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

    @MainActor
    /// 固化一次扫描使用的类别、阈值与校准快照，避免扫描途中设置变化污染结果。
    static func capture(selectedCategory: FruitCategory, settings: ScanSettingsProviding) -> ScanFruitConfiguration {
        let parametersSnapshot = FruitParametersStore.shared.parameterSnapshot()
        let defaultParams = parametersSnapshot[selectedCategory.rawValue]
            ?? FruitVarietyParams(category: selectedCategory)
        let calibrationRecords = (try? CalibrationRecordPersistence.load()) ?? []
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
            )
        )
    }
}

/// 协调 AR 会话、点云采集、图像检测与产量估算的扫描级生命周期。
class ScanCoordinator: NSObject {
    let settings: ScanSettingsProviding
    private let sessionRuntime: ScanSessionRuntime

    var renderer: Renderer?
    var session: ARSession?
    weak var mtkView: MTKView?

    init(
        settings: ScanSettingsProviding = SettingsStore.shared,
        sessionRuntime: ScanSessionRuntime = .live
    ) {
        self.settings = settings
        self.sessionRuntime = sessionRuntime
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

        let depthStatus = configureAndRunSession(session)
        publishDepthRuntimeStatus(depthStatus)

        // 注册帧回调用于图像检测
        session.delegate = self
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
        stopRuntimeServices()
        clearRuntimeReferences()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    private func resetRuntimeState() {
        isTornDown = false
        hasPublishedCameraResolution = false
        setReliableEvidenceAcceptance(false)
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
        onLifecycleStateChange = nil
        #if DEBUG
        onDetectionDebugStateChange = nil
        #endif
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()
        activeFruitConfiguration = nil
        hasPublishedCategoryMismatch = false
    }

    func lifecycleSnapshot() -> ScanLifecycleSnapshot {
        scanLifecycle.snapshot()
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

    func publishLifecycleSnapshot(_ snapshot: ScanLifecycleSnapshot) {
        DispatchQueue.main.async { [weak self] in
            guard let self, !self.isTornDown else { return }
            self.onLifecycleStateChange?(snapshot)
        }
    }

    /// This is safe to call from ARSession's callback queue. It closes the
    /// evidence gate before the MainActor updates presentation state.
    func invalidateReliableEvidenceImmediately() {
        _ = setReliableEvidenceAcceptance(false)
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
