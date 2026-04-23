// ScanView.swift
// 扫描主界面 + 产量估算（扫描停止后自动触发）

import SwiftUI
import MetalKit
import ARKit

struct ScanView: View {
    let treeID: String
    let fruitType: FruitType       // 果种
    let nVisual: Int?              // AI 视觉计数（可 nil）
    let season: Season             // mature / off
    @ObservedObject var gps: GPSRecorder

    @StateObject private var coordinator = ScanCoordinator()
    @Environment(\.presentationMode) var presentationMode

    @State private var isRecording = false
    @State private var showGuide = true
    @State private var savedFilename = ""
    @State private var yieldResult: YieldResult? = nil
    @State private var showResult = false
    @State private var isEstimating = false

    var body: some View {
        ZStack {
            // 金属渲染层（真实 MTKView）
            MetalView(coordinator: coordinator)
                .ignoresSafeArea()

            // 扫描引导
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

            // 顶部状态栏
            VStack {
                topStatusBar
                Spacer()
            }

            // 底部控制栏
            VStack {
                Spacer()
                bottomControlBar
            }

            // 扫描完成 → 显示结果
            if showResult, let result = yieldResult {
                ResultView(treeID: treeID, result: result) {
                    presentationMode.wrappedValue.dismiss()
                }
            }

            // 正在估算
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
        .onAppear {
            // MetalView 内部会启动 ARSession，这里只需要启动渲染
        }
        .onDisappear {
            coordinator.teardown()
        }
    }

    // MARK: - 顶部状态栏
    private var topStatusBar: some View {
        HStack {
            VStack(alignment: .leading, spacing: 4) {
                Text("树 #\(treeID)")
                    .font(.headline)
                Text(gps.isAvailable
                     ? String(format: "%.5f, %.5f", gps.latitude, gps.longitude)
                     : "GPS不可用")
                    .font(.caption)
                    .foregroundColor(.white.opacity(0.7))
            }
            Spacer()
            VStack(alignment: .trailing, spacing: 4) {
                Text("\(coordinator.pointCount) 点")
                    .font(.headline.monospacedDigit())
                Circle()
                    .fill(isRecording ? Color.red : Color.green)
                    .frame(width: 10, height: 10)
                Text(isRecording ? "采集中" : "就绪")
                    .font(.caption)
            }
        }
        .padding()
        .background(Color.black.opacity(0.6))
    }

    // MARK: - 底部控制栏
    private var bottomControlBar: some View {
        HStack(spacing: 24) {
            Button(action: { showGuide.toggle() }) {
                Image(systemName: "questionmark.circle")
                    .font(.title)
            }
            .foregroundColor(.white)

            Button(action: toggleRecording) {
                Circle()
                    .fill(isRecording ? Color.red : Color.green)
                    .frame(width: 70, height: 70)
                    .overlay(
                        Circle().stroke(Color.white, lineWidth: 3)
                    )
            }

            Button(action: exportAndEstimate) {
                Image(systemName: "square.and.arrow.up")
                    .font(.title)
            }
            .foregroundColor(.white)
            .disabled(isRecording || coordinator.pointCount == 0)
        }
        .padding()
        .background(Color.black.opacity(0.6))
    }

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
        isEstimating = true
        coordinator.exportPLY(treeID: treeID, lat: gps.latitude, lon: gps.longitude) { filename in
            savedFilename = filename
            // 触发 iOS 端估算
            coordinator.runYieldEstimate(fruitType: fruitType, nVisual: nVisual, season: season) { result in
                isEstimating = false
                yieldResult = result
                showResult = true
            }
        }
    }
}

// MARK: - ScanCoordinator
class ScanCoordinator: NSObject, ObservableObject, TaskDelegate, ImageDetectorDelegate {
    var renderer: Renderer?
    var session: ARSession?
    weak var mtkView: MTKView?

    @Published var pointCount: Int = 0

    private var displayLink: CADisplayLink?
    private let estimator = YieldEstimator()

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
        PointCloudCluster(config: ClusterConfig(
            minPoints: 5,
            minDiameter: 0.04,
            maxDiameter: 0.15,
            baseEps: 0.1
        ))
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

    // 存储检测到的水果（用于事后融合）
    private var detectedFruits: [DetectedFruit] = []
    private let detectorLock = NSLock()

