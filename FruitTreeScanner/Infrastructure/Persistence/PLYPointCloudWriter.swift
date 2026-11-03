import Foundation
import simd
import Darwin
import CryptoKit

enum PLYPointCloudEncoding {
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
            let header = PLYPointCloudEncoding.makeHeader(
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
                    chunk.append(PLYPointCloudEncoding.makeVertexLine(
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
