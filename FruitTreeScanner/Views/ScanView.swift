// ScanView.swift
// 扫描主界面 + 产量估算（扫描停止后自动触发）

import SwiftUI
import MetalKit
import ARKit

struct ScanHUDSnapshot: Equatable {
    var pointCount: Int = 0
    var scannedRegionCount: Int = 0
    var coveragePercent: Int = 0
    var coverageVoxelCount: Int = 0
    var meshArea: Float = 0
    var scanCompletion: ScanCompletion = ScanCompletion()
}

final class ScanHUDState: ObservableObject {
    @Published private(set) var snapshot = ScanHUDSnapshot()

    var pointCount: Int { snapshot.pointCount }
    var scannedRegionCount: Int { snapshot.scannedRegionCount }
    var coveragePercent: Int { snapshot.coveragePercent }
    var coverageVoxelCount: Int { snapshot.coverageVoxelCount }
    var meshArea: Float { snapshot.meshArea }
    var scanCompletion: ScanCompletion { snapshot.scanCompletion }

    func resetForNewScan() {
        update(to: ScanHUDSnapshot())
    }

    func update(
        pointCount: Int? = nil,
        scannedRegionCount: Int? = nil,
        coveragePercent: Int? = nil,
        coverageVoxelCount: Int? = nil,
        meshArea: Float? = nil,
        scanCompletion: ScanCompletion? = nil
    ) {
        var next = snapshot
        if let pointCount { next.pointCount = pointCount }
        if let scannedRegionCount { next.scannedRegionCount = scannedRegionCount }
        if let coveragePercent { next.coveragePercent = coveragePercent }
        if let coverageVoxelCount { next.coverageVoxelCount = coverageVoxelCount }
        if let meshArea { next.meshArea = meshArea }
        if let scanCompletion { next.scanCompletion = scanCompletion }
        update(to: next)
    }

    private func update(to next: ScanHUDSnapshot) {
        guard snapshot != next else { return }
        snapshot = next
    }
}

struct ScanView: View {
    let treeID: String
    let nVisual: Int?              // AI 视觉计数（可 nil）
    let season: Season             // mature / off
    @ObservedObject var gps: GPSRecorder

    @State private var coordinator = ScanCoordinator()
    @StateObject private var hudState = ScanHUDState()
    @StateObject private var qualityMonitor = ScanQualityMonitor()
    @StateObject private var measurementController = MetalMeasurementController()
    @Environment(\.dismiss) var dismiss

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
    @State private var debugCandidates: [FruitCandidate] = []
    @State private var debugDetectedFruits: [DetectedFruit] = []
    #endif
    @State private var measuredDistance: Float?
    @State private var scanNotice: String?
    @State private var isViewActive = false
    @State private var autoExportTask: Task<Void, Never>?

    var body: some View {
        ZStack {
            renderLayer
            guideLayer
            statusLayer
            measurementLayer
            controlLayer
            resultLayer
            estimatingLayer
            coverageCompleteLayer
            noticeLayer
        }
        .onAppear {
            isViewActive = true
            coordinator.hudState = hudState
            coordinator.onCoveragePercentChange = handleCoveragePercentChange
            coordinator.onMeasurementReady = { renderer in
                measurementController.renderer = renderer
            }
        }
        .onDisappear {
            isViewActive = false
            isEstimating = false
            autoExportTask?.cancel()
            autoExportTask = nil
            measurementController.deactivate()
            measurementController.renderer = nil
            coordinator.teardown()
        }
        #if DEBUG
            .sheet(isPresented: $showDebugView) {
                FruitDetectionDebugView(
                    candidates: debugCandidates,
                    detectedFruits: debugDetectedFruits
                )
            }
        #endif
    }

    private var renderLayer: some View {
        MetalView(coordinator: coordinator)
            .ignoresSafeArea()
            .onAppear {
                coordinator.onQualitySampleUpdate = { sample in
                    DispatchQueue.main.async {
                        qualityMonitor.update(with: sample)
                    }
                }
            }
    }

    @ViewBuilder
    private var guideLayer: some View {
        if showGuide {
            VStack {
                HStack {
                    Button("跳过引导") { showGuide = false }
                        .padding()
                    Spacer()
                }
                Spacer()
            }
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
            #if DEBUG
                ScanBottomControlBar(
                    isRecording: isRecording,
                    isEstimating: isEstimating,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: { showGuide.toggle() },
                    onToggleRecording: toggleRecording,
                    onToggleMeasurement: toggleMeasurement,
                    onExport: exportAndEstimate,
                    onDebug: showDebugSnapshot
                )
            #else
                ScanBottomControlBar(
                    isRecording: isRecording,
                    isEstimating: isEstimating,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: { showGuide.toggle() },
                    onToggleRecording: toggleRecording,
                    onToggleMeasurement: toggleMeasurement,
                    onExport: exportAndEstimate
                )
            #endif
        }
    }

    @ViewBuilder
    private var resultLayer: some View {
        if showResult, let result = yieldResult {
            ResultView(treeID: treeID, result: result) {
                showResult = false
            } onDismissToHome: {
                showResult = false
                dismiss()
            }
        }
    }

    @ViewBuilder
    private var estimatingLayer: some View {
        if isEstimating {
            Color.black.opacity(0.5)
            VStack(spacing: 16) {
                ProgressView()
                    .scaleEffect(1.5)
                Text("正在估算产量…")
                    .foregroundColor(.white)
            }
        }
    }

