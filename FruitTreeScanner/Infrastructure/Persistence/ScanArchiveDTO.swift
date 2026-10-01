import Foundation

/// Typed values consumed outside the legacy JSON codec. Optional envelope
/// fields keep pre-manifest archives readable without inventing an identity.
struct ScanMetadataDTO: Sendable {
    let scanID: String?
    let sourceFilename: String?
    let exportRevision: String?
    let hasExportRevision: Bool
    let treeID: String?
    let fruitType: String
    let hasFruitTypeField: Bool
    let fruitCount: Int
    let yieldKg: Float
    let confidence: String
    let algorithmRevision: String?
    let calibrationContext: String?
    let calibrationBaseCount: Int?
    let calibrationBaseYieldKg: Float?
    let diagnostics: DiagnosticsDTO?
}

struct DiagnosticsDTO: Sendable {
    let pointCloudPointCount: Int
    let fusedFruitCount: Int
    let validatedFruitCount: Int
    let imageOnlyFruitCount: Int
    let cloudOnlyFruitCount: Int
    let zeroYieldReasons: [String]
}

struct CompletionManifestDTO: Sendable {
    let schemaVersion: Int
    let scanID: String?
    let exportRevision: String
    let requiredFiles: [String]
    let fileSHA256: [String: String]?
    let sourcePLYFilename: String?
    let sourcePLYSHA256: String?
}

/// Bridges legacy envelope fields to typed values. The larger research payload
/// keeps its existing encoder and JSONSerialization options so revision and
/// SHA-256 inputs remain byte-for-byte compatible.
enum ScanLegacyArchiveCodec {
    static func hasExportRevisionField(_ payload: [String: Any]) -> Bool {
        payload.keys.contains("exportRevision")
    }

    static func metadata(from payload: [String: Any]) -> ScanMetadataDTO? {
        guard let count = PLYParserHelper.nonNegativeIntValue(payload["fruitCount"]),
              let yield = PLYParserHelper.nonNegativeFloatValue(payload["yieldKg"]) else {
            return nil
        }
        let diagnostics = (payload["diagnostics"] as? [String: Any]).map { values in
            DiagnosticsDTO(
                pointCloudPointCount: PLYParserHelper.nonNegativeIntValue(values["pointCloudPointCount"]) ?? 0,
                fusedFruitCount: PLYParserHelper.nonNegativeIntValue(values["fusedFruitCount"]) ?? 0,
                validatedFruitCount: PLYParserHelper.nonNegativeIntValue(values["validatedFruitCount"]) ?? 0,
                imageOnlyFruitCount: PLYParserHelper.nonNegativeIntValue(values["imageOnlyFruitCount"]) ?? 0,
                cloudOnlyFruitCount: PLYParserHelper.nonNegativeIntValue(values["cloudOnlyFruitCount"]) ?? 0,
                zeroYieldReasons: values["zeroYieldReasons"] as? [String] ?? []
            )
        }
        return ScanMetadataDTO(
            scanID: payload["scanID"] as? String,
            sourceFilename: payload["sourceFilename"] as? String,
            exportRevision: payload["exportRevision"] as? String,
            hasExportRevision: hasExportRevisionField(payload),
            treeID: payload["treeID"] as? String,
            fruitType: payload["fruitType"] as? String ?? "",
            hasFruitTypeField: payload.keys.contains("fruitType"),
            fruitCount: count,
            yieldKg: yield,
            confidence: payload["confidence"] as? String ?? "",
            algorithmRevision: payload["algorithmRevision"] as? String,
            calibrationContext: payload["calibrationContext"] as? String,
            calibrationBaseCount: PLYParserHelper.nonNegativeIntValue(payload["calibrationBaseCount"]),
            calibrationBaseYieldKg: PLYParserHelper.nonNegativeFloatValue(payload["calibrationBaseYieldKg"]),
            diagnostics: diagnostics
        )
    }

    static func manifest(from payload: [String: Any]) -> CompletionManifestDTO? {
        guard let version = payload["schemaVersion"] as? Int,
              (1...3).contains(version),
              let revision = payload["exportRevision"] as? String,
              !revision.isEmpty,
              let required = payload["requiredFiles"] as? [String] else {
            return nil
        }
        return CompletionManifestDTO(
            schemaVersion: version,
            scanID: payload["scanID"] as? String,
            exportRevision: revision,
            requiredFiles: required,
            fileSHA256: payload["fileSHA256"] as? [String: String],
            sourcePLYFilename: payload["sourcePLYFilename"] as? String,
            sourcePLYSHA256: payload["sourcePLYSHA256"] as? String
        )
    }

    static func manifest(from data: Data) -> CompletionManifestDTO? {
        guard data.count <= PLYParserHelper.maximumCompanionManifestByteCount,
              let payload = try? JSONSerialization.jsonObject(with: data) as? [String: Any] else {
            return nil
        }
        return manifest(from: payload)
    }

    static func readManifest(at url: URL) -> CompletionManifestDTO? {
        guard let data = PLYParserHelper.readBoundedCompanionData(
            at: url,
            maximumByteCount: PLYParserHelper.maximumCompanionManifestByteCount
        ), !data.isEmpty else {
            return nil
        }
        return manifest(from: data)
    }

    static func encodeManifest(_ dto: CompletionManifestDTO) throws -> Data {
        var payload: [String: Any] = [
            "schemaVersion": dto.schemaVersion,
            "scanID": dto.scanID ?? "",
            "exportRevision": dto.exportRevision,
            "requiredFiles": dto.requiredFiles
        ]
        if let digests = dto.fileSHA256 { payload["fileSHA256"] = digests }
        if let source = dto.sourcePLYFilename { payload["sourcePLYFilename"] = source }
        if let digest = dto.sourcePLYSHA256 { payload["sourcePLYSHA256"] = digest }
        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }
}
