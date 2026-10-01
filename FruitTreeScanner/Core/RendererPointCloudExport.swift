import Foundation
import simd
import Darwin
import CryptoKit

struct FinalPointCloud: Sendable {
    let identity: RendererSnapshotSignature
    let points: [ColoredPoint]
    let inputSampleCount: Int
    let retainedSampleCount: Int
    let buildDuration: TimeInterval
    let estimatedPeakPayloadBytes: Int
}

struct StagedPointCloud: Sendable {
    let draft: DraftScan
    let pointCloud: FinalPointCloud
}

enum PointCloudExportError: Error {
    case rendererUnavailable
    case gpuDrainTimedOut
    case emptyPointCloud
}

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
    static func makeHeader(
        sampleCount: Int,
        treeID: String,
        scanDate: String,
        gpsLat: Double,
        gpsLon: Double
    ) -> Data {
        let safeTreeID = TreeIdentifierPolicy.safePLYCommentValue(treeID)
        let safeGPSLat = latitude(gpsLat)
        let safeGPSLon = longitude(gpsLon)
        let headers = [
            "ply",
            "format ascii 1.0",
            "comment tree_id \(safeTreeID)",
            "comment scan_date \(scanDate)",
            "comment gps_lat \(StableDataFormatting.decimal(safeGPSLat, precision: 6))",
            "comment gps_lon \(StableDataFormatting.decimal(safeGPSLon, precision: 6))",
            "element vertex \(sampleCount)",
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
        return Data((headers.joined(separator: "\r\n") + "\r\n").utf8)
    }

    static func makeVertexLine(position: SIMD3<Float>, color: SIMD3<Float>) -> Data {
        let r = Int(color.x * 255.0)
        let g = Int(color.y * 255.0)
        let b = Int(color.z * 255.0)
        let line = [
            StableDataFormatting.decimal(position.x, precision: 4),
            StableDataFormatting.decimal(position.y, precision: 4),
            StableDataFormatting.decimal(position.z, precision: 4),
            "\(r)",
            "\(g)",
            "\(b)"
        ].joined(separator: " ") + "\r\n"
        return Data(line.utf8)
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

    private static func latitude(_ value: Double) -> Double {
        guard value.isFinite, (-90...90).contains(value) else { return 0 }
        return value
    }

    private static func longitude(_ value: Double) -> Double {
        guard value.isFinite, (-180...180).contains(value) else { return 0 }
        return value
    }
}

enum PLYPointCloudWriterError: Error {
    case invalidDestination
    case cancelled
    case systemCall(operation: String, code: Int32)
}

/// Chunked ASCII PLY publisher. It writes a sibling temporary file and uses
/// the existing exclusive atomic move primitive so readers see a complete file
/// and an existing scan cannot be overwritten on a name collision.
enum PLYPointCloudWriter {
    static let defaultChunkVertexCount = 1024

    struct Receipt: Sendable {
        let sourceSHA256: String
        let fileIdentity: ScanSourceFileIdentity
    }

    @discardableResult
    static func write(
        points: [ColoredPoint],
        treeID: String,
        scanDate: String,
        gpsLat: Double,
        gpsLon: Double,
        to destination: URL,
        chunkVertexCount: Int = defaultChunkVertexCount,
        isCancelled: () -> Bool = currentTaskIsCancelled
    ) throws -> Receipt {
        guard LocalFileStorage.isSafeLeafFilename(destination.lastPathComponent),
              !destination.lastPathComponent.isEmpty else {
            throw PLYPointCloudWriterError.invalidDestination
        }
        let chunkSize = max(chunkVertexCount, 1)
        let fileManager = FileManager.default
        let directory = destination.deletingLastPathComponent()
        try fileManager.createDirectory(at: directory, withIntermediateDirectories: true)

        let temporary = directory.appendingPathComponent(
            ".\(destination.lastPathComponent).\(UUID().uuidString).tmp",
            isDirectory: false
        )
        let descriptor = temporary.path.withCString {
            Darwin.open($0, O_WRONLY | O_CREAT | O_EXCL, mode_t(S_IRUSR | S_IWUSR))
        }
        guard descriptor >= 0 else {
            throw PLYPointCloudWriterError.systemCall(operation: "open", code: errno)
        }

        var descriptorOpen = true
        do {
            try checkCancellation(isCancelled)
            var hasher = SHA256()
            let header = RendererPLYDataBuilder.makeHeader(
                sampleCount: points.count,
                treeID: treeID,
                scanDate: scanDate,
                gpsLat: gpsLat,
                gpsLon: gpsLon
            )
            try writeAll(header, to: descriptor)
            hasher.update(data: header)

            var start = 0
            while start < points.count {
                try checkCancellation(isCancelled)
                let end = min(start + chunkSize, points.count)
                var chunk = Data()
                chunk.reserveCapacity((end - start) * 40)
                for point in points[start..<end] {
                    chunk.append(RendererPLYDataBuilder.makeVertexLine(
                        position: point.pos,
                        color: SIMD3<Float>(point.r, point.g, point.b)
                    ))
                }
                try writeAll(chunk, to: descriptor)
                hasher.update(data: chunk)
                start = end
            }

            try checkCancellation(isCancelled)
            guard Darwin.fsync(descriptor) == 0 else {
                throw PLYPointCloudWriterError.systemCall(operation: "fsync", code: errno)
            }
            guard Darwin.close(descriptor) == 0 else {
                descriptorOpen = false
                throw PLYPointCloudWriterError.systemCall(operation: "close", code: errno)
            }
            descriptorOpen = false

            // Complete every fallible receipt operation before publication.
            // The exclusive rename preserves this file's identity. Once it
            // succeeds, even a concurrent cancellation must receive a receipt.
            let receipt = Receipt(
                sourceSHA256: hasher.finalize().map { String(format: "%02x", $0) }.joined(),
                fileIdentity: try ScanSourceFileIdentity.read(at: temporary)
            )
            try checkCancellation(isCancelled)
            try LocalFileStorage.moveItemExclusively(from: temporary, to: destination)
            return receipt
        } catch {
            if descriptorOpen { _ = Darwin.close(descriptor) }
            try? fileManager.removeItem(at: temporary)
            throw error
        }
    }

    private static func writeAll(_ data: Data, to descriptor: Int32) throws {
        guard !data.isEmpty else { return }
        try data.withUnsafeBytes { rawBuffer in
            guard let baseAddress = rawBuffer.baseAddress else { return }
            var offset = 0
            while offset < rawBuffer.count {
                let written = Darwin.write(
                    descriptor,
                    baseAddress.advanced(by: offset),
                    rawBuffer.count - offset
                )
                if written < 0 {
                    if errno == EINTR { continue }
                    throw PLYPointCloudWriterError.systemCall(operation: "write", code: errno)
                }
                guard written > 0 else {
                    throw PLYPointCloudWriterError.systemCall(operation: "short write", code: EIO)
                }
                offset += written
            }
        }
    }

    private static func checkCancellation(_ isCancelled: () -> Bool) throws {
        if isCancelled() { throw PLYPointCloudWriterError.cancelled }
    }

    private static var currentTaskIsCancelled: () -> Bool {
        { withUnsafeCurrentTask { task in task?.isCancelled ?? false } }
    }
}

extension Renderer {
    /// - Parameters:
    ///   - treeID: 树木编号，如 "T001"
    ///   - gpsLat: GPS 纬度
    ///   - gpsLon: GPS 经度
    ///   - completion: 保存完成后在主线程回调（成功时 filename 非空）
    func savePointCloud(treeID: String, gpsLat: Double, gpsLon: Double,
                        completion: @escaping (String?) -> Void = { _ in }) {
        stagePointCloud(treeID: treeID, gpsLat: gpsLat, gpsLon: gpsLon) {
            completion($0?.draft.sourceFilename)
        }
    }

    func stagePointCloud(treeID: String, gpsLat: Double, gpsLon: Double,
                         completion: @escaping (StagedPointCloud?) -> Void) {
        Task(priority: .utility) {
            do {
                let staged = try await stagePointCloud(treeID: treeID, gpsLat: gpsLat, gpsLon: gpsLon)
                await MainActor.run { completion(staged) }
            } catch {
                Log.export.error("PLY export failed: \(error.localizedDescription)")
                await MainActor.run { completion(nil) }
            }
        }
    }

    func stagePointCloud(treeID: String, gpsLat: Double, gpsLon: Double,
                         context: ScanContext? = nil,
                         repository: ScanRepository = .shared) async throws -> StagedPointCloud {
        let worker = Task.detached(priority: .utility) { [self] in
            try Task.checkCancellation()
            // `currentPointIndex` advances when work is encoded, not when the
            // GPU has written the buffer. Drain in-flight rendering first.
            guard waitForPointCloudWritesToComplete() else { throw PointCloudExportError.gpuDrainTimedOut }
            try Task.checkCancellation()
            guard let finalPointCloud = makeFinalPointCloudSnapshot(),
                  !finalPointCloud.points.isEmpty else {
                throw PointCloudExportError.emptyPointCloud
            }
            try Task.checkCancellation()
            let scanDate = getTimeStr()
            let filename = makeTreeFileName(treeID: treeID, lat: gpsLat, lon: gpsLon)
            let destination = try repository.pointCloudDestination(filename: filename, fallbackFolder: currentFolder)
            let capture = context.map { ScanCaptureIdentity(context: $0, pointCloud: finalPointCloud.identity) }
            let draft = try repository.stagePointCloud(to: destination, captureIdentity: capture) {
                try PLYPointCloudWriter.write(
                    points: finalPointCloud.points, treeID: treeID, scanDate: scanDate,
                    gpsLat: gpsLat, gpsLon: gpsLon, to: destination
                )
            }
            // No cancellation check after publication: the owner must settle
            // this receipt even if the UI attempt has already been cancelled.
            return StagedPointCloud(draft: draft, pointCloud: finalPointCloud)
        }
        return try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
    }
}