    @ViewBuilder
    private var coverageCompleteLayer: some View {
        if showCoverageComplete {
            VStack {
                Spacer()
                HStack {
                    Spacer()
                    VStack(spacing: 8) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 28))
                            .foregroundColor(Design.Colors.forest)
                        Text("扫描覆盖充足")
                            .font(.system(size: 14, weight: .semibold))
                            .foregroundColor(.white)
                        Text("可以点击导出按钮")
                            .font(.system(size: 12))
                            .foregroundColor(.white.opacity(0.7))
                    }
                    .padding(Design.Space.md)
                    .background(
                        RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                            .fill(Design.Colors.Dark.hudBackground)
                    )
                    .overlay(
                        RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                            .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
                    )
                    Spacer()
                }
                .padding(.bottom, 120)
            }
            .transition(.opacity)
            .animation(.easeInOut(duration: 0.3), value: showCoverageComplete)
        }
    }

    @ViewBuilder
    private var noticeLayer: some View {
        if let scanNotice {
            VStack {
                Spacer()
                Text(scanNotice)
                    .font(.system(size: 13, weight: .medium))
                    .foregroundColor(.white)
                    .padding(.horizontal, 14)
                    .padding(.vertical, 10)
                    .background(
                        Capsule()
                            .fill(Design.Colors.Dark.hudBackground)
                    )
                    .overlay(
                        Capsule()
                            .stroke(Design.Colors.Dark.hudBorder, lineWidth: 1)
                    )
                    .padding(.bottom, 112)
            }
            .transition(.opacity)
        }
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
            showTemporaryNotice("请先录制一段点云后再测量")
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
            let snapshot = coordinator.debugSnapshot()
            debugCandidates = snapshot.candidates
            debugDetectedFruits = snapshot.detectedFruits
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
        createDirectory(folder: "scans")
        coordinator.startRecording()
        isRecording = true
        showGuide = false
    }

    private func stopRecording() {
        coordinator.stopRecording()
        isRecording = false
    }

    // MARK: - 导出 + 估算
    private func exportAndEstimate() {
        guard !isEstimating else { return }
        guard coordinator.pointCount > 0 else {
            showTemporaryNotice("当前没有可导出的点云")
            return
        }

        isEstimating = true
        coordinator.exportPLY(treeID: treeID, lat: gps.latitude, lon: gps.longitude) { filename in
            guard self.isViewActive else { return }
            self.savedFilename = filename ?? ""
            guard filename != nil else {
                self.isEstimating = false
                self.showTemporaryNotice("点云导出失败，请继续扫描后重试")
                return
            }

            ScanHistoryStore.shared.notifyRecordsUpdated()

            self.coordinator.runYieldEstimate(nVisual: self.nVisual, season: self.season) { result in
                guard self.isViewActive else { return }
                self.isEstimating = false
                self.yieldResult = result
                self.showResult = true

                if let filename {
                    self.persistScanResult(result: result, filename: filename)
                }
            }
        }
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

    private func persistScanResult(result: YieldResult, filename: String) {
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

        autoExportTask?.cancel()
        autoExportTask = Task.detached(priority: .utility) {
            do {
                let exportedFiles = try ScanResultExportService.shared.exportIfNeeded(request)
                guard !Task.isCancelled else { return }
                await MainActor.run {
                    ScanHistoryStore.shared.notifyRecordsUpdated()
                }
                #if DEBUG
                if let exportedFiles {
                    if includeCSV {
                        print("📄 [ScanView] CSV 自动导出成功: \(exportedFiles.csvURL.lastPathComponent)")
                    }
                    if let metadataURL = exportedFiles.metadataURL {
                        print("📄 [ScanView] JSON 元数据导出成功: \(metadataURL.lastPathComponent)")
                    }
                }
                #endif
            } catch {
                #if DEBUG
                print("❌ [ScanView] 结果元数据保存失败: \(error.localizedDescription)")
                #endif
            }
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

private struct ScanStatusBar: View {
    let treeID: String
    let isRecording: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                HUDPill(label: "TREE", value: treeID, accentColor: Design.Colors.harvest)
                HUDPill(label: "COVER", value: "\(hudState.coveragePercent)%", accentColor: Design.Colors.forest)
                HUDPill(label: "AREA", value: String(format: "%.1fm²", hudState.meshArea), accentColor: Design.Colors.harvest)
                HUDPill(label: "PTS", value: formatPointCount(hudState.pointCount), accentColor: Design.Colors.harvest)
                HUDPill(label: "DENSITY", value: String(format: "%.0f", qualityMonitor.pointDensity), accentColor: qualityMonitor.pointDensity > 100 ? Design.Colors.forest : Design.Colors.warning)
                HUDPill(label: "LIGHT", value: qualityMonitor.lightLevel.description, accentColor: qualityMonitor.lightLevel.color)
                HUDPill(label: "QUALITY", value: qualityMonitor.getQualityStatus(), accentColor: qualityColor)
                StatusIndicator(status: isRecording ? .recording : .ready)
            }
            .padding(.horizontal, Design.Space.md)
            .padding(.vertical, Design.Space.sm)
        }
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, Design.Space.md)
        .padding(.top, Design.Space.md)
    }

    private var qualityColor: Color {
        let score = qualityMonitor.qualityScore
        switch score {
        case 0..<30: return .red
        case 30..<50: return .orange
        case 50..<70: return .yellow
        case 70..<90: return .green
        default: return .blue
        }
    }

    private func formatPointCount(_ count: Int) -> String {
        if count >= 1_000_000 {
            return String(format: "%.1fM", Double(count) / 1_000_000)
        } else if count >= 1_000 {
            return String(format: "%.1fK", Double(count) / 1_000)
        } else {
            return "\(count)"
        }
    }
}

private struct ScanCoverageHintBar: View {
    @ObservedObject var hudState: ScanHUDState

    var body: some View {
        CoverageMapView(completion: hudState.scanCompletion)
            .padding(.horizontal, Design.Space.lg)
            .padding(.bottom, Design.Space.sm)
    }
}

private struct ScanBottomControlBar: View {
    let isRecording: Bool
    let isEstimating: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var measurementController: MetalMeasurementController
    let onToggleGuide: () -> Void
    let onToggleRecording: () -> Void
    let onToggleMeasurement: () -> Void
    let onExport: () -> Void
    #if DEBUG
    let onDebug: () -> Void
    #endif

    var body: some View {
        HStack(spacing: 24) {
            GlassIconButton(icon: "questionmark.circle", size: 44, action: onToggleGuide)
            ScanRecordButton(isRecording: isRecording, action: onToggleRecording)
            MeasurementToolButton(isActive: measurementController.isActive, action: onToggleMeasurement)

            GlassIconButton(icon: isEstimating ? "clock" : "square.and.arrow.up", size: 44, action: onExport)
                .disabled(isExportDisabled)
                .opacity(isExportDisabled ? 0.5 : 1)

            #if DEBUG
            GlassIconButton(icon: "wrench.and.screwdriver", size: 44, action: onDebug)
            #endif
        }
        .padding(.horizontal, Design.Space.lg)
        .padding(.vertical, Design.Space.md)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.large)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.large)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, Design.Space.md)
        .padding(.bottom, Design.Space.lg)
    }

    private var isExportDisabled: Bool {
        isRecording || isEstimating || hudState.pointCount == 0
    }
}

// MARK: - ScanCoordinator
class ScanCoordinator: NSObject, TaskDelegate, ImageDetectorDelegate {
    private struct FusionFrameContext: @unchecked Sendable {
        let depthMap: CVPixelBuffer?
        let cameraIntrinsics: simd_float3x3
        let cameraTransform: simd_float4x4
        let imageSize: CGSize
    }

    var renderer: Renderer?
    var session: ARSession?
    weak var mtkView: MTKView?

    var pointCount: Int = 0
    var scannedRegionCount: Int = 0
    var coveragePercent: Int = 0
    var coverageVoxelCount: Int = 0
    var meshArea: Float = 0

    // 扫描完成度相关
    var scanCompletion: ScanCompletion = ScanCompletion()

    private var fruitCandidates: [FruitCandidate] = []
    private var detectedFruits: [DetectedFruit] = []

