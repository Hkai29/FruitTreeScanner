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
}

// MARK: - Shared PLY filename + result parsing
//
// Filename: treeID_yyyyMMdd_HHmmss_latXX_lonXX.ply
// Companion CSV: header row + data row with >= 6 columns:
//   [0]? [1]fruitType [2]? [3]fruitCount [4]yieldKg [5]?
//
enum PLYParserHelper {
    static func parsePLYFile(at url: URL) -> PLYParserResult? {
        let metadata = parseFilenameMetadata(from: url)
            ?? parseHeaderMetadata(from: url)
            ?? fallbackMetadata(from: url)
        let result = readCompanionResult(for: url)

        return PLYParserResult(
            treeID: metadata.treeID,
            scanDate: metadata.scanDate,
            gpsLat: metadata.gpsLat,
            gpsLon: metadata.gpsLon,
            fruitCount: result.fruitCount,
            yieldKg: result.yieldKg,
            fruitType: result.fruitType
        )
    }

    static func parsePointCloudData(at url: URL) -> PointCloudData? {
        guard let data = try? Data(contentsOf: url) else { return nil }
        guard let headerEndRange = data.range(of: Data("end_header\n".utf8))
                ?? data.range(of: Data("end_header\r\n".utf8)) else { return nil }
        guard let header = String(data: data[data.startIndex..<headerEndRange.lowerBound], encoding: .utf8) else {
            return nil
        }

        let headerLines = header
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        let properties = parsePointCloudHeader(headerLines)
        guard properties.vertexCount > 0 else { return nil }

        let bodyStart = headerEndRange.upperBound
        if properties.isBinary {
            return parseBinaryPointCloud(
                data: data,
                bodyStart: bodyStart,
                vertexCount: properties.vertexCount,
                bigEndian: properties.isBigEndian,
                hasColor: properties.hasColor,
                sourceURL: url
            )
        }
        return parseASCIIPointCloud(
            data: data,
            bodyStart: bodyStart,
            vertexCount: properties.vertexCount,
            sourceURL: url
        )
    }
}
