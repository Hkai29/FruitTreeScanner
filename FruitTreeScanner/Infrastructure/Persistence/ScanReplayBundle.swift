import Foundation
import CryptoKit

/// Local, versioned container. Each entry retains exact input and golden output;
/// no PLY, GPS, tree/classification envelope, image or wall-clock scan date is copied.
/// Frame uptime and scan-local coordinates remain unchanged for numerical replay.
enum ScanReplayBundle {
    private static let magic = Data("FTSRSET1".utf8)
    private static let maximumRecords = 1_000
    private static let maximumHeaderBytes = 16 * 1_024
    private static let maximumGoldenBytes = 4 * 1_024 * 1_024

    private struct Entry: Codable {
        let schemaVersion: Int
        let descriptor: ScanReplayDescriptor
        let exportRevision: String
        let goldenByteCount: Int
        let goldenSHA256: String

        func validate() throws {
            try descriptor.validate()
            guard schemaVersion == 1, descriptor.status == "complete",
                  !exportRevision.isEmpty, exportRevision.utf8.count <= 256,
                  (1...maximumGoldenBytes).contains(goldenByteCount), goldenSHA256.count == 64,
                  goldenSHA256.utf8.allSatisfy({ (48...57).contains($0) || (97...102).contains($0) }) else {
                throw ScanReplayError.invalidArchive
            }
        }
    }

    static func write(records: [ScanFileRecord], repository: ScanRepository = .shared, to destination: URL) throws {
        guard (1...maximumRecords).contains(records.count) else { throw ScanReplayError.budgetExceeded }
        let temporary = destination.deletingLastPathComponent().appendingPathComponent(".replay-\(UUID()).pending")
        defer { try? FileManager.default.removeItem(at: temporary) }
        try Data().write(to: temporary, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: temporary)
        defer { try? handle.close() }
        try handle.write(contentsOf: magic)
        try writeWord(records.count, to: handle)
        for record in records {
            try Task.checkCancellation()
            try repository.appendObservationReplay(for: record, to: handle)
        }
        try handle.synchronize()
        try handle.close()
        try Task.checkCancellation()
        try LocalFileStorage.moveItemExclusively(from: temporary, to: destination)
    }

    /// Caller owns the existing repository source transaction, including revision
    /// checks. Copying is chunked and verifies the exact bytes written.
    static func append(source: URL, descriptor: ScanReplayDescriptor, exportRevision: String,
                       goldenData: Data, to handle: FileHandle) throws {
        let entry = Entry(schemaVersion: 1, descriptor: descriptor, exportRevision: exportRevision,
                          goldenByteCount: goldenData.count, goldenSHA256: ScanCompanionIntegrity.digest(goldenData))
        try entry.validate()
        // Validate the complete typed input, then release the decoded point array
        // before streaming its original files. Only one bounded cloud is decoded.
        try autoreleasepool { _ = try ScanReplayArchive.read(source: source, descriptor: descriptor) }
        let header = try JSONEncoder().encode(entry)
        guard header.count <= maximumHeaderBytes else { throw ScanReplayError.budgetExceeded }
        try writeWord(header.count, to: handle)
        try handle.write(contentsOf: header)
        let urls = ScanReplayArchive.artifactURLs(for: source)
        try copy(urls.input, size: descriptor.inputByteCount!, digest: descriptor.inputSHA256!, to: handle)
        try copy(urls.points, size: descriptor.pointsByteCount!, digest: descriptor.pointsSHA256!, to: handle)
        try handle.write(contentsOf: goldenData)
    }

    /// Consume one verified entry at a time; no collection of point clouds is
    /// retained by the reader. The last entry is rejected if trailing bytes exist.
    final class Reader {
        private let handle: FileHandle
        private let fileSize: UInt64
        private(set) var remainingRecords: Int
        private var failed = false

