import Foundation
import CryptoKit
import simd

struct ScanReplayDescriptor: Codable, Equatable, Sendable {
    var schemaVersion = 1
    let status: String
    let reason: String?
    let identity: ScanEvidenceIdentity?
    let inputByteCount: Int?
    let inputSHA256: String?
    let pointCount: Int?
    let pointsByteCount: Int?
    let pointsSHA256: String?
    let observationCount: Int?

    static func unavailable(_ reason: String, identity: ScanEvidenceIdentity? = nil) -> Self {
        .init(status: "unavailable", reason: reason, identity: identity, inputByteCount: nil, inputSHA256: nil,
              pointCount: nil, pointsByteCount: nil, pointsSHA256: nil, observationCount: nil)
    }

    func validate() throws {
        guard schemaVersion == 1 else { throw ScanReplayError.invalidArchive }
        switch status {
        case "complete":
            guard reason == nil, let identity, Self.isDigest(identity.sourceSHA256),
                  let inputByteCount, (1...ScanReplayLimits.maximumInputBytes).contains(inputByteCount),
                  let inputSHA256, Self.isDigest(inputSHA256),
                  let pointCount, (1...ScanReplayLimits.maximumPoints).contains(pointCount),
                  pointsByteCount == ScanReplayLimits.pointHeaderBytes + pointCount * ScanReplayLimits.pointStrideBytes,
                  let pointsSHA256, Self.isDigest(pointsSHA256),
                  let observationCount, (0...ScanReplayLimits.maximumObservations).contains(observationCount) else {
                throw ScanReplayError.invalidArchive
            }
        case "unavailable":
            guard let reason, !reason.isEmpty, reason.utf8.count <= 256,
                  inputByteCount == nil, inputSHA256 == nil, pointCount == nil,
                  pointsByteCount == nil, pointsSHA256 == nil, observationCount == nil else {
                throw ScanReplayError.invalidArchive
            }
        default: throw ScanReplayError.invalidArchive
        }
    }

    func payload() throws -> [String: Any] {
        try validate()
        return try JSONSerialization.jsonObject(with: JSONEncoder().encode(self)) as! [String: Any]
    }

    static func decode(_ payload: Any?) throws -> Self? {
        guard let payload else { return nil }
        guard let dictionary = payload as? [String: Any] else { throw ScanReplayError.invalidArchive }
        let value = try JSONDecoder().decode(Self.self, from: JSONSerialization.data(withJSONObject: dictionary))
        try value.validate()
        return value
    }

    private static func isDigest(_ value: String) -> Bool {
        value.utf8.count == 64 && value.utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
    }
}

/// A small draft-owned receipt; it does not retain point or observation arrays.
struct PreparedScanReplay: Sendable {
    let descriptor: ScanReplayDescriptor
    let directory: URL?
}

enum ScanReplayArchive {
    private static let magic = Data("FTSRPLY1".utf8)

