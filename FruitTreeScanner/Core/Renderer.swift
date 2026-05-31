// Renderer.swift
// 原始来源：ios-depth-point-cloud (Apple WWDC20 sample, MIT License)
// 改动说明：
//   1. maxPoints: 500_000 → 2_000_000（果树点云更大）
//   2. savePointCloud() 新增 treeID / gpsLat / gpsLon 参数
//   3. PLY header 加入 tree_id / scan_date / gps_lat / gps_lon 注释
//   4. 文件名改为规范格式（makeTreeFileName）

import Metal
import MetalKit
import ARKit
import UIKit
import CoreVideo

final class Renderer: NSObject {
    // MARK: - 公开属性
    public var isRecording = false {
        didSet {
            if isRecording {
                scannedRegions.removeAll()
                currentPointIndex = 0
                currentPointCount = 0
                coverageVoxels.removeAll()
                scanStartTime = Date()
                voxelDiscoveryHistory.removeAll()
                lastVoxelCount = 0
                lastDiscoveryCheckTime = Date()
            }
        }
    }
    public var currentFolder = ""
    public var pickFrames = 5
    public var currentFrameIndex = 0
    public weak var delegate: TaskDelegate?

    // MARK: - 扫描时长和完成度追踪
    public private(set) var scanStartTime: Date = Date()
    public var scanDuration: TimeInterval { Date().timeIntervalSince(scanStartTime) }
    private var voxelDiscoveryHistory: [Int] = []
    private var lastVoxelCount: Int = 0
    private var lastDiscoveryCheckTime: Date = Date()
    private let discoveryCheckInterval: TimeInterval = 1.0
    public var voxelDiscoveryRate: Float {
        guard !voxelDiscoveryHistory.isEmpty else { return 0 }
        let sum = voxelDiscoveryHistory.reduce(0, +)
        return Float(sum) / Float(voxelDiscoveryHistory.count)
    }
    public var voxelDiscoveryTrend: VoxelDiscoveryTrend {
        guard voxelDiscoveryHistory.count >= 3 else { return .collecting }
        let recent = Array(voxelDiscoveryHistory.suffix(3))
        let avgRecent = recent.reduce(0, +) / 3
        let avgAll = voxelDiscoveryHistory.reduce(0, +) / voxelDiscoveryHistory.count
        if avgRecent < 5 { return .stable }
        if Float(avgRecent) < Float(avgAll) * 0.5 { return .decreasing }
        return .increasing
    }

    // MARK: - 关键改动：maxPoints 从 50万 → 200万（果树点云更大）
    // 原始：private let maxPoints = 500_000
    // 注意：实际点数上限由 SettingsStore.shared.maxPointCount 控制
    private var maxPoints: Int = 1000000

    @MainActor
    func updateMaxPointsFromSettings() {
        maxPoints = min(SettingsStore.shared.maxPointCount, particlesBuffer.count)
        pointCloudUniforms.maxPoints = Int32(maxPoints)
    }

    @MainActor
    func applyScanQualitySettings() {
        let store = SettingsStore.shared
        updateMaxPointsFromSettings()
        rgbRadius = Float(store.rgbRadius)
        minDepth = Float(store.depthRangeMin)
        maxDepth = Float(store.depthRangeMax)
        snapshotVoxelSize = Self.exportVoxelSize(
            scanPrecision: Float(store.scanPrecision),
            qualityPreset: store.qualityPreset
        )

        switch store.qualityPreset {
        case "高":
            confidenceThreshold = max(store.confidenceThreshold, 2)
            depthEdgeThreshold = 0.08
        case "低":
            confidenceThreshold = max(store.confidenceThreshold, 1)
            depthEdgeThreshold = 0.16
        default:
            confidenceThreshold = max(store.confidenceThreshold, 1)
            depthEdgeThreshold = 0.12
        }
    }

    private static func exportVoxelSize(scanPrecision: Float, qualityPreset: String) -> Float {
        let clamped = min(max(scanPrecision, 0.001), 0.05)
        switch qualityPreset {
        case "高":
            return max(clamped * 0.7, 0.001)
        case "低":
            return min(clamped * 1.5, 0.06)
        default:
            return clamped
        }
    }

    // MARK: - 私有属性（原始不改动）
    private let numGridPoints = 1_000
    private let particleSize: Float = 10
    private var orientation = UIInterfaceOrientation.portrait
    private let cameraRotationThreshold = cos(2 * Float.degreesToRadian)
    private let cameraTranslationThreshold: Float = pow(0.02, 2)
    private let maxInFlightBuffers = 3

