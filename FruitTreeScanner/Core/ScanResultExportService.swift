import Foundation
import os

final class ScanResultExportService: @unchecked Sendable {
    static let shared = ScanResultExportService()

    struct ExportRequest: Sendable {
        let treeID: String
        let fruitType: String
        let scanDate: Date
        let gpsLat: Double
        let gpsLon: Double
        let sourceFilename: String
        let result: YieldResult
        var includeCSV: Bool = true
    }

    struct ExportedFiles: Sendable {
        let csvURL: URL?
        let metadataURL: URL?
        let manifestURL: URL?
    }

    private let fileManager: FileManager
    private let scansDirectoryOverride: URL?
    private let writeData: (Data, URL) throws -> Void
    private let publishFile: (URL, URL) throws -> Void
    private let exportQueue = DispatchQueue(label: "com.fruittreescanner.scan-result-export")

    init(
        fileManager: FileManager = .default,
        scansDirectory: URL? = nil,
        writeData: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        },
        publishFile: ((URL, URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.scansDirectoryOverride = scansDirectory
        self.writeData = writeData
        self.publishFile = publishFile ?? { source, destination in
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    @discardableResult
    func exportIfNeeded(_ request: ExportRequest) throws -> ExportedFiles? {
        try exportQueue.sync {
            try exportIfNeededOnQueue(request)
        }
    }

    @discardableResult
    private func exportIfNeededOnQueue(_ request: ExportRequest) throws -> ExportedFiles? {
        try Task.checkCancellation()
        let scansDir = try scansDirectory()
        guard LocalFileStorage.isSafeLeafFilename(request.sourceFilename) else {
            throw LocalFileStorageError.invalidFilename
        }
        let baseName = (request.sourceFilename as NSString).deletingPathExtension
        guard !baseName.isEmpty else {
            throw LocalFileStorageError.invalidFilename
        }
        let csvURL = scansDir.appendingPathComponent("\(baseName).csv")
        let metadataURL = scansDir.appendingPathComponent("\(baseName)_result.json")
        let manifestURL = scansDir.appendingPathComponent("\(baseName)_complete.json")
        let unsignedMetadata = try makeMetadataData(for: request, baseName: baseName, revision: "")
        let revision = transactionRevision(for: unsignedMetadata, includeCSV: request.includeCSV)

        if isCommittedTransaction(
            metadataURL: metadataURL,
            csvURL: csvURL,
            manifestURL: manifestURL,
            revision: revision,
            includeCSV: request.includeCSV
        ) {
            return ExportedFiles(
                csvURL: request.includeCSV ? csvURL : nil,
                metadataURL: metadataURL,
                manifestURL: manifestURL
            )
        }

        let stagingDirectory = scansDir.appendingPathComponent(
            ".\(baseName).\(revision).staging",
            isDirectory: true
        )
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        defer { try? fileManager.removeItem(at: stagingDirectory) }

        let stagedMetadata = stagingDirectory.appendingPathComponent(metadataURL.lastPathComponent)
        let stagedCSV = stagingDirectory.appendingPathComponent(csvURL.lastPathComponent)
        let stagedManifest = stagingDirectory.appendingPathComponent(manifestURL.lastPathComponent)

        try writeData(try makeMetadataData(for: request, baseName: baseName, revision: revision), stagedMetadata)
        if request.includeCSV {
            try writeData(Data(makeCSVContent(for: request, revision: revision).utf8), stagedCSV)
        }

        let requiredFiles = request.includeCSV
            ? [metadataURL.lastPathComponent, csvURL.lastPathComponent]
            : [metadataURL.lastPathComponent]
        let manifestData = try JSONSerialization.data(withJSONObject: [
            "schemaVersion": 1,
            "scanID": baseName,
            "exportRevision": revision,
            "requiredFiles": requiredFiles
        ], options: [.prettyPrinted, .sortedKeys])
        try writeData(manifestData, stagedManifest)
        try Task.checkCancellation()
        try publishTransaction(
            stagedMetadata: stagedMetadata,
            stagedCSV: request.includeCSV ? stagedCSV : nil,
            stagedManifest: stagedManifest,
            metadataURL: metadataURL,
            csvURL: csvURL,
            manifestURL: manifestURL,
            stagingDirectory: stagingDirectory
        )

        Log.export.info("Export complete for \(request.treeID)")
        return ExportedFiles(
            csvURL: request.includeCSV ? csvURL : nil,
            metadataURL: metadataURL,
            manifestURL: manifestURL
        )
    }

    private func scansDirectory() throws -> URL {
        if let scansDirectoryOverride {
            try fileManager.createDirectory(at: scansDirectoryOverride, withIntermediateDirectories: true)
            return scansDirectoryOverride
        }
        return try LocalFileStorage.directoryURL(folder: "scans", fileManager: fileManager)
    }

    private func makeCSVContent(for request: ExportRequest, revision: String) -> String {
        let result = request.result
        let formatter = StableDataFormatting.dateFormatter(dateFormat: "yyyy-MM-dd HH:mm:ss")

        let header = [
            "树编号",
            "水果类型",
            "扫描日期",
            "果实数量",
            "产量(kg)",
            "GPS纬度",
            "GPS经度",
            "聚类Eps",
            "聚类MinPoints",
            "颜色过滤",
            "遮挡系数K",
            "点云大小",
            "置信度",
            "方法",
            "备注",
            "ExportRevision"
        ]

        let row = [
            SpreadsheetTextSafety.neutralizingFormula(request.treeID),
            SpreadsheetTextSafety.neutralizingFormula(request.fruitType),
            formatter.string(from: request.scanDate),
            "\(nonNegative(result.nLidar))",
            formatNonNegative(result.yieldFinalKg, precision: 2),
            formatLatitude(request.gpsLat),
            formatLongitude(request.gpsLon),
            format(result.clusterEps, precision: 3),
            "\(result.clusterMinPoints)",
            SpreadsheetTextSafety.neutralizingFormula(
                result.colorFilterDesc.isEmpty ? "N/A" : result.colorFilterDesc
            ),
            format(result.occlusionK, precision: 2),
            "\(result.pointCloudSize)",
            SpreadsheetTextSafety.neutralizingFormula(result.confidence),
            SpreadsheetTextSafety.neutralizingFormula(result.methodUsed),
            SpreadsheetTextSafety.neutralizingFormula(result.note),
            revision
        ]

        return csvLine(header) + csvLine(row)
    }

    private func makeMetadataData(for request: ExportRequest, baseName: String, revision: String) throws -> Data {
        let result = request.result
        let diagnostics = result.diagnostics
        let payload: [String: Any] = [
            "schemaVersion": 1,
            "exportRevision": revision,
            "scanID": baseName,
            "sourceFilename": request.sourceFilename,
            "treeID": request.treeID,
            "fruitType": request.fruitType,
            "fruitCount": nonNegative(result.nLidar),
            "yieldKg": nonNegativeFinite(result.yieldFinalKg),
            "confidence": result.confidence,
            "methodUsed": result.methodUsed,
            "note": result.note,
            "clusterEps": finite(result.clusterEps),
            "clusterMinPoints": result.clusterMinPoints,
            "fruitCategory": result.fruitCategory,
            "colorFilterDesc": result.colorFilterDesc,
            "occlusionK": finite(result.occlusionK),
            "pointCloudSize": result.pointCloudSize,
            "meanDiameterCm": finite(result.meanDiameterCm),
            "meanVolumeCm3": finite(result.meanVolumeCm3),
            "correctionK": finite(result.correctionK),
            "yieldBVisibleKg": finite(result.yieldBVisibleKg),
            "yieldBCorrectedKg": finite(result.yieldBCorrectedKg),
            "treeHeightM": finite(result.treeHeightM),
            "crownVolM3": finite(result.crownVolM3),
            "fruitMassEstimates": fruitMassEstimatePayloads(result.fruitMassEstimates),
            "validatedFruits": validatedFruitPayloads(result.validatedFruits),
            "recognitionDiagnostics": recognitionDiagnosticsPayload(diagnostics),
            "diagnostics": [
                "pointCloudPointCount": diagnostics.pointCloudPointCount,
                "imageDetectionCount": diagnostics.imageDetectionCount,
                "deduplicatedImageDetectionCount": diagnostics.deduplicatedImageDetectionCount,
                "pointCloudColorFilteredCount": diagnostics.pointCloudColorFilteredCount,
                "pointCloudDenoisedPointCount": diagnostics.pointCloudDenoisedPointCount,
                "pointCloudOutlierPointCount": diagnostics.pointCloudOutlierPointCount,
                "pointCloudOutlierRatio": finite(diagnostics.pointCloudOutlierRatio),
                "pointCloudCandidateCount": diagnostics.pointCloudCandidateCount,
                "pointCloudClusterCandidateCount": diagnostics.pointCloudClusterCandidateCount,
                "detectionDepthCandidateCount": diagnostics.detectionDepthCandidateCount,
                "detectionDepthSupportRatio": finite(diagnostics.detectionDepthSupportRatio),
                "fusedFruitCount": diagnostics.fusedFruitCount,
                "validatedFruitCount": diagnostics.validatedFruitCount,
                "fusedValidationCount": diagnostics.fusedValidationCount,
                "trackedImageFruitCount": diagnostics.trackedImageFruitCount,
                "imageOnlyFruitCount": diagnostics.imageOnlyFruitCount,
                "cloudOnlyFruitCount": diagnostics.cloudOnlyFruitCount,
                "validationSourceReliability": finite(diagnostics.validationSourceReliability),
                "localCalibrationCountFactor": finite(diagnostics.localCalibrationCountFactor),
                "localCalibrationYieldFactor": finite(diagnostics.localCalibrationYieldFactor),
                "localCalibrationCountSampleCount": diagnostics.localCalibrationCountSampleCount,
                "localCalibrationYieldSampleCount": diagnostics.localCalibrationYieldSampleCount,
                "canopyPointCount": diagnostics.canopyPointCount,
                "canopyPreprocessedPointCount": diagnostics.canopyPreprocessedPointCount,
                "canopyGroundFilteredPointCount": diagnostics.canopyGroundFilteredPointCount,
                "canopyTrunkFilteredPointCount": diagnostics.canopyTrunkFilteredPointCount,
                "canopyNeighborFilteredPointCount": diagnostics.canopyNeighborFilteredPointCount,
                "canopyClusterCount": diagnostics.canopyClusterCount,
                "canopyRobustPointCount": diagnostics.canopyRobustPointCount,
                "canopyHeightM": finite(diagnostics.canopyHeightM),
                "canopyWidthM": finite(diagnostics.canopyWidthM),
                "canopyDepthM": finite(diagnostics.canopyDepthM),
                "canopyOuterVolumeM3": finite(diagnostics.canopyOuterVolumeM3),
                "canopyVolumeM3": finite(diagnostics.canopyVolumeM3),
                "canopyEffectiveVolumeCoefficient": finite(diagnostics.canopyEffectiveVolumeCoefficient),
                "canopyProjectionXYCoefficient": finite(diagnostics.canopyProjectionXYCoefficient),
                "canopyProjectionXZCoefficient": finite(diagnostics.canopyProjectionXZCoefficient),
                "canopyProjectionYZCoefficient": finite(diagnostics.canopyProjectionYZCoefficient),
                "canopyProjectionEffectiveCoefficient": finite(diagnostics.canopyProjectionEffectiveCoefficient),
                "canopyVoxelSizeM": finite(diagnostics.canopyVoxelSizeM),
                "canopyPartitionSizeM": finite(diagnostics.canopyPartitionSizeM),
                "canopyPartitionCount": diagnostics.canopyPartitionCount,
                "pointCloudAngleCoverage": finite(diagnostics.pointCloudAngleCoverage),
                "cameraAngleCoverage": finite(diagnostics.cameraAngleCoverage),
                "scanAngleCoverage": finite(diagnostics.scanAngleCoverage),
                "depthAvailable": diagnostics.depthAvailable,
                "cloudOnlyConservativeMode": diagnostics.cloudOnlyConservativeMode,
                "imageFramesProcessed": diagnostics.imageFramesProcessed,
                "imageObservationCount": diagnostics.imageObservationCount,
                "imageConfidenceFilteredCount": diagnostics.imageConfidenceFilteredCount,
                "imageMappedFruitCount": diagnostics.imageMappedFruitCount,
                "imageModelStatus": diagnostics.imageModelStatus,
                "imageModelName": diagnostics.imageModelName,
                "imageFailureReason": diagnostics.imageFailureReason,
                "selectedCategory": diagnostics.selectedCategory,
                "detectedCategoryCounts": diagnostics.detectedCategoryCounts,
                "nonTargetDetectionCount": diagnostics.nonTargetDetectionCount,
                "dominantNonTargetCategory": diagnostics.dominantNonTargetCategory,
                "categoryMismatchDetected": diagnostics.categoryMismatchDetected,
                "automaticSuggestionCategory": diagnostics.automaticSuggestionCategory,
                "automaticSuggestionConfidence": finite(diagnostics.automaticSuggestionConfidence),
                "automaticSuggestionFrameCount": diagnostics.automaticSuggestionFrameCount,
                "zeroYieldReasons": diagnostics.zeroYieldReasons
            ],
            "gpsLat": latitude(request.gpsLat),
            "gpsLon": longitude(request.gpsLon),
            "timestamp": ISO8601DateFormatter().string(from: request.scanDate)
        ]

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    private func transactionRevision(for snapshotData: Data, includeCSV: Bool) -> String {
        var hash: UInt64 = 0xcbf29ce484222325
        for byte in snapshotData {
            hash ^= UInt64(byte)
            hash = hash &* 0x100000001b3
        }
        hash ^= includeCSV ? 1 : 0
        return String(format: "v1-%016llx", hash)
    }

    private func isCommittedTransaction(
        metadataURL: URL,
        csvURL: URL,
        manifestURL: URL,
        revision: String,
        includeCSV: Bool
    ) -> Bool {
        guard let manifestData = try? Data(contentsOf: manifestURL),
              let manifest = try? JSONSerialization.jsonObject(with: manifestData) as? [String: Any],
              manifest["exportRevision"] as? String == revision,
              let requiredFiles = manifest["requiredFiles"] as? [String],
              requiredFiles.contains(metadataURL.lastPathComponent),
              requiredFiles.contains(csvURL.lastPathComponent) == includeCSV,
              let metadataData = try? Data(contentsOf: metadataURL),
              let metadata = try? JSONSerialization.jsonObject(with: metadataData) as? [String: Any],
              metadata["exportRevision"] as? String == revision
        else { return false }

        guard includeCSV,
              let csv = try? String(contentsOf: csvURL, encoding: .utf8)
        else { return !includeCSV }
        let rows = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }
        guard let header = rows.first,
              let row = rows.dropFirst().first else { return false }
        return header.hasSuffix("ExportRevision") && row.hasSuffix(",\(revision)")
    }

    private func publishTransaction(
        stagedMetadata: URL,
        stagedCSV: URL?,
        stagedManifest: URL,
        metadataURL: URL,
        csvURL: URL,
        manifestURL: URL,
        stagingDirectory: URL
    ) throws {
        let destinations = [metadataURL, csvURL, manifestURL]
        var backups: [(backup: URL, destination: URL)] = []
        for destination in destinations where fileManager.fileExists(atPath: destination.path) {
            let backup = stagingDirectory.appendingPathComponent("backup-\(destination.lastPathComponent)")
            try fileManager.copyItem(at: destination, to: backup)
            backups.append((backup, destination))
        }

        do {
            if fileManager.fileExists(atPath: manifestURL.path) {
                try fileManager.removeItem(at: manifestURL)
            }
            // Readers fail closed until every required file matches this revision.
            try publishFile(stagedManifest, manifestURL)
            if stagedCSV == nil, fileManager.fileExists(atPath: csvURL.path) {
                try fileManager.removeItem(at: csvURL)
            }
            try publishFile(stagedMetadata, metadataURL)
            if let stagedCSV {
                try publishFile(stagedCSV, csvURL)
            }
        } catch {
            for destination in destinations where fileManager.fileExists(atPath: destination.path) {
                try? fileManager.removeItem(at: destination)
            }
            for pair in backups {
                try? fileManager.copyItem(at: pair.backup, to: pair.destination)
            }
            throw error
        }
    }

    private func recognitionDiagnosticsPayload(_ diagnostics: ScanYieldDiagnostics) -> [String: Any] {
        [
            "metadataAvailable": true,
            "modelLabelCompatibilityStatus": diagnostics.imageModelLabelCompatibilityStatus,
            "modelLabelCompatibilityWarnings": limitedStrings(diagnostics.imageModelLabelCompatibilityWarnings),
            "runtimeModelLabelsAvailable": diagnostics.imageRuntimeModelLabelsAvailable,
            "runtimeModelLabelCount": diagnostics.imageRuntimeModelLabels.count,
            "rawDetectedLabels": limitedStrings(diagnostics.imageRawDetectedLabels),
            "mappedDetectedCategories": limitedStrings(diagnostics.imageMappedCategories),
            "unmappedDetectedLabels": limitedStrings(diagnostics.imageUnmappedLabels),
            "filteredBySelectedFruitTypeCount": diagnostics.filteredBySelectedFruitTypeCount,
            "confidenceFilteredCount": diagnostics.imageConfidenceFilteredCount,
            "unmappedObservationCount": max(0, diagnostics.imageObservationCount - diagnostics.imageConfidenceFilteredCount - diagnostics.imageMappedFruitCount),
            "mappedFruitCount": diagnostics.imageMappedFruitCount
        ]
    }

    private func fruitMassEstimatePayloads(_ estimates: [FruitMassEstimate]) -> [[String: Any]] {
        estimates.map { estimate in
            [
                "id": estimate.id.uuidString,
                "fruitCategory": estimate.fruitCategory,
                "lengthCm": finite(estimate.lengthCm),
                "widthCm": finite(estimate.widthCm),
                "heightCm": finite(estimate.heightCm),
                "equivalentDiameterCm": finite(estimate.equivalentDiameterCm),
                "sphereVolumeCm3": finite(estimate.sphereVolumeCm3),
                "ellipsoidVolumeCm3": finite(estimate.ellipsoidVolumeCm3),
                "selectedVolumeCm3": finite(estimate.selectedVolumeCm3),
                "densityGPerCm3": finite(estimate.densityGPerCm3),
                "estimatedWeightG": finite(estimate.estimatedWeightG),
                "confidenceScore": finite(estimate.confidenceScore),
                "pointCount": nonNegative(estimate.pointCount),
                "highConfidenceRatio": finite(estimate.highConfidenceRatio),
                "validDepthRatio": finite(estimate.validDepthRatio),
                "shapeModelUsed": estimate.shapeModelUsed.rawValue,
                "warningFlags": estimate.warningFlags.map(\.rawValue),
                "createdAt": ISO8601DateFormatter().string(from: estimate.createdAt)
            ]
        }
    }

    private func validatedFruitPayloads(_ fruits: [ValidatedFruitData]) -> [[String: Any]] {
        fruits.map { fruit in
            [
                "id": fruit.id,
                "category": fruit.category.map { $0 as Any } ?? NSNull(),
                "positionX": finite(fruit.positionX),
                "positionY": finite(fruit.positionY),
                "positionZ": finite(fruit.positionZ),
                "confidence": finite(fruit.confidence),
                "source": fruit.source
            ]
        }
    }

    private func finite(_ value: Float) -> Float {
        value.isFinite ? value : 0
    }

    private func nonNegative(_ value: Int) -> Int {
        max(0, value)
    }

    private func nonNegativeFinite(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }

    private func format(_ value: Float, precision: Int) -> String {
        StableDataFormatting.decimal(finite(value), precision: precision)
    }

    private func formatNonNegative(_ value: Float, precision: Int) -> String {
        StableDataFormatting.decimal(nonNegativeFinite(value), precision: precision)
    }

    private func latitude(_ value: Double) -> Double {
        guard value.isFinite, (-90...90).contains(value) else { return 0 }
        return value
    }

    private func longitude(_ value: Double) -> Double {
        guard value.isFinite, (-180...180).contains(value) else { return 0 }
        return value
    }

    private func formatLatitude(_ value: Double) -> String {
        StableDataFormatting.decimal(latitude(value), precision: 6)
    }

    private func formatLongitude(_ value: Double) -> String {
        StableDataFormatting.decimal(longitude(value), precision: 6)
    }

    private func limitedStrings(_ values: [String], limit: Int = 32) -> [String] {
        Array(values.filter { !$0.isEmpty }.prefix(limit))
    }

    private func csvLine(_ fields: [String]) -> String {
        fields.map(csvEscape).joined(separator: ",") + "\n"
    }

    private func csvEscape(_ field: String) -> String {
        let escaped = field.replacingOccurrences(of: "\"", with: "\"\"")
        if escaped.contains(",") || escaped.contains("\"") || escaped.contains("\n") || escaped.contains("\r") {
            return "\"\(escaped)\""
        }
        return escaped
    }
}
