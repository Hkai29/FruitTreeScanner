// BatchExportCSVWriter.swift
// CSV writer for batch scan exports.

import Foundation

enum BatchExportCSVWriter {
    static func write(
        records: [ScanFileRecord],
        options: BatchExportService.ExportOptions,
        to url: URL
    ) throws {
        var rows: [String] = []
        rows.reserveCapacity(records.count + 4)

        rows.append(
            BatchExportFormatting.headers(options: options)
                .map(BatchExportFormatting.escapeCSV)
                .joined(separator: ",")
        )

        let dateFormatter = StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd HH:mm")

        for record in BatchExportFormatting.orderedRecords(records, options: options) {
            try Task.checkCancellation()
            rows.append(row(for: record, options: options, dateFormatter: dateFormatter))
        }

        rows.append("")
        rows.append("汇总")
        rows.append(summaryRow(records: records))

        let csvContent = "\u{FEFF}" + rows.joined(separator: "\n") + "\n"
        try csvContent.write(to: url, atomically: true, encoding: .utf8)
    }

    private static func row(
        for record: ScanFileRecord,
        options: BatchExportService.ExportOptions,
        dateFormatter: DateFormatter
    ) -> String {
        var row: [String] = []
        if options.groupBy != .none {
            row.append(
                SpreadsheetTextSafety.neutralizingFormula(
                    BatchExportFormatting.groupLabel(for: record, options: options)
                )
            )
        }
        if options.includeTreeID {
            row.append(SpreadsheetTextSafety.neutralizingFormula(record.treeID))
        }
        if options.includeFruitCount { row.append("\(record.fruitCount)") }
        if options.includeYield { row.append(StableDataFormatting.decimal(record.yieldKg, precision: 2)) }
        if options.includeGPS {
            row.append(StableDataFormatting.decimal(record.gpsLat, precision: 6))
            row.append(StableDataFormatting.decimal(record.gpsLon, precision: 6))
        }
        if options.includeDate { row.append(dateFormatter.string(from: record.scanDate)) }
        row.append(SpreadsheetTextSafety.neutralizingFormula(record.fruitType))

        return row.map(BatchExportFormatting.escapeCSV).joined(separator: ",")
    }

    private static func summaryRow(records: [ScanFileRecord]) -> String {
        [
            "总计",
            "\(records.count) 棵",
            "\(BatchExportFormatting.totalFruitCount(records)) 个",
            "\(StableDataFormatting.decimal(BatchExportFormatting.totalYield(records), precision: 2)) kg"
        ]
        .map(BatchExportFormatting.escapeCSV)
        .joined(separator: ",")
    }
}

enum BatchExportJSONWriter {
    private static let exportVersion = 1

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
                return recordPayload(for: record)
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

    private static func recordPayload(for record: ScanFileRecord) -> [String: Any] {
        let sidecar = singleScanMetadata(for: record)
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
            "diagnostics": diagnostics ?? [:],
            "imageDiagnostics": imageDiagnostics(from: diagnostics),
            "singleScanMetadataAvailable": sidecar != nil,
            "compatibilityNote": sidecar == nil
                ? "Single-scan _result.json sidecar unavailable; batch JSON includes scan-history summary fields only for this record."
                : "Single-scan _result.json sidecar found; detailed research fields included where available."
        ]
    }

    private static func singleScanMetadata(for record: ScanFileRecord) -> [String: Any]? {
        let baseName = (record.fileURL.lastPathComponent as NSString).deletingPathExtension
        guard !baseName.isEmpty else { return nil }
        let metadataURL = record.fileURL
            .deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")
        guard let data = try? Data(contentsOf: metadataURL),
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return payload
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

    private static func intValue(_ value: Any?) -> Int {
        if let value = value as? Int { return value }
        if let value = value as? NSNumber { return value.intValue }
        return 0
    }

    private static func stringValue(_ value: Any?) -> String {
        value as? String ?? ""
    }

    private static func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }
}
