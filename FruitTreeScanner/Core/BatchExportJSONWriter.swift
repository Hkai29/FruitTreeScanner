// BatchExportJSONWriter.swift
// Research JSON writer for batch scan exports.

import Foundation

enum BatchExportJSONWriter {
    private static let exportVersion = 1
    private static let compatibilityNote = "Batch research JSON appends structured research fields without changing CSV, Excel, or single-scan JSON compatibility. Per-scan detailed fields are populated when the matching single-scan _result.json sidecar is available."
    static let maximumSingleScanMetadataByteCount = 16 * 1_024 * 1_024

    static func write(
        records: [ScanFileRecord],
        totals: BatchExportTotals,
        options: BatchExportService.ExportOptions,
        to url: URL
    ) throws {
        let metadataData = try JSONSerialization.data(
            withJSONObject: exportMetadata(
                recordCount: records.count,
                totals: totals,
                options: options
            ),
            options: [.prettyPrinted, .sortedKeys]
        )
        let compatibilityNoteData = try JSONSerialization.data(
            withJSONObject: compatibilityNote,
            options: [.fragmentsAllowed]
        )

        try BatchExportStreamWriter.write(to: url) { writer in
            try writer.write("{\n  \"compatibilityNote\" : ")
            try writer.write(compatibilityNoteData)
            try writer.write(",\n  \"exportMetadata\" : ")
            try writer.write(metadataData)
            try writer.write(",\n  \"records\" : [")

            var isFirstRecord = true
            try BatchExportFormatting.forEachOrderedRecord(records, options: options) { record, _ in
                let recordData = try autoreleasepool {
                    try ScanRepository.shared.researchExportRecordData(for: record)
                }
                try Task.checkCancellation()
                try writer.write(isFirstRecord ? "\n" : ",\n")
                try writer.write(recordData)
                isFirstRecord = false
            }

            try writer.write("\n  ]\n}")
        }
    }

    private static func exportMetadata(
        recordCount: Int,
        totals: BatchExportTotals,
        options: BatchExportService.ExportOptions
    ) -> [String: Any] {
        [
            "exportVersion": exportVersion,
            "exportedAt": ISO8601DateFormatter().string(from: Date()),
            "recordCount": recordCount,
            "totalEstimatedCount": totals.totalFruitCount,
            "totalEstimatedYieldKg": totals.totalYield,
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

}
