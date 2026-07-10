import ARKit
import MetalKit
import os
import UIKit

// MARK: - ScanCoordinator
enum ScanDepthRuntimeStatus: String {
    case unsupportedAR = "NoAR"
    case unsupportedSceneDepth = "NoDepth"
    case waitingForDepth = "Wait"
    case activeDepth = "LiDAR"
}

struct YieldEstimationRequestGate: Sendable {
    private(set) var currentGeneration: UInt64 = 0

    mutating func beginRequest() -> UInt64 {
        currentGeneration &+= 1
        return currentGeneration
    }

    mutating func invalidate() {
        currentGeneration &+= 1
    }

    func accepts(_ generation: UInt64) -> Bool {
        generation == currentGeneration
    }
}

class ScanCoordinator: NSObject {
    let settings: ScanSettingsProviding

    var renderer: Renderer?
    var session: ARSession?
    weak var mtkView: MTKView?

    init(settings: ScanSettingsProviding = SettingsStore.shared) {
        self.settings = settings
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

    var onMeasurementReady: ((Renderer) -> Void)?
    var onQualitySampleUpdate: ((ScanQualitySample) -> Void)?
    var onCoveragePercentChange: ((Int) -> Void)?
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
    var fusionEstimateTask: Task<Void, Never>?
    var yieldEstimationRequestGate = YieldEstimationRequestGate()

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

    private func configureAndRunSession(_ session: ARSession) -> ScanDepthRuntimeStatus {
        requestedSceneDepth = false

        guard ARWorldTrackingConfiguration.isSupported else {
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
        session.run(config)

        return requestedSceneDepth ? .waitingForDepth : .unsupportedSceneDepth
    }

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

    private func stopRuntimeServices() {
        detectionTask?.cancel()
        detectionTask = nil
        invalidateYieldEstimationRequest()
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
        mtkView = nil
        renderer = nil
        session = nil
        hudState = nil
        depthRuntimeStatus = nil
        requestedSceneDepth = false
        onMeasurementReady = nil
        onQualitySampleUpdate = nil
        onCoveragePercentChange = nil
        #if DEBUG
        onDetectionDebugStateChange = nil
        #endif
        detectedFruits.removeAll()
        archivedFusionEvidenceDetections.removeAll()
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