    func bind(session: ARSession, renderer: Renderer, mtkView: MTKView) {
        self.session = session
        self.renderer = renderer
        self.mtkView = mtkView
        renderer.delegate = self

        let config = ARWorldTrackingConfiguration()
        if ARWorldTrackingConfiguration.supportsFrameSemantics(.sceneDepth) {
            config.frameSemantics = .sceneDepth
        }
        session.run(config)

        // 注册帧回调用于图像检测
        session.delegate = self

        // 设置图像检测器的 delegate
        imageDetector.delegate = self

        // 启动定期处理队列的定时器
        startDetectionTimer()

        // 延迟设置 rgbRadius，等 session 初始化完成
        DispatchQueue.main.asyncAfter(deadline: .now() + 0.5) {
            self.renderer?.rgbRadius = 3.0
        }

        displayLink = CADisplayLink(target: self, selector: #selector(updatePointCount))
        displayLink?.add(to: .main, forMode: .common)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func teardown() {
        displayLink?.invalidate()
        displayLink = nil
        detectionTimer?.invalidate()
        detectionTimer = nil
        session?.pause()
        session?.delegate = nil
        renderer = nil
        session = nil
        detectedFruits.removeAll()
        UIApplication.shared.isIdleTimerDisabled = false
    }

    // MARK: - 图像检测定时器
    private var detectionTimer: Timer?

    private func startDetectionTimer() {
        // 每秒处理一次检测队列
        detectionTimer = Timer.scheduledTimer(withTimeInterval: 1.0, repeats: true) { [weak self] _ in
            self?.processDetectionQueue()
        }
    }

    private func processDetectionQueue() {
        Task { [weak self] in
            guard let self = self else { return }
            let detected = await self.imageDetector.processQueue()

            if !detected.isEmpty {
                print("📸 [ScanCoordinator] 检测到 \(detected.count) 个果实:")
                for fruit in detected {
                    print("      - \(fruit.category.displayName), 置信度: \(fruit.confidence), 边界框: \(fruit.boundingBox)")
                }
                self.detectorLock.lock()
                self.detectedFruits.append(contentsOf: detected)
                self.detectorLock.unlock()
            }
        }
    }

    func startRecording() {
        createDirectory(folder: "scans")
        renderer?.currentFolder = "scans"
        renderer?.isRecording = true
    }

    func stopRecording() {
        renderer?.isRecording = false
    }

    func exportPLY(treeID: String, lat: Double, lon: Double,
                   completion: @escaping (String) -> Void) {
        renderer?.savePointCloud(treeID: treeID, gpsLat: lat, gpsLon: lon)
        let filename = makeTreeFileName(treeID: treeID, lat: lat, lon: lon)
        completion(filename)
    }

    private func extractColoredPoints() -> [ColoredPoint] {
        guard let r = renderer else { return [] }
        var pts: [ColoredPoint] = []
        let count = r.currentPointCountPublic
        for i in 0 ..< count {
            let p = r.particlesBuffer[i]
            pts.append(ColoredPoint(
                pos: p.position,
                r: p.color.x, g: p.color.y, b: p.color.z
            ))
        }
        return pts
    }

    /// 多模态融合产量估算（新 pipeline）
    func runMultiModalYieldEstimate(
        fruitType: FruitType,
        nVisual: Int?,
        season: Season,
        completion: @escaping (YieldResult, FruitCountResult?) -> Void
    ) {
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }

            Task { [weak self] in
                guard let self = self else { return }

                let points = self.extractColoredPoints()
                print("🔍 [Fusion] 共有 \(points.count) 个点云点")

                // 取出并清空检测结果
                self.detectorLock.lock()
                let savedDetections = self.detectedFruits
                self.detectedFruits.removeAll()
                self.detectorLock.unlock()

                print("🔍 [Fusion] 图像检测结果: \(savedDetections.count) 个")

                // Step 1: 点云聚类
                let candidates = await self.pointCloudCluster.processInMemory(
                    position: points.map { $0.pos },
                    colors: points.map { SIMD3<Float>($0.r, $0.g, $0.b) }
                )
                print("🔍 [Fusion] 点云聚类候选: \(candidates.count) 个")

                // Step 2: 融合验证（如果有图像检测结果）
                var validatedFruits: [ValidatedFruit] = []
                if !savedDetections.isEmpty, let frame = self.session?.currentFrame {
                    // 从 ARFrame 获取相机参数
                    let depthMap = frame.sceneDepth?.depthMap
                    let cameraIntrinsics = frame.camera.intrinsics
                    let cameraTransform = frame.camera.transform
                    let imageSize = CGSize(
                        width: CGFloat(frame.camera.imageResolution.width),
                        height: CGFloat(frame.camera.imageResolution.height)
                    )

                    validatedFruits = self.fusionValidator.validate(
                        detections: savedDetections,
                        candidates: candidates,
                        depthMap: depthMap,
                        cameraIntrinsics: cameraIntrinsics,
                        cameraTransform: cameraTransform,
                        imageSize: imageSize
                    )
                } else {
                    // ⚠️ 重要：没有图像检测结果时，不应该只靠点云就判定为果实！
                    // cloudOnly 路径现在默认拒绝所有候选，除非满足非常严格的条件
                    print("🔍 [Fusion] ⚠️ 无图像检测，进入保守模式")
                    print("🔍 [Fusion] 点云候选数: \(candidates.count)")

                    // 只有当球形度非常高 (>0.8) 且颜色非常符合时才接受
                    // 这大大减少了误判（窗帘、台灯、桌面物品等）
                    var accepted = 0
                    for candidate in candidates {
                        // 严格条件：球形度 > 0.8 AND 颜色必须完全符合果实特征
                        if candidate.sphericity > 0.8 && candidate.hasFruitColor() {
                            // 只接受球形度非常高的（接近完美球体）
                            let fruit = ValidatedFruit(
                                category: nil,
                                position: candidate.position,
                                confidence: candidate.sphericity * 0.3,  // cloudOnly 权重很低
                                source: .cloudOnly
                            )
                            validatedFruits.append(fruit)
                            accepted += 1
                        }
                    }
                    print("🔍 [Fusion] cloudOnly 保守模式: \(candidates.count) 候选, 只接受 \(accepted) 个（需要 sphericity>0.8 且颜色符合）")
                }

                // Step 3: 计数
                print("🔍 [Fusion] 最终有效果实: \(validatedFruits.count) 个")
                let countResult = self.fruitCounter.count(validatedFruits)

                // Step 4: 只有当新 pipeline 找到果实时才输出结果
                // 新 pipeline 为 0 时直接返回 0，不使用旧算法（因为旧算法误判太多）
                var finalResult: YieldResult
                if countResult.totalCount > 0 {
                    // 新 pipeline 找到了果实，使用新结果
                    print("🔍 [Fusion] ✅ 使用新 pipeline 结果: \(countResult.totalCount) 个果实")

                    // 构建 YieldResult 从 countResult
                    var yr = YieldResult()
                    yr.nLidar = countResult.totalCount
                    yr.yieldFinalKg = Float(countResult.totalCount) * 0.2  // 粗估每个果实约 200g
                    yr.confidence = "medium"
                    yr.methodUsed = "fusion_only"
                    yr.note = "RGB+LiDAR 融合检测"
                    finalResult = yr
                } else {
                    // ⚠️ 关键修复：不要再用旧算法！直接输出 0
                    print("🔍 [Fusion] ⚠️ 新 pipeline 无检测，输出 0 kg（旧算法已禁用）")
                    print("🔍 [Fusion] 原因: 没有图像检测确认的果实不可信")

                    var yr = YieldResult()
                    yr.nLidar = 0
                    yr.yieldFinalKg = 0  // 直接设为 0！
                    yr.confidence = "low"
                    yr.methodUsed = "fusion_only"
                    yr.note = "⚠️ RGB+LiDAR 未检测到果实（图像检测未确认）"
                    finalResult = yr
                }

                await MainActor.run {
                    completion(finalResult, countResult)
                }
            }
        }
    }

