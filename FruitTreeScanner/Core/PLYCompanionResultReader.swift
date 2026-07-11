// PLYCompanionResultReader.swift
// Reads transactional and legacy scan result companions stored next to PLY files.

import Foundation

extension PLYParserHelper {
    struct CompanionResult: Equatable {
        let fruitCount: Int
        let yieldKg: Float
        let fruitType: String
        let confidence: String
    }

    struct CompanionReadResult: Equatable {
        let state: ScanPersistenceState
        let result: CompanionResult?
        let failureReason: String?
    }

    static func readCompanionResult(for plyURL: URL) -> CompanionReadResult {
        let urls = companionURLs(for: plyURL)
        if FileManager.default.fileExists(atPath: urls.manifest.path) {
            return readTransactionalCompanions(urls: urls)
        }

        let jsonExists = FileManager.default.fileExists(atPath: urls.metadata.path)
        if let metadata = readCompanionMetadata(at: urls.metadata) {
            return CompanionReadResult(state: .complete, result: metadata.result, failureReason: nil)
        }
        if let csv = readCompanionCSV(at: urls.csv) {
            return CompanionReadResult(state: .complete, result: csv.result, failureReason: nil)
        }
        if jsonExists {
            return CompanionReadResult(
                state: .invalid,
                result: nil,
                failureReason: "scanResultJSONFailed"
            )
        }
        return CompanionReadResult(
            state: .incomplete,
            result: nil,
            failureReason: "orphanPLYDetected"
        )
    }

    static func readCompanionMetadata(for plyURL: URL) -> CompanionResult? {
        readCompanionMetadata(at: companionURLs(for: plyURL).metadata)?.result
    }

    static func readCompanionCSV(for plyURL: URL) -> CompanionResult? {
        readCompanionCSV(at: companionURLs(for: plyURL).csv)?.result
    }

    private static func readTransactionalCompanions(
        urls: (metadata: URL, csv: URL, manifest: URL)
    ) -> CompanionReadResult {
        guard let manifestData = try? Data(contentsOf: urls.manifest),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              let revision = manifest["exportRevision"] as? String,
              let requiredFiles = manifest["requiredFiles"] as? [String],
              requiredFiles.contains(urls.metadata.lastPathComponent),
              let metadata = readCompanionMetadata(at: urls.metadata),
              metadata.revision == revision else {
            return CompanionReadResult(
                state: .invalid,
                result: nil,
                failureReason: "scanResultRevisionMismatch"
            )
        }

        if requiredFiles.contains(urls.csv.lastPathComponent) {
            guard let csv = readCompanionCSV(at: urls.csv), csv.revision == revision else {
                return CompanionReadResult(
                    state: .invalid,
                    result: nil,
                    failureReason: "scanResultRevisionMismatch"
                )
            }
        }
        return CompanionReadResult(state: .complete, result: metadata.result, failureReason: nil)
    }

    private static func companionURLs(for plyURL: URL) -> (metadata: URL, csv: URL, manifest: URL) {
        let directory = plyURL.deletingLastPathComponent()
        let baseName = plyURL.deletingPathExtension().lastPathComponent
        return (
            directory.appendingPathComponent("\(baseName)_result.json"),
            directory.appendingPathComponent("\(baseName).csv"),
            directory.appendingPathComponent("\(baseName)_complete.json")
        )
    }

