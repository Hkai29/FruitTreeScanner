// PLYParserMetadata.swift
// Scan metadata and companion result readers for PLY files.

import Foundation

extension PLYParserHelper {
    struct ParsedPLYMetadata {
        let treeID: String
        let scanDate: Date
        let gpsLat: Double
        let gpsLon: Double
    }

    static func parseFilenameMetadata(from url: URL) -> ParsedPLYMetadata? {
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

    static func parseHeaderMetadata(from url: URL) -> ParsedPLYMetadata? {
        guard let header = readPLYHeader(from: url) else { return nil }
        var treeID: String?
        var scanDate: Date?
        var gpsLat: Double?
        var gpsLon: Double?

        for line in header.components(separatedBy: .newlines) {
            let trimmed = line.trimmingCharacters(in: .whitespacesAndNewlines)
            guard !trimmed.isEmpty else { continue }
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
        let safeTreeID = treeID.map(TreeIdentifierPolicy.safePLYCommentValue)
        return ParsedPLYMetadata(
            treeID: safeTreeID?.isEmpty == false ? safeTreeID! : url.deletingPathExtension().lastPathComponent,
            scanDate: scanDate ?? fallbackDate(for: url),
            gpsLat: gpsLat ?? 0,
            gpsLon: gpsLon ?? 0
        )
    }

    static func fallbackMetadata(from url: URL) -> ParsedPLYMetadata {
        ParsedPLYMetadata(
            treeID: url.deletingPathExtension().lastPathComponent,
            scanDate: fallbackDate(for: url),
            gpsLat: 0,
            gpsLon: 0
        )
    }

    static func parseScanDate(from parts: [Substring], fallbackURL url: URL) -> Date {
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

    static func fallbackDate(for url: URL) -> Date {
        do {
            return (try url.resourceValues(forKeys: [.creationDateKey])).creationDate ?? Date()
        } catch {
            return Date()
        }
    }

    static func readPLYHeader(from url: URL) -> String? {
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }
        let data = handle.readData(ofLength: PLYParserHelper.maximumHeaderSize)
        guard let prefix = String(data: data, encoding: .utf8) else { return nil }
        if let endRange = prefix.range(of: "end_header") {
            return String(prefix[..<endRange.upperBound])
        }
        return prefix
    }

    static func commentValue(in line: String, key: String) -> String? {
        let prefix = "comment \(key) "
        guard line.hasPrefix(prefix) else { return nil }
        return String(line.dropFirst(prefix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
    }

    static func parseHeaderDate(_ value: String) -> Date? {
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

    static func readCompanionResult(for plyURL: URL) -> (fruitCount: Int, yieldKg: Float, fruitType: String, confidence: String) {
        if let metadata = readCompanionMetadata(for: plyURL) {
            return metadata
        }
        return readCompanionCSV(for: plyURL)
    }

    static func readCompanionMetadata(for plyURL: URL) -> (fruitCount: Int, yieldKg: Float, fruitType: String, confidence: String)? {
        let baseName = plyURL.deletingPathExtension().lastPathComponent
        let metadataURL = plyURL.deletingLastPathComponent().appendingPathComponent("\(baseName)_result.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else { return nil }

        return (
            fruitCount: intValue(payload["fruitCount"]),
            yieldKg: floatValue(payload["yieldKg"]),
            fruitType: payload["fruitType"] as? String ?? "apple",
            confidence: payload["confidence"] as? String ?? "low"
        )
    }

    static func readCompanionCSV(for plyURL: URL) -> (fruitCount: Int, yieldKg: Float, fruitType: String, confidence: String) {
        let csvURL = plyURL.deletingPathExtension().appendingPathExtension("csv")
        guard FileManager.default.fileExists(atPath: csvURL.path) else {
            return (0, 0, "apple", "low")
        }

        do {
            let csvContent = try String(contentsOf: csvURL, encoding: .utf8)
            let lines = csvContent
                .components(separatedBy: .newlines)
                .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            guard let headerLine = lines.first,
                  let dataLine = lines.dropFirst().first else {
                return (0, 0, "apple", "low")
            }
            let header = parseCSVLine(headerLine)
            let values = parseCSVLine(dataLine)
            guard !values.isEmpty else { return (0, 0, "apple", "low") }
            return (
                fruitCount: intValue(csvValue(
                    in: values,
                    header: header,
                    named: ["果实数量", "fruitCount", "fruit_count"],
                    fallbackIndex: 3
                )),
                yieldKg: floatValue(csvValue(
                    in: values,
                    header: header,
                    named: ["产量(kg)", "yieldKg", "yield_kg"],
                    fallbackIndex: 4
                )),
                fruitType: csvValue(
                    in: values,
                    header: header,
                    named: ["水果类型", "fruitType", "fruit_type"],
                    fallbackIndex: 1
                ) ?? "apple",
                confidence: csvValue(
                    in: values,
                    header: header,
                    named: ["置信度", "confidence"],
                    fallbackIndex: 12
                ) ?? "low"
            )
        } catch {
            return (0, 0, "apple", "low")
        }
    }

    static func csvValue(
        in values: [String],
        header: [String],
        named names: [String],
        fallbackIndex: Int
    ) -> String? {
        let normalizedNames = Set(names.map(normalizedCSVHeader))
        if let headerIndex = header.firstIndex(where: { normalizedNames.contains(normalizedCSVHeader($0)) }),
           values.indices.contains(headerIndex),
           let value = nonEmptyCSVValue(values[headerIndex]) {
            return value
        }
        guard values.indices.contains(fallbackIndex),
              let value = nonEmptyCSVValue(values[fallbackIndex]) else {
            return nil
        }
        return value
    }

    static func normalizedCSVHeader(_ value: String) -> String {
        value
            .replacingOccurrences(of: "\u{FEFF}", with: "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
            .lowercased()
    }

    static func nonEmptyCSVValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return Int(double) }
        if let number = value as? NSNumber { return number.intValue }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    static func floatValue(_ value: Any?) -> Float {
        if let float = value as? Float { return float }
        if let double = value as? Double { return Float(double) }
        if let number = value as? NSNumber { return number.floatValue }
        if let string = value as? String { return Float(string) ?? 0 }
        return 0
    }

    static func parseCSVLine(_ line: String) -> [String] {
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
