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
            // Metal 点云渲染视图
            MetalView(coordinator: coordinator)
                .ignoresSafeArea()

            // 绕树引导（4秒后消失）
            if showGuide {
                VStack {
                    Spacer()
                    Text("📍 请缓慢绕树走一圈（30~60秒）")
                        .font(.headline)
                        .padding()
                        .background(.ultraThinMaterial)
                        .cornerRadius(12)
                        .padding(.bottom, 120)
                }
                .transition(.opacity)
                .onAppear {
                    DispatchQueue.main.asyncAfter(deadline: .now() + 4) {
                        withAnimation { showGuide = false }
                    }
                }
            }

            // 顶部信息栏
            VStack {
                HStack {
                    Button {
                        coordinator.stopRecording()
                        presentationMode.wrappedValue.dismiss()
                    } label: {
                        Image(systemName: "chevron.left")
                            .font(.title2.bold())
                            .padding(10)
                            .background(.ultraThinMaterial)
                            .clipShape(Circle())
                    }
                    .padding(.leading, 20)

                    Spacer()

                    VStack(alignment: .trailing, spacing: 2) {
                        Text(treeID)
                            .font(.headline.bold())
                        Text("\(coordinator.pointCount) 点")
                            .font(.caption)
                            .foregroundColor(.secondary)
                    }
                    .padding(10)
                    .background(.ultraThinMaterial)
                    .cornerRadius(10)
                    .padding(.trailing, 20)
                }
                .padding(.top, 10)

                Spacer()

                // 底部控制栏
                HStack(spacing: 24) {
                    // 录制按钮
                    Button {
                        if isRecording {
                            coordinator.stopRecording()
                        } else {
                            coordinator.startRecording()
                        }
                        isRecording.toggle()
                    } label: {
                        ZStack {
                            Circle()
                                .fill(isRecording ? Color.red : Color.green)
                                .frame(width: 70, height: 70)
                            Image(systemName: isRecording ? "stop.fill" : "record.circle")
                                .font(.system(size: 28))
                                .foregroundColor(.white)
                        }
                    }

                    // 估算产量按钮（录制停止 + 有点云 才能用）
                    Button {
                        // 先导出 PLY
                        coordinator.exportPLY(treeID: treeID,
                                              lat: gps.latitude,
                                              lon: gps.longitude) { filename in
                            savedFilename = filename
                        }
                        // 跑产量估算
                        isEstimating = true
                        coordinator.runYieldEstimate(
                            fruitType: fruitType,
                            nVisual: nVisual,
                            season: season
                        ) { result in
                            yieldResult = result
                            isEstimating = false
                            showResult = true
                        }
                    } label: {
                        VStack(spacing: 4) {
                            if isEstimating {
                                ProgressView().tint(.white)
                            } else {
                                Image(systemName: "chart.bar.fill")
                                    .font(.title2)
                            }
                            Text(isEstimating ? "估算中..." : "估算产量")
                                .font(.caption.bold())
                        }
                        .padding(12)
                        .background((isRecording || coordinator.pointCount == 0 || isEstimating)
                                    ? Color.gray.opacity(0.5) : Color.blue)
                        .foregroundColor(.white)
                        .cornerRadius(12)
                    }
                    .disabled(isRecording || coordinator.pointCount == 0 || isEstimating)
                }
                .padding(.bottom, 40)
            }
        }
        // 结果页
        .sheet(isPresented: $showResult) {
            if let r = yieldResult {
                ResultView(treeID: treeID, result: r) {
                    showResult = false
                    presentationMode.wrappedValue.dismiss()
                }
            }
        }
        .onAppear { coordinator.setup() }
        .onDisappear { coordinator.teardown() }
    }
}

// MARK: - ScanCoordinator

class ScanCoordinator: NSObject, ObservableObject, TaskDelegate {
    var renderer: Renderer?
    var session: ARSession?
    var mtkView: MTKView?

    @Published var pointCount: Int = 0

    private var displayLink: CADisplayLink?
    private let estimator = YieldEstimator()

    func setup() {
        guard let device = MTLCreateSystemDefaultDevice() else { return }
        let arSession = ARSession()
        let r = Renderer(session: arSession, metalDevice: device,
                         renderDestination: MTKView())
        r.drawRectResized(size: UIScreen.main.bounds.size)
        r.delegate = self
        let config = ARWorldTrackingConfiguration()
        config.frameSemantics = [.sceneDepth, .smoothedSceneDepth]
        arSession.run(config)
        self.session = arSession
        self.renderer = r
        displayLink = CADisplayLink(target: self, selector: #selector(updatePointCount))
        displayLink?.add(to: .main, forMode: .common)
        UIApplication.shared.isIdleTimerDisabled = true
    }

    func teardown() {
        displayLink?.invalidate()
        session?.pause()
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
        let filename = makeTreeFileName(treeID: treeID, lat: lat, lon: lon)
        renderer?.savePointCloud(treeID: treeID, gpsLat: lat, gpsLon: lon)
        completion(filename)
    }

    /// 从当前点云粒子缓冲区提取 ColoredPoint 列表
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

    /// 产量估算（在后台线程跑，结果回主线程）
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
    func draw(in view: MTKView) { draw() }
}

// MARK: - MetalView
struct MetalView: UIViewRepresentable {
    let coordinator: ScanCoordinator
    func makeUIView(context: Context) -> MTKView {
        guard let device = MTLCreateSystemDefaultDevice() else { return MTKView() }
        let view = MTKView()
        view.device = device
        view.backgroundColor = .black
        view.depthStencilPixelFormat = .depth32Float
        view.contentScaleFactor = 1
        if let r = coordinator.renderer { view.delegate = r }
        coordinator.mtkView = view
        return view
    }
    func updateUIView(_ uiView: MTKView, context: Context) {}
}