    var onMeasurementReady: ((Renderer) -> Void)?
    var onBindingComplete: (() -> Void)?

    var onQualitySampleUpdate: ((ScanQualitySample) -> Void)?
    var onCoveragePercentChange: ((Int) -> Void)?
    var hudState: ScanHUDState?

    func debugSnapshot() -> (candidates: [FruitCandidate], detectedFruits: [DetectedFruit]) {
        (fruitCandidates, detectedFruits)
    }

    private var collectedMeshAnchors: [ARMeshAnchor] = []
    private let maxMeshAnchors = 500
    private var lastMeshAreaUpdate = Date.distantPast
    private let meshAreaUpdateInterval: TimeInterval = 1.0
    private let maxFacesPerMeshAreaUpdate = 2_500

    private var displayLink: CADisplayLink?
    private var lastHUDUpdateTime: TimeInterval = 0
    private var lastCompletionUpdateTime: TimeInterval = 0
    private var lastQualitySampleTime: TimeInterval = 0
    private var hasPublishedCameraResolution = false
    private var isTornDown = false
    private let activeHUDUpdateInterval: TimeInterval = 0.1
    private let idleHUDUpdateInterval: TimeInterval = 0.25
    private let activeCompletionUpdateInterval: TimeInterval = 0.25
    private let idleCompletionUpdateInterval: TimeInterval = 0.5
    private let qualitySampleInterval: TimeInterval = 0.25
    private let estimator = YieldEstimator()
    private let completionEvaluator = ScanCompletionEvaluator()
    private let detectionProcessingLock = NSLock()
    private var isDetectionProcessing = false

    // MARK: - 多模态融合组件
    private lazy var imageDetector: ImageDetector = {
        let detector = ImageDetector(config: FruitScanConfig(
            imageDetectionInterval: 10,
            minConfidence: 0.5,
            sizeTolerance: 0.2,
            sphericityThreshold: 0.5
        ))
        return detector
    }()
    private lazy var pointCloudCluster: PointCloudCluster = {
        let settings = SettingsStore.shared
        let category = FruitCategory(rawValue: settings.fruitType) ?? .apple
        let params = FruitParametersStore.shared.param(for: category)
        return PointCloudCluster(config: settings.clusterConfig(for: params))
    }()
    private lazy var fusionValidator: FusionValidator = {
        FusionValidator(config: FruitScanConfig(
            imageDetectionInterval: 10,
            minConfidence: 0.5,
            sizeTolerance: 0.2,
            sphericityThreshold: 0.5
        ))
    }()
    private let fruitCounter = FruitCounter()
    private var detectionTask: Task<Void, Never>?
    private var fusionEstimateTask: Task<Void, Never>?

    func bind(session: ARSession, renderer: Renderer, mtkView: MTKView) {
        isTornDown = false
        self.session = session
        self.renderer = renderer
        self.mtkView = mtkView
        renderer.delegate = self
        hasPublishedCameraResolution = false

        // 重置分辨率显示，下次扫描时更新。延后发布，避免 UIViewRepresentable 创建期触发 SwiftUI 状态警告。
        DispatchQueue.main.async {
            SettingsStore.shared.currentCameraResolutionDisplay = "检测中..."
        }

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        }
        if let videoFormat = preferredVideoFormat() {
            config.videoFormat = videoFormat
        }
        // 实时产量估计主要依赖 sceneDepth 点云。ARKit mesh 重建会在启动后高频推送
        // 大量三角面 anchor，容易让扫描入口卡住；网格导出后续应作为单独的高负载模式开启。
        session.run(config)

        // 注册帧回调用于图像检测
        session.delegate = self

        // 设置图像检测器的 delegate
        imageDetector.delegate = self

        // 启动定期处理队列的定时器
        startDetectionTimer()

