import Foundation

private final class ScanHistoryEnumerationFailureBox: @unchecked Sendable {
    private let lock = NSLock()
    private var storedDescription: String?

    var description: String? {
        lock.lock()
        defer { lock.unlock() }
        return storedDescription
    }

    func record(_ error: Error) {
        lock.lock()
        storedDescription = error.localizedDescription
        lock.unlock()
    }
}

struct ScanAssessment: Sendable {
    let draft: DraftScan
    let exportRequest: ScanResultExportService.ExportRequest
    let evidenceReceipt: ScanEvidenceReceipt?
    private let resultEvidence: ScanEvidenceIdentity?

    /// Compatibility for archives without a live scan capture context.
    init(draft: DraftScan, exportRequest: ScanResultExportService.ExportRequest) {
        self.draft = draft
        self.exportRequest = exportRequest
        evidenceReceipt = nil
        resultEvidence = nil
    }

    init(receipt: ScanEvidenceReceipt, estimate: ScanEstimate,
         treeID: String, fruitType: String, scanDate: Date, gpsLat: Double, gpsLon: Double,
         includeCSV: Bool) {
        self.draft = receipt.draft
        self.evidenceReceipt = receipt
        resultEvidence = estimate.evidenceIdentity
        exportRequest = .init(treeID: treeID, fruitType: fruitType, scanDate: scanDate,
                              gpsLat: gpsLat, gpsLon: gpsLon, sourceFilename: draft.sourceFilename,
                              result: estimate.result, includeCSV: includeCSV)
    }

    func validateEvidence() throws {
        guard let evidenceReceipt else {
            // A live capture cannot bypass provenance using the legacy entry.
            guard draft.captureIdentity == nil, resultEvidence == nil else {
                throw ScanEvidenceError.mismatchedInput
            }
            return
        }
        let expectedEvidence = evidenceReceipt.identity
        guard expectedEvidence == resultEvidence,
              expectedEvidence.capture == draft.captureIdentity,
              expectedEvidence.sourceOwnershipID == draft.ownershipID,
              expectedEvidence.sourceSHA256 == draft.sourceSHA256 else {
            throw ScanEvidenceError.mismatchedInput
        }
    }
}

struct CommittedScan: Sendable {
    let sourceURL: URL
    let metadataURL: URL
    let manifestURL: URL
    let exportRevision: String
}

struct CalibrationScanBaseline: Sendable {
    let algorithmRevision: String
    let calibrationContext: String
    let fruitCount: Int
    let yieldKg: Float
}

/// A complete record verified using its format's existing rules. Legacy
/// CSV/JSON records have no manifest; this does not invent a source hash for them.
struct VerifiedScanRecord: Sendable {
    let summary: ScanFileRecord
    let manifest: CompletionManifestDTO?

    fileprivate init(summary: ScanFileRecord, manifest: CompletionManifestDTO?) {
        self.summary = summary
        self.manifest = manifest
    }
}

final class ScanRepository: @unchecked Sendable {
    static let shared = ScanRepository()

    private let access = ScanArchiveAccess.shared
    private let scansDirectoryOverride: URL?
    private let exporter: ScanResultExportService

    init(scansDirectory: URL? = nil, exporter: ScanResultExportService? = nil) {
        scansDirectoryOverride = scansDirectory
        self.exporter = exporter ?? (scansDirectory == nil ? .shared : ScanResultExportService(scansDirectory: scansDirectory))
    }

    func pointCloudDestination(filename: String, fallbackFolder: String = "scans") throws -> URL {
        guard LocalFileStorage.isSafeLeafFilename(filename), (filename as NSString).pathExtension.lowercased() == "ply" else {
            throw LocalFileStorageError.invalidFilename
        }
        let directory = try scansDirectoryOverride ?? LocalFileStorage.directoryURL(folder: fallbackFolder)
        return directory.appendingPathComponent(filename, isDirectory: false)
    }

    /// Read-only query: a missing archive directory remains missing. Callers
    /// run this blocking file work through their cancellable background worker.
    func loadHistoryRecords() -> ScanHistoryLoadResult {
        let directory = scansDirectoryOverride ?? LocalFileStorage.documentsDirectory()
            .appendingPathComponent("scans")
        return Self.readHistoryRecords(
            at: directory,
            directoryExists: { FileManager.default.fileExists(atPath: $0) },
            directoryIterator: { directory in
                let failureBox = ScanHistoryEnumerationFailureBox()
                guard let enumerator = FileManager.default.enumerator(
                    at: directory,
                    includingPropertiesForKeys: [.fileSizeKey],
                    options: [.skipsHiddenFiles, .skipsSubdirectoryDescendants],
                    errorHandler: { _, error in
                        failureBox.record(error)
                        return false
                    }
                ) else {
                    return nil
                }
                return ScanHistoryDirectoryIterator(
                    nextURL: { enumerator.nextObject() as? URL },
                    failureDescription: { failureBox.description }
                )
            },
            recordBuilder: { try? self.summary(at: $0) }
        )
    }

