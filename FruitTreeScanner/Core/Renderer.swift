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

final class Renderer: NSObject {
    // MARK: - 公开属性
    public var isRecording = false
    public var currentFolder = ""
    public var pickFrames = 5
    public var currentFrameIndex = 0
    public weak var delegate: TaskDelegate?

    // MARK: - 关键改动：maxPoints 从 50万 → 200万
    // 原始：private let maxPoints = 500_000
    private let maxPoints = 2_000_000

    // MARK: - 私有属性（原始不改动）
    private let numGridPoints = 500
    private let particleSize: Float = 10
    private let orientation = UIInterfaceOrientation.landscapeRight
    private let cameraRotationThreshold = cos(2 * Float.degreesToRadian)
    private let cameraTranslationThreshold: Float = pow(0.02, 2)
    private let maxInFlightBuffers = 3

    private lazy var rotateToARCamera = Self.makeRotateToARCameraMatrix(orientation: orientation)
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
    private lazy var gridPointsBuffer = MetalBuffer<Float2>(device: device,
                                                            array: makeGridPoints(),
                                                            index: kGridPoints.rawValue, options: [])
    private lazy var rgbUniforms: RGBUniforms = {
        var u = RGBUniforms()
        u.radius = rgbRadius
        if let vtc = viewToCamera {
            u.viewToCamera.copy(from: vtc)
        }
        u.viewRatio = Float(viewportSize.width / viewportSize.height)
        return u
    }()
    private var rgbUniformsBuffers = [MetalBuffer<RGBUniforms>]()
    private lazy var pointCloudUniforms: PointCloudUniforms = {
        var u = PointCloudUniforms()
        u.maxPoints = Int32(maxPoints)
        u.confidenceThreshold = Int32(confidenceThreshold)
        u.particleSize = particleSize
        u.cameraResolution = cameraResolution ?? simd_float2(1920, 1080)
        return u
    }()
    private var pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
    public lazy var particlesBuffer: MetalBuffer<ParticleUniforms> = .init(device: device, count: maxPoints, index: kParticleUniforms.rawValue)
    private var currentPointIndex = 0
    private var currentPointCount = 0
    private var sampleFrame: ARFrame? {
        guard hasReceivedFirstFrame else { return nil }
        return session.currentFrame
    }
    private lazy var cameraResolution: Float2? = {
        guard let frame = sampleFrame else { return nil }
        return Float2(Float(frame.camera.imageResolution.width),
                      Float(frame.camera.imageResolution.height))
    }()
    private lazy var viewToCamera: CGAffineTransform? = {
        guard let frame = sampleFrame else { return nil }
        return frame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
    }()
    private lazy var lastCameraTransform: simd_float4x4? = {
        guard let frame = sampleFrame else { return nil }
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

    func drawRectResized(size: CGSize) { viewportSize = size }

    // MARK: - 当前点数（供 UI 显示）
    var currentPointCountPublic: Int { currentPointCount }

    // MARK: - Draw（原始不改动）
    func renderFrame() {
        guard let currentFrame = session.currentFrame,
              let renderDescriptor = renderDestination.currentRenderPassDescriptor,
              let commandBuffer = commandQueue.makeCommandBuffer(),
              let renderEncoder = commandBuffer.makeRenderCommandEncoder(descriptor: renderDescriptor)
        else { return }

        _ = inFlightSemaphore.wait(timeout: .distantFuture)
        commandBuffer.addCompletedHandler { [weak self] _ in
            self?.inFlightSemaphore.signal()
        }
        update(frame: currentFrame)
        updateCapturedImageTextures(frame: currentFrame)
        currentBufferIndex = (currentBufferIndex + 1) % maxInFlightBuffers
        pointCloudUniformsBuffers[currentBufferIndex][0] = pointCloudUniforms

        if shouldAccumulate(frame: currentFrame), updateDepthTextures(frame: currentFrame) {
            accumulatePoints(frame: currentFrame, commandBuffer: commandBuffer,
                             renderEncoder: renderEncoder)
        }

        if rgbUniforms.radius > 0 {
            var retaining = [capturedImageTextureY, capturedImageTextureCbCr]
            commandBuffer.addCompletedHandler { _ in retaining.removeAll() }
            rgbUniformsBuffers[currentBufferIndex][0] = rgbUniforms
            renderEncoder.setDepthStencilState(relaxedStencilState)
            renderEncoder.setRenderPipelineState(rgbPipelineState)
            renderEncoder.setVertexBuffer(rgbUniformsBuffers[currentBufferIndex])
            renderEncoder.setFragmentBuffer(rgbUniformsBuffers[currentBufferIndex])
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureY!),
                                             index: Int(kTextureY.rawValue))
            renderEncoder.setFragmentTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!),
                                             index: Int(kTextureCbCr.rawValue))
            renderEncoder.drawPrimitives(type: .triangleStrip, vertexStart: 0, vertexCount: 4)
        }

        renderEncoder.setDepthStencilState(depthStencilState)
        renderEncoder.setRenderPipelineState(particlePipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: currentPointCount)
        renderEncoder.endEncoding()
        commandBuffer.present(renderDestination.currentDrawable!)
        commandBuffer.commit()
    }

    // MARK: - PLY 导出（核心改动：加树木编号 + GPS 元数据）
    /// - Parameters:
    ///   - treeID: 树木编号，如 "T001"
    ///   - gpsLat: GPS 纬度
    ///   - gpsLon: GPS 经度
    func savePointCloud(treeID: String, gpsLat: Double, gpsLon: Double) {
        delegate?.didStartTask()
        let pointCount = currentPointCount
        // 深拷贝点云数据，避免异步访问竞争
        var pointsCopy = [(position: SIMD3<Float>, color: SIMD3<Float>)]()
        for i in 0 ..< pointCount {
            let p = particlesBuffer[i]
            pointsCopy.append((p.position, p.color))
        }

        Task(priority: .utility) {
            do {
                // ---- PLY Header（改动：加入果树元数据）----
                let scanDate = getTimeStr()
                var fileContent = ""
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
                fileContent = headers.joined(separator: "\r\n") + "\r\n"

                // ---- 点云数据（原始逻辑不变）----
                for (position, color) in pointsCopy {
                    let r = Int(color.x * 255.0)
                    let g = Int(color.y * 255.0)
                    let b = Int(color.z * 255.0)
                    fileContent += "\(position.x) \(position.y) \(position.z) \(r) \(g) \(b)\r\n"
                }

                // ---- 文件命名（改动：规范格式）----
                let filename = makeTreeFileName(treeID: treeID, lat: gpsLat, lon: gpsLon)
                try await saveFile(content: fileContent, filename: filename,
                                   folder: self.currentFolder)
                print("✅ PLY 保存成功: \(filename)，共 \(pointCount) 点")
                self.delegate?.didFinishTask()
            } catch {
                print("❌ PLY 保存失败: \(error.localizedDescription)")
            }
        }
    }

    // MARK: - 私有方法（原始不改动）

    private func update(frame: ARFrame) {
        hasReceivedFirstFrame = true
        let camera = frame.camera
        let viewMatrix = camera.viewMatrix(for: orientation)
        let projMatrix = camera.projectionMatrix(for: orientation, viewportSize: viewportSize,
                                                 zNear: 0.001, zFar: 0)
        pointCloudUniforms.viewProjectionMatrix = projMatrix * viewMatrix
        pointCloudUniforms.localToWorld = viewMatrix.inverse * rotateToARCamera
        pointCloudUniforms.cameraIntrinsicsInversed = camera.intrinsics.inverse
    }

    private func updateCapturedImageTextures(frame: ARFrame) {
        let pb = frame.capturedImage
        guard CVPixelBufferGetPlaneCount(pb) >= 2 else { return }
        capturedImageTextureY = makeTexture(fromPixelBuffer: pb, pixelFormat: .r8Unorm, planeIndex: 0)
        capturedImageTextureCbCr = makeTexture(fromPixelBuffer: pb, pixelFormat: .rg8Unorm, planeIndex: 1)
    }

    private func updateDepthTextures(frame: ARFrame) -> Bool {
        guard let depthMap = frame.sceneDepth?.depthMap,
              let confidenceMap = frame.sceneDepth?.confidenceMap else { return false }
        depthTexture = makeTexture(fromPixelBuffer: depthMap, pixelFormat: .r32Float, planeIndex: 0)
        confidenceTexture = makeTexture(fromPixelBuffer: confidenceMap, pixelFormat: .r8Uint, planeIndex: 0)
        return true
    }

    private func shouldAccumulate(frame: ARFrame) -> Bool {
        guard isRecording else { return false }
        let ct = frame.camera.transform
        let lastTransform = lastCameraTransform ?? simd_float4x4(1)
        return currentPointCount == 0
            || dot(ct.columns.2, lastTransform.columns.2) <= cameraRotationThreshold
            || distance_squared(ct.columns.3, lastTransform.columns.3) >= cameraTranslationThreshold
    }

    private func accumulatePoints(frame: ARFrame, commandBuffer: MTLCommandBuffer,
                                  renderEncoder: MTLRenderCommandEncoder) {
        pointCloudUniforms.pointCloudCurrentIndex = Int32(currentPointIndex)
        var retaining = [capturedImageTextureY, capturedImageTextureCbCr, depthTexture, confidenceTexture]
        commandBuffer.addCompletedHandler { _ in retaining.removeAll() }
        renderEncoder.setDepthStencilState(relaxedStencilState)
        renderEncoder.setRenderPipelineState(unprojectPipelineState)
        renderEncoder.setVertexBuffer(pointCloudUniformsBuffers[currentBufferIndex])
        renderEncoder.setVertexBuffer(particlesBuffer)
        renderEncoder.setVertexBuffer(gridPointsBuffer)
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(capturedImageTextureY!),
                                       index: Int(kTextureY.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(capturedImageTextureCbCr!),
                                       index: Int(kTextureCbCr.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(depthTexture!),
                                       index: Int(kTextureDepth.rawValue))
        renderEncoder.setVertexTexture(CVMetalTextureGetTexture(confidenceTexture!),
                                       index: Int(kTextureConfidence.rawValue))
        renderEncoder.drawPrimitives(type: .point, vertexStart: 0, vertexCount: gridPointsBuffer.count)
        currentPointIndex = (currentPointIndex + gridPointsBuffer.count) % maxPoints
        currentPointCount = min(currentPointCount + gridPointsBuffer.count, maxPoints)
        lastCameraTransform = frame.camera.transform
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
        let resolution = cameraResolution ?? Float2(1920, 1080)
        let area = resolution.x * resolution.y
        let spacing = sqrt(area / Float(numGridPoints))
        let dx = Int(round(resolution.x / spacing))
        let dy = Int(round(resolution.y / spacing))
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


