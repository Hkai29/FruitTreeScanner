import Foundation

/// Owns legacy research JSON keys and compatibility defaults. The repository
/// validates the sidecar before calling this codec; no dynamic payload escapes
/// into batch orchestration and no intermediate JSON encoding is introduced.
enum ScanResearchArchiveCodec {
    static func encodeRecord(_ record: ScanFileRecord, sidecar: [String: Any]?) throws -> Data {
        try JSONSerialization.data(
            withJSONObject: recordPayload(for: record, sidecar: sidecar),
            options: [.prettyPrinted, .sortedKeys]
        )
    }

    private static func recordPayload(for record: ScanFileRecord, sidecar: [String: Any]?) -> [String: Any] {
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
            "unmappedObservationCount": max(0, max(0, intValue(diagnostics?["imageObservationCount"]) - intValue(diagnostics?["imageConfidenceFilteredCount"])) - intValue(diagnostics?["imageMappedFruitCount"])),
            "mappedFruitCount": intValue(diagnostics?["imageMappedFruitCount"])
        ]
    }

    private static func intValue(_ value: Any?) -> Int {
        PLYParserHelper.nonNegativeIntValue(value) ?? 0
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
