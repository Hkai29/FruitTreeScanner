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
            gpsLat: finiteDouble(String(latStr.dropFirst(3))) ?? 0,
            gpsLon: finiteDouble(String(lonStr.dropFirst(3))) ?? 0
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
                gpsLat = finiteDouble(value)
            } else if let value = commentValue(in: trimmed, key: "gps_lon") {
                gpsLon = finiteDouble(value)
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

    static func finiteDouble(_ value: String) -> Double? {
        guard let number = Double(value), number.isFinite else { return nil }
        return number
    }

}
