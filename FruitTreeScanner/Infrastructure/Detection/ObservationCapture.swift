import CoreGraphics
import Foundation
@preconcurrency import CoreVideo
import simd

private final class DepthSampler {
    // ARConfidenceLevelLow is 0, medium is 1, high is 2 in the SDK enum.
    private let minimumReliableConfidence: UInt8

    let width: Int
    let height: Int

    private let depthMap: CVPixelBuffer
    private let confidenceSampler: DepthConfidenceSampler?
    private let baseAddress: UnsafeMutableRawPointer
    private let pixelFormat: FourCharCode

    /// 在采样器生命周期内锁定像素缓冲区，避免每个采样点重复加锁。
    init?(depthMap: CVPixelBuffer, confidenceMap: CVPixelBuffer? = nil, configuration: DepthExperimentConfig) {
        minimumReliableConfidence = configuration.reliableConfidence
        if let confidenceMap {
            guard let confidenceSampler = DepthConfidenceSampler(confidenceMap: confidenceMap) else {
                return nil
            }
            self.confidenceSampler = confidenceSampler
        } else {
            self.confidenceSampler = nil
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
            return nil
        }

        self.depthMap = depthMap
        self.baseAddress = baseAddress
        self.width = CVPixelBufferGetWidth(depthMap)
        self.height = CVPixelBufferGetHeight(depthMap)
        self.pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
    }

    deinit {
        CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
    }

    func depth(x: Int, y: Int) -> Float? {
        guard width > 0, height > 0 else { return nil }

        let clampedX = max(0, min(x, width - 1))
        let clampedY = max(0, min(y, height - 1))
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        // 有 confidenceMap 时，低置信度像素在读取深度值前直接拒绝。
        if let confidenceSampler,
           !confidenceSampler.isReliable(
               x: clampedX,
               y: clampedY,
               depthWidth: width,
               depthHeight: height,
               minimumConfidence: minimumReliableConfidence
           ) {
            return nil
        }

        let fp32: FourCharCode = 0x66703233 // 'fp32' legacy/custom float map
        let depthFloat32 = kCVPixelFormatType_DepthFloat32
        let oneComponentFloat32 = kCVPixelFormatType_OneComponent32Float
        let depthFloat16 = kCVPixelFormatType_DepthFloat16
        let oneComponentFloat16 = kCVPixelFormatType_OneComponent16Half
        let up16: FourCharCode = 0x75703136 // 'up16' = kCVPixelFormatType_16U
        let depth: Float

        // 兼容 ARKit 深度图以及导入或测试路径使用的常见浮点和毫米格式。
        if pixelFormat == fp32 || pixelFormat == depthFloat32 || pixelFormat == oneComponentFloat32 {
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            let rowBytes = bytesPerRow / MemoryLayout<Float>.size
            depth = floatBuffer[clampedY * rowBytes + clampedX]
        } else if pixelFormat == depthFloat16 || pixelFormat == oneComponentFloat16 {
            let halfBuffer = baseAddress.assumingMemoryBound(to: UInt16.self)
            let rowHalfs = bytesPerRow / MemoryLayout<UInt16>.size
            depth = Float(Float16(bitPattern: halfBuffer[clampedY * rowHalfs + clampedX]))
        } else if pixelFormat == up16 {
            let shortBuffer = baseAddress.assumingMemoryBound(to: UInt16.self)
            let rowShorts = bytesPerRow / MemoryLayout<UInt16>.size
            let rawDepth = shortBuffer[clampedY * rowShorts + clampedX]
            depth = Float(rawDepth) / 1000.0
        } else {
            return nil
        }

        guard depth > 0.1, depth < 10.0 else { return nil }
        return depth
    }
}