        // 延迟设置 rgbRadius 和加载算法配置，等 session 初始化完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            guard !self.isTornDown else { return }
            self.loadSettings()
            self.renderer?.applyScanQualitySettings()
        }

        displayLink?.invalidate()
        displayLink = CADisplayLink(target: self, selector: #selector(updatePointCount))
        displayLink?.add(to: .main, forMode: .common)
        UIApplication.shared.isIdleTimerDisabled = true

        DispatchQueue.main.async {
            self.onMeasurementReady?(renderer)
            self.onBindingComplete?()
        }
    }

    func teardown() {
        isTornDown = true
        detectionTask?.cancel()
        detectionTask = nil
        fusionEstimateTask?.cancel()
        fusionEstimateTask = nil
        displayLink?.invalidate()
        displayLink = nil
        detectionTimer?.invalidate()
        detectionTimer = nil
        imageDetector.clearQueue()
        session?.pause()
        session?.delegate = nil
        mtkView?.delegate = nil
        mtkView = nil
        renderer = nil
        session = nil
        hudState = nil
        onMeasurementReady = nil
        onBindingComplete = nil
        onQualitySampleUpdate = nil
        onCoveragePercentChange = nil
        detectedFruits.removeAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - 图像检测定时器
    private var detectionTimer: Timer?

    private func startDetectionTimer() {
        // 低频处理最新帧，避免 Vision/CoreML 抢占扫描渲染资源。
        detectionTimer?.invalidate()
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 0.5, repeats: true) { [weak self] _ in
            self?.processDetectionQueue()
        }
    }

    // MARK: - Settings
    @MainActor
    private func loadSettings() {
        let store = SettingsStore.shared
        let category = FruitCategory(rawValue: store.fruitType) ?? .apple
        let params = FruitParametersStore.shared.param(for: category)
        imageDetector.updateConfig(store.fruitScanConfig)
        pointCloudCluster.updateConfig(store.clusterConfig(for: params))
        fusionValidator.updateConfig(store.fruitScanConfig)
        renderer?.applyScanQualitySettings()
    }

    private func preferredVideoFormat() -> ARConfiguration.VideoFormat? {
        let settings = SettingsStore.shared
        let targetFPS = requestedFrameRate(from: settings.cameraFrameRate)
        let targetWidth = requestedResolutionWidth(from: settings.cameraResolution)

        return ARWorldTrackingConfiguration.supportedVideoFormats
            .filter { $0.framesPerSecond <= targetFPS }
            .sorted { lhs, rhs in
                let lhsScore = videoFormatScore(lhs, targetFPS: targetFPS, targetWidth: targetWidth)
                let rhsScore = videoFormatScore(rhs, targetFPS: targetFPS, targetWidth: targetWidth)
                return lhsScore < rhsScore
            }
            .first
    }

    private func requestedFrameRate(from option: String) -> Int {
        switch option {
        case "30fps": return 30
        case "120fps": return 120
        default: return 60
        }
    }

    private func requestedResolutionWidth(from option: String) -> Int {
        switch option {
        case "720p": return 1280
        case "4K": return 3840
        default: return 1920
        }
    }

    private func videoFormatScore(
        _ format: ARConfiguration.VideoFormat,
        targetFPS: Int,
        targetWidth: Int
    ) -> Int {
        let resolution = format.imageResolution
        let width = Int(max(resolution.width, resolution.height))
        return abs(format.framesPerSecond - targetFPS) * 10_000 + abs(width - targetWidth)
    }

    private func processDetectionQueue() {
        guard renderer?.isRecording == true else { return }
        guard beginDetectionProcessing() else { return }

        detectionTask = Task { [weak self] in
            guard let self = self else { return }
            defer { self.finishDetectionProcessing() }
            let detected = await self.imageDetector.processQueue()
            guard !Task.isCancelled else { return }

            await self.appendDetectedFruits(detected)
        }
    }

    private func flushPendingDetections() async {
        if let detectionTask {
            await detectionTask.value
        }
        guard !Task.isCancelled, !isTornDown else { return }
        guard beginDetectionProcessing() else { return }
        defer { finishDetectionProcessing() }

        let detected = await imageDetector.processQueue()
        guard !Task.isCancelled else { return }
        await appendDetectedFruits(detected)
    }

    private func appendDetectedFruits(_ detected: [DetectedFruit]) async {
        guard !detected.isEmpty else { return }

        #if DEBUG
        print("📸 [ScanCoordinator] 检测到 \(detected.count) 个果实:")
        for fruit in detected {
            print("      - \(fruit.category.displayName), 置信度: \(fruit.confidence), 边界框: \(fruit.boundingBox)")
        }
        #endif

        await MainActor.run {
            guard !self.isTornDown else { return }
            self.detectedFruits.append(contentsOf: detected)
        }
    }

    private func beginDetectionProcessing() -> Bool {
        detectionProcessingLock.lock()
        defer { detectionProcessingLock.unlock() }
        guard !isDetectionProcessing else { return false }
        isDetectionProcessing = true
        return true
    }

    private func finishDetectionProcessing() {
        detectionProcessingLock.lock()
        isDetectionProcessing = false
        detectionProcessingLock.unlock()
    }

    func startRecording() {
        detectionTask?.cancel()
        detectionTask = nil
        fusionEstimateTask?.cancel()
        fusionEstimateTask = nil
        imageDetector.clearQueue()
        createDirectory(folder: "scans")
        pointCount = 0
        scannedRegionCount = 0
        coveragePercent = 0
        coverageVoxelCount = 0
        meshArea = 0
        scanCompletion = ScanCompletion()
        hudState?.resetForNewScan()
        renderer?.currentFolder = "scans"
        renderer?.isRecording = true
    }

    func stopRecording() {
        processDetectionQueue()
        renderer?.isRecording = false
        collectedMeshAnchors.removeAll()
    }

    func exportPLY(treeID: String, lat: Double, lon: Double,
                   completion: @escaping (String?) -> Void) {
        guard let renderer else {
            completion(nil)
            return
        }

        renderer.savePointCloud(treeID: treeID, gpsLat: lat, gpsLon: lon) { filename in
            completion(filename)
        }
    }

    private func extractColoredPoints() -> [ColoredPoint] {
        guard let r = renderer else { return [] }
        return r.makeAnalysisPoints()
    }

    /// 多模态融合产量估算（新 pipeline）
    func runMultiModalYieldEstimate(
        nVisual: Int?,
        season: Season,
        completion: @escaping (YieldResult, FruitCountResult?) -> Void
    ) {
        let frameContext = makeFusionFrameContext()
        let settings = SettingsStore.shared
        let fruitType = settings.fruitType
        let fruitCat = FruitCategory(rawValue: fruitType)
        let paramsSnapshot = FruitParametersStore.shared.parameterSnapshot()
        let defaultParams = fruitCat.flatMap { paramsSnapshot[$0.rawValue] } ?? FruitVarietyParams(category: fruitCat ?? .apple)
        let clusterConfig = settings.clusterConfig(for: defaultParams)
        let fusionConfig = settings.fruitScanConfig

        fusionEstimateTask?.cancel()
        fusionEstimateTask = Task.detached(priority: .userInitiated) { [weak self] in
            guard let self = self else { return }
            await self.flushPendingDetections()
            guard !Task.isCancelled else { return }

            let points = self.extractColoredPoints()
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("🔍 [Fusion] 共有 \(points.count) 个点云点")
                #endif

                // 取出并清空检测结果（在 MainActor 上操作，安全）
                let savedDetections: [DetectedFruit] = await MainActor.run {
                    guard !self.isTornDown else { return [] as [DetectedFruit] }
                    let saved = self.detectedFruits
                    self.detectedFruits.removeAll()
                    return saved
                }
                guard !Task.isCancelled else { return }

                #if DEBUG
                print("🔍 [Fusion] 图像检测结果: \(savedDetections.count) 个")
                #endif

                // Step 1: 点云聚类
                let clusterer = PointCloudCluster(config: clusterConfig)
                let candidates = await clusterer.processInMemory(
                    position: points.map { $0.pos },
                    colors: points.map { SIMD3<Float>($0.r, $0.g, $0.b) }
                )
                guard !Task.isCancelled else { return }
                #if DEBUG
                print("🔍 [Fusion] 点云聚类候选: \(candidates.count) 个")
                #endif

                // Step 2: 融合验证（如果有图像检测结果）
                var validatedFruits: [ValidatedFruit] = []
                if !savedDetections.isEmpty, let frameContext {
                    // 2D 去重：消除同一果实的重复检测
                    let deduplicatedDetections = DetectionDeduplicator.deduplicate2D(savedDetections)
                    #if DEBUG
                    print("🔍 [Fusion] 2D去重后: \(deduplicatedDetections.count) / \(savedDetections.count) 个检测")
                    #endif

                    let fusionValidator = FusionValidator(config: fusionConfig)
                    validatedFruits = fusionValidator.validate(
                        detections: deduplicatedDetections,
                        candidates: candidates,
                        depthMap: frameContext.depthMap,
                        cameraIntrinsics: frameContext.cameraIntrinsics,
                        cameraTransform: frameContext.cameraTransform,
                        imageSize: frameContext.imageSize
                    )

                    // 3D 空间去重：消除融合后的重复计数
                    validatedFruits = ValidatedFruit.deduplicate3D(validatedFruits)
                    #if DEBUG
                    print("🔍 [Fusion] 3D去重后: \(validatedFruits.count) 个果实")
                    #endif
                } else {
                    // ⚠️ 重要：没有图像检测结果时，不应该只靠点云就判定为果实！
                    // cloudOnly 路径现在默认拒绝所有候选，除非满足非常严格的条件
                    #if DEBUG
                    print("🔍 [Fusion] ⚠️ 无图像检测，进入保守模式")
                    print("🔍 [Fusion] 点云候选数: \(candidates.count)")
                    #endif

                    // 只有当球形度非常高 (>0.8) 且颜色非常符合时才接受
                    // 这大大减少了误判（窗帘、台灯、桌面物品等）
                    var accepted = 0
                    for candidate in candidates {
                        if candidate.sphericity > 0.7 && candidate.hasFruitColor() {
                            let fruit = ValidatedFruit(
                                category: nil,
                                position: candidate.position,
                                confidence: candidate.sphericity * 0.5,
                                source: .cloudOnly
                            )
                            validatedFruits.append(fruit)
                            accepted += 1
                        }
                    }
                    #if DEBUG
                    print("🔍 [Fusion] cloudOnly 模式: \(candidates.count) 候选, 只接受 \(accepted) 个（需要 sphericity>0.7 且颜色符合）")
                    #endif
                }

                // Step 3: 计数
                #if DEBUG
                print("🔍 [Fusion] 最终有效果实: \(validatedFruits.count) 个")
                #endif
                let countResult = self.fruitCounter.count(validatedFruits, defaultCategory: fruitCat ?? .apple)
                let weightedVisibleCount = self.fruitCounter.weightedTotal(validatedFruits)

                // Step 4: 基于实测直径的重量估算
                let visibleYieldEstimate = computeYieldFromValidatedFruits(
                    validatedFruits,
                    candidates: candidates,
                    paramsByCategory: paramsSnapshot,
                    defaultParams: defaultParams
                )

                let defaultFruitWeightKg = defaultParams.averageWeightG / 1000
                let visualCorrection = self.correctVisibleEstimate(
                    weightedVisibleCount: weightedVisibleCount,
                    estimatedVisibleYieldKg: visibleYieldEstimate.yieldKg,
                    nVisual: nVisual,
                    defaultFruitWeightKg: defaultFruitWeightKg
                )

                // Step 5: 冠层几何遮挡校正（从点云估算冠层半径）
                let crownRadius = OcclusionCorrector.estimateCrownRadius(from: points)
                let crownDepth = OcclusionCorrector.estimateCrownDepth(from: points)
                let scanAngleCoverage = OcclusionCorrector.estimateScanAngleCoverage(from: points)
                let occlusionResult = OcclusionCorrector.correctionFactorDetailed(
                    visibleCount: max(Int(visualCorrection.visibleCount.rounded()), validatedFruits.count),
                    crownRadiusM: crownRadius,
                    crownDepthM: crownDepth,
                    lidarPenetrationM: 0.4,
                    scanAngleCoverage: scanAngleCoverage
                )
                let occlusionCorrection = occlusionResult.k
                let yieldAfterOcclusion = visualCorrection.visibleYieldKg * occlusionCorrection
                let correctedTotalCount = Int((visualCorrection.visibleCount * occlusionCorrection).rounded())
                let totalCorrection = visualCorrection.visualFactor * occlusionCorrection
                #if DEBUG
                print("🔍 [Fusion] 遮挡校正: 冠层半径 \(String(format: "%.2f", crownRadius))m, \(String(format: "%.1f", visualCorrection.visibleCount)) 个校正可见果实, \(occlusionResult.description)")
                #endif

                // Step 5: 只有当新 pipeline 找到果实时才输出结果
                // 新 pipeline 为 0 时直接返回 0，不使用旧算法（因为旧算法误判太多）
                var finalResult: YieldResult

                if visualCorrection.visibleCount > 0 {
                    // 新 pipeline 找到了果实，使用新结果
                    #if DEBUG
                    print("🔍 [Fusion] ✅ 使用校正后结果: \(String(format: "%.1f", visualCorrection.visibleCount)) 个可见果实")
                    #endif

                    // 构建 YieldResult 从 countResult
                    var yr = YieldResult()
                    yr.nLidar = correctedTotalCount
                    yr.nVisual = nVisual
                    yr.correctionK = totalCorrection
                    yr.yieldFinalKg = yieldAfterOcclusion
                    yr.yieldBVisibleKg = visualCorrection.visibleYieldKg
                    yr.yieldBCorrectedKg = yieldAfterOcclusion
                    yr.meanDiameterCm = visibleYieldEstimate.meanDiameterCm
                    yr.meanVolumeCm3 = visibleYieldEstimate.meanVolumeCm3
                    let estimateQuality = self.estimateQuality(
                        for: validatedFruits,
                        visualCorrection: visualCorrection
                    )
                    yr.confidence = estimateQuality.confidence
                    yr.methodUsed = estimateQuality.methodUsed
                    yr.note = visualCorrection.note.replacingOccurrences(
                        of: "RGB+LiDAR 融合检测",
                        with: estimateQuality.sourceDescription
                    )
                    yr.pointCloudSize = points.count
                    yr.clusterEps = clusterConfig.baseEps
                    yr.clusterMinPoints = clusterConfig.minPoints
                    yr.fruitCategory = fruitCat?.displayName ?? fruitType
                    yr.colorFilterDesc = fruitCat?.colorFilter.description ?? "N/A"
                    yr.occlusionK = occlusionCorrection
                    finalResult = yr
                } else {
                    // ⚠️ 关键修复：不要再用旧算法！直接输出 0
                    #if DEBUG
                    print("🔍 [Fusion] ⚠️ 新 pipeline 无检测，输出 0 kg（旧算法已禁用）")
                    print("🔍 [Fusion] 原因: 没有图像检测确认的果实不可信")
                    #endif

                    var yr = YieldResult()
                    yr.nLidar = 0
                    yr.yieldFinalKg = 0
                    yr.confidence = "low"
                    yr.methodUsed = "fusion_only"
                    yr.note = "⚠️ RGB+LiDAR 未检测到果实（图像检测未确认）"
                    yr.pointCloudSize = points.count
                    yr.clusterEps = clusterConfig.baseEps
                    yr.clusterMinPoints = clusterConfig.minPoints
                    yr.fruitCategory = fruitCat?.displayName ?? fruitType
                    yr.colorFilterDesc = fruitCat?.colorFilter.description ?? "N/A"
                    yr.occlusionK = occlusionCorrection
                    finalResult = yr
                }

                let resultToSend = finalResult
                await MainActor.run {
                    guard !Task.isCancelled, !self.isTornDown else { return }
                    completion(resultToSend, countResult)
                }
        }
    }

    private func makeFusionFrameContext() -> FusionFrameContext? {
        guard let frame = session?.currentFrame else { return nil }

        let depthMap: CVPixelBuffer?
        if let sourceDepthMap = (frame.smoothedSceneDepth ?? frame.sceneDepth)?.depthMap {
            depthMap = duplicatePixelBuffer(input: sourceDepthMap)
        } else {
            depthMap = nil
        }

        return FusionFrameContext(
            depthMap: depthMap,
            cameraIntrinsics: frame.camera.intrinsics,
            cameraTransform: frame.camera.transform,
            imageSize: CGSize(
                width: CGFloat(frame.camera.imageResolution.width),
                height: CGFloat(frame.camera.imageResolution.height)
            )
        )
    }

    /// 原有产量估算（兼容模式）
    func runYieldEstimate(nVisual: Int?,
                          season: Season,
                          completion: @escaping (YieldResult) -> Void) {
        runMultiModalYieldEstimate(nVisual: nVisual, season: season) { result, _ in
            completion(result)
        }
    }

    @objc private func updatePointCount() {
        let now = CACurrentMediaTime()
        let hudInterval = renderer?.isRecording == true ? activeHUDUpdateInterval : idleHUDUpdateInterval
        guard now - lastHUDUpdateTime >= hudInterval else { return }
        lastHUDUpdateTime = now

        var hudPointCount: Int?
        var hudRegionCount: Int?
        var hudCoveragePercent: Int?
        var hudCoverageVoxelCount: Int?

        if let renderer {
            let exportableCount = renderer.exportablePointCountPublic
            let nextPointCount = exportableCount > 0 ? exportableCount : renderer.currentPointCountPublic
            if pointCount != nextPointCount {
                pointCount = nextPointCount
                hudPointCount = nextPointCount
            }
        } else {
            if pointCount != 0 {
                pointCount = 0
                hudPointCount = 0
            }
        }
        let regionCount = renderer?.scannedRegionCountPublic ?? 0
        if scannedRegionCount != regionCount {
            scannedRegionCount = regionCount
            hudRegionCount = regionCount
        }
        let maxRegions = 600
        let nextCoveragePercent = min(Int(Double(regionCount) / Double(maxRegions) * 100), 100)
        if coveragePercent != nextCoveragePercent {
            coveragePercent = nextCoveragePercent
            hudCoveragePercent = nextCoveragePercent
            onCoveragePercentChange?(nextCoveragePercent)
        }
        let nextCoverageVoxelCount = renderer?.coverageVoxelCount ?? 0
        if coverageVoxelCount != nextCoverageVoxelCount {
            coverageVoxelCount = nextCoverageVoxelCount
            hudCoverageVoxelCount = nextCoverageVoxelCount
        }

        if hudPointCount != nil || hudRegionCount != nil || hudCoveragePercent != nil || hudCoverageVoxelCount != nil {
            hudState?.update(
                pointCount: hudPointCount,
                scannedRegionCount: hudRegionCount,
                coveragePercent: hudCoveragePercent,
                coverageVoxelCount: hudCoverageVoxelCount
            )
        }

        updateScanCompletion()
    }

    private func updateScanCompletion() {
        guard let renderer = renderer else { return }
        let now = CACurrentMediaTime()
        let completionInterval = renderer.isRecording ? activeCompletionUpdateInterval : idleCompletionUpdateInterval
        guard now - lastCompletionUpdateTime >= completionInterval else { return }
        lastCompletionUpdateTime = now

        let completion = completionEvaluator.evaluate(
            .init(
                voxelCount: renderer.coverageVoxelCount,
                scanDuration: renderer.scanDuration,
                discoveryTrend: renderer.voxelDiscoveryTrendPublic,
                discoveryRate: renderer.voxelDiscoveryRatePublic
            )
        )

        scanCompletion = completion
        hudState?.update(scanCompletion: completion)
    }

    func didStartTask() {}
    func didFinishTask() {}

    // MARK: - ImageDetectorDelegate
    func imageDetector(_ detector: ImageDetector, didDetect fruits: [DetectedFruit]) {
        #if DEBUG
        print("📸 [Delegate] 收到 \(fruits.count) 个检测结果（由 processDetectionQueue 统一处理）")
        #endif
    }
}

