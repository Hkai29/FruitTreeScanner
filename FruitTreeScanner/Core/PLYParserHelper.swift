import Foundation

enum ScanPersistenceState: String, Sendable {
    case complete
    case incomplete
    case invalid
}

// MARK: - Result type returned by PLYParserHelper
struct PLYParserResult: Sendable {
    let treeID: String
    let scanDate: Date
    let gpsLat: Double
    let gpsLon: Double
    let fruitCount: Int
    let yieldKg: Float
    let fruitType: String
    let confidence: String
    let persistenceState: ScanPersistenceState
    let persistenceFailureReason: String?
}

// MARK: - Shared PLY filename + result parsing
//
// Filename: treeID_yyyyMMdd_HHmmss_latXX_lonXX.ply
// Companion CSV: header row + data row with >= 6 columns:
//   [0]? [1]fruitType [2]? [3]fruitCount [4]yieldKg [5]?
//
enum PLYParserHelper {
    static let maximumHeaderSize = 64 * 1_024

    static func parsePLYFile(at url: URL) -> PLYParserResult? {
        let metadata = parseHeaderMetadata(from: url)
            ?? parseFilenameMetadata(from: url)
            ?? fallbackMetadata(from: url)
        let companion = readCompanionResult(for: url)

        return PLYParserResult(
            treeID: metadata.treeID,
            scanDate: metadata.scanDate,
            gpsLat: metadata.gpsLat,
            gpsLon: metadata.gpsLon,
            fruitCount: companion.result?.fruitCount ?? 0,
            yieldKg: companion.result?.yieldKg ?? 0,
            fruitType: companion.result?.fruitType ?? "",
            confidence: companion.result?.confidence ?? "",
            persistenceState: companion.state,
            persistenceFailureReason: companion.failureReason
        )
    }

    static func parsePointCloudData(at url: URL) -> PointCloudData? {
        try? parsePointCloudDataCancellable(at: url)
    }

    static func parsePointCloudDataCancellable(at url: URL) throws -> PointCloudData? {
        try Task.checkCancellation()
        let pointCloudData = parsePointCloudDataUnchecked(at: url)
        try Task.checkCancellation()
        return pointCloudData
    }

    private static func parsePointCloudDataUnchecked(at url: URL) -> PointCloudData? {
        guard let prefix = readPointCloudHeaderPrefix(at: url) else { return nil }
        guard let headerEndRange = headerEndRange(in: prefix),
              headerEndRange.upperBound <= maximumHeaderSize,
              let header = String(
                  data: prefix[prefix.startIndex..<headerEndRange.lowerBound],
                  encoding: .utf8
              )
        else {
            return nil
        }

        let headerLines = header
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard let schema = parsePointCloudHeader(headerLines) else { return nil }

        let bodyStart = headerEndRange.upperBound
        switch schema.format {
        case .ascii:
            return parseStreamingASCIIPointCloud(
                at: url,
                bodyStart: bodyStart,
                schema: schema,
                sourceURL: url
            )
        case .binaryLittleEndian, .binaryBigEndian:
            guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
            return parseBinaryPointCloud(
                data: data,
                bodyStart: bodyStart,
                schema: schema,
                sourceURL: url
            )
        }
    }

    static func headerEndRange(in data: Data) -> Range<Data.Index>? {
        data.range(of: Data("\nend_header\r\n".utf8))
            ?? data.range(of: Data("\nend_header\n".utf8))
    }

    private static func readPointCloudHeaderPrefix(at url: URL) -> Data? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        do {
            return try handle.read(upToCount: maximumHeaderSize + 1) ?? Data()
        } catch {
            return nil
        }
    }
}