    static func pendingDirectories(for source: URL) throws -> [URL] {
        let parent = source.deletingLastPathComponent()
        guard FileManager.default.fileExists(atPath: parent.path) else { return [] }
        let prefix = ".\(source.deletingPathExtension().lastPathComponent).replay-"
        return try FileManager.default.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(".pending") else { return false }
            return UUID(uuidString: String(name.dropFirst(prefix.count).dropLast(".pending".count))) != nil
        }
    }

    static func artifactURLs(for source: URL) -> (input: URL, points: URL) {
        let base = source.deletingPathExtension().lastPathComponent
        let parent = source.deletingLastPathComponent()
        return (parent.appendingPathComponent("\(base)_replay.json"), parent.appendingPathComponent("\(base)_replay.f32"))
    }

    static func preparedDirectory(for draft: DraftScan) -> URL {
        draft.sourceURL.deletingLastPathComponent().appendingPathComponent(
            ".\(draft.sourceURL.deletingPathExtension().lastPathComponent).replay-\(draft.ownershipID.uuidString).pending",
            isDirectory: true)
    }

    static func encoder() -> JSONEncoder {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        encoder.nonConformingFloatEncodingStrategy = .convertToString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return encoder
    }

    static func decoder() -> JSONDecoder {
        let decoder = JSONDecoder()
        decoder.nonConformingFloatDecodingStrategy = .convertFromString(positiveInfinity: "+Infinity", negativeInfinity: "-Infinity", nan: "NaN")
        return decoder
    }

    /// Called under the existing source transaction before binding the receipt.
    /// IO failure fails preparation; an explicit size limit records unavailable
    /// without truncating the estimator input or changing a yield threshold.
    static func prepare(input: ScanFusionYieldBuilder.Input, identity: ScanEvidenceIdentity,
                        plan: ScanPlan, draft: DraftScan) throws -> PreparedScanReplay {
        let dto: ScanReplayInputDTO
        let data: Data
        do {
            dto = try ScanReplayInputDTO(input: input, identity: identity, plan: plan)
            data = try encoder().encode(dto)
            guard data.count <= ScanReplayLimits.maximumInputBytes else { throw ScanReplayError.budgetExceeded }
        } catch ScanReplayError.budgetExceeded {
            return PreparedScanReplay(descriptor: .unavailable("inputExceedsReplayBudget", identity: identity), directory: nil)
        }
        try Task.checkCancellation()
        let directory = preparedDirectory(for: draft)
        let manager = FileManager.default
        if manager.fileExists(atPath: directory.path) {
            let values = try directory.resourceValues(forKeys: [.isDirectoryKey, .isSymbolicLinkKey])
            guard values.isDirectory == true, values.isSymbolicLink != true else { throw ScanReplayError.invalidArchive }
            try manager.removeItem(at: directory)
        }
        try manager.createDirectory(at: directory, withIntermediateDirectories: false)
        do {
            try data.write(to: directory.appendingPathComponent("input.json"), options: .withoutOverwriting)
            let pointURL = directory.appendingPathComponent("points.f32")
            try writePoints(input.points, to: pointURL)
            try Task.checkCancellation()
            let descriptor = ScanReplayDescriptor(status: "complete", reason: nil, identity: identity,
                inputByteCount: data.count, inputSHA256: ScanCompanionIntegrity.digest(data),
                pointCount: input.points.count,
                pointsByteCount: ScanReplayLimits.pointHeaderBytes + input.points.count * ScanReplayLimits.pointStrideBytes,
                pointsSHA256: try ScanCompanionIntegrity.digestFile(at: pointURL), observationCount: input.observations.count)
            try descriptor.validate()
            return PreparedScanReplay(descriptor: descriptor, directory: directory)
        } catch {
            try? manager.removeItem(at: directory)
            throw error
        }
    }

    static func verifyArtifacts(source: URL, descriptor: ScanReplayDescriptor) throws {
        try descriptor.validate()
        let urls = artifactURLs(for: source)
        if descriptor.status == "unavailable" {
            guard !FileManager.default.fileExists(atPath: urls.input.path),
                  !FileManager.default.fileExists(atPath: urls.points.path) else { throw ScanReplayError.invalidArchive }
            return
        }
        try verifyFile(urls.input, size: descriptor.inputByteCount!, digest: descriptor.inputSHA256!)
        try verifyFile(urls.points, size: descriptor.pointsByteCount!, digest: descriptor.pointsSHA256!)
    }

    static func read(source: URL, descriptor: ScanReplayDescriptor) throws -> (ScanReplayInputDTO, ScanFusionYieldBuilder.Input) {
        let urls = artifactURLs(for: source)
        return try read(inputURL: urls.input, pointsURL: urls.points, descriptor: descriptor)
    }

    static func read(inputURL: URL, pointsURL: URL, descriptor: ScanReplayDescriptor) throws -> (ScanReplayInputDTO, ScanFusionYieldBuilder.Input) {
        try descriptor.validate()
        guard descriptor.status == "complete" else { throw ScanReplayError.unavailable }
        guard let data = PLYParserHelper.readBoundedCompanionData(at: inputURL, maximumByteCount: ScanReplayLimits.maximumInputBytes),
              data.count == descriptor.inputByteCount, ScanCompanionIntegrity.digest(data) == descriptor.inputSHA256 else {
            throw ScanReplayError.invalidArchive
        }
        let dto = try decoder().decode(ScanReplayInputDTO.self, from: data)
        guard dto.identity == descriptor.identity, dto.pointCount == descriptor.pointCount,
              dto.observations.values.count == descriptor.observationCount else { throw ScanReplayError.invalidArchive }
        let points = try readPoints(at: pointsURL, count: dto.pointCount, digest: descriptor.pointsSHA256!)
        return (dto, try dto.input(points: points))
    }

    static func verifyFile(_ url: URL, size: Int, digest: String) throws {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == size,
              try ScanCompanionIntegrity.digestFile(at: url) == digest else { throw ScanReplayError.invalidArchive }
    }

    static func writePoints(_ points: [ColoredPoint], to url: URL) throws {
        guard points.count > 0, points.count <= ScanReplayLimits.maximumPoints else { throw ScanReplayError.budgetExceeded }
        try Data().write(to: url, options: .withoutOverwriting)
        let handle = try FileHandle(forWritingTo: url)
        defer { try? handle.close() }
        var header = magic
        appendWord(UInt32(points.count), to: &header)
        try handle.write(contentsOf: header)
        var chunk = Data()
        chunk.reserveCapacity(1_024 * ScanReplayLimits.pointStrideBytes)
        for start in stride(from: 0, to: points.count, by: 1_024) {
            try Task.checkCancellation()
            chunk.removeAll(keepingCapacity: true)
            for point in points[start..<min(start + 1_024, points.count)] {
                appendWord(point.pos.x.bitPattern, to: &chunk)
                appendWord(point.pos.y.bitPattern, to: &chunk)
                appendWord(point.pos.z.bitPattern, to: &chunk)
                appendWord(point.r.bitPattern, to: &chunk)
                appendWord(point.g.bitPattern, to: &chunk)
                appendWord(point.b.bitPattern, to: &chunk)
            }
            try handle.write(contentsOf: chunk)
        }
        try handle.synchronize()
        try handle.close()
    }

    static func readPoints(at url: URL, count: Int, digest: String) throws -> [ColoredPoint] {
        guard (1...ScanReplayLimits.maximumPoints).contains(count) else { throw ScanReplayError.budgetExceeded }
        let expectedSize = ScanReplayLimits.pointHeaderBytes + count * ScanReplayLimits.pointStrideBytes
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard attributes[.type] as? FileAttributeType == .typeRegular,
              (attributes[.size] as? NSNumber)?.intValue == expectedSize else { throw ScanReplayError.invalidArchive }
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        return try readPoints(handle: handle, count: count, digest: digest, requireEndOfFile: true)
    }

    static func readPoints(handle: FileHandle, count: Int, digest: String, requireEndOfFile: Bool) throws -> [ColoredPoint] {
        guard (1...ScanReplayLimits.maximumPoints).contains(count) else { throw ScanReplayError.budgetExceeded }
        let header = try readExactly(ScanReplayLimits.pointHeaderBytes, handle: handle)
        guard header.prefix(8) == magic, Int(word(header, 8)) == count else { throw ScanReplayError.invalidArchive }
        var hash = SHA256()
        hash.update(data: header)
        var points: [ColoredPoint] = []
        points.reserveCapacity(count)
        while points.count < count {
            try Task.checkCancellation()
            let chunkCount = min(1_024, count - points.count)
            let data = try readExactly(chunkCount * ScanReplayLimits.pointStrideBytes, handle: handle)
            hash.update(data: data)
            for index in 0..<chunkCount {
                let offset = index * ScanReplayLimits.pointStrideBytes
                points.append(.init(pos: .init(Float(bitPattern: word(data, offset)), Float(bitPattern: word(data, offset + 4)),
                                              Float(bitPattern: word(data, offset + 8))),
                                    r: Float(bitPattern: word(data, offset + 12)), g: Float(bitPattern: word(data, offset + 16)),
                                    b: Float(bitPattern: word(data, offset + 20))))
            }
        }
        guard hash.finalize().map({ String(format: "%02x", $0) }).joined() == digest else { throw ScanReplayError.invalidArchive }
        if requireEndOfFile, !(try handle.read(upToCount: 1)?.isEmpty ?? true) { throw ScanReplayError.invalidArchive }
        return points
    }

    private static func appendWord(_ word: UInt32, to data: inout Data) {
        var value = word.littleEndian
        withUnsafeBytes(of: &value) { data.append(contentsOf: $0) }
    }

    private static func word(_ data: Data, _ offset: Int) -> UInt32 {
        (0..<4).reduce(UInt32(0)) { $0 | UInt32(data[offset + $1]) << UInt32($1 * 8) }
    }

    static func readExactly(_ count: Int, handle: FileHandle) throws -> Data {
        var result = Data()
        while result.count < count {
            try Task.checkCancellation()
            guard let data = try handle.read(upToCount: count - result.count), !data.isEmpty else { throw ScanReplayError.invalidArchive }
            result.append(data)
        }
        return result
    }
}