// MARK: - ARSessionDelegate（帧回调用于图像检测）
extension ScanCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        if renderer?.isRecording == true {
            let imageSize = CGSize(
                width: CGFloat(frame.camera.imageResolution.width),
                height: CGFloat(frame.camera.imageResolution.height)
            )
            imageDetector.enqueueFrame(
                frame.capturedImage,
                timestamp: frame.timestamp,
                cameraTransform: frame.camera.transform,
                cameraIntrinsics: frame.camera.intrinsics,
                imageSize: imageSize
            )
        }

        if !hasPublishedCameraResolution {
            hasPublishedCameraResolution = true
            let res = frame.camera.imageResolution
            let display = "\(Int(res.width))×\(Int(res.height))"
            DispatchQueue.main.async {
                SettingsStore.shared.currentCameraResolutionDisplay = display
            }
        }

        let now = CACurrentMediaTime()
        if now - lastQualitySampleTime >= qualitySampleInterval {
            lastQualitySampleTime = now
            onQualitySampleUpdate?(makeQualitySample(from: frame))
        }
    }

    private func makeQualitySample(from frame: ARFrame) -> ScanQualitySample {
        ScanQualitySample(
            pointDensity: calculatePointDensity(from: frame.rawFeaturePoints),
            trackingState: frame.camera.trackingState,
            scanAngle: abs(frame.camera.eulerAngles.x * 180 / .pi),
            ambientIntensity: frame.lightEstimate?.ambientIntensity
        )
    }

    private func calculatePointDensity(from pointCloud: ARPointCloud?) -> Float {
        guard let points = pointCloud?.points, !points.isEmpty else { return 0 }

        let maxSamples = 240
        let step = max(points.count / maxSamples, 1)
        var minX: Float = .greatestFiniteMagnitude
        var maxX: Float = -.greatestFiniteMagnitude
        var minY: Float = .greatestFiniteMagnitude
        var maxY: Float = -.greatestFiniteMagnitude
        var minZ: Float = .greatestFiniteMagnitude
        var maxZ: Float = -.greatestFiniteMagnitude
        var sampledCount = 0

        var index = 0
        while index < points.count {
            let point = points[index]
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minY = min(minY, point.y)
            maxY = max(maxY, point.y)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
            sampledCount += 1
            index += step
        }

        guard sampledCount > 0 else { return 0 }
        let volume = (maxX - minX) * (maxY - minY) * (maxZ - minZ)
        guard volume > 0 else { return 0 }
        return Float(points.count) / volume
    }

    func session(_ session: ARSession, didAdd anchors: [ARAnchor]) {
        updateMeshArea(from: anchors)
    }

    func session(_ session: ARSession, didUpdate anchors: [ARAnchor]) {
        updateMeshArea(from: anchors)
    }

    private func updateMeshArea(from anchors: [ARAnchor]) {
        let meshAnchors = anchors.compactMap { $0 as? ARMeshAnchor }
        guard !meshAnchors.isEmpty else { return }

        collectedMeshAnchors.append(contentsOf: meshAnchors)
        if collectedMeshAnchors.count > maxMeshAnchors {
            collectedMeshAnchors.removeFirst(collectedMeshAnchors.count - maxMeshAnchors)
        }

        let now = Date()
        guard now.timeIntervalSince(lastMeshAreaUpdate) >= meshAreaUpdateInterval else { return }
        lastMeshAreaUpdate = now

        var totalArea: Float = 0
        var processedFaces = 0

        for meshAnchor in meshAnchors {
            let geometry = meshAnchor.geometry
            let faces = geometry.faces
            let vertices = geometry.vertices
            let vertexCount = vertices.count
            let faceCount = faces.count

            guard faceCount > 0, vertexCount >= 3 else { continue }
            guard faces.indexCountPerPrimitive == 3 else { continue }

            let vertexBufferPtr = vertices.buffer.contents().bindMemory(to: SIMD3<Float>.self, capacity: vertexCount)
            let vertexStride = vertices.stride

            for f in 0..<faceCount {
                guard processedFaces < maxFacesPerMeshAreaUpdate else { break }
                let indices = faces[f]
                guard indices.count == 3 else { continue }
                let i0 = Int(indices[0])
                let i1 = Int(indices[1])
                let i2 = Int(indices[2])
                guard i0 < vertexCount, i1 < vertexCount, i2 < vertexCount else { continue }

                let v0 = vertexBufferPtr[i0 * vertexStride / MemoryLayout<SIMD3<Float>>.stride]
                let v1 = vertexBufferPtr[i1 * vertexStride / MemoryLayout<SIMD3<Float>>.stride]
                let v2 = vertexBufferPtr[i2 * vertexStride / MemoryLayout<SIMD3<Float>>.stride]

                let e1 = v1 - v0
                let e2 = v2 - v0
                totalArea += length(cross(e1, e2)) * 0.5
                processedFaces += 1
            }

            guard processedFaces < maxFacesPerMeshAreaUpdate else { break }
        }

        if totalArea > 0 {
            DispatchQueue.main.async {
                self.meshArea = totalArea
                let targetArea: Float = 30.0
                let meshCoverage = min(Int(totalArea / targetArea * 100), 100)
                if meshCoverage > self.coveragePercent {
                    self.coveragePercent = meshCoverage
                    self.hudState?.update(coveragePercent: meshCoverage, meshArea: totalArea)
                    self.onCoveragePercentChange?(meshCoverage)
                } else {
                    self.hudState?.update(meshArea: totalArea)
                }
            }
        }
    }
}