    /// 原有产量估算（兼容模式）
    func runYieldEstimate(fruitType: FruitType,
                          nVisual: Int?,
                          season: Season,
                          completion: @escaping (YieldResult) -> Void) {
        runMultiModalYieldEstimate(fruitType: fruitType, nVisual: nVisual, season: season) { result, _ in
            completion(result)
        }
    }

    @objc private func updatePointCount() {
        pointCount = renderer?.currentPointCountPublic ?? 0
    }

    func didStartTask() {}
    func didFinishTask() {}

    // MARK: - ImageDetectorDelegate
    func imageDetector(_ detector: ImageDetector, didDetect fruits: [DetectedFruit]) {
        print("📸 [Delegate] 收到 \(fruits.count) 个检测结果")
        detectorLock.lock()
        detectedFruits.append(contentsOf: fruits)
        detectorLock.unlock()
    }
}

// MARK: - ARSessionDelegate（帧回调用于图像检测）
extension ScanCoordinator: ARSessionDelegate {
    func session(_ session: ARSession, didUpdate frame: ARFrame) {
        // 入队 RGB 帧用于图像检测（每 N 帧处理一次）
        imageDetector.enqueueFrame(frame.capturedImage, timestamp: frame.timestamp)
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
    @ObservedObject var coordinator: ScanCoordinator

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
        renderer.drawRectResized(size: UIScreen.main.bounds.size)

        // 关键：设置 MTKView 的 delegate，让渲染循环启动
        mtkView.delegate = renderer

        // 绑定到 Coordinator
        context.coordinator.coordinator?.bind(session: arSession, renderer: renderer, mtkView: mtkView)

        return mtkView
    }

    func updateUIView(_ uiView: MTKView, context: Context) {}
}

// MARK: - MetalViewCoordinator
class MetalViewCoordinator: NSObject {
    weak var coordinator: ScanCoordinator?

    init(coordinator: ScanCoordinator) {
        self.coordinator = coordinator
        super.init()
    }
}