    static func readHistoryRecords(
        at scansDirectory: URL,
        directoryExists: (String) -> Bool,
        contentsOfDirectory: (URL) throws -> [URL],
        recordBuilder: (URL) -> ScanFileRecord?
    ) -> ScanHistoryLoadResult {
        readHistoryRecords(
            at: scansDirectory,
            directoryExists: directoryExists,
            directoryIterator: { directory in
                let files = try contentsOfDirectory(directory)
                var index = files.startIndex
                return ScanHistoryDirectoryIterator(
                    nextURL: {
                        guard index < files.endIndex else { return nil }
                        defer { files.formIndex(after: &index) }
                        return files[index]
                    },
                    failureDescription: { nil }
                )
            },
            recordBuilder: recordBuilder
        )
    }

    static func readHistoryRecords(
        at scansDirectory: URL,
        directoryExists: (String) -> Bool,
        directoryIterator: (URL) throws -> ScanHistoryDirectoryIterator?,
        recordBuilder: (URL) -> ScanFileRecord?
    ) -> ScanHistoryLoadResult {
        guard directoryExists(scansDirectory.path) else {
            return .success([])
        }
        do {
            guard let files = try directoryIterator(scansDirectory) else {
                Log.general.error("Failed to create scan history directory enumerator")
                return .failure(.directoryUnavailable)
            }
            var records: [ScanFileRecord] = []
            while true {
                guard !Task.isCancelled else { return .cancelled }
                guard let file = files.next() else { break }
                guard file.pathExtension == "ply" else { continue }
                if let record = autoreleasepool(invoking: { recordBuilder(file) }) {
                    records.append(record)
                }
            }
            guard !Task.isCancelled else { return .cancelled }
            if let failureDescription = files.failureDescription() {
                Log.general.error("Failed to read scan history directory: \(failureDescription)")
                return .failure(.directoryUnavailable)
            }
            records.sort { $0.scanDate > $1.scanDate }
            guard !Task.isCancelled else { return .cancelled }
            return .success(records)
        } catch {
            Log.general.error("Failed to read scan history directory: \(error.localizedDescription)")
            return .failure(.directoryUnavailable)
        }
    }

    func withScanTransaction<T>(at sourceURL: URL, operation: () throws -> T) throws -> T {
        try access.withTransaction(at: sourceURL, operation: operation)
    }

    func draft(at sourceURL: URL) throws -> DraftScan {
        try withScanTransaction(at: sourceURL) {
            try captureDraft(at: sourceURL)
        }
    }

    func bindEvidence(_ identity: ScanEvidenceIdentity, to draft: DraftScan) throws -> ScanEvidenceReceipt {
        try withScanTransaction(at: draft.sourceURL) {
            try access.bindEvidence(identity, to: draft)
        }
    }

    private func captureDraft(at sourceURL: URL) throws -> DraftScan {
        guard !access.requiresEvidenceReceipt(at: sourceURL) else {
            throw ScanEvidenceError.mismatchedInput
        }
        guard LocalFileStorage.isSafeLeafFilename(sourceURL.lastPathComponent),
              sourceURL.pathExtension.lowercased() == "ply",
              PLYParserHelper.hasValidPointCloudHeader(at: sourceURL) else {
            throw LocalFileStorageError.invalidFilename
        }
        let identity = try ScanSourceFileIdentity.read(at: sourceURL)
        let digest = try ScanCompanionIntegrity.digestFile(at: sourceURL)
        guard try ScanSourceFileIdentity.read(at: sourceURL) == identity else {
            throw ScanSourceFileError.invalidOrChanged
        }
        let draft = DraftScan(sourceURL: sourceURL, sourceSHA256: digest,
                              fileIdentity: identity, ownershipID: UUID())
        access.registerDraft(draft)
        return draft
    }

    func readRecord(at sourceURL: URL) throws -> PLYParserResult? {
        try withScanTransaction(at: sourceURL) {
            PLYParserHelper.parsePLYFile(at: sourceURL)
        }
    }

    func readVerifiedRecord(at sourceURL: URL) throws -> VerifiedScanRecord? {
        try withScanTransaction(at: sourceURL) {
            verifiedRecordUnlocked(at: sourceURL)
        }
    }

