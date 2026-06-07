import Foundation
import simd
import UIKit

extension Renderer {
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
        let pointBuffer = pointBufferSnapshot()
        let count = pointBuffer.count
        let currentIdx = pointBuffer.index
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
        let maxPts = maxPoints
        let clampedMaxSamples = max(maxSamples, 1)
        let sampleStep = max((count + clampedMaxSamples - 1) / clampedMaxSamples, 1)
        let hitRadius: Float = count > clampedMaxSamples ? 0.04 : 0.03

        var i = 0
        while i < count {
            let bufferIndex = (currentIdx - count + i + maxPts) % maxPts
            let p = particlesBuffer[bufferIndex]
            defer { i += sampleStep }
            guard RendererPointCloudSnapshot.isExportableParticle(
                p,
                confidenceThreshold: confidenceThreshold
            ) else { continue }

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
        let denoised = PointCloudDenoiser.statisticalOutlierRemoval(samples: samples)
        let pts = RendererPointCloudSnapshot.makeColoredPoints(from: denoised)
        storeSnapshot(points: pts, fullSignature: signature)

        return pts
    }

    var exportablePointCountPublic: Int {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        return snapshotPoints.count
    }

    func updateSnapshot() {
        let now = Date()
        guard now.timeIntervalSince(lastSnapshotUpdateTime) >= currentSnapshotUpdateInterval else { return }
        lastSnapshotUpdateTime = now

        let samples = makeFilteredPointSamples(
            voxelSize: snapshotVoxelSize,
            inputSampleLimit: liveSnapshotInputSampleLimit
        )
        guard !samples.isEmpty else { return }

        let pts = RendererPointCloudSnapshot.makeColoredPoints(from: samples)
        storeSnapshot(points: pts, fullSignature: nil)
    }

    private func cachedAnalysisPoints(for signature: RendererSnapshotSignature) -> [ColoredPoint]? {
        snapshotLock.lock()
        defer { snapshotLock.unlock() }
        guard fullAnalysisSnapshotSignature == signature else { return nil }
        return snapshotPoints
    }

    func currentSnapshotSignature() -> RendererSnapshotSignature {
        let pointBuffer = pointBufferSnapshot()
        return RendererPointCloudSnapshot.makeSignature(
            pointCount: pointBuffer.count,
            pointIndex: pointBuffer.index,
            voxelSize: snapshotVoxelSize,
            confidenceThreshold: confidenceThreshold
        )
    }

    func storeSnapshot(points: [ColoredPoint], fullSignature: RendererSnapshotSignature?) {
        snapshotLock.lock()
        snapshotPoints = points
        fullAnalysisSnapshotSignature = fullSignature
        snapshotLock.unlock()
    }

    private var currentSnapshotUpdateInterval: TimeInterval {
        pointBufferLock.lock()
        let count = currentPointCount
        pointBufferLock.unlock()
        switch count {
        case 0..<150_000:
            return baseSnapshotUpdateInterval
        case 150_000..<500_000:
            return 1.5
        default:
            return 2.5
        }
    }

    func makeFilteredPointSamples(
        voxelSize: Float,
        inputSampleLimit: Int? = nil
    ) -> [RendererPointSample] {
        pointBufferLock.lock()
        let count = currentPointCount
        let index = currentPointIndex
        pointBufferLock.unlock()

        // Try GPU-accelerated voxel key computation for large point clouds
        if inputSampleLimit == nil, count > 50_000,
           let compute = computePipeline,
           let metalBuffer = particlesBuffer.metalBuffer {
            if let voxelKeys = compute.computeVoxelKeys(
                particlesBuffer: metalBuffer,
                pointCount: count,
                pointIndex: index,
                maxPoints: maxPoints,
                voxelSize: voxelSize,
                confidenceThreshold: confidenceThreshold
            ) {
                return gpuAssistedFilter(
                    voxelKeys: voxelKeys,
                    count: count,
                    index: index,
                    voxelSize: voxelSize
                )
            }
        }

        // Fallback to CPU path
        return RendererPointCloudSnapshot.makeFilteredSamples(
            particlesBuffer: particlesBuffer,
            currentPointCount: count,
            currentPointIndex: index,
            maxPoints: maxPoints,
            voxelSize: voxelSize,
            confidenceThreshold: confidenceThreshold,
            inputSampleLimit: inputSampleLimit
        )
    }

    /// Use GPU-computed voxel keys to deduplicate on CPU (fast dictionary insert).
    private func gpuAssistedFilter(
        voxelKeys: [UInt32],
        count: Int,
        index: Int,
        voxelSize: Float
    ) -> [RendererPointSample] {
        var bestByVoxel: [UInt32: RendererPointSample] = [:]
        bestByVoxel.reserveCapacity(min(count, 200_000))

        for i in 0..<count {
            let key = voxelKeys[i]
            guard key != 0 else { continue }

            let bufferIndex = (index - count + i + maxPoints) % maxPoints
            let particle = particlesBuffer[bufferIndex]
            let sample = RendererPointSample(
                position: particle.position,
                color: RendererPointCloudSnapshot.clampColorPublic(particle.color),
                confidence: particle.confidence
            )
            if let existing = bestByVoxel[key], existing.confidence >= sample.confidence {
                continue
            }
            bestByVoxel[key] = sample
        }

        return Array(bestByVoxel.values)
    }
}
