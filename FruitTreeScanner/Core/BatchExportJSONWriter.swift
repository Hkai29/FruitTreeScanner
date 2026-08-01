// BatchExportJSONWriter.swift
// Research JSON writer for batch scan exports.

import Foundation

enum BatchExportJSONWriter {
    private static let exportVersion = 1
    static let maximumSingleScanManifestByteCount = 64 * 1_024
    static let maximumSingleScanMetadataByteCount = 16 * 1_024 * 1_024
    static let maximumSingleScanCSVByteCount = 1 * 1_024 * 1_024
    private static let sidecarReadChunkByteCount = 64 * 1_024

    static func write(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions,
        to url: URL
    ) throws {
        let payload: [String: Any] = [
            "exportMetadata": exportMetadata(records: records, options: options),
            "compatibilityNote": "Batch research JSON appends structured research fields without changing CSV, Excel, or single-scan JSON compatibility. Per-scan detailed fields are populated when the matching single-scan _result.json sidecar is available.",
            "records": try BatchExportFormatting.orderedRecords(records, options: options).map { record in
                try Task.checkCancellation()
                return try recordPayload(for: record)
            }
        ]

        let data = try JSONSerialization.data(
            withJSONObject: payload,
            options: [.prettyPrinted, .sortedKeys]
        )
        try data.write(to: url, options: .atomic)
    }

    private static func exportMetadata(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions
    ) -> [String: Any] {
        [
            "exportVersion": exportVersion,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "recordCount": records.count,
            "totalEstimatedCount": BatchExportFormatting.totalFruitCount(records),
            "totalEstimatedYieldKg": finite(BatchExportFormatting.totalYield(records)),
            "format": "batch_research_json",
            "groupBy": options.groupBy.rawValue,
            "csvExcelColumnOptions": [
                "includeTreeID": options.includeTreeID,
                "includeFruitCount": options.includeFruitCount,
                "includeYield": options.includeYield,
                "includeGPS": options.includeGPS,
                "includeDate": options.includeDate
            ]
        ]
    }

    private static func recordPayload(for record: ScanFileRecord) throws -> [String: Any] {
        let sidecar = try singleScanMetadata(for: record)
        let diagnostics = sidecar?["diagnostics"] as? [String: Any]
        let baseName = (record.fileURL.lastPathComponent as NSString).deletingPathExtension
        let scanID = sidecar?["scanID"] as? String ?? baseName
        let sourceFilename = sidecar?["sourceFilename"] as? String ?? record.fileURL.lastPathComponent

        return [
            "scanID": scanID,
            "sourceFilename": sourceFilename,
            "treeID": record.treeID,
            "treeName": NSNull(),
            "orchardName": NSNull(),
            "timestamp": ISO8601DateFormatter().string(from: record.scanDate),
            "date": StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss").string(from: record.scanDate),
            "fruitType": record.fruitType,
            "estimatedCount": record.fruitCount,
            "estimatedYield": finite(record.yieldKg),
            "estimatedYieldKg": finite(record.yieldKg),
            "gpsLat": record.gpsLat,
            "gpsLon": record.gpsLon,
            "confidence": record.confidence,
            "validatedFruits": sidecar?["validatedFruits"] as? [[String: Any]] ?? [],
            "fruitMassEstimates": sidecar?["fruitMassEstimates"] as? [[String: Any]] ?? [],
            "sourceCounts": sourceCounts(from: diagnostics),
            "zeroYieldReasons": diagnostics?["zeroYieldReasons"] as? [String] ?? [],
            "diagnostics": sanitizedDiagnostics(diagnostics),
            "imageDiagnostics": imageDiagnostics(from: diagnostics),
            "recognitionDiagnostics": recognitionDiagnostics(from: sidecar, diagnostics: diagnostics),
            "singleScanMetadataAvailable": sidecar != nil,
            "compatibilityNote": sidecar == nil
                ? "Single-scan _result.json sidecar unavailable; batch JSON includes scan-history summary fields only for this record."
                : "Single-scan _result.json sidecar found; detailed research fields included where available."
        ]
    }