    private func verifiedRecordUnlocked(at sourceURL: URL) -> VerifiedScanRecord? {
        guard PLYParserHelper.hasValidPointCloudHeader(at: sourceURL),
              let result = PLYParserHelper.parsePLYFile(at: sourceURL), result.persistenceState == .complete else { return nil }
        let manifestURL = sourceURL.deletingLastPathComponent()
            .appendingPathComponent("\(sourceURL.deletingPathExtension().lastPathComponent)_complete.json")
        return VerifiedScanRecord(summary: makeSummary(at: sourceURL, result: result),
                                  manifest: ScanLegacyArchiveCodec.readManifest(at: manifestURL))
    }

    func summary(at sourceURL: URL) throws -> ScanFileRecord? {
        try withScanTransaction(at: sourceURL) {
            guard let result = PLYParserHelper.parsePLYFile(at: sourceURL) else { return nil }
            return makeSummary(at: sourceURL, result: result)
        }
    }

    private func makeSummary(at sourceURL: URL, result: PLYParserResult) -> ScanFileRecord {
        let size = (try? sourceURL.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ScanFileRecord(
            id: sourceURL.lastPathComponent,
            treeID: result.treeID,
            fileURL: sourceURL,
            scanDate: result.scanDate,
            fruitCount: result.fruitCount,
            yieldKg: result.yieldKg,
            gpsLat: result.gpsLat,
            gpsLon: result.gpsLon,
            fruitType: result.fruitType,
            confidence: result.confidence,
            fileSizeBytes: size,
            requiresSourceValidation: true,
            persistenceState: result.persistenceState,
            persistenceFailureReason: result.persistenceFailureReason
        )
    }

    /// Batch export calls this before and after writing. The lock gives each
    /// validation pass one coherent scan revision, without removing either pass.
    func validateBatchRecord(_ record: ScanFileRecord) throws {
        try withScanTransaction(at: record.fileURL) {
            let fileManager = FileManager.default
            let baseURL = record.fileURL.deletingPathExtension()
            let directory = record.fileURL.deletingLastPathComponent()
            let sidecarExists = [
                baseURL.appendingPathExtension("csv"),
                directory.appendingPathComponent("\(baseURL.lastPathComponent)_result.json"),
                directory.appendingPathComponent("\(baseURL.lastPathComponent)_complete.json")
            ].contains { fileManager.fileExists(atPath: $0.path) }
            if !record.requiresSourceValidation &&
                (!sidecarExists || !fileManager.fileExists(atPath: record.fileURL.path)) {
                return
            }
            if record.requiresSourceValidation {
                guard let current = verifiedRecordUnlocked(at: record.fileURL)?.summary,
                      current.fruitCount == record.fruitCount,
                      current.yieldKg == record.yieldKg,
                      current.fruitType == record.fruitType,
                      current.fileSizeBytes == record.fileSizeBytes,
                      current.confidence == record.confidence,
                      current.treeID == record.treeID,
                      current.scanDate == record.scanDate,
                      current.gpsLat == record.gpsLat,
                      current.gpsLon == record.gpsLon else {
                    throw BatchExportError.inconsistentRecord
                }
            } else {
                guard let current = PLYParserHelper.readCompanionResult(for: record.fileURL).result,
                      current.fruitCount == record.fruitCount,
                      current.yieldKg == record.yieldKg,
                      current.fruitType == record.fruitType else {
                    throw BatchExportError.inconsistentRecord
                }
            }
        }
    }

    /// Dynamic legacy keys stay inside persistence/codec. Capture and validate
    /// one coherent sidecar under the source lock, then encode outside the lock.
    func researchExportRecordData(for record: ScanFileRecord) throws -> Data {
        let payload: [String: Any]? = try withScanTransaction(at: record.fileURL) {
            let baseName = record.fileURL.deletingPathExtension().lastPathComponent
            let directory = record.fileURL.deletingLastPathComponent()
            let metadataURL = directory.appendingPathComponent("\(baseName)_result.json")
            let manifestURL = directory.appendingPathComponent("\(baseName)_complete.json")
            guard let payload = PLYParserHelper.readValidatedCompanionMetadataPayload(for: record.fileURL) else {
                if record.requiresSourceValidation,
                   FileManager.default.fileExists(atPath: metadataURL.path)
                    || FileManager.default.fileExists(atPath: manifestURL.path) {
                    throw BatchExportError.inconsistentRecord
                }
                return nil
            }
            if record.requiresSourceValidation {
                guard let dto = ScanLegacyArchiveCodec.metadata(from: payload),
                      dto.fruitCount == record.fruitCount, dto.yieldKg == record.yieldKg,
                      dto.treeID == nil || dto.treeID == record.treeID,
                      !dto.hasFruitTypeField || dto.fruitType == record.fruitType else {
                    throw BatchExportError.inconsistentRecord
                }
            }
            return payload
        }
        return try ScanResearchArchiveCodec.encodeRecord(record, sidecar: payload)
    }

    func readCalibrationBaseline(for record: ScanFileRecord) throws -> CalibrationScanBaseline? {
        try withScanTransaction(at: record.fileURL) {
            let baseName = record.fileURL.deletingPathExtension().lastPathComponent
            let manifestURL = record.fileURL.deletingLastPathComponent()
                .appendingPathComponent("\(baseName)_complete.json")
            guard let manifest = ScanLegacyArchiveCodec.readManifest(at: manifestURL),
                  manifest.schemaVersion == 3,
                  manifest.scanID == baseName,
                  manifest.sourcePLYFilename == record.fileURL.lastPathComponent,
                  let payload = PLYParserHelper.readValidatedCompanionMetadataPayload(for: record.fileURL),
                  let dto = ScanLegacyArchiveCodec.metadata(from: payload),
                  dto.scanID == baseName,
                  dto.sourceFilename == record.fileURL.lastPathComponent,
                  dto.exportRevision == manifest.exportRevision,
                  dto.treeID == record.treeID,
                  dto.fruitCount == record.fruitCount,
                  dto.yieldKg == record.yieldKg,
                  let revision = dto.algorithmRevision,
                  !revision.isEmpty,
                  revision != "unknown",
                  let context = dto.calibrationContext,
                  !context.isEmpty,
                  let baselineCount = dto.calibrationBaseCount,
                  let baselineYield = dto.calibrationBaseYieldKg else {
                return nil
            }
            return CalibrationScanBaseline(
                algorithmRevision: revision,
                calibrationContext: context,
                fruitCount: baselineCount,
                yieldKg: baselineYield
            )
        }
    }

    func commit(
        _ assessment: ScanAssessment,
        using service: ScanResultExportService? = nil
    ) throws -> CommittedScan {
        try assessment.validateEvidence()
        guard assessment.exportRequest.sourceFilename == assessment.draft.sourceFilename else {
            throw LocalFileStorageError.invalidFilename
        }
        guard let exported = try (service ?? exporter).exportAssessment(assessment) else {
            throw ScanSourceFileError.invalidOrChanged
        }
        return try confirm(exported, for: assessment.draft)
    }

    /// The export service releases the per-scan lock before returning. A new
    /// revision may arrive before confirmation, so verify this export's exact
    /// metadata and source identity rather than any complete revision.
    func confirm(_ exported: ScanResultExportService.ExportedFiles, for draft: DraftScan) throws -> CommittedScan {
        guard let metadataURL = exported.metadataURL,
              let manifestURL = exported.manifestURL,
              metadataURL.deletingLastPathComponent().standardizedFileURL ==
                draft.sourceURL.deletingLastPathComponent().standardizedFileURL else {
            throw ScanSourceFileError.invalidOrChanged
        }
        return try withScanTransaction(at: draft.sourceURL) {
            guard let parsed = PLYParserHelper.parsePLYFile(at: draft.sourceURL),
                  parsed.persistenceState == .complete,
                  let manifest = ScanLegacyArchiveCodec.readManifest(at: manifestURL),
                  manifest.schemaVersion == 3,
                  manifest.exportRevision == exported.exportRevision,
                  manifest.fileSHA256?[metadataURL.lastPathComponent] == exported.metadataSHA256,
                  manifest.sourcePLYSHA256 == exported.sourcePLYSHA256,
                  exported.sourcePLYSHA256 == draft.sourceSHA256,
                  try ScanSourceFileIdentity.read(at: draft.sourceURL) == draft.fileIdentity else {
                throw ScanSourceFileError.invalidOrChanged
            }
            access.releaseDraft(draft)
            return CommittedScan(
                sourceURL: draft.sourceURL,
                metadataURL: metadataURL,
                manifestURL: manifestURL,
                exportRevision: manifest.exportRevision
            )
        }
    }

    func settleCancelledDraft(
        _ draft: DraftScan,
        removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) -> DraftSettlement {
        do {
            return try withScanTransaction(at: draft.sourceURL) {
                let manager = FileManager.default
                let base = draft.sourceURL.deletingPathExtension()
                let companions = [base.appendingPathExtension("csv"),
                    base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent)_result.json"),
                    base.deletingLastPathComponent().appendingPathComponent("\(base.lastPathComponent)_complete.json")]
                guard manager.fileExists(atPath: draft.sourceURL.path) else {
                    guard !companions.contains(where: { manager.fileExists(atPath: $0.path) }) else {
                        return .requiresRecovery("Source missing with companion files remaining")
                    }
                    access.releaseDraft(draft)
                    return .discarded
                }
                guard try ScanSourceFileIdentity.read(at: draft.sourceURL) == draft.fileIdentity,
                      try ScanCompanionIntegrity.digestFile(at: draft.sourceURL) == draft.sourceSHA256 else {
                    return .requiresRecovery("Source changed; preserved the replacement")
                }
                if PLYParserHelper.parsePLYFile(at: draft.sourceURL)?.persistenceState == .complete {
                    access.releaseDraft(draft)
                    return .preservedCommitted
                }
                guard access.ownsDraft(draft) else {
                    return .requiresRecovery("Draft ownership changed; preserved the current record")
                }
                // Preserve the history anchor when companion cleanup fails.
                for url in companions where manager.fileExists(atPath: url.path) { try removeItem(url) }
                try removeItem(draft.sourceURL)
                access.releaseDraft(draft)
                return .discarded
            }
        } catch {
            return .requiresRecovery(error.localizedDescription)
        }
    }

