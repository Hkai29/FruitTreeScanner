import Foundation
import CryptoKit
import os

enum ScanCompanionIntegrity {
    static func digest(_ data: Data) -> String {
        SHA256.hash(data: data).map { String(format: "%02x", $0) }.joined()
    }

    static func digestFile(at url: URL) throws -> String {
        let handle = try FileHandle(forReadingFrom: url)
        defer { try? handle.close() }
        var hasher = SHA256()
        while let chunk = try handle.read(upToCount: 256 * 1_024), !chunk.isEmpty {
            try Task.checkCancellation()
            hasher.update(data: chunk)
        }
        return hasher.finalize().map { String(format: "%02x", $0) }.joined()
    }
}

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
        let classification: ScanClassificationSnapshot?

        init(treeID: String, fruitType: String, scanDate: Date, gpsLat: Double, gpsLon: Double,
             sourceFilename: String, result: YieldResult, includeCSV: Bool = true,
             classification: ScanClassificationSnapshot? = nil) {
            self.treeID = treeID
            self.fruitType = fruitType
            self.scanDate = scanDate
            self.gpsLat = gpsLat
            self.gpsLon = gpsLon
            self.sourceFilename = sourceFilename
            self.result = result
            self.includeCSV = includeCSV
            self.classification = classification
        }
    }

    struct ExportedFiles: Sendable {
        let csvURL: URL?
        let metadataURL: URL?
        let manifestURL: URL?
        let exportRevision: String
        let metadataSHA256: String
        let sourcePLYSHA256: String
    }

    typealias SourcePointCloudError = ScanSourceFileError

    struct RecoveryRequiredError: LocalizedError {
        let stagingDirectory: URL
        let cause: Error?

        var errorDescription: String? { NSLocalizedString("export.recoveryRequired", comment: "Archive recovery required") }
    }

    /// Match the complete source basename and the actual transaction revision.
    /// A prefix alone would also claim recovery files for `scan.other.ply`.
    static func stagingDirectories(for source: URL, fileManager: FileManager = .default) throws -> [URL] {
        let parent = source.deletingLastPathComponent()
        guard fileManager.fileExists(atPath: parent.path) else { return [] }
        let prefix = ".\(source.deletingPathExtension().lastPathComponent)."
        let suffix = ".staging"
        return try fileManager.contentsOfDirectory(at: parent, includingPropertiesForKeys: nil).filter { url in
            let name = url.lastPathComponent
            guard name.hasPrefix(prefix), name.hasSuffix(suffix) else { return false }
            let revision = name.dropFirst(prefix.count).dropLast(suffix.count)
            return revision.count == 19 && revision.hasPrefix("v1-")
                && revision.dropFirst(3).utf8.allSatisfy { (48...57).contains($0) || (97...102).contains($0) }
        }
    }

    private let fileManager: FileManager
    private let scansDirectoryOverride: URL?
    private let writeData: (Data, URL) throws -> Void
    private let publishFile: (URL, URL) throws -> Void
    private let removeStagingDirectory: (URL) throws -> Void
    private let exportQueue = DispatchQueue(label: "com.fruittreescanner.scan-result-export")
    private static let committedFileReadChunkByteCount = 64 * 1_024
    private var discardedFilenames = Set<String>()

    init(
        fileManager: FileManager = .default,
        scansDirectory: URL? = nil,
        writeData: @escaping (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: .atomic)
        },
        removeStagingDirectory: ((URL) throws -> Void)? = nil,
        publishFile: ((URL, URL) throws -> Void)? = nil
    ) {
        self.fileManager = fileManager
        self.scansDirectoryOverride = scansDirectory
        self.writeData = writeData
        self.removeStagingDirectory = removeStagingDirectory ?? { url in
            try fileManager.removeItem(at: url)
        }
        self.publishFile = publishFile ?? { source, destination in
            if fileManager.fileExists(atPath: destination.path) {
                try fileManager.removeItem(at: destination)
            }
            try fileManager.moveItem(at: source, to: destination)
        }
    }

    @discardableResult
    func exportIfNeeded(_ request: ExportRequest, expectedSource: DraftScan? = nil) throws -> ExportedFiles? {
        guard expectedSource?.captureIdentity == nil else { throw ScanEvidenceError.mismatchedInput }
        return try exportQueue.sync {
            try exportIfNeededOnQueue(request, expectedSource: expectedSource, evidenceReceipt: nil)
        }
    }

    func exportAssessment(_ assessment: ScanAssessment) throws -> ExportedFiles? {
        try assessment.validateEvidence()
        return try exportQueue.sync {
            try exportIfNeededOnQueue(assessment.exportRequest, expectedSource: assessment.draft,
                                      evidenceReceipt: assessment.evidenceReceipt)
        }
    }

    func discardScanArtifacts(sourceFilename: String) throws {
        try exportQueue.sync {
            guard LocalFileStorage.isSafeLeafFilename(sourceFilename),
                  (sourceFilename as NSString).pathExtension.lowercased() == "ply" else {
                throw LocalFileStorageError.invalidFilename
            }
            let directory = try scansDirectory()
            let baseName = (sourceFilename as NSString).deletingPathExtension
            let sourceURL = directory.appendingPathComponent(sourceFilename)
            try ScanArchiveAccess.shared.withTransaction(at: sourceURL) {
                guard !ScanArchiveAccess.shared.requiresEvidenceReceipt(at: sourceURL) else {
                    throw ScanEvidenceError.mismatchedInput
                }
                discardedFilenames.insert(sourceFilename)
                let replayURLs = ScanReplayArchive.artifactURLs(for: sourceURL)
                for url in try ScanReplayArchive.pendingDirectories(for: sourceURL) {
                    try fileManager.removeItem(at: url)
                }
                for filename in ["\(baseName)_complete.json", "\(baseName)_result.json", "\(baseName).csv",
                                 replayURLs.input.lastPathComponent, replayURLs.points.lastPathComponent, sourceFilename] {
                    let url = directory.appendingPathComponent(filename)
                    if fileManager.fileExists(atPath: url.path) { try fileManager.removeItem(at: url) }
                }
            }
        }
    }

    @discardableResult
    private func exportIfNeededOnQueue(_ request: ExportRequest, expectedSource: DraftScan?,
                                       evidenceReceipt: ScanEvidenceReceipt?) throws -> ExportedFiles? {
        try Task.checkCancellation()
        guard !discardedFilenames.contains(request.sourceFilename) else { throw CancellationError() }
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
        let sourceURL = scansDir.appendingPathComponent(request.sourceFilename)

        return try ScanArchiveAccess.shared.withTransaction(at: sourceURL) {
            if ScanArchiveAccess.shared.requiresEvidenceReceipt(at: sourceURL), evidenceReceipt == nil {
                throw ScanEvidenceError.mismatchedInput
            }
            if let expectedSource {
                if let capture = expectedSource.captureIdentity {
                    guard let evidenceReceipt else { throw ScanEvidenceError.mismatchedInput }
                    let expectedEvidence = evidenceReceipt.identity
                    guard evidenceReceipt.draft == expectedSource,
                          expectedEvidence.capture == capture,
                          expectedEvidence.sourceOwnershipID == expectedSource.ownershipID,
                          expectedEvidence.sourceSHA256 == expectedSource.sourceSHA256 else {
                        throw ScanEvidenceError.mismatchedInput
                    }
                }
                guard sourceURL.standardizedFileURL.resolvingSymlinksInPath() ==
                        expectedSource.sourceURL.standardizedFileURL.resolvingSymlinksInPath(),
                      try ScanSourceFileIdentity.read(at: sourceURL) == expectedSource.fileIdentity else {
                    throw SourcePointCloudError.invalidOrChanged
                }
            }
            return try exportTransactionIfNeeded(
                request,
                scansDirectory: scansDir,
                baseName: baseName,
                csvURL: csvURL,
                metadataURL: metadataURL,
                manifestURL: manifestURL,
                expectedSource: expectedSource,
                replay: evidenceReceipt?.replay
            )
        }
    }

    private func exportTransactionIfNeeded(
        _ request: ExportRequest,
        scansDirectory: URL,
        baseName: String,
        csvURL: URL,
        metadataURL: URL,
        manifestURL: URL,
        expectedSource: DraftScan?,
        replay: PreparedScanReplay?
    ) throws -> ExportedFiles? {
        let sourceURL = scansDirectory.appendingPathComponent(request.sourceFilename)
        guard fileManager.fileExists(atPath: sourceURL.path),
              PLYParserHelper.hasValidPointCloudHeader(at: sourceURL) else {
            throw SourcePointCloudError.invalidOrChanged
        }
        if let previousManifest = ScanLegacyArchiveCodec.readManifest(at: manifestURL),
           previousManifest.schemaVersion == 3 {
            guard let previousDigest = previousManifest.sourcePLYSHA256,
                  (try? ScanCompanionIntegrity.digestFile(at: sourceURL)) == previousDigest else {
                throw SourcePointCloudError.invalidOrChanged
            }
        }
        let sourceDigest = try ScanCompanionIntegrity.digestFile(at: sourceURL)
        if let expectedSource, sourceDigest != expectedSource.sourceSHA256 {
            throw SourcePointCloudError.invalidOrChanged
        }
        let previousReplay = ScanLegacyArchiveCodec.readManifest(at: manifestURL)?.observationReplay
        let replayDescriptor = replay?.descriptor ?? previousReplay.map { _ in
            ScanReplayDescriptor.unavailable("inputNotCapturedForRevision")
        }
        if let replay {
            try replay.descriptor.validate()
            guard let expectedSource, replay.descriptor.identity?.sourceSHA256 == sourceDigest,
                  replay.descriptor.identity?.sourceOwnershipID == expectedSource.ownershipID,
                  replay.descriptor.identity?.capture == expectedSource.captureIdentity,
                  replay.directory == nil || replay.directory == ScanReplayArchive.preparedDirectory(for: expectedSource) else {
                throw ScanEvidenceError.mismatchedInput
            }
        }
        let classificationPayload = try classificationPayload(for: request, sourceURL: sourceURL, metadataURL: metadataURL)
        let revision: String
        do {
            let unsignedMetadata = try makeMetadataData(
                for: request,
                baseName: baseName,
                revision: "",
                classificationPayload: classificationPayload,
                replayDescriptor: replayDescriptor
            )
            revision = transactionRevision(
                for: unsignedMetadata,
                includeCSV: request.includeCSV
            )
        }
        try Task.checkCancellation()
        let metadataData = try makeMetadataData(
            for: request,
            baseName: baseName,
            revision: revision,
            classificationPayload: classificationPayload,
            replayDescriptor: replayDescriptor
        )
        let csvData = request.includeCSV
            ? Data(makeCSVContent(for: request, revision: revision).utf8)
            : nil
        let requiredFiles = request.includeCSV
            ? [metadataURL.lastPathComponent, csvURL.lastPathComponent]
            : [metadataURL.lastPathComponent]
        let metadataDigest = ScanCompanionIntegrity.digest(metadataData)
        var digests = [metadataURL.lastPathComponent: metadataDigest]
        if let csvData { digests[csvURL.lastPathComponent] = ScanCompanionIntegrity.digest(csvData) }
        let manifestData = try ScanLegacyArchiveCodec.encodeManifest(
            CompletionManifestDTO(
                schemaVersion: 3,
                scanID: baseName,
                exportRevision: revision,
                requiredFiles: requiredFiles,
                fileSHA256: digests,
                sourcePLYFilename: request.sourceFilename,
                sourcePLYSHA256: sourceDigest,
                observationReplay: replayDescriptor
            )
        )
        try Task.checkCancellation()
        let stagingDirectory = scansDirectory.appendingPathComponent(
            ".\(baseName).\(revision).staging",
            isDirectory: true
        )

        if try isCommittedTransaction(
            metadataURL: metadataURL,
            csvURL: csvURL,
            manifestURL: manifestURL,
            expectedMetadata: metadataData,
            expectedCSV: csvData,
            expectedManifest: manifestData
        ) {
            if let replayDescriptor { try ScanReplayArchive.verifyArtifacts(source: sourceURL, descriptor: replayDescriptor) }
            // A committed snapshot remains usable even if crash residue cannot be removed.
            if fileManager.fileExists(atPath: stagingDirectory.path) {
                do {
                    try removeStagingDirectory(stagingDirectory)
                } catch {
                    Log.export.error(
                        "Failed to remove stale staging directory for committed scan \(baseName): \(error.localizedDescription)"
                    )
                }
            }
            return ExportedFiles(
                csvURL: request.includeCSV ? csvURL : nil,
                metadataURL: metadataURL,
                manifestURL: manifestURL,
                exportRevision: revision,
                metadataSHA256: metadataDigest,
                sourcePLYSHA256: sourceDigest
            )
        }

        // A retired receipt can acknowledge the exact committed revision above,
        // but cannot overwrite it or a draft adopted by a newer operation.
        if let expectedSource, !ScanArchiveAccess.shared.ownsDraft(expectedSource) {
            throw SourcePointCloudError.invalidOrChanged
        }

        // Process termination can bypass the transaction's deferred cleanup.
        // Backups from an incomplete rollback are recovery material, including
        // those owned by a previous revision of this same source.
        for directory in try Self.stagingDirectories(for: sourceURL, fileManager: fileManager) {
            let entries = try fileManager.contentsOfDirectory(at: directory, includingPropertiesForKeys: nil)
            if entries.contains(where: { $0.lastPathComponent.hasPrefix("backup-") }) {
                throw RecoveryRequiredError(stagingDirectory: directory, cause: nil)
            }
        }
        if fileManager.fileExists(atPath: stagingDirectory.path) {
            try removeStagingDirectory(stagingDirectory)
        }
        try fileManager.createDirectory(at: stagingDirectory, withIntermediateDirectories: false)
        var preserveStaging = false
        defer { if !preserveStaging { try? removeStagingDirectory(stagingDirectory) } }

        let stagedMetadata = stagingDirectory.appendingPathComponent(metadataURL.lastPathComponent)
        let stagedCSV = stagingDirectory.appendingPathComponent(csvURL.lastPathComponent)
        let stagedManifest = stagingDirectory.appendingPathComponent(manifestURL.lastPathComponent)

        try writeData(metadataData, stagedMetadata)
        if let csvData {
            try writeData(csvData, stagedCSV)
        }
        try writeData(manifestData, stagedManifest)
        let replayURLs = ScanReplayArchive.artifactURLs(for: sourceURL)
        let stagedReplay: (input: URL, points: URL)?
        if let replay, replay.descriptor.status == "complete" {
            guard let directory = replay.directory,
                  try directory.resourceValues(forKeys: [.isSymbolicLinkKey]).isSymbolicLink != true else {
                throw ScanReplayError.invalidArchive
            }
            let inputURL = directory.appendingPathComponent("input.json")
            let pointsURL = directory.appendingPathComponent("points.f32")
            try ScanReplayArchive.verifyFile(inputURL, size: replay.descriptor.inputByteCount!, digest: replay.descriptor.inputSHA256!)
            try ScanReplayArchive.verifyFile(pointsURL, size: replay.descriptor.pointsByteCount!, digest: replay.descriptor.pointsSHA256!)
            let input = stagingDirectory.appendingPathComponent(replayURLs.input.lastPathComponent)
            let points = stagingDirectory.appendingPathComponent(replayURLs.points.lastPathComponent)
            try fileManager.copyItem(at: inputURL, to: input)
            try fileManager.copyItem(at: pointsURL, to: points)
            try ScanReplayArchive.verifyFile(input, size: replay.descriptor.inputByteCount!, digest: replay.descriptor.inputSHA256!)
            try ScanReplayArchive.verifyFile(points, size: replay.descriptor.pointsByteCount!, digest: replay.descriptor.pointsSHA256!)
            stagedReplay = (input, points)
        } else { stagedReplay = nil }
        try Task.checkCancellation()
        guard try ScanCompanionIntegrity.digestFile(at: sourceURL) == sourceDigest else {
            throw SourcePointCloudError.invalidOrChanged
        }
        if let expectedSource,
           try ScanSourceFileIdentity.read(at: sourceURL) != expectedSource.fileIdentity {
            throw SourcePointCloudError.invalidOrChanged
        }
        do { try publishTransaction(
            stagedMetadata: stagedMetadata,
            stagedCSV: request.includeCSV ? stagedCSV : nil,
            stagedManifest: stagedManifest,
            metadataURL: metadataURL,
            csvURL: csvURL,
            manifestURL: manifestURL,
            stagingDirectory: stagingDirectory,
            stagedReplay: stagedReplay,
            replayURLs: replayURLs
        ) } catch let recovery as RecoveryRequiredError {
            preserveStaging = true
            throw recovery
        }

        Log.export.info("Export complete for \(request.treeID)")
        return ExportedFiles(
            csvURL: request.includeCSV ? csvURL : nil,
            metadataURL: metadataURL,
            manifestURL: manifestURL,
            exportRevision: revision,
            metadataSHA256: metadataDigest,
            sourcePLYSHA256: sourceDigest
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

    private func classificationPayload(for request: ExportRequest, sourceURL: URL, metadataURL: URL) throws -> [String: Any]? {
        let verified = PLYParserHelper.readValidatedCompanionMetadataPayload(for: sourceURL)
        // Only the failed-validation path needs a second bounded read. A present
        // classification must not be silently erased while repairing other fields.
        let existing: [String: Any]?
        if let verified {
            existing = verified
        } else if let data = PLYParserHelper.readBoundedCompanionData(
            at: metadataURL, maximumByteCount: PLYParserHelper.maximumCompanionMetadataByteCount
        ) {
            existing = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        } else {
            existing = nil
        }
        if let existing, let original = try ScanClassificationArchiveCodec.snapshot(in: existing) {
            guard let verified, ScanLegacyArchiveCodec.metadata(from: verified) != nil else {
                throw ScanClassificationArchiveError.unverifiedArchive
            }
            if let requested = request.classification, requested != original {
                throw ScanClassificationArchiveError.conflictingSnapshot
            }
            return existing["scanClassification"] as? [String: Any]
        }
        return try request.classification.map(ScanClassificationArchiveCodec.payload(for:))
    }

    private func makeMetadataData(for request: ExportRequest, baseName: String, revision: String,
                                  classificationPayload: [String: Any]?,
                                  replayDescriptor: ScanReplayDescriptor? = nil) throws -> Data {
        let result = request.result
        let diagnostics = result.diagnostics
        var payload: [String: Any] = [
            "schemaVersion": 1,
            "exportRevision": revision,
            "scanID": baseName,
            "sourceFilename": request.sourceFilename,
            "algorithmRevision": result.algorithmRevision ?? "unknown",
            "calibrationContext": result.calibrationContext ?? "",
            "calibrationBaseCount": result.calibrationBaseCount.map { $0 as Any } ?? NSNull(),
            "calibrationBaseYieldKg": result.calibrationBaseYieldKg.map { finite($0) as Any } ?? NSNull(),
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
        if let classificationPayload { payload["scanClassification"] = classificationPayload }
        if let replayDescriptor { payload["observationReplay"] = try replayDescriptor.payload() }

        return try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted, .sortedKeys])
    }

    /// Uses the actual persisted-result encoder; only the archive envelope and
    /// generated output IDs/timestamps are removed by the comparison codec.
    static func replayGoldenData(for result: YieldResult) throws -> Data {
        let request = ExportRequest(treeID: "", fruitType: "", scanDate: Date(timeIntervalSince1970: 0),
                                    gpsLat: 0, gpsLon: 0, sourceFilename: "replay.ply", result: result)
        let data = try shared.makeMetadataData(for: request, baseName: "replay", revision: "", classificationPayload: nil)
        return try ScanObservationReplay.goldenData(from: JSONSerialization.jsonObject(with: data) as! [String: Any])
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
        expectedMetadata: Data,
        expectedCSV: Data?,
        expectedManifest: Data
    ) throws -> Bool {
        guard try fileContentsEqual(
                  at: manifestURL,
                  expected: expectedManifest
              ),
              try fileContentsEqual(
                  at: metadataURL,
                  expected: expectedMetadata
              )
        else {
            return false
        }
        guard let expectedCSV else { return true }
        return try fileContentsEqual(at: csvURL, expected: expectedCSV)
    }

    private func fileContentsEqual(at url: URL, expected: Data) throws -> Bool {
        try Task.checkCancellation()
        guard let fileSize = try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize,
              fileSize == expected.count,
              let handle = try? FileHandle(forReadingFrom: url)
        else {
            return false
        }
        defer { try? handle.close() }

        var offset = 0
        do {
            while offset < expected.count {
                try Task.checkCancellation()
                let readByteCount = min(
                    Self.committedFileReadChunkByteCount,
                    expected.count - offset
                )
                guard let chunk = try handle.read(upToCount: readByteCount),
                      !chunk.isEmpty
                else {
                    return false
                }
                let endOffset = offset + chunk.count
                guard endOffset <= expected.count,
                      chunk.elementsEqual(expected[offset..<endOffset])
                else {
                    return false
                }
                offset = endOffset
            }
            try Task.checkCancellation()
            let trailingData = try handle.read(upToCount: 1)
            return trailingData?.isEmpty ?? true
        } catch let cancellation as CancellationError {
            throw cancellation
        } catch {
            return false
        }
    }

    private func publishTransaction(
        stagedMetadata: URL,
        stagedCSV: URL?,
        stagedManifest: URL,
        metadataURL: URL,
        csvURL: URL,
        manifestURL: URL,
        stagingDirectory: URL,
        stagedReplay: (input: URL, points: URL)?,
        replayURLs: (input: URL, points: URL)
    ) throws {
        let destinations = [metadataURL, csvURL, replayURLs.input, replayURLs.points, manifestURL]
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
            // Readers fail closed while the manifest is absent. Publish it only
            // after both companion files are at the committed revision.
            if stagedCSV == nil, fileManager.fileExists(atPath: csvURL.path) {
                try fileManager.removeItem(at: csvURL)
            }
            if let stagedReplay {
                try publishFile(stagedReplay.input, replayURLs.input)
                try publishFile(stagedReplay.points, replayURLs.points)
            } else {
                for url in [replayURLs.input, replayURLs.points] where fileManager.fileExists(atPath: url.path) {
                    try fileManager.removeItem(at: url)
                }
            }
            try publishFile(stagedMetadata, metadataURL)
            if let stagedCSV {
                try publishFile(stagedCSV, csvURL)
            }
            try publishFile(stagedManifest, manifestURL)
        } catch {
            var rollbackFailed = false
            // Keep readers closed until every original artifact is restored.
            for destination in [manifestURL] + destinations.filter({ $0 != manifestURL })
                where fileManager.fileExists(atPath: destination.path) {
                do { try fileManager.removeItem(at: destination) }
                catch { rollbackFailed = true }
            }
            for pair in backups where pair.destination != manifestURL {
                do { try fileManager.copyItem(at: pair.backup, to: pair.destination) }
                catch { rollbackFailed = true }
            }
            if !rollbackFailed, let manifest = backups.first(where: { $0.destination == manifestURL }) {
                do { try fileManager.copyItem(at: manifest.backup, to: manifest.destination) }
                catch { rollbackFailed = true }
            }
            if rollbackFailed {
                throw RecoveryRequiredError(stagingDirectory: stagingDirectory, cause: error)
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