    private let session: ARSession
    private let device: MTLDevice
    private let library: MTLLibrary
    private let renderDestination: MTKView
    private let relaxedStencilState: MTLDepthStencilState
    private let depthStencilState: MTLDepthStencilState
    private let commandQueue: MTLCommandQueue
    private lazy var unprojectPipelineState = makeUnprojectionPipelineState()!
    private lazy var rgbPipelineState = makeRGBPipelineState()!
    private lazy var particlePipelineState = makeParticlePipelineState()!
    private lazy var textureCache = makeTextureCache()
    private var capturedImageTextureY: CVMetalTexture?
    private var capturedImageTextureCbCr: CVMetalTexture?
    private var depthTexture: CVMetalTexture?
    private var confidenceTexture: CVMetalTexture?
    private var hasReceivedFirstFrame = false
    private let inFlightSemaphore: DispatchSemaphore
    private var currentBufferIndex = 0
    private var viewportSize = CGSize()
    private lazy var gridPointsBuffer = MetalBuffer<Float2>(
        device: device,
        array: makeGridPoints(),
        index: kGridPoints.rawValue,
        options: []
    )

    private func makeViewToCameraMatrix(frame: ARFrame) -> matrix_float3x3 {
        let t = frame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
        let a = Float(t.a)
        let b = Float(t.b)
        let c = Float(t.c)
        let d = Float(t.d)
        let tx = Float(t.tx)
        let ty = Float(t.ty)
        var result = matrix_float3x3()
        result[0] = simd_float3(a, b, 0)
        result[1] = simd_float3(c, d, 0)
        result[2] = simd_float3(tx, ty, 1)
        return result
    }

    private lazy var rgbUniforms: RGBUniforms = {
        var u = RGBUniforms()
        u.radius = rgbRadius
        u.viewToCamera = matrix_identity_float3x3
        u.viewRatio = 1
        return u
    }()
    private var rgbUniformsBuffers = [MetalBuffer<RGBUniforms>]()
    private lazy var pointCloudUniforms: PointCloudUniforms = {
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
    private var pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
    public lazy var particlesBuffer: MetalBuffer<ParticleUniforms> = .init(device: device, count: maxPoints, index: kParticleUniforms.rawValue)
    private var currentPointIndex = 0
    private var currentPointCount = 0

    private let snapshotLock = NSLock()
    private var snapshotPoints: [ColoredPoint] = []
    private var fullAnalysisSnapshotSignature: SnapshotSignature?
    private var lastSnapshotUpdateTime = Date.distantPast
    private let baseSnapshotUpdateInterval: TimeInterval = 0.9
    private let liveSnapshotInputSampleLimit = 240_000

    private struct SnapshotSignature: Equatable {
        let pointCount: Int
        let pointIndex: Int
        let voxelSize: Float
        let confidenceThreshold: Int
    }

    private struct PointSample {
        let position: SIMD3<Float>
        let color: SIMD3<Float>
        let confidence: Float
    }

    private struct VoxelKey: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }

    private struct CameraRegionKey: Hashable {
        let x: Int
        let y: Int
        let z: Int
        let forwardX: Int
        let forwardY: Int
        let forwardZ: Int
    }

    // MARK: - 体素网格去重（避免重复扫描）
    private var scannedRegions: Set<CameraRegionKey> = []  // 已扫描的区域（相机位置离散化）
    private var coverageVoxels: Set<VoxelKey> = []   // 实际深度点覆盖的世界空间体素
    private let coverageVoxelSize: Float = 0.1    // 10cm 覆盖体素
    private var minDepth: Float = 0.5 {
        didSet { pointCloudUniforms.minDepth = minDepth }
    }
    private var maxDepth: Float = 5.0 {
        didSet { pointCloudUniforms.maxDepth = maxDepth }
    }
    private var depthEdgeThreshold: Float = 0.10 {
        didSet { pointCloudUniforms.depthEdgeThreshold = depthEdgeThreshold }
    }
    private var snapshotVoxelSize: Float = 0.015
    private var sampleFrame: ARFrame? {
        guard hasReceivedFirstFrame, let frame = session.currentFrame else { return nil }
        return frame
    }
    private var cameraResolution = Float2(1920, 1080)
    private lazy var lastCameraTransform: simd_float4x4 = {
        guard let frame = sampleFrame else { return matrix_identity_float4x4 }
        return frame.camera.transform
    }()

