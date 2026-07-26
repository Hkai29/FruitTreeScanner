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

struct RendererDepthQuality: Equatable, Sendable {
    let validSampleCount: Int
    let totalSampleCount: Int
    let medianDepth: Float

    var validRatio: Float {
        guard totalSampleCount > 0 else { return 0 }
        return Float(validSampleCount) / Float(totalSampleCount)
    }
}

enum RendererCaptureFrameDecision: Sendable {
    case accepted(RendererDepthQuality)
    case skippedForMotion
    case rejectedMissingDepth
    case rejectedSparseReliableDepth(RendererDepthQuality)
    case skippedDuplicateRegion
}

struct RendererCaptureDiagnostics: Equatable, Sendable {
    private(set) var acceptedFrameCount = 0
    private(set) var motionSkippedFrameCount = 0
    private(set) var missingDepthRejectedFrameCount = 0
    private(set) var sparseDepthRejectedFrameCount = 0
    private(set) var duplicateRegionSkippedFrameCount = 0
    private(set) var latestDepthQuality: RendererDepthQuality?

    mutating func record(_ decision: RendererCaptureFrameDecision) {
        switch decision {
        case let .accepted(quality):
            acceptedFrameCount += 1
            latestDepthQuality = quality
        case .skippedForMotion:
            motionSkippedFrameCount += 1
        case .rejectedMissingDepth:
            missingDepthRejectedFrameCount += 1
            latestDepthQuality = nil
        case let .rejectedSparseReliableDepth(quality):
            sparseDepthRejectedFrameCount += 1
            latestDepthQuality = quality
        case .skippedDuplicateRegion:
            duplicateRegionSkippedFrameCount += 1
        }
    }
}

enum RendererDepthCoverage {
    static func acceptsCaptureDepthQuality(_ quality: RendererDepthQuality) -> Bool {
        let config = FruitScanExperimentConfig.default.depth
        return quality.validSampleCount >= config.minimumCaptureValidSampleCount
            && quality.validRatio >= config.minimumCaptureValidSampleRatio
    }

    static func estimateHorizontalAngleCoverage(
        from voxels: Set<RendererVoxelKey>,
        binCount: Int = 36
    ) -> Float {
        guard let bins = horizontalAngleBins(from: voxels, binCount: binCount) else { return 0 }
        let occupied = bins.occupancy.map { $0 >= bins.minimumBinSupport }
        guard occupied.contains(true) else { return 0 }

        var longestEmptyRun = 0
        var currentEmptyRun = 0
        for index in 0..<(binCount * 2) {
            if occupied[index % binCount] {
                currentEmptyRun = 0
            } else {
                currentEmptyRun += 1
                longestEmptyRun = min(max(longestEmptyRun, currentEmptyRun), binCount)
            }
        }

        let coverage = 1.0 - Double(longestEmptyRun) / Double(binCount)
        return Float(min(max(coverage, 0), 1))
    }

    static func estimateHorizontalAngleUniformity(
        from voxels: Set<RendererVoxelKey>,
        binCount: Int = 36
    ) -> Float {
        guard let bins = horizontalAngleBins(from: voxels, binCount: binCount) else { return 0 }
        let supportedCounts = bins.occupancy.map { $0 >= bins.minimumBinSupport ? $0 : 0 }
        let supportedTotal = supportedCounts.reduce(0, +)
        guard supportedTotal > 0 else { return 0 }

        var entropy = 0.0
        for count in supportedCounts where count > 0 {
            let p = Double(count) / Double(supportedTotal)
            entropy -= p * log(p)
        }

        let normalizedEntropy = entropy / log(Double(binCount))
        return Float(min(max(normalizedEntropy, 0), 1))
    }

    static func estimateOppositeSideCoverage(
        from regions: Set<RendererCameraRegionKey>,
        binCount: Int = 36
    ) -> Float {
        guard regions.count > 2, binCount > 3 else { return 0 }

        var binOccupancy = [Int](repeating: 0, count: binCount)
        for region in regions {
            let forwardX = Float(region.forwardX)
            let forwardZ = Float(region.forwardZ)
            guard hypot(forwardX, forwardZ) >= 1 else { continue }

            var normalizedAngle = (atan2(forwardZ, forwardX) + Float.pi) / (2 * Float.pi)
            if normalizedAngle >= 1 {
                normalizedAngle = 0
            }
            let bin = min(max(Int(floor(normalizedAngle * Float(binCount))), 0), binCount - 1)
            binOccupancy[bin] += 1
        }

        let minimumBinSupport = max(1, Int(ceil(Float(regions.count) * 0.01)))
        let occupied = binOccupancy.map { $0 >= minimumBinSupport }
        let occupiedCount = occupied.filter { $0 }.count
        guard occupiedCount > 0 else { return 0 }

        let halfTurn = max(binCount / 2, 1)
        let tolerance = max(1, binCount / 36)
        var matchedCount = 0

        for index in occupied.indices where occupied[index] {
            let oppositeCenter = (index + halfTurn) % binCount
            let hasOppositeSupport = (-tolerance...tolerance).contains { offset in
                let oppositeIndex = (oppositeCenter + offset + binCount) % binCount
                return occupied[oppositeIndex]
            }
            if hasOppositeSupport {
                matchedCount += 1
            }
        }

        return min(max(Float(matchedCount) / Float(occupiedCount), 0), 1)
    }

