// PLYCompanionResultReader.swift
// Reads transactional and legacy scan result companions stored next to PLY files.

import Foundation

extension PLYParserHelper {
    struct CompanionResult: Equatable, Sendable {
        let fruitCount: Int
        let yieldKg: Float
        let fruitType: String
        let confidence: String
    }

    struct CompanionReadResult: Equatable, Sendable {
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
        let csvExists = FileManager.default.fileExists(atPath: urls.csv.path)
        if let metadata = readCompanionMetadata(at: urls.metadata) {
            guard !metadata.hasRevisionField else {
                return CompanionReadResult(state: .invalid, result: nil, failureReason: "scanResultManifestMissing")
            }
            return CompanionReadResult(state: .complete, result: metadata.result, failureReason: nil)
        }
        if jsonExists {
            return CompanionReadResult(state: .invalid, result: nil, failureReason: "scanResultJSONFailed")
        }
        if let csv = readCompanionCSV(at: urls.csv) {
            guard !csv.hasRevisionField else {
                return CompanionReadResult(state: .invalid, result: nil, failureReason: "scanResultManifestMissing")
            }
            return CompanionReadResult(state: .complete, result: csv.result, failureReason: nil)
        }
        if csvExists {
            return CompanionReadResult(state: .invalid, result: nil, failureReason: "scanResultCSVFailed")
        }
        return CompanionReadResult(state: .incomplete, result: nil, failureReason: "orphanPLYDetected")
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
              manifest["schemaVersion"] as? Int == 1,
              let revision = manifest["exportRevision"] as? String,
              !revision.isEmpty,
              let requiredFiles = manifest["requiredFiles"] as? [String],
              requiredFiles.contains(urls.metadata.lastPathComponent),
              let metadata = readCompanionMetadata(at: urls.metadata),
              metadata.revision == revision
        else {
            return CompanionReadResult(state: .invalid, result: nil, failureReason: "scanResultRevisionMismatch")
        }

        if requiredFiles.contains(urls.csv.lastPathComponent) {
            guard let csv = readCompanionCSV(at: urls.csv), csv.revision == revision else {
                return CompanionReadResult(state: .invalid, result: nil, failureReason: "scanResultRevisionMismatch")
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

    private static func readCompanionMetadata(
        at url: URL
    ) -> (result: CompanionResult, revision: String?, hasRevisionField: Bool)? {
        guard let data = try? Data(contentsOf: url),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
              let fruitCount = nonNegativeIntValue(payload["fruitCount"]),
              let yieldKg = nonNegativeFloatValue(payload["yieldKg"])
        else { return nil }
        return (
            CompanionResult(
                fruitCount: fruitCount,
                yieldKg: yieldKg,
                fruitType: payload["fruitType"] as? String ?? "",
                confidence: payload["confidence"] as? String ?? ""
            ),
            payload["exportRevision"] as? String,
            payload.keys.contains("exportRevision")
        )
    }

    private static func readCompanionCSV(
        at url: URL
    ) -> (result: CompanionResult, revision: String?, hasRevisionField: Bool)? {
        guard let csvContent = try? String(contentsOf: url, encoding: .utf8) else { return nil }
        let records = csvRecords(csvContent)
        guard let headerLine = records.first, let dataLine = records.dropFirst().first else { return nil }
        let header = parseCSVLine(headerLine)
        let values = parseCSVLine(dataLine)
        let revisionHeaders = Set(["ExportRevision", "exportRevision"].map(normalizedCSVHeader))
        guard let countValue = csvValue(in: values, header: header, named: ["果实数量", "fruitCount", "fruit_count"], fallbackIndex: 3),
              let yieldValue = csvValue(in: values, header: header, named: ["产量(kg)", "yieldKg", "yield_kg"], fallbackIndex: 4),
              let fruitCount = nonNegativeIntValue(countValue),
              let yieldKg = nonNegativeFloatValue(yieldValue)
        else { return nil }
        return (
            CompanionResult(
                fruitCount: fruitCount,
                yieldKg: yieldKg,
                fruitType: csvValue(in: values, header: header, named: ["水果类型", "fruitType", "fruit_type"], fallbackIndex: 1) ?? "",
                confidence: csvValue(in: values, header: header, named: ["置信度", "confidence"], fallbackIndex: 12) ?? ""
            ),
            csvValue(in: values, header: header, named: ["ExportRevision", "exportRevision"], fallbackIndex: .max),
            header.contains { revisionHeaders.contains(normalizedCSVHeader($0)) }
        )
    }

    static func csvValue(in values: [String], header: [String], named names: [String], fallbackIndex: Int) -> String? {
        let normalizedNames = Set(names.map(normalizedCSVHeader))
        if let headerIndex = header.firstIndex(where: { normalizedNames.contains(normalizedCSVHeader($0)) }),
           values.indices.contains(headerIndex), let value = nonEmptyCSVValue(values[headerIndex]) {
            return value
        }
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

    static func nonNegativeIntValue(_ value: Any?) -> Int? {
        guard let raw = finiteDouble(value), raw >= 0, raw.rounded(.towardZero) == raw,
              raw <= Double(Int.max) else { return nil }
        return Int(raw)
    }

    static func nonNegativeFloatValue(_ value: Any?) -> Float? {
        guard let raw = finiteDouble(value), raw >= 0, raw <= Double(Float.greatestFiniteMagnitude) else { return nil }
        return Float(raw)
    }

    private static func finiteDouble(_ value: Any?) -> Double? {
        let parsed: Double?
        if let value = value as? Int { parsed = Double(value) }
        else if let value = value as? Double { parsed = value }
        else if let value = value as? Float { parsed = Double(value) }
        else if let value = value as? NSNumber { parsed = value.doubleValue }
        else if let value = value as? String { parsed = Double(value.trimmingCharacters(in: .whitespacesAndNewlines)) }
        else { parsed = nil }
        guard let parsed, parsed.isFinite else { return nil }
        return parsed
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

    private static func csvRecords(_ content: String) -> [String] {
        let normalized = content.replacingOccurrences(of: "\r\n", with: "\n").replacingOccurrences(of: "\r", with: "\n")
        var records: [String] = []
        var current = ""
        var isQuoted = false
        var index = normalized.startIndex
        while index < normalized.endIndex {
            let char = normalized[index]
            if char == "\"" {
                let next = normalized.index(after: index)
                if isQuoted, next < normalized.endIndex, normalized[next] == "\"" {
                    current.append(char)
                    current.append(normalized[next])
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
            index = normalized.index(after: index)
        }
        if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { records.append(current) }
        return records
    }
}
