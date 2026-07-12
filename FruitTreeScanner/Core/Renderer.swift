// Renderer.swift
// 原始来源：ios-depth-point-cloud (Apple WWDC20 sample, MIT License)

import Metal
import MetalKit
import ARKit
import UIKit
import CoreVideo

final class Renderer: NSObject {
    // MARK: - 公开属性
    var shouldResetPointCloudOnRecordingStart = true

    public var isRecording = false {
        didSet {
            guard isRecording else {
                scanProgress.pause()
                return
            }
            if shouldResetPointCloudOnRecordingStart {
                resetPointCloudCapture()
            } else {
                scanProgress.resume()
            }
            shouldResetPointCloudOnRecordingStart = true
        }
    }
    public var currentFolder = ""

    // MARK: - 扫描时长和完成度追踪
    var scanProgress = RendererScanProgress()
    public var scanDuration: TimeInterval { scanProgress.scanDuration }

    var maxPoints: Int = 1000000

    @MainActor
    func applyScanQualitySettings() {
        let settings = RendererScanSettings(store: SettingsStore.shared, particleCapacity: particlesBuffer.count)
        maxPoints = settings.maxPoints
        pointCloudUniforms.maxPoints = Int32(maxPoints)
        rgbRadius = settings.rgbRadius
        minDepth = settings.minDepth
        maxDepth = settings.maxDepth
        snapshotVoxelSize = settings.snapshotVoxelSize
        confidenceThreshold = settings.confidenceThreshold
        depthEdgeThreshold = settings.depthEdgeThreshold
    }

    // MARK: - 私有属性
    let numGridPoints = 1_000
    private let particleSize: Float = 10
    var orientation = UIInterfaceOrientation.portrait
    static let cameraRotationThresholdDegrees: Float = 2
    static let cameraTranslationThresholdMeters: Float = 0.05
    static let cameraTranslationThresholdSquared: Float =
        cameraTranslationThresholdMeters * cameraTranslationThresholdMeters
    /// One frozen spatial resolution shared by final PLY export and yield analysis.
    /// Keeping this centralized guarantees that persisted scans can reproduce the
    /// point-cloud evidence used by the fusion pipeline.
    static let finalPointCloudVoxelSizeMeters: Float = 0.005
    let cameraRotationThreshold = cos(Renderer.cameraRotationThresholdDegrees * Float.degreesToRadian)
    let cameraTranslationThreshold: Float = Renderer.cameraTranslationThresholdSquared
    let maxInFlightBuffers = 3

    let session: ARSession
    let device: MTLDevice
    private let library: MTLLibrary
    let renderDestination: MTKView
    let relaxedStencilState: MTLDepthStencilState
    let depthStencilState: MTLDepthStencilState
    let commandQueue: MTLCommandQueue
    lazy var unprojectPipelineState = RendererMetalHelpers.makeUnprojectionPipelineState(
        library: library,
        renderDestination: renderDestination,
        device: device
    )!
    lazy var rgbPipelineState = RendererMetalHelpers.makeRGBPipelineState(
        library: library,
        renderDestination: renderDestination,
        device: device
    )!
    lazy var particlePipelineState = RendererMetalHelpers.makeParticlePipelineState(
        library: library,
        renderDestination: renderDestination,
        device: device
    )!
    lazy var textureCache = RendererMetalHelpers.makeTextureCache(device: device)
    var capturedImageTextureY: CVMetalTexture?
    var capturedImageTextureCbCr: CVMetalTexture?
    var depthTexture: CVMetalTexture?
    var confidenceTexture: CVMetalTexture?
    var hasReceivedFirstFrame = false
    let inFlightSemaphore: DispatchSemaphore
    var currentBufferIndex = 0
    var viewportSize = CGSize()
    lazy var gridPointsBuffer = MetalBuffer<Float2>(
        device: device,
        array: RendererMetalHelpers.makeGridPoints(
            cameraResolution: cameraResolution,
            numGridPoints: numGridPoints
        ),
        index: kGridPoints.rawValue,
        options: []
    )

