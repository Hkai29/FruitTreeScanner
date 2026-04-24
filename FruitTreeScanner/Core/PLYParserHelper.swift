import Foundation

// MARK: - Result type returned by PLYParserHelper
struct PLYParserResult {
    let treeID: String
    let scanDate: Date
    let gpsLat: Double
    let gpsLon: Double
    let fruitCount: Int
    let yieldKg: Float
    let fruitType: String
}

// MARK: - Shared PLY filename + CSV parsing
//
// Filename: treeID_yyyyMMdd_HHmmss_latXX_lonXX.ply
// Companion CSV: header row + data row with >= 6 columns:
//   [0]? [1]fruitType [2]? [3]fruitCount [4]yieldKg [5]?
//
enum PLYParserHelper {
    static func parsePLYFile(at url: URL) -> PLYParserResult? {
        let filename = url.deletingPathExtension().lastPathComponent
        let parts = filename.split(separator: "_")
        guard parts.count >= 5,
              parts[parts.count - 2].hasPrefix("lat"),
              parts[parts.count - 1].hasPrefix("lon") else { return nil }

        let treeID = parts[0..<parts.count - 4].joined(separator: "_")
        let scanDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

        let latStr = String(parts[parts.count - 2])
        let lonStr = String(parts[parts.count - 1])
        let gpsLat = Double(latStr.dropFirst(3)) ?? 0
        let gpsLon = Double(lonStr.dropFirst(3)) ?? 0

        let csv = readCompanionCSV(for: url)

        return PLYParserResult(
            treeID: treeID,
            scanDate: scanDate,
            gpsLat: gpsLat,
            gpsLon: gpsLon,
            fruitCount: csv.fruitCount,
            yieldKg: csv.yieldKg,
            fruitType: csv.fruitType
        )
    }

    // MARK: - Companion CSV reader
    private static func readCompanionCSV(for plyURL: URL) -> (fruitCount: Int, yieldKg: Float, fruitType: String) {
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")
        guard let csvContent = try? String(contentsOf: csvURL, encoding: .utf8) else {
            return (0, 0, "apple")
        }
        let lines = csvContent.split(separator: "\n")
        guard lines.count >= 2, let dataLine = lines.dropFirst().first else {
            return (0, 0, "apple")
        }
        let values = dataLine.split(separator: ",")
        guard values.count >= 6 else { return (0, 0, "apple") }
        return (
            fruitCount: Int(values[3]) ?? 0,
            yieldKg: Float(values[4]) ?? 0,
            fruitType: String(values[1])
        )
    }
}