        init(at url: URL) throws {
            let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
            guard attributes[.type] as? FileAttributeType == .typeRegular,
                  let size = (attributes[.size] as? NSNumber)?.uint64Value, size >= 12 else {
                throw ScanReplayError.invalidArchive
            }
            let opened = try FileHandle(forReadingFrom: url)
            do {
                guard try ScanReplayArchive.readExactly(8, handle: opened) == magic else { throw ScanReplayError.invalidArchive }
                let count = try readWord(from: opened)
                guard (1...maximumRecords).contains(count) else { throw ScanReplayError.budgetExceeded }
                handle = opened
                fileSize = size
                remainingRecords = count
            } catch { try? opened.close(); throw error }
        }

        deinit { try? handle.close() }

        func next() throws -> ScanObservationReplayRecord? {
            guard !failed else { throw ScanReplayError.invalidArchive }
            do { return try readNext() }
            catch {
                failed = true
                throw error
            }
        }

        private func readNext() throws -> ScanObservationReplayRecord? {
            guard remainingRecords > 0 else { return nil }
            try Task.checkCancellation()
            let headerSize = try readWord(from: handle)
            guard (1...maximumHeaderBytes).contains(headerSize) else { throw ScanReplayError.budgetExceeded }
            let entry = try JSONDecoder().decode(Entry.self, from: ScanReplayArchive.readExactly(headerSize, handle: handle))
            try entry.validate()
            let descriptor = entry.descriptor
            let payloadSize = UInt64(descriptor.inputByteCount! + descriptor.pointsByteCount! + entry.goldenByteCount)
            let offset = try handle.offset()
            guard offset <= fileSize, payloadSize <= fileSize - offset else { throw ScanReplayError.invalidArchive }
            let data = try ScanReplayArchive.readExactly(descriptor.inputByteCount!, handle: handle)
            guard ScanCompanionIntegrity.digest(data) == descriptor.inputSHA256 else { throw ScanReplayError.invalidArchive }
            let dto = try ScanReplayArchive.decoder().decode(ScanReplayInputDTO.self, from: data)
            guard dto.identity == descriptor.identity, dto.pointCount == descriptor.pointCount,
                  dto.observations.values.count == descriptor.observationCount else { throw ScanReplayError.invalidArchive }
            let points = try ScanReplayArchive.readPoints(handle: handle, count: dto.pointCount,
                digest: descriptor.pointsSHA256!, requireEndOfFile: false)
            let input = try dto.input(points: points)
            let golden = try ScanReplayArchive.readExactly(entry.goldenByteCount, handle: handle)
            guard ScanCompanionIntegrity.digest(golden) == entry.goldenSHA256,
                  (try JSONSerialization.jsonObject(with: golden)) is [String: Any] else { throw ScanReplayError.invalidArchive }
            remainingRecords -= 1
            if remainingRecords == 0, !(try handle.read(upToCount: 1)?.isEmpty ?? true) { throw ScanReplayError.invalidArchive }
            return ScanObservationReplayRecord(identity: dto.identity, producer: dto.producer, input: input,
                                               goldenData: golden, exportRevision: entry.exportRevision)
        }
    }

    private static func copy(_ url: URL, size: Int, digest: String, to output: FileHandle) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == size else { throw ScanReplayError.invalidArchive }
        let input = try FileHandle(forReadingFrom: url)
        defer { try? input.close() }
        var hash = SHA256()
        var remaining = size
        while remaining > 0 {
            try Task.checkCancellation()
            let data = try ScanReplayArchive.readExactly(min(remaining, 64 * 1_024), handle: input)
            hash.update(data: data)
            try output.write(contentsOf: data)
            remaining -= data.count
        }
        guard try input.read(upToCount: 1)?.isEmpty ?? true,
              hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest else { throw ScanReplayError.invalidArchive }
    }

    private static func writeWord(_ value: Int, to handle: FileHandle) throws {
        var word = UInt32(value).littleEndian
        try withUnsafeBytes(of: &word) { try handle.write(contentsOf: Data($0)) }
    }

    private static func readWord(from handle: FileHandle) throws -> Int {
        let data = try ScanReplayArchive.readExactly(4, handle: handle)
        return data.enumerated().reduce(0) { $0 | (Int($1.element) << ($1.offset * 8)) }
    }
}