    lazy var rgbUniforms: RGBUniforms = {
        var u = RGBUniforms()
        u.radius = rgbRadius
        u.viewToCamera = matrix_identity_float3x3
        u.viewRatio = 1
        return u
    }()
    var rgbUniformsBuffers = [MetalBuffer<RGBUniforms>]()
    lazy var pointCloudUniforms: PointCloudUniforms = {
        var u = PointCloudUniforms()
        u.maxPoints = Int32(maxPoints)
        u.confidenceThreshold = Int32(confidenceThreshold)
        u.particleSize = particleSize
        u.cameraResolution = cameraResolution
        u.minDepth = minDepth
        u.maxDepth = maxDepth
        u.depthEdgeThreshold = depthEdgeThreshold
        return u
    }()
    var pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
    public lazy var particlesBuffer: MetalBuffer<ParticleUniforms> = .init(device: device, count: maxPoints, index: kParticleUniforms.rawValue)
    var currentPointIndex = 0
    var currentPointCount = 0

    let snapshotLock = NSLock()
    let pointBufferLock = NSLock()
    var snapshotPoints: [ColoredPoint] = []
    var fullAnalysisSnapshotSignature: RendererSnapshotSignature?
    var lastSnapshotUpdateTime = Date.distantPast
    let baseSnapshotUpdateInterval: TimeInterval = 0.9
    let liveSnapshotInputSampleLimit = 240_000
    /// The final estimation path performs CPU KNN denoising and DBSCAN. Keep
    /// its input bounded on mobile hardware even when capture retains millions
    /// of raw points for display quality.
    let analysisInputSampleLimit = 120_000

    // MARK: - 体素网格去重（避免重复扫描）
    var scannedRegions: Set<RendererCameraRegionKey> = []  // 已扫描的区域（相机位置离散化）
    var coverageVoxels: Set<RendererVoxelKey> = []   // 实际深度点覆盖的世界空间体素
    let coverageVoxelSize: Float = 0.1    // 10cm 覆盖体素
    var minDepth: Float = 0.5 {
        didSet { pointCloudUniforms.minDepth = minDepth }
    }
    var maxDepth: Float = 5.0 {
        didSet { pointCloudUniforms.maxDepth = maxDepth }
    }
    var depthEdgeThreshold: Float = 0.10 {
        didSet { pointCloudUniforms.depthEdgeThreshold = depthEdgeThreshold }
    }
    var snapshotVoxelSize: Float = 0.015
    private var sampleFrame: ARFrame? {
        guard hasReceivedFirstFrame, let frame = session.currentFrame else { return nil }
        return frame
    }
    var cameraResolution = Float2(1920, 1080)
    lazy var lastCameraTransform: simd_float4x4 = {
        guard let frame = sampleFrame else { return matrix_identity_float4x4 }
        return frame.camera.transform
    }()

    var confidenceThreshold = 1 {
        didSet { pointCloudUniforms.confidenceThreshold = Int32(confidenceThreshold) }
    }
    var rgbRadius: Float = 3 {
        didSet { rgbUniforms.radius = rgbRadius }
    }

    // MARK: - GPU Compute Pipeline
    private(set) var computePipeline: MetalComputePipeline?

    // MARK: - Init
    init(session: ARSession, metalDevice device: MTLDevice,
         renderDestination: MTKView) {
        self.session = session
        self.device = device
        self.renderDestination = renderDestination
        maxPoints = SettingsStore.shared.maxPointCount
        // super.init() must be LAST: all let properties must be initialized before super.init()
        library = device.makeDefaultLibrary()!
        commandQueue = device.makeCommandQueue()!
        for _ in 0 ..< maxInFlightBuffers {
            rgbUniformsBuffers.append(.init(device: device, count: 1, index: 0))
            pointCloudUniformsBuffers.append(.init(device: device, count: 1,
                                                   index: kPointCloudUniforms.rawValue))
        }
        let relaxedDesc = MTLDepthStencilDescriptor()
        relaxedStencilState = device.makeDepthStencilState(descriptor: relaxedDesc)!
        let depthDesc = MTLDepthStencilDescriptor()
        depthDesc.depthCompareFunction = .lessEqual
        depthDesc.isDepthWriteEnabled = true
        depthStencilState = device.makeDepthStencilState(descriptor: depthDesc)!
        inFlightSemaphore = DispatchSemaphore(value: maxInFlightBuffers)
        super.init()
        computePipeline = MetalComputePipeline(device: device)
    }

}