    func stagePointCloud(
        to sourceURL: URL,
        captureIdentity: ScanCaptureIdentity? = nil,
        writing: () throws -> PLYPointCloudWriter.Receipt
    ) throws -> DraftScan {
        try withScanTransaction(at: sourceURL) {
            let receipt = try writing()
            let draft = DraftScan(sourceURL: sourceURL, sourceSHA256: receipt.sourceSHA256,
                                  fileIdentity: receipt.fileIdentity, ownershipID: UUID(),
                                  captureIdentity: captureIdentity)
            access.registerDraft(draft)
            return draft
        }
    }

    func importPointCloud(_ sourceURL: URL) throws -> String {
        try PLYImportService.importFile(sourceURL, scansDirectory: scansDirectoryOverride)
    }

    func delete(
        _ record: ScanFileRecord,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) -> ScanHistoryRecordDeletionResult {
        do {
            return try withScanTransaction(at: record.fileURL) {
                deleteUnlocked(record, fileExists: fileExists, removeItem: removeItem)
            }
        } catch {
            return ScanHistoryRecordDeletionResult(
                recordID: record.id,
                residualArtifacts: [ScanHistoryDeletionArtifact(
                    kind: .pointCloud,
                    url: record.fileURL,
                    reason: .removalFailed(error.localizedDescription)
                )]
            )
        }
    }

