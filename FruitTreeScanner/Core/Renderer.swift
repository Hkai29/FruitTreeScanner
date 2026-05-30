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
                // 开始新扫描时清空区域记录
                scannedRegions.removeAll()
                currentPointIndex = 0
                currentPointCount = 0
            }
        }
    }
    public var currentFolder = ""
    public var pickFrames = 5
    public var currentFrameIndex = 0
    public weak var delegate: TaskDelegate?

    // MARK: - 关键改动：maxPoints 从 50万 → 200万（果树点云更大）
    // 原始：private let maxPoints = 500_000
    // 注意：实际点数上限由 SettingsStore.shared.maxPointCount 控制
    private var maxPoints: Int { SettingsStore.shared.maxPointCount }

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
    private lazy var viewToCameraMatrix: matrix_float3x3 = {
        let t = viewToCamera
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
    }()

    private lazy var rgbUniforms: RGBUniforms = {
        var u = RGBUniforms()
        u.radius = rgbRadius
        u.viewToCamera = viewToCameraMatrix
        u.viewRatio = Float(viewportSize.width / viewportSize.height)
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
        return u
    }()
    private var pointCloudUniformsBuffers = [MetalBuffer<PointCloudUniforms>]()
    public lazy var particlesBuffer: MetalBuffer<ParticleUniforms> = .init(device: device, count: maxPoints, index: kParticleUniforms.rawValue)
    private var currentPointIndex = 0
    private var currentPointCount = 0

    // MARK: - 体素网格去重（避免重复扫描）
    private let voxelSize: Float = 0.1  // 10cm 体素
    private var occupiedVoxels: Set<String> = []
    private var scannedRegions: Set<String> = []  // 已扫描的区域（相机位置离散化）
    private let minDepth: Float = 0.5   // 0.5m
    private let maxDepth: Float = 5.0   // 5.0m
    private var sampleFrame: ARFrame? {
        guard hasReceivedFirstFrame, let frame = session.currentFrame else { return nil }
        return frame
    }
    private lazy var cameraResolution: Float2 = {
        guard let frame = sampleFrame else { return Float2(1920, 1080) }
        return Float2(Float(frame.camera.imageResolution.width),
                      Float(frame.camera.imageResolution.height))
    }()
    private lazy var viewToCamera: CGAffineTransform = {
        guard let frame = sampleFrame else { return .identity }
        return frame.displayTransform(for: orientation, viewportSize: viewportSize).inverted()
    }()
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
    var scannedRegionCountPublic: Int { scannedRegions.count }

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
    ///   - completion: 保存完成后在主线程回调（成功时 filename 非空）
    func savePointCloud(treeID: String, gpsLat: Double, gpsLon: Double,
                        completion: @escaping (String?) -> Void = { _ in }) {
        delegate?.didStartTask()
        // 原子性捕获 pointCount 和 currentIdx，避免二者不同步
        let pointCount = currentPointCount
        let currentIdx = currentPointIndex
        // 同步深拷贝点云数据（环形缓冲区顺序），避免异步访问竞争和 GPU 覆写
        var pointsCopy = [(position: SIMD3<Float>, color: SIMD3<Float>)]()
        pointsCopy.reserveCapacity(pointCount)
        for i in 0 ..< pointCount {
            let bufferIndex = (currentIdx - pointCount + i + maxPoints) % maxPoints
            let p = particlesBuffer[bufferIndex]
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

        // 检查相机是否移动到新区域
        let cameraMoved = currentPointCount == 0
            || dot(ct.columns.2, lastCameraTransform.columns.2) <= cameraRotationThreshold
            || distance_squared(ct.columns.3, lastCameraTransform.columns.3) >= cameraTranslationThreshold

        guard cameraMoved else { return false }

        // 检查是否在有效深度范围内
        guard let depthMap = frame.sceneDepth?.depthMap else { return false }

        // 采样中心点深度（果树目标：0.5m - 5.0m）
        let depthWidth = CVPixelBufferGetWidth(depthMap)
        let depthHeight = CVPixelBufferGetHeight(depthMap)
        let centerX = depthWidth / 2
        let centerY = depthHeight / 2

        let centerDepth = sampleDepth(from: depthMap, x: centerX, y: centerY)
        guard centerDepth >= minDepth && centerDepth <= maxDepth else { return false }

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
    private func getCameraRegionKey(frame: ARFrame) -> String {
        let pos = frame.camera.transform.columns.3
        let forward = -frame.camera.transform.columns.2  // 相机前方向量
        let regionSize: Float = 0.1  // 10cm 网格
        let angleBin: Float = 0.3    // ~17° 朝向区间
        let x = Int(floor(pos.x / regionSize))
        let y = Int(floor(pos.y / regionSize))
        let z = Int(floor(pos.z / regionSize))
        let fx = Int(floor(forward.x / angleBin))
        let fy = Int(floor(forward.y / angleBin))
        let fz = Int(floor(forward.z / angleBin))
        return "\(x),\(y),\(z),\(fx),\(fy),\(fz)"
    }

    /// 从深度图采样单个点深度
    private func sampleDepth(from depthMap: CVPixelBuffer, x: Int, y: Int) -> Float {
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard x >= 0 && x < width && y >= 0 && y < height else { return 0 }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else { return 0 }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

        // ARKit sceneDepth 使用 Float32 格式
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let depth = floatBuffer[y * (bytesPerRow / MemoryLayout<Float>.size) + x]

        return depth
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


