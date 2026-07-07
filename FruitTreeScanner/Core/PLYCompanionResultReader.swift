// PLYCompanionResultReader.swift
// Reads scan result metadata stored next to imported PLY files.

import Foundation

extension PLYParserHelper {
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
            fruitCount: nonNegativeIntValue(payload["fruitCount"]),
            yieldKg: nonNegativeFloatValue(payload["yieldKg"]),
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
                fruitCount: nonNegativeIntValue(csvValue(
                    in: values,
                    header: header,
                    named: ["果实数量", "fruitCount", "fruit_count"],
                    fallbackIndex: 3
                )),
                yieldKg: nonNegativeFloatValue(csvValue(
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

    static func nonNegativeIntValue(_ value: Any?) -> Int {
        max(0, intValue(value))
    }

    static func nonNegativeFloatValue(_ value: Any?) -> Float {
        max(0, floatValue(value))
    }

    static func intValue(_ value: Any?) -> Int {
        if let int = value as? Int { return int }
        if let double = value as? Double { return finiteInt(double) ?? 0 }
        if let number = value as? NSNumber { return finiteInt(number.doubleValue) ?? 0 }
        if let string = value as? String { return Int(string) ?? 0 }
        return 0
    }

    static func floatValue(_ value: Any?) -> Float {
        if let float = value as? Float { return finiteFloat(float) ?? 0 }
        if let double = value as? Double { return finiteFloat(Float(double)) ?? 0 }
        if let number = value as? NSNumber { return finiteFloat(number.floatValue) ?? 0 }
        if let string = value as? String,
           let float = Float(string) {
            return finiteFloat(float) ?? 0
        }
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

    private static func finiteInt(_ value: Double) -> Int? {
        guard value.isFinite,
              value >= Double(Int.min),
              value <= Double(Int.max) else { return nil }
        return Int(value)
    }

    private static func finiteFloat(_ value: Float) -> Float? {
        value.isFinite ? value : nil
    }
}