    private func deleteUnlocked(
        _ record: ScanFileRecord,
        fileExists: (String) -> Bool,
        removeItem: (URL) throws -> Void
    ) -> ScanHistoryRecordDeletionResult {
        let baseName = record.fileURL.deletingPathExtension().lastPathComponent
        let directory = record.fileURL.deletingLastPathComponent()
        let companions: [(ScanHistoryDeletionArtifact.Kind, URL)] = [
            (.csv, record.fileURL.deletingPathExtension().appendingPathExtension("csv")),
            (.resultJSON, directory.appendingPathComponent("\(baseName)_result.json")),
            (.completionManifest, directory.appendingPathComponent("\(baseName)_complete.json"))
        ]
        var residualArtifacts: [ScanHistoryDeletionArtifact] = []

        // The PLY is the history anchor. A failed companion removal must leave
        // it discoverable so the incomplete deletion remains visible.
        for (kind, url) in companions where fileExists(url.path) {
            do {
                try removeItem(url)
            } catch {
                residualArtifacts.append(ScanHistoryDeletionArtifact(
                    kind: kind,
                    url: url,
                    reason: .removalFailed(error.localizedDescription)
                ))
            }
        }

        if !residualArtifacts.isEmpty {
            if fileExists(record.fileURL.path) {
                residualArtifacts.append(ScanHistoryDeletionArtifact(
                    kind: .pointCloud,
                    url: record.fileURL,
                    reason: .notAttemptedAfterCompanionFailure
                ))
            }
            return ScanHistoryRecordDeletionResult(
                recordID: record.id,
                residualArtifacts: residualArtifacts
            )
        }

        if fileExists(record.fileURL.path) {
            do {
                try removeItem(record.fileURL)
            } catch {
                residualArtifacts.append(ScanHistoryDeletionArtifact(
                    kind: .pointCloud,
                    url: record.fileURL,
                    reason: .removalFailed(error.localizedDescription)
                ))
            }
        }
        return ScanHistoryRecordDeletionResult(
            recordID: record.id,
            residualArtifacts: residualArtifacts
        )
    }
}