    static func estimateVerticalCoverage(
        from voxels: Set<RendererVoxelKey>,
        binCount: Int = 6
    ) -> Float {
        guard voxels.count > 20, binCount > 2 else { return 0 }

        let sortedY = voxels.map { Int($0.y) }.sorted()
        let lowerIndex = max(Int(Float(sortedY.count - 1) * 0.05), 0)
        let upperIndex = min(Int(ceil(Float(sortedY.count - 1) * 0.95)), sortedY.count - 1)
        let lowerY = sortedY[lowerIndex]
        let upperY = sortedY[upperIndex]
        guard upperY > lowerY else { return 0 }

        var occupancy = [Int](repeating: 0, count: binCount)
        let span = max(upperY - lowerY + 1, 1)
        for voxel in voxels {
            guard voxel.y >= lowerY, voxel.y <= upperY else { continue }
            let normalized = Float(Int(voxel.y) - lowerY) / Float(span)
            let bin = min(max(Int(floor(normalized * Float(binCount))), 0), binCount - 1)
            occupancy[bin] += 1
        }

        let minimumBinSupport = max(2, Int(ceil(Double(voxels.count) * 0.01)))
        let supportedBinCount = occupancy.filter { $0 >= minimumBinSupport }.count
        return min(max(Float(supportedBinCount) / Float(binCount), 0), 1)
    }

    private static func horizontalAngleBins(
        from voxels: Set<RendererVoxelKey>,
        binCount: Int
    ) -> (occupancy: [Int], minimumBinSupport: Int)? {
        guard voxels.count > 20, binCount > 3 else { return nil }

        var sumX: Double = 0
        var sumZ: Double = 0
        for voxel in voxels {
            sumX += Double(voxel.x)
            sumZ += Double(voxel.z)
        }

        let centerX = sumX / Double(voxels.count)
        let centerZ = sumZ / Double(voxels.count)
        var radialDistances: [Double] = []
        radialDistances.reserveCapacity(voxels.count)
        for voxel in voxels {
            radialDistances.append(hypot(Double(voxel.x) - centerX, Double(voxel.z) - centerZ))
        }
        radialDistances.sort()
        let medianRadius = radialDistances[radialDistances.count / 2]
        let minimumUsableRadius = max(medianRadius * 0.20, 1.0)

        var binOccupancy = [Int](repeating: 0, count: binCount)
        for voxel in voxels {
            let dx = Double(voxel.x) - centerX
            let dz = Double(voxel.z) - centerZ
            guard hypot(dx, dz) >= minimumUsableRadius else { continue }

            var normalizedAngle = (atan2(dz, dx) + Double.pi) / (2 * Double.pi)
            if normalizedAngle >= 1 {
                normalizedAngle = 0
            }
            let bin = min(max(Int(floor(normalizedAngle * Double(binCount))), 0), binCount - 1)
            binOccupancy[bin] += 1
        }

        let minimumBinSupport = max(2, Int(ceil(Double(voxels.count) * 0.005)))
        return (binOccupancy, minimumBinSupport)
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
    ) -> RendererDepthQuality {
        let config = FruitScanExperimentConfig.default.depth
        let sampleGrid = max(config.captureQualitySampleGrid, 2)
        let sampleCount = sampleGrid * sampleGrid
        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)
        guard width > 0, height > 0 else {
            return RendererDepthQuality(
                validSampleCount: 0,
                totalSampleCount: sampleCount,
                medianDepth: 0
            )
        }
        let confidenceWidth = CVPixelBufferGetWidth(confidenceMap)
        let confidenceHeight = CVPixelBufferGetHeight(confidenceMap)
        guard confidenceWidth > 0, confidenceHeight > 0 else {
            return RendererDepthQuality(
                validSampleCount: 0,
                totalSampleCount: sampleCount,
                medianDepth: 0
            )
        }
        guard RendererMetalHelpers.depthMetalPixelFormat(for: depthMap) != nil,
              RendererMetalHelpers.confidenceMetalPixelFormat(for: confidenceMap) != nil else {
            return RendererDepthQuality(
                validSampleCount: 0,
                totalSampleCount: sampleCount,
                medianDepth: 0
            )
        }

        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        CVPixelBufferLockBaseAddress(confidenceMap, .readOnly)
        defer {
            CVPixelBufferUnlockBaseAddress(confidenceMap, .readOnly)
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap),
              let confidenceBaseAddress = CVPixelBufferGetBaseAddress(confidenceMap) else {
            return RendererDepthQuality(
                validSampleCount: 0,
                totalSampleCount: sampleCount,
                medianDepth: 0
            )
        }
        let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
        let stride = bytesPerRow / MemoryLayout<Float>.size
        let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
        let confidenceBytesPerRow = CVPixelBufferGetBytesPerRow(confidenceMap)
        let confidenceBuffer = confidenceBaseAddress.assumingMemoryBound(to: UInt8.self)

        var validDepths: [Float] = []
        validDepths.reserveCapacity(sampleCount)
        let margin = min(max(config.captureQualitySampleMargin, 0), 0.45)
        let usableSpan = 1 - margin * 2

        for row in 0..<sampleGrid {
            let ratioY = margin + Float(row) / Float(sampleGrid - 1) * usableSpan
            let y = Int(Float(height - 1) * ratioY)
            let confidenceY = min(Int(Float(confidenceHeight - 1) * ratioY), confidenceHeight - 1)
            for col in 0..<sampleGrid {
                let ratioX = margin + Float(col) / Float(sampleGrid - 1) * usableSpan
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

        guard !validDepths.isEmpty else {
            return RendererDepthQuality(
                validSampleCount: 0,
                totalSampleCount: sampleCount,
                medianDepth: 0
            )
        }
        validDepths.sort()
        return RendererDepthQuality(
            validSampleCount: validDepths.count,
            totalSampleCount: sampleCount,
            medianDepth: validDepths[validDepths.count / 2]
        )
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