    private static func singleScanMetadata(
        for record: ScanFileRecord
    ) throws -> [String: Any]? {
        let baseName = (record.fileURL.lastPathComponent as NSString).deletingPathExtension
        guard !baseName.isEmpty else { return nil }
        let directory = record.fileURL.deletingLastPathComponent()
        let metadataURL = directory.appendingPathComponent("\(baseName)_result.json")
        let manifestURL = directory.appendingPathComponent("\(baseName)_complete.json")
        let csvURL = directory.appendingPathComponent("\(baseName).csv")

        let transaction: (revision: String, requiredFiles: [String])?
        if FileManager.default.fileExists(atPath: manifestURL.path) {
            guard let manifestData = try readBoundedSidecarData(
                      at: manifestURL,
                      maximumByteCount: maximumSingleScanManifestByteCount
                  ),
                  let manifest = try? JSONSerialization.jsonObject(
                      with: manifestData
                  ) as? [String: Any],
                  manifest["schemaVersion"] as? Int == 1,
                  let revision = manifest["exportRevision"] as? String,
                  !revision.isEmpty,
                  let requiredFiles = manifest["requiredFiles"] as? [String],
                  requiredFiles.contains(metadataURL.lastPathComponent)
            else {
                return nil
            }
            try Task.checkCancellation()
            transaction = (revision, requiredFiles)
        } else {
            transaction = nil
        }

        guard let metadataData = try readBoundedSidecarData(
                  at: metadataURL,
                  maximumByteCount: maximumSingleScanMetadataByteCount
              ),
              let payload = try? JSONSerialization.jsonObject(
                  with: metadataData
              ) as? [String: Any]
        else {
            return nil
        }
        try Task.checkCancellation()

        if let transaction {
            guard payload["exportRevision"] as? String == transaction.revision else {
                return nil
            }
            if transaction.requiredFiles.contains(csvURL.lastPathComponent) {
                guard try csvRevisionMatches(
                    at: csvURL,
                    revision: transaction.revision
                ) else {
                    return nil
                }
            }
        } else if payload.keys.contains("exportRevision") {
            return nil
        }
        return payload
    }

    private static func readBoundedSidecarData(
        at url: URL,
        maximumByteCount: Int
    ) throws -> Data? {
        try Task.checkCancellation()
        guard maximumByteCount >= 0, maximumByteCount < Int.max else { return nil }
        if let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
           fileSize > maximumByteCount {
            return nil
        }
        guard let handle = try? FileHandle(forReadingFrom: url) else { return nil }
        defer { try? handle.close() }

        var data = Data()
        data.reserveCapacity(min(maximumByteCount, sidecarReadChunkByteCount))
        do {
            while data.count <= maximumByteCount {
                try Task.checkCancellation()
                let remainingByteCount = maximumByteCount - data.count + 1
                let readByteCount = min(sidecarReadChunkByteCount, remainingByteCount)
                guard let chunk = try handle.read(upToCount: readByteCount),
                      !chunk.isEmpty
                else {
                    return data
                }
                data.append(chunk)
                guard data.count <= maximumByteCount else { return nil }
            }
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            return nil
        }
        return nil
    }

    private static func csvRevisionMatches(
        at url: URL,
        revision: String
    ) throws -> Bool {
        guard let data = try readBoundedSidecarData(
                  at: url,
                  maximumByteCount: maximumSingleScanCSVByteCount
              ),
              let content = String(data: data, encoding: .utf8)
        else {
            return false
        }
        try Task.checkCancellation()
        let records = firstCSVRecords(content, limit: 2)
        guard let headerLine = records.first,
              let dataLine = records.dropFirst().first
        else {
            return false
        }
        let header = PLYParserHelper.parseCSVLine(headerLine)
        let values = PLYParserHelper.parseCSVLine(dataLine)
        return PLYParserHelper.csvValue(
            in: values,
            header: header,
            named: ["ExportRevision", "exportRevision"],
            fallbackIndex: .max
        ) == revision
    }

