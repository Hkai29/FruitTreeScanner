import Foundation
import simd

struct RendererSnapshotSignature: Equatable {
    let pointCount: Int
    let pointIndex: Int
    let voxelSize: Float
    let confidenceThreshold: Int
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
        confidenceThreshold: Int
    ) -> RendererSnapshotSignature {
        RendererSnapshotSignature(
            pointCount: pointCount,
            pointIndex: pointIndex,
            voxelSize: voxelSize,
            confidenceThreshold: confidenceThreshold
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

        let sampleStep = inputSampleLimit.map { limit in
            let clampedLimit = max(limit, 1)
            return max((currentPointCount + clampedLimit - 1) / clampedLimit, 1)
        } ?? 1
        var bestSamplesByVoxel: [RendererVoxelKey: RendererPointSample] = [:]
        bestSamplesByVoxel.reserveCapacity(min(currentPointCount / sampleStep, 200_000))

        var i = 0
        while i < currentPointCount {
            let bufferIndex = (currentPointIndex - currentPointCount + i + maxPoints) % maxPoints
            let particle = particlesBuffer[bufferIndex]
            defer { i += sampleStep }
            guard isExportableParticle(particle, confidenceThreshold: confidenceThreshold) else { continue }

            let key = voxelKey(for: particle.position, size: voxelSize)
            let sample = RendererPointSample(
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
    static func makeData(
        samples: [RendererPointSample],
        treeID: String,
        scanDate: String,
        gpsLat: Double,
        gpsLon: Double
    ) -> Data {
        let safeTreeID = TreeIdentifierPolicy.safePLYCommentValue(treeID)
        let headers = [
            "ply",
            "format ascii 1.0",
            "comment tree_id \(safeTreeID)",
            "comment scan_date \(scanDate)",
            "comment gps_lat \(String(format: "%.6f", gpsLat))",
            "comment gps_lon \(String(format: "%.6f", gpsLon))",
            "element vertex \(samples.count)",
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

        let header = headers.joined(separator: "\r\n") + "\r\n"
        var data = Data()
        data.reserveCapacity(header.utf8.count + samples.count * 40)
        data.append(contentsOf: header.utf8)

        for sample in samples {
            let position = sample.position
            let color = sample.color
            let r = Int(color.x * 255.0)
            let g = Int(color.y * 255.0)
            let b = Int(color.z * 255.0)
            let line = String(format: "%.4f %.4f %.4f %d %d %d\r\n",
                              position.x, position.y, position.z, r, g, b)
            data.append(contentsOf: line.utf8)
        }

        return data
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
        Task(priority: .utility) {
            let rawSamples = makeFilteredPointSamples(voxelSize: snapshotVoxelSize)
            let pointsCopy = PointCloudDenoiser.statisticalOutlierRemoval(samples: rawSamples)
            guard !pointsCopy.isEmpty else {
                await MainActor.run {
                    completion(nil)
                }
                return
            }
            let analysisPoints = RendererPointCloudSnapshot.makeColoredPoints(from: pointsCopy)
            let analysisSignature = currentSnapshotSignature()
            storeSnapshot(points: analysisPoints, fullSignature: analysisSignature)

            do {
                let scanDate = getTimeStr()
                let data = RendererPLYDataBuilder.makeData(
                    samples: pointsCopy,
                    treeID: treeID,
                    scanDate: scanDate,
                    gpsLat: gpsLat,
                    gpsLon: gpsLon
                )

                let filename = makeTreeFileName(treeID: treeID, lat: gpsLat, lon: gpsLon)
                try await saveFile(data: data, filename: filename,
                                   folder: self.currentFolder)
                await MainActor.run { completion(filename) }
            } catch {
                await MainActor.run { completion(nil) }
            }
        }
    }
}