    private static func readCompanionMetadata(at url: URL) -> (result: CompanionResult, revision: String?)? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              payload["fruitCount"] != nil,
              payload["yieldKg"] != nil else { return nil }
        return (
            CompanionResult(
                fruitCount: nonNegativeIntValue(payload["fruitCount"]),
                yieldKg: nonNegativeFloatValue(payload["yieldKg"]),
                fruitType: payload["fruitType"] as? String ?? "",
                confidence: payload["confidence"] as? String ?? ""
            ),
            payload["exportRevision"] as? String
        )
    }

    private static func readCompanionCSV(at url: URL) -> (result: CompanionResult, revision: String?)? {
        guard let csvContent = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let lines = csvRecords(csvContent)
        guard let headerLine = lines.first, let dataLine = lines.dropFirst().first else { return nil }
        let header = parseCSVLine(headerLine)
        let values = parseCSVLine(dataLine)
        guard !values.isEmpty,
              let fruitCount = csvValue(in: values, header: header, named: ["果实数量", "fruitCount", "fruit_count"], fallbackIndex: 3),
              let yieldKg = csvValue(in: values, header: header, named: ["产量(kg)", "yieldKg", "yield_kg"], fallbackIndex: 4) else { return nil }
        return (
            CompanionResult(
                fruitCount: nonNegativeIntValue(fruitCount),
                yieldKg: nonNegativeFloatValue(yieldKg),
                fruitType: csvValue(in: values, header: header, named: ["水果类型", "fruitType", "fruit_type"], fallbackIndex: 1) ?? "",
                confidence: csvValue(in: values, header: header, named: ["置信度", "confidence"], fallbackIndex: 12) ?? ""
            ),
            csvValue(in: values, header: header, named: ["ExportRevision", "exportRevision"], fallbackIndex: Int.max)
        )
    }

    static func csvValue(in values: [String], header: [String], named names: [String], fallbackIndex: Int) -> String? {
        let normalizedNames = Set(names.map(normalizedCSVHeader))
        if let headerIndex = header.firstIndex(where: { normalizedNames.contains(normalizedCSVHeader($0)) }),
           values.indices.contains(headerIndex), let value = nonEmptyCSVValue(values[headerIndex]) { return value }
        guard values.indices.contains(fallbackIndex) else { return nil }
        return nonEmptyCSVValue(values[fallbackIndex])
    }

    static func normalizedCSVHeader(_ value: String) -> String {
        value.replacingOccurrences(of: "\u{FEFF}", with: "").trimmingCharacters(in: .whitespacesAndNewlines).lowercased()
    }

    static func nonEmptyCSVValue(_ value: String) -> String? {
        let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? nil : trimmed
    }

    static func nonNegativeIntValue(_ value: Any?) -> Int { max(0, intValue(value)) }
    static func nonNegativeFloatValue(_ value: Any?) -> Float { max(0, floatValue(value)) }
    static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let number = value as? NSNumber, number.doubleValue.isFinite { return Int(number.doubleValue) }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }
    static func floatValue(_ rawValue: Any?) -> Float {
        let parsed: Float?
        if let float = rawValue as? Float { parsed = float }
        else if let number = rawValue as? NSNumber { parsed = number.floatValue }
        else if let string = rawValue as? String { parsed = Float(string) }
        else { parsed = nil }
        guard let parsed, parsed.isFinite else { return 0 }
        return parsed
    }

    static func parseCSVLine(_ line: String) -> [String] {
        var fields: [String] = [], current = "", isQuoted = false
        var index = line.startIndex
        while index < line.endIndex {
            let char = line[index]
            if char == "\"" {
                let next = line.index(after: index)
                if isQuoted, next < line.endIndex, line[next] == "\"" { current.append("\""); index = next }
                else { isQuoted.toggle() }
            } else if char == "," && !isQuoted { fields.append(current); current = "" }
            else { current.append(char) }
            index = line.index(after: index)
        }
        fields.append(current)
        return fields
    }

    private static func csvRecords(_ content: String) -> [String] {
        let content = content
            .replacingOccurrences(of: "\r\n", with: "\n")
            .replacingOccurrences(of: "\r", with: "\n")
        var records: [String] = [], current = "", isQuoted = false
        var index = content.startIndex
        while index < content.endIndex {
            let char = content[index]
            if char == "\"" {
                let next = content.index(after: index)
                if isQuoted, next < content.endIndex, content[next] == "\"" {
                    current.append(char)
                    current.append(content[next])
                    index = next
                } else {
                    isQuoted.toggle()
                    current.append(char)
                }
            } else if char == "\n" && !isQuoted {
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { records.append(current) }
                current = ""
            } else {
                current.append(char)
            }
            index = content.index(after: index)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { records.append(current) }
        return records
    }
}
