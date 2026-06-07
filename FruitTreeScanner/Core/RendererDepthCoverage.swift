import ARKit
import CoreVideo
import UIKit

struct RendererCameraRegionKey: Hashable {
    let x: Int
    let y: Int
    let z: Int
    let forwardX: Int
    let forwardY: Int
    let forwardZ: Int
}

enum RendererDepthCoverage {
    static func minimumDepthQualityRatio(confidenceThreshold: Int) -> Float {
        confidenceThreshold >= 2 ? 0.22 : 0.30
    }

    static func makeCameraRegionKey(frame: ARFrame) -> RendererCameraRegionKey {
        let pos = frame.camera.transform.columns.3
        let forward = -frame.camera.transform.columns.2
        let regionSize: Float = 0.1
        let angleBin: Float = 0.3
        return RendererCameraRegionKey(
            x: Int(floor(pos.x / regionSize)),
            y: Int(floor(pos.y / regionSize)),
            z: Int(floor(pos.z / regionSize)),
            forwardX: Int(floor(forward.x / angleBin)),
            forwardY: Int(floor(forward.y / angleBin)),
            forwardZ: Int(floor(forward.z / angleBin))
        )
    }

    static func sampleDepthQuality(
        from depthMap: CVPixelBuffer,
        confidenceMap: CVPixelBuffer,
        minDepth: Float,
        maxDepth: Float,
        confidenceThreshold: Int
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

    static func makeCoverageVoxels(
        frame: ARFrame,
        orientation: UIInterfaceOrientation,
        viewportSize: CGSize,
        minDepth: Float,
        maxDepth: Float,
        confidenceThreshold: Int,
        voxelSize: Float
    ) -> Set<RendererVoxelKey> {
        let depthData = frame.smoothedSceneDepth ?? frame.sceneDepth
        guard let depthMap = depthData?.depthMap,
              let confidenceMap = depthData?.confidenceMap else { return [] }
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
              let confidenceBaseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else { return [] }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        let confidenceBuffer = confidenceBaseAddress.assumingMemoryBound(to: UInt8.self)

        let sampleStep = 4
        var newVoxels: Set<RendererVoxelKey> = []
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

                let invSize = 1.0 / voxelSize
                let key = RendererVoxelKey(
                    x: Int32(floor(worldPos.x * invSize)),
                    y: Int32(floor(worldPos.y * invSize)),
                    z: Int32(floor(worldPos.z * invSize))
                )
                newVoxels.insert(key)
            }
        }

        return newVoxels
    }
}