    private static func firstCSVRecords(_ content: String, limit: Int) -> [String] {
        guard limit > 0 else { return [] }
        var records: [String] = []
        var current = ""
        var isQuoted = false
        var index = content.startIndex
        while index < content.endIndex {
            var char = content[index]
            if char == "\r\n" {
                char = "\n"
            } else if char == "\r" {
                let next = content.index(after: index)
                if next < content.endIndex, content[next] == "\n" {
                    index = next
                }
                char = "\n"
            }
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
                if !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    records.append(current)
                    if records.count == limit {
                        return records
                    }
                }
                current = ""
            } else {
                current.append(char)
            }
            index = content.index(after: index)
        }
        if records.count < limit,
           !current.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            records.append(current)
        }
        return records
    }

    private static func sourceCounts(from diagnostics: [String: Any]?) -> [String: Any] {
        [
            "validatedFruitCount": intValue(diagnostics?["validatedFruitCount"]),
            "fusedCount": intValue(diagnostics?["fusedValidationCount"]),
            "trackedImageCount": intValue(diagnostics?["trackedImageFruitCount"]),
            "imageOnlyCount": intValue(diagnostics?["imageOnlyFruitCount"]),
            "cloudOnlyCount": intValue(diagnostics?["cloudOnlyFruitCount"])
        ]
    }

    private static func imageDiagnostics(from diagnostics: [String: Any]?) -> [String: Any] {
        [
            "imageFramesProcessed": intValue(diagnostics?["imageFramesProcessed"]),
            "imageObservationCount": intValue(diagnostics?["imageObservationCount"]),
            "imageConfidenceFilteredCount": intValue(diagnostics?["imageConfidenceFilteredCount"]),
            "imageMappedFruitCount": intValue(diagnostics?["imageMappedFruitCount"]),
            "imageModelStatus": stringValue(diagnostics?["imageModelStatus"]),
            "imageModelName": stringValue(diagnostics?["imageModelName"]),
            "imageFailureReason": stringValue(diagnostics?["imageFailureReason"])
        ]
    }

    private static func sanitizedDiagnostics(_ diagnostics: [String: Any]?) -> [String: Any] {
        guard var diagnostics else { return [:] }
        diagnostics.removeValue(forKey: "rawPredictions")
        diagnostics.removeValue(forKey: "filteredPredictions")
        return diagnostics
    }

    private static func recognitionDiagnostics(
        from sidecar: [String: Any]?,
        diagnostics: [String: Any]?
    ) -> [String: Any] {
        if let payload = sidecar?["recognitionDiagnostics"] as? [String: Any] {
            return [
                "metadataAvailable": boolValue(payload["metadataAvailable"], defaultValue: sidecar != nil),
                "modelLabelCompatibilityStatus": stringValue(payload["modelLabelCompatibilityStatus"]),
                "modelLabelCompatibilityWarnings": stringArrayValue(payload["modelLabelCompatibilityWarnings"]),
                "runtimeModelLabelsAvailable": boolValue(payload["runtimeModelLabelsAvailable"]),
                "runtimeModelLabelCount": intValue(payload["runtimeModelLabelCount"]),
                "rawDetectedLabels": stringArrayValue(payload["rawDetectedLabels"]),
                "mappedDetectedCategories": stringArrayValue(payload["mappedDetectedCategories"]),
                "unmappedDetectedLabels": stringArrayValue(payload["unmappedDetectedLabels"]),
                "filteredBySelectedFruitTypeCount": intValue(payload["filteredBySelectedFruitTypeCount"]),
                "confidenceFilteredCount": intValue(payload["confidenceFilteredCount"]),
                "unmappedObservationCount": intValue(payload["unmappedObservationCount"]),
                "mappedFruitCount": intValue(payload["mappedFruitCount"])
            ]
        }

        return [
            "metadataAvailable": sidecar != nil,
            "modelLabelCompatibilityStatus": stringValue(diagnostics?["imageModelLabelCompatibilityStatus"]),
            "modelLabelCompatibilityWarnings": stringArrayValue(diagnostics?["imageModelLabelCompatibilityWarnings"]),
            "runtimeModelLabelsAvailable": boolValue(diagnostics?["imageRuntimeModelLabelsAvailable"]),
            "runtimeModelLabelCount": stringArrayValue(diagnostics?["imageRuntimeModelLabels"]).count,
            "rawDetectedLabels": stringArrayValue(diagnostics?["imageRawDetectedLabels"]),
            "mappedDetectedCategories": stringArrayValue(diagnostics?["imageMappedCategories"]),
            "unmappedDetectedLabels": stringArrayValue(diagnostics?["imageUnmappedLabels"]),
            "filteredBySelectedFruitTypeCount": intValue(diagnostics?["filteredBySelectedFruitTypeCount"]),
            "confidenceFilteredCount": intValue(diagnostics?["imageConfidenceFilteredCount"]),
            "unmappedObservationCount": max(0, intValue(diagnostics?["imageObservationCount"]) - intValue(diagnostics?["imageConfidenceFilteredCount"]) - intValue(diagnostics?["imageMappedFruitCount"])),
            "mappedFruitCount": intValue(diagnostics?["imageMappedFruitCount"])
        ]
    }

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func boolValue(_ value: Any?, defaultValue: Bool = false) -> Bool {
        if let value = value as? Bool { return value }
        if let value = value as? NSNumber { return value.boolValue }
        return defaultValue
    }

    private static func stringValue(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private static func stringArrayValue(_ value: Any?, limit: Int = 32) -> [String] {
        guard let values = value as? [String] else { return [] }
        return Array(values.filter { !$0.isEmpty }.prefix(limit))
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