// MARK: - OBJ 导出

extension ScanCoordinator {
    func exportOBJ(treeID: String, completion: @escaping (String?) -> Void) {
        ScanMeshExportService.shared.exportOBJ(
            treeID: treeID,
            anchors: collectedMeshAnchors,
            completion: completion
        )
    }

    func exportUSDZ(treeID: String, completion: @escaping (URL?) -> Void) {
        ScanMeshExportService.shared.exportUSDZ(
            treeID: treeID,
            anchors: collectedMeshAnchors,
            completion: completion
        )
    }

    func exportPointCloudUSDZ(treeID: String, completion: @escaping (URL?) -> Void) {
        ScanMeshExportService.shared.exportPointCloudUSDZ(
            treeID: treeID,
            points: renderer?.getSnapshotPoints() ?? [],
            completion: completion
        )
    }
}

// MARK: - 重量估算

extension ScanCoordinator {

    private struct VisibleEstimateCorrection {
        let visibleCount: Float
        let visibleYieldKg: Float
        let visualFactor: Float
        let usedVisualOnly: Bool
        let note: String
    }

    private struct VisibleYieldEstimate {
        let yieldKg: Float
        let meanDiameterCm: Float
        let meanVolumeCm3: Float
    }

    private func correctVisibleEstimate(
        weightedVisibleCount: Float,
        estimatedVisibleYieldKg: Float,
        nVisual: Int?,
        defaultFruitWeightKg: Float
    ) -> VisibleEstimateCorrection {
        guard let nVisual, nVisual > 0 else {
            return VisibleEstimateCorrection(
                visibleCount: weightedVisibleCount,
                visibleYieldKg: estimatedVisibleYieldKg,
                visualFactor: 1.0,
                usedVisualOnly: false,
                note: "RGB+LiDAR 融合检测"
            )
        }

        let visualCount = Float(nVisual)
        guard weightedVisibleCount > 0 else {
            return VisibleEstimateCorrection(
                visibleCount: visualCount,
                visibleYieldKg: visualCount * defaultFruitWeightKg,
                visualFactor: 1.0,
                usedVisualOnly: true,
                note: "视觉计数兜底 + 品类平均重量估算"
            )
        }

        let blendedVisibleCount = weightedVisibleCount * 0.65 + visualCount * 0.35
        let visualFactor = min(max(blendedVisibleCount / weightedVisibleCount, 0.5), 2.0)

        return VisibleEstimateCorrection(
            visibleCount: weightedVisibleCount * visualFactor,
            visibleYieldKg: estimatedVisibleYieldKg * visualFactor,
            visualFactor: visualFactor,
            usedVisualOnly: false,
            note: String(
                format: "RGB+LiDAR 融合检测 + 视觉计数校正（K=%.2f，visual=%d）",
                visualFactor,
                nVisual
            )
        )
    }

