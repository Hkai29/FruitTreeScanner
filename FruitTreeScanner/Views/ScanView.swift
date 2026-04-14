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
                ResultView(result: result, treeID: treeID) {
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
                Text(gps.statusText)
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
class ScanCoordinator: NSObject, ObservableObject, TaskDelegate {
    var renderer: Renderer?
    var session: ARSession?
    weak var mtkView: MTKView?

    @Published var pointCount: Int = 0

    private var displayLink: CADisplayLink?
    private let estimator = YieldEstimator()

    func bind(session: ARSession, renderer: Renderer, mtkView: MTKView) {
        self.session = session
        self.renderer = renderer
        self.mtkView = mtkView
        renderer.delegate = self

        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        session.run(config)

        displayLink = CADisplayLink(target: self, selector: #selector(updatePointCount))
        displayLink?.add(to: .main, forMode: .common)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func teardown() {
        displayLink?.invalidate()
        displayLink = nil
        session?.pause()
        renderer = nil
        session = nil
        UIApplication.shared.isIdleTimerDisabled = false
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

    func runYieldEstimate(fruitType: FruitType,
                          nVisual: Int?,
                          season: Season,
                          completion: @escaping (YieldResult) -> Void) {
        let points = extractColoredPoints()
        DispatchQueue.global(qos: .userInitiated).async { [weak self] in
            guard let self = self else { return }
            let (_, result) = self.estimator.run(
                points: points,
                fruitType: fruitType,
                nVisual: nVisual,
                season: season
            )
            DispatchQueue.main.async { completion(result) }
        }
    }

    @objc private func updatePointCount() {
        pointCount = renderer?.currentPointCountPublic ?? 0
    }

    func didStartTask() {}
    func didFinishTask() {}
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

        // 绑定到 Coordinator
        context.coordinator.coordinator.bind(session: arSession, renderer: renderer, mtkView: mtkView)

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
