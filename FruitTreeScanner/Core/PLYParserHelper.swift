import Foundation

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
        let result = readCompanionResult(for: url)

        return PLYParserResult(
            treeID: metadata.treeID,
            scanDate: metadata.scanDate,
            gpsLat: metadata.gpsLat,
            gpsLon: metadata.gpsLon,
            fruitCount: result.fruitCount,
            yieldKg: result.yieldKg,
            fruitType: result.fruitType,
            confidence: result.confidence
        )
    }

    static func parsePointCloudData(at url: URL) -> PointCloudData? {
        guard let data = try? Data(contentsOf: url, options: .mappedIfSafe) else { return nil }
        let prefix = Data(data.prefix(maximumHeaderSize + 1))
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
            return parseASCIIPointCloud(
                data: data,
                bodyStart: bodyStart,
                schema: schema,
                sourceURL: url
            )
        case .binaryLittleEndian, .binaryBigEndian:
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
}