    private func estimateQuality(
        for validatedFruits: [ValidatedFruit],
        visualCorrection: VisibleEstimateCorrection
    ) -> (confidence: String, methodUsed: String, sourceDescription: String) {
        if visualCorrection.usedVisualOnly {
            return ("low", "visual_only_calibrated", "视觉计数")
        }

        if validatedFruits.contains(where: { $0.source == .fused }) {
            let confidence = weightedEvidence(for: validatedFruits) >= 5 ? "high" : "medium"
            return (confidence, "fusion_visual_calibrated", "RGB+LiDAR 融合检测")
        }

        if validatedFruits.contains(where: { $0.source == .imageOnly }) {
            return ("medium", "image_visual_calibrated", "视觉检测估计")
        }

        return ("low", "cloud_only_calibrated", "点云候选估计")
    }

    private func weightedEvidence(for validatedFruits: [ValidatedFruit]) -> Float {
        validatedFruits.reduce(0) { total, fruit in
            total + fruit.source.countWeight * max(fruit.confidence, 0)
        }
    }

    /// 基于实测果实尺寸的重量估算
    /// 优先用 LiDAR 测得的直径计算体积，再乘以密度
    /// 已使用的 candidate 会被标记，避免重复计算同一果实
    private func computeYieldFromValidatedFruits(
        _ validatedFruits: [ValidatedFruit],
        candidates: [FruitCandidate],
        paramsByCategory: [String: FruitVarietyParams],
        defaultParams: FruitVarietyParams
    ) -> VisibleYieldEstimate {
        guard !validatedFruits.isEmpty else {
            return VisibleYieldEstimate(yieldKg: 0, meanDiameterCm: 0, meanVolumeCm3: 0)
        }

        var totalWeightKg: Float = 0
        var weightedDiameterSum: Float = 0
        var weightedVolumeSum: Float = 0
        var measuredWeight: Float = 0
        var usedCandidateIDs = Set<UUID>()

        for fruit in validatedFruits {
            // 找最近的、未被使用过的 FruitCandidate（有实测直径）
            let availableCandidates = candidates.filter { !usedCandidateIDs.contains($0.id) }
            let matchedCandidate = availableCandidates
                .map { c in (candidate: c, dist: simd_distance(c.position, fruit.position)) }
                .filter { $0.dist < 0.1 }
                .min(by: { $0.dist < $1.dist })
                .map { $0.candidate }

            if let candidate = matchedCandidate {
                let radiusCm = candidate.diameter * 100 / 2
                let volumeCm3 = (4.0 / 3.0) * Float.pi * pow(radiusCm, 3)
                let density = fruit.category.flatMap { paramsByCategory[$0.rawValue] }?.density ?? defaultParams.density
                let weightG = volumeCm3 * density
                let sourceWeight = fruit.source.countWeight
                totalWeightKg += weightG / 1000 * sourceWeight
                weightedDiameterSum += candidate.diameter * 100 * sourceWeight
                weightedVolumeSum += volumeCm3 * sourceWeight
                measuredWeight += sourceWeight
                usedCandidateIDs.insert(candidate.id)
            } else {
                // Fallback：用类别平均重量
                let avgG = fruit.category.flatMap { paramsByCategory[$0.rawValue] }?.averageWeightG ?? defaultParams.averageWeightG
                totalWeightKg += avgG / 1000 * fruit.source.countWeight
            }
        }

        let meanDiameter = measuredWeight > 0 ? weightedDiameterSum / measuredWeight : 0
        let meanVolume = measuredWeight > 0 ? weightedVolumeSum / measuredWeight : 0
        return VisibleYieldEstimate(
            yieldKg: totalWeightKg,
            meanDiameterCm: meanDiameter,
            meanVolumeCm3: meanVolume
        )
    }
}

