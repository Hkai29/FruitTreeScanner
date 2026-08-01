// BatchExportJSONWriter.swift
// Research JSON writer for batch scan exports.

import Foundation

enum BatchExportJSONWriter {
    private static let exportVersion = 1
    private static let compatibilityNote = "Batch research JSON appends structured research fields without changing CSV, Excel, or single-scan JSON compatibility. Per-scan detailed fields are populated when the matching single-scan _result.json sidecar is available."

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
            for record in BatchExportFormatting.orderedRecords(records, options: options) {
                try Task.checkCancellation()
                let recordData = try autoreleasepool {
                    try JSONSerialization.data(
                        withJSONObject: recordPayload(for: record),
                        options: [.prettyPrinted, .sortedKeys]
                    )
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
            "diagnostics": sanitizedDiagnostics(diagnostics),
            "imageDiagnostics": imageDiagnostics(from: diagnostics),
            "recognitionDiagnostics": recognitionDiagnostics(from: sidecar, diagnostics: diagnostics),
            "singleScanMetadataAvailable": sidecar != nil,
            "compatibilityNote": sidecar == nil
                ? "Single-scan _result.json sidecar unavailable; batch JSON includes scan-history summary fields only for this record."
                : "Single-scan _result.json sidecar found; detailed research fields included where available."
        ]
    }

    private static func singleScanMetadata(for record: ScanFileRecord) -> [String: Any]? {
        PLYParserHelper.readValidatedCompanionMetadataPayload(for: record.fileURL)
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
