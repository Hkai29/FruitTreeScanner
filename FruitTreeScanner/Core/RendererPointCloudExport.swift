import Foundation
import simd

struct RendererPointSample {
    let position: SIMD3<Float>
    let color: SIMD3<Float>
    let confidence: Float
}

struct RendererVoxelKey: Hashable {
    let x: Int32
    let y: Int32
    let z: Int32

    func hash(into hasher: inout Hasher) {
        hasher.combine(x)
        hasher.combine(y &* 73856093)
        hasher.combine(z &* 19349669)
    }
}

enum RendererPointCloudSnapshot {
    static func makeSignature(
        pointCount: Int,
        pointIndex: Int,
        voxelSize: Float,
        confidenceThreshold: Int,
        pointBufferRevision: UInt64 = 0,
        analysisInputSampleLimit: Int? = nil
    ) -> RendererSnapshotSignature {
        RendererSnapshotSignature(
            pointCount: pointCount,
            pointIndex: pointIndex,
            voxelSize: voxelSize,
            confidenceThreshold: confidenceThreshold,
            pointBufferRevision: pointBufferRevision,
            analysisInputSampleLimit: analysisInputSampleLimit
        )
    }

    static func makeColoredPoints(from samples: [RendererPointSample]) -> [ColoredPoint] {
        samples.map {
            ColoredPoint(pos: $0.position, r: $0.color.x, g: $0.color.y, b: $0.color.z)
        }
    }

    static func makeFilteredSamples(
        particlesBuffer: MetalBuffer<ParticleUniforms>,
        currentPointCount: Int,
        currentPointIndex: Int,
        maxPoints: Int,
        voxelSize: Float,
        confidenceThreshold: Int,
        inputSampleLimit: Int? = nil
    ) -> [RendererPointSample] {
        guard currentPointCount > 0 else { return [] }

        let validPointCount: Int
        if inputSampleLimit != nil {
            validPointCount = (0..<currentPointCount).reduce(into: 0) { count, offset in
                let index = (currentPointIndex - currentPointCount + offset + maxPoints) % maxPoints
                if isExportableParticle(particlesBuffer[index], confidenceThreshold: confidenceThreshold) {
                    count += 1
                }
            }
        } else {
            validPointCount = currentPointCount
        }
        let sampleStep = inputSampleLimit.map { limit in
            let clampedLimit = max(limit, 1)
            return max((validPointCount + clampedLimit - 1) / clampedLimit, 1)
        } ?? 1
        var bestSamplesByVoxel: [RendererVoxelKey: RendererPointSample] = [:]
        bestSamplesByVoxel.reserveCapacity(min(validPointCount / sampleStep, 200_000))

        var i = 0
        var validOrdinal = 0
        var sampledCount = 0
        while i < currentPointCount {
            let bufferIndex = (currentPointIndex - currentPointCount + i + maxPoints) % maxPoints
            let particle = particlesBuffer[bufferIndex]
            defer { i += 1 }
            guard let sample = makeExportableSample(
                from: particle,
                confidenceThreshold: confidenceThreshold
            ) else { continue }
            // 步长应用于有效证据序号，避免深度孔洞与固定槽位相位重合。
            let shouldSample = validOrdinal % sampleStep == 0
            validOrdinal += 1
            guard shouldSample else { continue }
            if let limit = inputSampleLimit, sampledCount >= max(limit, 1) { break }
            sampledCount += 1

            let key = voxelKey(for: sample.position, size: voxelSize)
            if let existing = bestSamplesByVoxel[key], existing.confidence >= sample.confidence {
                continue
            }
            bestSamplesByVoxel[key] = sample
        }

        return Array(bestSamplesByVoxel.values)
    }

    static func isExportableParticle(
        _ particle: ParticleUniforms,
        confidenceThreshold: Int
    ) -> Bool {
        guard particle.confidence >= Float(confidenceThreshold) else { return false }
        let position = particle.position
        guard position.x.isFinite, position.y.isFinite, position.z.isFinite else { return false }
        guard simd_length_squared(position) > 0.000001 else { return false }
        let color = particle.color
        return color.x.isFinite && color.y.isFinite && color.z.isFinite
    }