// MARK: - Renderer MTKViewDelegate
extension Renderer: MTKViewDelegate {
    func mtkView(_ view: MTKView, drawableSizeWillChange size: CGSize) {
        drawRectResized(size: size)
    }
    func draw(in view: MTKView) { renderFrame() }
}

// MARK: - MetalView（真实 MTKView 创建点）
struct MetalView: UIViewRepresentable {
    let coordinator: ScanCoordinator

    func makeCoordinator() -> MetalViewCoordinator {
        MetalViewCoordinator(coordinator: coordinator)
    }

    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else {
            return MTKView()
        }

        let mtkView = MTKView()
        mtkView.device = device
        mtkView.backgroundColor = .black
        mtkView.depthStencilPixelFormat = .depth32Float
        mtkView.contentScaleFactor = 1

        // 创建 ARSession
        let arSession = ARSession()

        // 创建 Renderer（使用真实的 MTKView）
        let renderer = Renderer(session: arSession, metalDevice: device,
                                renderDestination: mtkView)
        // Use actual MTKView bounds instead of UIScreen.main.bounds to avoid 0x0 size
        let viewSize = mtkView.bounds.size
        if viewSize.width > 0 && viewSize.height > 0 {
            renderer.drawRectResized(size: viewSize)
        }

        // 关键：设置 MTKView 的 delegate，让渲染循环启动
        mtkView.delegate = renderer

        // 绑定到 Coordinator
        context.coordinator.coordinator?.bind(session: arSession, renderer: renderer, mtkView: mtkView)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {
        // Update viewport size when the MTKView size changes
        if uiView.bounds.size.width > 0 && uiView.bounds.size.height > 0 {
            context.coordinator.coordinator?.renderer?.drawRectResized(size: uiView.bounds.size)
        }
    }
}

// MARK: - MetalViewCoordinator
class MetalViewCoordinator: NSObject {
    weak var coordinator: ScanCoordinator?

    init(coordinator: ScanCoordinator) {
        self.coordinator = coordinator
        super.init()
    }
}

// MARK: - Glass Icon Button
struct GlassIconButton: View {
    let icon: String
    var size: CGFloat = 50
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: icon)
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .frame(width: size, height: size)
                .background(
                    Circle()
                        .fill(Color.white.opacity(0.08))
                )
        }
        .buttonStyle(ScanControlButtonStyle())
    }
}

// MARK: - Scan Record Button
struct ScanRecordButton: View {
    let isRecording: Bool
    let action: () -> Void

    @State private var pulseScale: CGFloat = 1.0
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            ZStack {
                // 外圈
                Circle()
                    .stroke(
                        isRecording ? Design.Colors.apple : Design.Colors.harvest,
                        lineWidth: 3
                    )
                    .frame(width: 70, height: 70)

                // 内部填充
                if isRecording {
                    // 录制中：显示停止图标
                    RoundedRectangle(cornerRadius: 6)
                        .fill(Design.Colors.apple)
                        .frame(width: 24, height: 24)
                } else {
                    // 就绪：显示录制点
                    Circle()
                        .fill(Design.Colors.harvest)
                        .frame(width: 56, height: 56)
                }

                // 录制中脉冲动画
                if isRecording {
                    Circle()
                        .stroke(Design.Colors.apple.opacity(0.5), lineWidth: 2)
                        .frame(width: 70, height: 70)
                        .scaleEffect(pulseScale)
                        .opacity(2 - pulseScale)
                }
            }
        }
        .buttonStyle(ScanControlButtonStyle())
        .onAppear {
            if isRecording && !reduceMotion {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                    pulseScale = 1.5
                }
            }
        }
        .onChange(of: isRecording) { newValue in
            if newValue && !reduceMotion {
                withAnimation(.easeInOut(duration: 1).repeatForever(autoreverses: false)) {
                    pulseScale = 1.5
                }
            } else {
                pulseScale = 1.0
            }
        }
    }
}

// MARK: - Measurement Tool Button
struct MeasurementToolButton: View {
    let isActive: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            Image(systemName: "ruler")
                .font(.system(size: 20, weight: .medium))
                .foregroundColor(isActive ? Design.Colors.harvest : .white)
                .frame(width: 44, height: 44)
                .background(
                    Circle()
                        .fill(isActive ? Design.Colors.harvest.opacity(0.2) : Color.clear)
                )
                .overlay(
                    Circle()
                        .stroke(isActive ? Design.Colors.harvest : Color.clear, lineWidth: 1)
                )
        }
        .buttonStyle(ScanControlButtonStyle())
    }
}

private struct ScanControlButtonStyle: ButtonStyle {
    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .scaleEffect(configuration.isPressed ? 0.95 : 1)
            .animation(.easeOut(duration: Design.Animation.micro), value: configuration.isPressed)
    }
}
