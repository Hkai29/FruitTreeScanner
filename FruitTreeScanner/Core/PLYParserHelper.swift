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
    private struct ParsedPLYMetadata {
        let treeID: String
        let scanDate: Date
        let gpsLat: Double
        let gpsLon: Double
    }

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

    // MARK: - Metadata readers
    private static func parseFilenameMetadata(from url: URL) -> ParsedPLYMetadata? {
        let filename = url.deletingPathExtension().lastPathComponent
        let parts = filename.split(separator: "_")
        guard parts.count >= 5,
              parts[parts.count - 2].hasPrefix("lat"),
              parts[parts.count - 1].hasPrefix("lon") else { return nil }

        let treeID = parts[0..<parts.count - 4].joined(separator: "_")
        let latStr = String(parts[parts.count - 2])
        let lonStr = String(parts[parts.count - 1])
        return ParsedPLYMetadata(
            treeID: treeID.isEmpty ? filename : treeID,
            scanDate: parseScanDate(from: parts, fallbackURL: url),
            gpsLat: Double(latStr.dropFirst(3)) ?? 0,
            gpsLon: Double(lonStr.dropFirst(3)) ?? 0
        )
    }

    private static func parseHeaderMetadata(from url: URL) -> ParsedPLYMetadata? {
        guard let header = readPLYHeader(from: url) else { return nil }
        var treeID: String?
        var scanDate: Date?
        var gpsLat: Double?
        var gpsLon: Double?

        for line in header.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            if let value = commentValue(in: trimmed, key: "tree_id") {
                treeID = value
            } else if let value = commentValue(in: trimmed, key: "scan_date") {
                scanDate = parseHeaderDate(value)
            } else if let value = commentValue(in: trimmed, key: "gps_lat") {
                gpsLat = Double(value)
            } else if let value = commentValue(in: trimmed, key: "gps_lon") {
                gpsLon = Double(value)
            }
        }

        guard treeID != nil || scanDate != nil || gpsLat != nil || gpsLon != nil else { return nil }
        return ParsedPLYMetadata(
            treeID: treeID?.isEmpty == false ? treeID! : url.deletingPathExtension().lastPathComponent,
            scanDate: scanDate ?? fallbackDate(for: url),
            gpsLat: gpsLat ?? 0,
            gpsLon: gpsLon ?? 0
        )
    }

    private static func fallbackMetadata(from url: URL) -> ParsedPLYMetadata {
        ParsedPLYMetadata(
            treeID: url.deletingPathExtension().lastPathComponent,
            scanDate: fallbackDate(for: url),
            gpsLat: 0,
            gpsLon: 0
        )
    }

    private static func parseScanDate(from parts: [Substring], fallbackURL url: URL) -> Date {
        let datePart = String(parts[parts.count - 4])
        let timePart = String(parts[parts.count - 3])
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        formatter.dateFormat = "yyyyMMdd_HHmmss"

        if let parsedDate = formatter.date(from: "\(datePart)_\(timePart)") {
            return parsedDate
        }

        return fallbackDate(for: url)
    }

    private static func fallbackDate(for url: URL) -> Date {
        do {
            return (try url.resourceValues(forKeys: [.creationDateKey])).creationDate ?? Date()
        } catch {
            #if DEBUG
            print("[PLYParser] Failed to read creation date: \(error)")
            #endif
            return Date()
        }
    }

    private static func readPLYHeader(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: 16_384)
        guard let prefix = String(data: data, encoding: .utf8) else { return nil }
        if let endRange = prefix.range(of: "end_header") {
            return String(prefix[..<endRange.upperBound])
        }
        return prefix
    }

    private static func commentValue(in line: String, key: String) -> String? {
        let prefix = "comment \(key) "
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    private static func parseHeaderDate(_ value: String) -> Date? {
        if let date = ISO8601DateFormatter().date(from: value) {
            return date
        }
        let formatter = DateFormatter()
        formatter.calendar = Calendar(identifier: .gregorian)
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.timeZone = TimeZone.current
        for format in ["yyyy-MM-dd HH:mm:ss", "yyyyMMdd_HHmmss"] {
            formatter.dateFormat = format
            if let date = formatter.date(from: value) {
                return date
            }
        }
        return nil
    }

    // MARK: - Companion CSV reader
    private static func readCompanionResult(for plyURL: URL) -> (fruitCount: Int, yieldKg: Float, fruitType: String) {
        if let metadata = readCompanionMetadata(for: plyURL) {
            return metadata
        }
        return readCompanionCSV(for: plyURL)
    }

    private static func readCompanionMetadata(for plyURL: URL) -> (fruitCount: Int, yieldKg: Float, fruitType: String)? {
        let baseName = plyURL.deletingPathExtension().lastPathComponent
        let metadataURL = plyURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_result.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return (
            fruitCount: intValue(payload["fruitCount"]),
            yieldKg: floatValue(payload["yieldKg"]),
            fruitType: payload["fruitType"] as? String ?? "apple"
        )
    }

    private static func readCompanionCSV(for plyURL: URL) -> (fruitCount: Int, yieldKg: Float, fruitType: String) {
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")
        guard FileManager.default.fileExists(atPath: csvURL.path) else {
            return (0, 0, "apple")
        }

        do {
            let csvContent = try String(contentsOf: csvURL, encoding: .utf8)
            let lines = csvContent.split(separator: "\n")
            guard lines.count >= 2, let dataLine = lines.dropFirst().first else {
                return (0, 0, "apple")
            }
            let values = parseCSVLine(String(dataLine))
            guard values.count >= 7 else { return (0, 0, "apple") }
            return (
                fruitCount: Int(values[3]) ?? 0,
                yieldKg: Float(values[4]) ?? 0,
                fruitType: values[1]
            )
        } catch {
            #if DEBUG
            print("[PLYParser] Failed to read CSV: \(error)")
            #endif
            return (0, 0, "apple")
        }
    }

    private static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    private static func floatValue(_ value: Any?) -> Float {
        if let float = value as? Float { return float }
        if let double = value as? Double { return Float(double) }
        if let number = value as? NSNumber { return number.floatValue }
        if let string = value as? String { return Float(string) ?? 0 }
        return 0
    }

    private static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = []
        var current = ""
        var isQuoted = false
        var index = line.startIndex

        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let next = line.index(after: index)
                if isQuoted, next < line.endIndex, line[next] == "\"" {
                    current.append("\"")
                    index = next
                } else {
                    isQuoted.toggle()
                }
            } else if char == "," && !isQuoted {
                fields.append(current)
                current = ""
            } else {
                current.append(char)
            }
            index = line.index(after: index)
        }

        fields.append(current)
        return fields
    }
}