extension Observation {
    /// Copies only bounded ROI evidence from the frame-owned buffers. Sampling
    /// uses the same normalized coordinates, confidence gate, and grid as the
    /// established ROI candidate and projection paths.
    static func capture(
        id: UUID,
        frameID: FrameID,
        category: FruitCategory,
        boundingBox: CGRect,
        confidence: Float,
        timestamp: TimeInterval,
        cameraTransform: simd_float4x4?,
        cameraIntrinsics: simd_float3x3?,
        imageSize: CGSize?,
        depthMap: CVPixelBuffer?,
        depthConfidenceMap: CVPixelBuffer?,
        depthConfidenceProvenance: DepthConfidenceProvenance,
        depthConfiguration: DepthExperimentConfig = .default
    ) -> Observation {
        let roiGrid = 9
        var roiSamples: [ObservationDepthSample] = []
        var projectionSamples: [Float] = []
        var rejectionReasons: [ObservationRejectionReason] = []

        if depthMap == nil { rejectionReasons.append(.missingDepthMap) }
        if cameraTransform == nil { rejectionReasons.append(.missingCameraPose) }
        if cameraIntrinsics == nil { rejectionReasons.append(.missingCameraIntrinsics) }
        if let imageSize, imageSize.width > 0, imageSize.height > 0 {
            // Valid geometry is required for normalized-to-depth pixel mapping.
        } else {
            rejectionReasons.append(.invalidImageGeometry)
        }
        if depthConfidenceProvenance == .copyFailed {
            rejectionReasons.append(.confidenceCopyFailed)
        }

        if let depthMap,
           let imageSize,
           imageSize.width > 0,
           imageSize.height > 0 {
            if let sampler = DepthSampler(depthMap: depthMap, confidenceMap: depthConfidenceMap, configuration: depthConfiguration) {
                roiSamples.reserveCapacity(roiGrid * roiGrid)
                for row in 0..<roiGrid {
                    for column in 0..<roiGrid {
                        let point = CGPoint(
                            x: boundingBox.minX + boundingBox.width * (CGFloat(column) + 0.5) / CGFloat(roiGrid),
                            y: boundingBox.minY + boundingBox.height * (CGFloat(row) + 0.5) / CGFloat(roiGrid)
                        )
                        let depthPoint = ObservationProjection.depthSamplePoint(
                            normalizedPoint: point,
                            imageSize: imageSize,
                            depthSize: CGSize(width: sampler.width, height: sampler.height)
                        )
                        guard let depth = sampler.depth(x: Int(depthPoint.x), y: Int(depthPoint.y)) else {
                            continue
                        }
                        roiSamples.append(ObservationDepthSample(
                            normalizedImageX: Float(point.x),
                            normalizedImageY: Float(point.y),
                            depthMeters: depth,
                            row: row,
                            column: column
                        ))
                    }
                }

                let projectionGrid = depthConfiguration.boundedProjectionGrid
                projectionSamples.reserveCapacity(projectionGrid * projectionGrid)
                for row in 0..<projectionGrid {
                    for column in 0..<projectionGrid {
                        let point = CGPoint(
                            x: boundingBox.minX + boundingBox.width * (CGFloat(column) + 0.5) / CGFloat(projectionGrid),
                            y: boundingBox.minY + boundingBox.height * (CGFloat(row) + 0.5) / CGFloat(projectionGrid)
                        )
                        let depthPoint = ObservationProjection.depthSamplePoint(
                            normalizedPoint: point,
                            imageSize: imageSize,
                            depthSize: CGSize(width: sampler.width, height: sampler.height)
                        )
                        if let depth = sampler.depth(x: Int(depthPoint.x), y: Int(depthPoint.y)) {
                            projectionSamples.append(depth)
                        }
                    }
                }
            } else {
                rejectionReasons.append(.invalidDepthBuffer)
            }
        }

        if depthMap != nil, roiSamples.isEmpty, projectionSamples.isEmpty,
           depthConfidenceProvenance != .copyFailed {
            rejectionReasons.append(.noReliableDepthSamples)
        }

        return Observation(
            id: id,
            frameID: frameID,
            category: category,
            boundingBox: boundingBox,
            confidence: confidence,
            timestamp: timestamp,
            cameraTransform: cameraTransform,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize,
            coordinateConvention: .visionNormalizedLowerLeft,
            depthConfidenceProvenance: depthConfidenceProvenance,
            hasDepthMap: depthMap != nil,
            roiDepthSamples: roiSamples,
            projectionDepthSamples: projectionSamples,
            rejectionReasons: rejectionReasons
        )
    }
}

private final class DepthConfidenceSampler {
    // 置信度图通常比深度图分辨率低，读取前需要按比例映射坐标。
    private let confidenceMap: CVPixelBuffer
    private let baseAddress: UnsafeMutableRawPointer
    private let bytesPerRow: Int
    private let width: Int
    private let height: Int

    /// 锁定置信度缓冲区，并缓存行跨度以便后续常量时间读取。
    init?(confidenceMap: CVPixelBuffer) {
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        guard let baseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            return nil
        }

        self.confidenceMap = confidenceMap
        self.baseAddress = baseAddress
        self.bytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        self.width = CVPixelBufferGetWidth(confidenceMap)
        self.height = CVPixelBufferGetHeight(confidenceMap)
    }

    deinit {
        CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
    }

    func isReliable(
        x: Int,
        y: Int,
        depthWidth: Int,
        depthHeight: Int,
        minimumConfidence: UInt8
    ) -> Bool {
        guard width > 0, height > 0, depthWidth > 0, depthHeight > 0 else {
            return false
        }

        // 用整数比例映射并夹紧边界，避免不同尺寸缓冲区发生越界访问。
        let confidenceX = max(0, min(x * width / depthWidth, width - 1))
        let confidenceY = max(0, min(y * height / depthHeight, height - 1))
        let confidenceBuffer = baseAddress.assumingMemoryBound(to: UInt8.self)
        return confidenceBuffer[confidenceY * bytesPerRow + confidenceX] >= minimumConfidence
    }
}