    var confidenceThreshold = 1 {
        didSet { pointCloudUniforms.confidenceThreshold = Int32(confidenceThreshold) }
    }
    var rgbRadius: Float = 0 {
        didSet { rgbUniforms.radius = rgbRadius }
    }

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
    }

    func drawRectResized(size: CGSize) {
        guard size.width > 0, size.height > 0 else { return }
        viewportSize = size
        updateOrientation()
        rgbUniforms.viewRatio = Float(size.width / max(size.height, 1))
    }

    // MARK: - 当前点数（供 UI 显示）
    var currentPointCountPublic: Int { currentPointCount }
    var scannedRegionCountPublic: Int { scannedRegions.count }
    var coverageVoxelCount: Int { coverageVoxels.count }
    var voxelDiscoveryTrendPublic: VoxelDiscoveryTrend { voxelDiscoveryTrend }
    var voxelDiscoveryRatePublic: Float { voxelDiscoveryRate }

    // MARK: - 点云射线求交（测量功能）
    struct HitResult {
        let worldPosition: SIMD3<Float>
        let distance: Float
    }

    func hitTest(
        viewPoint: CGPoint,
        viewportSize: CGSize,
        viewMatrix: simd_float4x4,
        maxSamples: Int = 80_000
    ) -> HitResult? {
        let count = currentPointCount
        guard count > 0 else { return nil }

        let aspect: Float = Float(viewportSize.width / max(viewportSize.height, 1))
        let ndcX: Float = Float((viewPoint.x / viewportSize.width) * 2 - 1)
        let ndcY: Float = Float(1 - (viewPoint.y / viewportSize.height) * 2)
        let tanHalfFov: Float = Darwin.tan(Swift.Float.pi / 6)

        let localX = ndcX * tanHalfFov * aspect
        let localY = ndcY * tanHalfFov

        let localDir = simd_normalize(simd_float3(localX, localY, -1))
        let viewInverse = viewMatrix.inverse
        let worldDir4 = viewInverse * SIMD4<Float>(localDir.x, localDir.y, localDir.z, 0)
        let worldDir = simd_normalize(simd_float3(worldDir4.x, worldDir4.y, worldDir4.z))
        let worldOrigin = simd_float3(
            viewInverse.columns.3.x,
            viewInverse.columns.3.y,
            viewInverse.columns.3.z
        )

        var closestHit: HitResult?
        var closestDist2: Float = .infinity

        let maxDist: Float = 10.0
        let currentIdx = currentPointIndex
        let maxPts = maxPoints
        let clampedMaxSamples = max(maxSamples, 1)
        let sampleStep = max((count + clampedMaxSamples - 1) / clampedMaxSamples, 1)
        let hitRadius: Float = count > clampedMaxSamples ? 0.04 : 0.03

        var i = 0
        while i < count {
            let bufferIndex = (currentIdx - count + i + maxPts) % maxPts
            let p = particlesBuffer[bufferIndex]
            defer { i += sampleStep }
            guard isExportableParticle(p) else { continue }

            let toPoint = p.position - worldOrigin
            let t = simd_dot(toPoint, worldDir)
            guard t > 0 && t < maxDist else { continue }

            let closest = worldOrigin + worldDir * t
            let diff = p.position - closest
            let dist2 = simd_length_squared(diff)
            if dist2 < hitRadius * hitRadius && dist2 < closestDist2 {
                closestDist2 = dist2
                closestHit = HitResult(worldPosition: p.position, distance: t)
            }
        }

        return closestHit
    }

    func getSnapshotPoints() -> [ColoredPoint] {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotPoints
    }

    func makeAnalysisPoints() -> [ColoredPoint] {
        let signature = currentSnapshotSignature()
        if let cachedPoints = cachedAnalysisPoints(for: signature) {
            return cachedPoints
        }

        let samples = makeFilteredPointSamples(voxelSize: snapshotVoxelSize)
        let pts = makeColoredPoints(from: samples)
        storeSnapshot(points: pts, fullSignature: signature)

        return pts
    }

    var exportablePointCountPublic: Int {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotPoints.count
    }

    struct CameraMatrices {
        let projectionMatrix: simd_float4x4
        let viewMatrix: simd_float4x4
        let viewportSize: CGSize
    }

    func getCameraMatrices() -> CameraMatrices? {
        guard let frame = session.currentFrame else { return nil }
        updateOrientation()
        let projMatrix = frame.camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 0)
        let viewMatrix = frame.camera.viewMatrix(for: orientation)
        return CameraMatrices(projectionMatrix: projMatrix, viewMatrix: viewMatrix, viewportSize: viewportSize)
    }

    private func updateSnapshot() {
        let now = Date()
        guard now.timeIntervalSince(lastSnapshotUpdateTime) >= currentSnapshotUpdateInterval else { return }
        lastSnapshotUpdateTime = now

        let samples = makeFilteredPointSamples(
            voxelSize: snapshotVoxelSize,
            inputSampleLimit: liveSnapshotInputSampleLimit
        )
        guard !samples.isEmpty else { return }

        let pts = makeColoredPoints(from: samples)
        storeSnapshot(points: pts, fullSignature: nil)
    }

    private func cachedAnalysisPoints(for signature: SnapshotSignature) -> [ColoredPoint]? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        guard fullAnalysisSnapshotSignature == signature else { return nil }
        return snapshotPoints
    }

    private func currentSnapshotSignature() -> SnapshotSignature {
        SnapshotSignature(
            pointCount: currentPointCount,
            pointIndex: currentPointIndex,
            voxelSize: snapshotVoxelSize,
            confidenceThreshold: confidenceThreshold
        )
    }

    private func makeColoredPoints(from samples: [PointSample]) -> [ColoredPoint] {
        samples.map {
            ColoredPoint(pos: $0.position, r: $0.color.x, g: $0.color.y, b: $0.color.z)
        }
    }

    private func storeSnapshot(points: [ColoredPoint], fullSignature: SnapshotSignature?) {
        snapshotLock.lock()
        snapshotPoints = points
        fullAnalysisSnapshotSignature = fullSignature
        snapshotLock.unlock()
    }

    private var currentSnapshotUpdateInterval: TimeInterval {
        switch currentPointCount {
        case 0..<150_000:
            return baseSnapshotUpdateInterval
        case 150_000..<500_000:
            return 1.5
        default:
            return 2.5
        }
    }

    private func makeFilteredPointSamples(
        voxelSize: Float,
        inputSampleLimit: Int? = nil
    ) -> [PointSample] {
        let count = currentPointCount
        guard count > 0 else { return [] }

        let currentIdx = currentPointIndex
        let maxPts = maxPoints
        let sampleStep = inputSampleLimit.map { limit in
            let clampedLimit = max(limit, 1)
            return max((count + clampedLimit - 1) / clampedLimit, 1)
        } ?? 1
        var bestSamplesByVoxel: [VoxelKey: PointSample] = [:]
        bestSamplesByVoxel.reserveCapacity(min(count / sampleStep, 200_000))

        var i = 0
        while i < count {
            let bufferIndex = (currentIdx - count + i + maxPts) % maxPts
            let particle = particlesBuffer[bufferIndex]
            defer { i += sampleStep }
            guard isExportableParticle(particle) else { continue }

            let key = voxelKey(for: particle.position, size: voxelSize)
            let sample = PointSample(
                position: particle.position,
                color: clampColor(particle.color),
                confidence: particle.confidence
            )
            if let existing = bestSamplesByVoxel[key], existing.confidence >= sample.confidence {
                continue
            }
            bestSamplesByVoxel[key] = sample
        }

        return Array(bestSamplesByVoxel.values)
    }

    private func isExportableParticle(_ particle: ParticleUniforms) -> Bool {
        guard particle.confidence >= Float(confidenceThreshold) else { return false }
        let position = particle.position
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return false }
        guard simd_length_squared(position) > 0.000001 else { return false }
        let color = particle.color
        return color.x.isFinite && color.y.isFinite && color.z.isFinite
    }

    private func voxelKey(for position: SIMD3<Float>, size: Float) -> VoxelKey {
        let vx = Int(floor(position.x / size))
        let vy = Int(floor(position.y / size))
        let vz = Int(floor(position.z / size))
        return VoxelKey(x: vx, y: vy, z: vz)
    }

    private func clampColor(_ color: SIMD3<Float>) -> SIMD3<Float> {
        SIMD3<Float>(
            min(max(color.x, 0), 1),
            min(max(color.y, 0), 1),
            min(max(color.z, 0), 1)
        )
    }

    // MARK: - Draw（原始不改动）
    func renderFrame() {
        guard let currentFrame = session.currentFrame,
              let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let drawable = renderDestination.currentDrawable
        else { return }

        guard inFlightSemaphore.wait(timeout: .now() + .milliseconds(16)) == .success else {
            return
        }

        guard let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor)
        else {
            inFlightSemaphore.signal()
            return
        }

        commandBuffer.addCompletedHandler { [weak self] _ in
            guard let self else { return }
            self.inFlightSemaphore.signal()
            if self.isRecording {
                self.updateSnapshot()
            }
        }
        update(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms

        if shouldAccumulate(frame: currentFrame), updateDepthTextures(frame: currentFrame) {
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer,
                             renderEncoder: renderEncoder)
        }

        if rgbUniforms.radius > 0, let texY = capturedImageTextureY, let texCbCr = capturedImageTextureCbCr {
            var retaining = [capturedImageTextureY, capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler { _ in retaining.removeAll() }
            rgbUniformsBuffers[currentBufferIndex][0] = rgbUniforms
            renderEncoder.setDepthStencilState(relaxedStencilState)
            renderEncoder.setRenderPipelineState(rgbPipelineState)
            renderEncoder.setVertexBuffer(rgbUniformsBuffers[currentBufferIndex])
            renderEncoder.setFragmentBuffer(rgbUniformsBuffers[currentBufferIndex])
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(texY),
                                             index: Int(kTextureY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(texCbCr),
                                             index: Int(kTextureCbCr.rawValue))
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setRenderPipelineState(particlePipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentPointCount)
        renderEncoder.endEncoding()
        commandBuffer.present(drawable)
        commandBuffer.commit()
    }

    // MARK: - PLY 导出（核心改动：加树木编号 + GPS 元数据）
    /// - Parameters:
    ///   - treeID: 树木编号，如 "T001"
    ///   - gpsLat: GPS 纬度
    ///   - gpsLon: GPS 经度
    ///   - completion: 保存完成后在主线程回调（成功时 filename 非空）
    func savePointCloud(treeID: String, gpsLat: Double, gpsLon: Double,
                        completion: @escaping (String?) -> Void = { _ in }) {
        delegate?.didStartTask()

        Task(priority: .utility) {
            let pointsCopy = makeFilteredPointSamples(voxelSize: snapshotVoxelSize)
            guard !pointsCopy.isEmpty else {
                await MainActor.run {
                    self.delegate?.didFinishTask()
                    completion(nil)
                }
                return
            }
            let analysisPoints = makeColoredPoints(from: pointsCopy)
            let analysisSignature = currentSnapshotSignature()
            storeSnapshot(points: analysisPoints, fullSignature: analysisSignature)

            do {
                let scanDate = getTimeStr()
                let pointCount = pointsCopy.count
                let headers = [
                    "ply",
                    "format ascii 1.0",
                    "comment tree_id \(treeID)",
                    "comment scan_date \(scanDate)",
                    "comment gps_lat \(String(format: "%.6f", gpsLat))",
                    "comment gps_lon \(String(format: "%.6f", gpsLon))",
                    "element vertex \(pointCount)",
                    "property float x",
                    "property float y",
                    "property float z",
                    "property uchar red",
                    "property uchar green",
                    "property uchar blue",
                    "element face 0",
                    "property list uchar int vertex_indices",
                    "end_header"
                ]

                var data = Data()
                data.reserveCapacity(pointCount * 35)
                data.append(contentsOf: headers.joined(separator: "\r\n").utf8)
                data.append(contentsOf: "\r\n".utf8)

                for sample in pointsCopy {
                    let position = sample.position
                    let color = sample.color
                    let r = Int(color.x * 255.0)
                    let g = Int(color.y * 255.0)
                    let b = Int(color.z * 255.0)
                    let line = String(format: "%.4f %.4f %.4f %d %d %d\r\n",
                                      position.x, position.y, position.z, r, g, b)
                    data.append(contentsOf: line.utf8)
                }

                let filename = makeTreeFileName(treeID: treeID, lat: gpsLat, lon: gpsLon)
                try await saveFile(data: data, filename: filename,
                                   folder: self.currentFolder)
                #if DEBUG
                print("✅ PLY 保存成功: \(filename)，共 \(pointCount) 点")
                #endif
                await MainActor.run { completion(filename) }
            } catch {
                #if DEBUG
                print("❌ PLY 保存失败: \(error.localizedDescription)")
                #endif
                await MainActor.run { completion(nil) }
            }
            await MainActor.run { self.delegate?.didFinishTask() }
        }
    }

    // MARK: - 私有方法（原始不改动）

    private func update(frame: ARFrame) {
        hasReceivedFirstFrame = true
        updateOrientation()
        updateCameraResolutionIfNeeded(frame: frame)

        let camera = frame.camera
        let viewMatrix = camera.viewMatrix(for: orientation)
        let projMatrix = camera.projectionMatrix(for: orientation, viewportSize: viewportSize,
                                                 zNear: 0.001, zFar: 0)
        pointCloudUniforms.viewProjectionMatrix = projMatrix * viewMatrix
        pointCloudUniforms.localToWorld = viewMatrix.inverse * Self.makeRotateToARCameraMatrix(orientation: orientation)
        pointCloudUniforms.cameraIntrinsicsInversed = camera.intrinsics.inverse
        rgbUniforms.viewToCamera = makeViewToCameraMatrix(frame: frame)
        rgbUniforms.viewRatio = Float(viewportSize.width / max(viewportSize.height, 1))
    }

    private func updateOrientation() {
        let sceneOrientation = renderDestination.window?.windowScene?.interfaceOrientation
        let nextOrientation: UIInterfaceOrientation

        if let sceneOrientation, sceneOrientation != .unknown {
            nextOrientation = sceneOrientation
        } else if viewportSize.width > viewportSize.height {
            nextOrientation = .landscapeRight
        } else {
            nextOrientation = .portrait
        }

        orientation = nextOrientation
    }

    private func updateCameraResolutionIfNeeded(frame: ARFrame) {
        let nextResolution = Float2(
            Float(frame.camera.imageResolution.width),
            Float(frame.camera.imageResolution.height)
        )

        guard abs(nextResolution.x - cameraResolution.x) > 0.5 ||
              abs(nextResolution.y - cameraResolution.y) > 0.5 else {
            return
        }

        cameraResolution = nextResolution
        pointCloudUniforms.cameraResolution = cameraResolution
        gridPointsBuffer = MetalBuffer<Float2>(
            device: device,
            array: makeGridPoints(),
            index: kGridPoints.rawValue,
            options: []
        )
    }

    private func updateCapturedImageTextures(frame: ARFrame) {
        let pb = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pb) >= 2 else { return }
        capturedImageTextureY = makeTexture(fromPixelBuffer: pb, pixelFormat: .r8Unorm, planeIndex: 0)
        capturedImageTextureCbCr = makeTexture(fromPixelBuffer: pb, pixelFormat: .rg8Unorm, planeIndex: 1)
    }

    private func updateDepthTextures(frame: ARFrame) -> Bool {
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthMap = depthData?.depthMap,
              let confidenceMap = depthData?.confidenceMap else { return false }
        depthTexture = makeTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
        confidenceTexture = makeTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        return true
    }

    private func shouldAccumulate(frame: ARFrame) -> Bool {
        guard isRecording else { return false }
        let ct = frame.camera.transform

        // 检查相机是否移动到新区域
        let cameraMoved = currentPointCount == 0
            || dot(ct.columns.2, lastCameraTransform.columns.2) <= cameraRotationThreshold
            || distance_squared(ct.columns.3, lastCameraTransform.columns.3) >= cameraTranslationThreshold

        guard cameraMoved else { return false }

        // 检查是否在有效深度范围内，并过滤低置信深度，避免消费级 LiDAR 的边缘噪声污染点云。
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthMap = depthData?.depthMap,
              let confidenceMap = depthData?.confidenceMap else { return false }

        let depthQuality = sampleDepthQuality(from: depthMap, confidenceMap: confidenceMap)
        guard depthQuality.validRatio >= minimumDepthQualityRatio else { return false }
        guard depthQuality.medianDepth >= minDepth && depthQuality.medianDepth <= maxDepth else { return false }

        // 检查相机位置区域是否已扫描（避免回看已扫描区域）
        // 使用更细的 10cm 网格（原 20cm 太粗糙，导致扫描一棵树很快就填满）
        // 只有当相机完全回到同一区域且点数已经很多时，才跳过累积
        let cameraRegion = getCameraRegionKey(frame: frame)
        if scannedRegions.contains(cameraRegion) && currentPointCount > 5000 {
            // 相机回到已扫描区域且已有足够点数，不累积新点
            return false
        }
        scannedRegions.insert(cameraRegion)

        return true
    }

    /// 获取相机位置+朝向的区域键（离散化到 10cm 网格 + ~17° 朝向区间）
    /// 加入朝向维度后，站在同一位置旋转扫不同方向不会被误判为重复区域
    private func getCameraRegionKey(frame: ARFrame) -> CameraRegionKey {
        let pos = frame.camera.transform.columns.3
        let forward = -frame.camera.transform.columns.2  // 相机前方向量
        let regionSize: Float = 0.1  // 10cm 网格
        let angleBin: Float = 0.3    // ~17° 朝向区间
        return CameraRegionKey(
            x: Int(floor(pos.x / regionSize)),
            y: Int(floor(pos.y / regionSize)),
            z: Int(floor(pos.z / regionSize)),
            forwardX: Int(floor(forward.x / angleBin)),
            forwardY: Int(floor(forward.y / angleBin)),
            forwardZ: Int(floor(forward.z / angleBin))
        )
    }

    private var minimumDepthQualityRatio: Float {
        confidenceThreshold >= 2 ? 0.22 : 0.30
    }

    private func sampleDepthQuality(
        from depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer
    ) -> (validRatio: Float, medianDepth: Float) {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else { return (0, 0) }
        let confidenceWidth = CVPixelBufferGetWidth(confidenceMap)
        let confidenceHeight = CVPixelBufferGetHeight(confidenceMap)
        guard confidenceWidth > 0, confidenceHeight > 0 else { return (0, 0) }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap),
              let confidenceBaseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else { return (0, 0) }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let stride = bytesPerRow / MemoryLayout<Float>.size
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        let confidenceBuffer = confidenceBaseAddress.assumingMemoryBound(to: UInt8.self)

        var validDepths: [Float] = []
        let sampleCount = 49
        validDepths.reserveCapacity(sampleCount)

        for row in 0..<7 {
            let ratioY = 0.18 + Float(row) * 0.106
            let y = Int(Float(height - 1) * ratioY)
            let confidenceY = min(Int(Float(confidenceHeight - 1) * ratioY), confidenceHeight - 1)
            for col in 0..<7 {
                let ratioX = 0.18 + Float(col) * 0.106
                let x = Int(Float(width - 1) * ratioX)
                let confidenceX = min(Int(Float(confidenceWidth - 1) * ratioX), confidenceWidth - 1)
                let depth = floatBuffer[y * stride + x]
                let confidence = confidenceBuffer[confidenceY * confidenceBytesPerRow + confidenceX]
                if depth >= minDepth,
                   depth <= maxDepth,
                   depth.isFinite,
                   confidence >= UInt8(confidenceThreshold) {
                    validDepths.append(depth)
                }
            }
        }

        guard !validDepths.isEmpty else { return (0, 0) }
        validDepths.sort()
        let ratio = Float(validDepths.count) / Float(sampleCount)
        let median = validDepths[validDepths.count / 2]
        return (ratio, median)
    }

    private func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer,
                                  renderEncoder: MTLRenderCommandEncoder) {
        guard let texY = capturedImageTextureY,
              let texCbCr = capturedImageTextureCbCr,
              let texDepth = depthTexture,
              let texConf = confidenceTexture else { return }

        pointCloudUniforms.pointCloudCurrentIndex = Int32(currentPointIndex)
        var retaining = [capturedImageTextureY, capturedImageTextureCbCr, depthTexture, confidenceTexture]
        commandBuffer.addCompletedHandler { _ in retaining.removeAll() }
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(unprojectPipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.setVertexBuffer(gridPointsBuffer)
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(texY),
                                       index: Int(kTextureY.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(texCbCr),
                                       index: Int(kTextureCbCr.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(texDepth),
                                       index: Int(kTextureDepth.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(texConf),
                                       index: Int(kTextureConfidence.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
        currentPointIndex = (currentPointIndex + gridPointsBuffer.count) % maxPoints
        currentPointCount = min(currentPointCount + gridPointsBuffer.count, maxPoints)
        lastCameraTransform = frame.camera.transform
        updateCoverageVoxels(frame: frame)
    }

    private func updateCoverageVoxels(frame: ARFrame) {
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthMap = depthData?.depthMap,
              let confidenceMap = depthData?.confidenceMap else { return }
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let confidenceWidth = CVPixelBufferGetWidth(confidenceMap)
        let confidenceHeight = CVPixelBufferGetHeight(confidenceMap)

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap),
              let confidenceBaseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else { return }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        let confidenceBuffer = confidenceBaseAddress.assumingMemoryBound(to: UInt8.self)

        let sampleStep = 4
        var newVoxels: Set<VoxelKey> = []
        let vs = coverageVoxelSize

        let projMatrix = frame.camera.projectionMatrix(for: orientation, viewportSize: viewportSize, zNear: 0.001, zFar: 0)
        let viewMatrix = frame.camera.viewMatrix(for: orientation)
        let vpInverse = (projMatrix * viewMatrix).inverse

        for gy in stride(from: 0, to: depthHeight, by: sampleStep) {
            for gx in stride(from: 0, to: depthWidth, by: sampleStep) {
                let depth = floatBuffer[gy * (bytesPerRow / 4) + gx]
                guard depth >= minDepth && depth <= maxDepth else { continue }
                let confidenceX = min(gx * confidenceWidth / max(depthWidth, 1), confidenceWidth - 1)
                let confidenceY = min(gy * confidenceHeight / max(depthHeight, 1), confidenceHeight - 1)
                let confidence = confidenceBuffer[confidenceY * confidenceBytesPerRow + confidenceX]
                guard confidence >= UInt8(confidenceThreshold) else { continue }

                let fx = Float(gx) / Float(depthWidth) * 2 - 1
                let fy = Float(gy) / Float(depthHeight) * 2 - 1

                let clipPos = simd_float4(fx * depth, fy * depth, -depth, 1)
                var worldPos = vpInverse * clipPos
                worldPos /= worldPos.w

                let key = VoxelKey(
                    x: Int(floor(worldPos.x / vs)),
                    y: Int(floor(worldPos.y / vs)),
                    z: Int(floor(worldPos.z / vs))
                )
                newVoxels.insert(key)
            }
        }

        if coverageVoxels.isEmpty {
            coverageVoxels = newVoxels
        } else {
            coverageVoxels.formUnion(newVoxels)
        }

        updateVoxelDiscoveryTracking()
    }

    private func updateVoxelDiscoveryTracking() {
        let now = Date()
        guard now.timeIntervalSince(lastDiscoveryCheckTime) >= discoveryCheckInterval else { return }

        let currentCount = coverageVoxels.count
        let discovered = currentCount - lastVoxelCount
        voxelDiscoveryHistory.append(discovered)

        if voxelDiscoveryHistory.count > 10 {
            voxelDiscoveryHistory.removeFirst()
        }

        lastVoxelCount = currentCount
        lastDiscoveryCheckTime = now
    }
}

// MARK: - Metal Pipeline Helpers（原始不改动）
private extension Renderer {
    func makeUnprojectionPipelineState() -> MTLRenderPipelineState? {
        guard let vf = library.makeFunction(name: "unprojectVertex") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vf
        desc.isRasterizationEnabled = false
        desc.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        desc.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    func makeRGBPipelineState() -> MTLRenderPipelineState? {
        guard let vf = library.makeFunction(name: "rgbVertex"),
              let ff = library.makeFunction(name: "rgbFragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vf; desc.fragmentFunction = ff
        desc.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        desc.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    func makeParticlePipelineState() -> MTLRenderPipelineState? {
        guard let vf = library.makeFunction(name: "particleVertex"),
              let ff = library.makeFunction(name: "particleFragment") else { return nil }
        let desc = MTLRenderPipelineDescriptor()
        desc.vertexFunction = vf; desc.fragmentFunction = ff
        desc.depthAttachmentPixelFormat = renderDestination.depthStencilPixelFormat
        desc.colorAttachments[0].pixelFormat = renderDestination.colorPixelFormat
        desc.colorAttachments[0].isBlendingEnabled = true
        desc.colorAttachments[0].sourceRGBBlendFactor = .sourceAlpha
        desc.colorAttachments[0].destinationRGBBlendFactor = .oneMinusSourceAlpha
        desc.colorAttachments[0].destinationAlphaBlendFactor = .oneMinusSourceAlpha
        return try? device.makeRenderPipelineState(descriptor: desc)
    }

    func makeGridPoints() -> [Float2] {
        let area = cameraResolution.x * cameraResolution.y
        let spacing = sqrt(area / Float(numGridPoints))
        let dx = Int(round(cameraResolution.x / spacing))
        let dy = Int(round(cameraResolution.y / spacing))
        var pts = [Float2]()
        for gy in 0 ..< dy {
            let offX = Float(gy % 2) * spacing / 2
            for gx in 0 ..< dx {
                pts.append(Float2(offX + (Float(gx) + 0.5) * spacing,
                                  (Float(gy) + 0.5) * spacing))
            }
        }
        return pts
    }

    func makeTextureCache() -> CVMetalTextureCache {
        var cache: CVMetalTextureCache!
        CVMetalTextureCacheCreate(nil, nil, device, nil, &cache)
        return cache
    }

    func makeTexture(fromPixelBuffer pb: CVPixelBuffer,
                     pixelFormat: MTLPixelFormat, planeIndex: Int) -> CVMetalTexture? {
        let w = CVPixelBufferGetWidthOfPlane(pb, planeIndex)
        let h = CVPixelBufferGetHeightOfPlane(pb, planeIndex)
        var tex: CVMetalTexture?
        CVMetalTextureCacheCreateTextureFromImage(nil, textureCache, pb, nil,
                                                  pixelFormat, w, h, planeIndex, &tex)
        return tex
    }

    static func cameraToDisplayRotation(orientation: UIInterfaceOrientation) -> Int {
        switch orientation {
        case .landscapeLeft: return 180
        case .portrait: return 90
        case .portraitUpsideDown: return -90
        default: return 0
        }
    }

    static func makeRotateToARCameraMatrix(orientation: UIInterfaceOrientation) -> matrix_float4x4 {
        let flipYZ = matrix_float4x4([1,0,0,0],[0,-1,0,0],[0,0,-1,0],[0,0,0,1])
        let angle = Float(cameraToDisplayRotation(orientation: orientation)) * Float.degreesToRadian
        return flipYZ * matrix_float4x4(simd_quaternion(angle, Float3(0, 0, 1)))
    }
}