    static func makeExportableSample(
        from particle: ParticleUniforms,
        confidenceThreshold: Int
    ) -> RendererPointSample? {
        guard isExportableParticle(particle, confidenceThreshold: confidenceThreshold) else {
            return nil
        }
        return RendererPointSample(
            position: particle.position,
            color: clampColor(particle.color),
            confidence: particle.confidence
        )
    }

    private static func voxelKey(for position: SIMD3<Float>, size: Float) -> RendererVoxelKey {
        let invSize = 1.0 / size
        return RendererVoxelKey(
            x: Int32(floor(position.x * invSize)),
            y: Int32(floor(position.y * invSize)),
            z: Int32(floor(position.z * invSize))
        )
    }

    static func clampColorPublic(_ color: SIMD3<Float>) -> SIMD3<Float> {
        clampColor(color)
    }

    private static func clampColor(_ color: SIMD3<Float>) -> SIMD3<Float> {
        simd_clamp(color, SIMD3<Float>.zero, SIMD3<Float>.one)
    }
}

enum RendererPLYDataBuilder {
    static func makeHeader(sampleCount: Int, treeID: String, scanDate: String,
                           gpsLat: Double, gpsLon: Double) -> Data {
        PLYPointCloudEncoding.makeHeader(sampleCount: sampleCount, treeID: treeID, scanDate: scanDate,
                                        gpsLat: gpsLat, gpsLon: gpsLon)
    }

    static func makeVertexLine(position: SIMD3<Float>, color: SIMD3<Float>) -> Data {
        PLYPointCloudEncoding.makeVertexLine(position: position, color: color)
    }

    static func makeData(
        samples: [RendererPointSample],
        treeID: String,
        scanDate: String,
        gpsLat: Double,
        gpsLon: Double
    ) -> Data {
        var data = Data()
        data.reserveCapacity(256 + samples.count * 40)
        data.append(makeHeader(
            sampleCount: samples.count,
            treeID: treeID,
            scanDate: scanDate,
            gpsLat: gpsLat,
            gpsLon: gpsLon
        ))
        for sample in samples {
            data.append(makeVertexLine(position: sample.position, color: sample.color))
        }

        return data
    }

}

extension Renderer {
    /// Pins capture generation before waiting for GPU writes or creating a worker.
    func freezeFinalPointCloudForExport() async throws -> FinalPointCloud {
        try await freezeFinalPointCloudForExport(captureGeneration: pointBufferSnapshot().generation)
    }

    private func freezeFinalPointCloudForExport(captureGeneration: UInt64) async throws -> FinalPointCloud {
        let worker = Task.detached(priority: .utility) { [self] in
            try Task.checkCancellation()
            // Indices advance at encoding time; GPU completion is the barrier.
            guard waitForPointCloudWritesToComplete() else { throw PointCloudExportError.gpuDrainTimedOut }
            try Task.checkCancellation()
            try validatePointCloudCapture(generation: captureGeneration)
            guard let finalPointCloud = makeFinalPointCloudSnapshot(expectedCaptureGeneration: captureGeneration),
                  !finalPointCloud.points.isEmpty else {
                try validatePointCloudCapture(generation: captureGeneration)
                throw PointCloudExportError.emptyPointCloud
            }
            try Task.checkCancellation()
            return finalPointCloud
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    /// Compatibility facade for existing asynchronous capture callers.
    func stagePointCloud(treeID: String, gpsLat: Double, gpsLon: Double,
                         context: ScanContext? = nil,
                         repository: ScanRepository = .shared) async throws -> StagedPointCloud {
        let captureGeneration = pointBufferSnapshot().generation
        let fallbackFolder = await MainActor.run { self.currentFolder }
        let cloud = try await freezeFinalPointCloudForExport(captureGeneration: captureGeneration)
        return try await PointCloudStaging.stage(
            PointCloudStageInput(
                frozen: FrozenPointCloudExport(
                    pointCloud: cloud,
                    captureIdentity: context.map { ScanCaptureIdentity(context: $0, pointCloud: cloud.identity) },
                    fallbackFolder: fallbackFolder
                ),
                treeID: treeID, latitude: gpsLat, longitude: gpsLon
            ),
            repository: repository
        )
    }
}
