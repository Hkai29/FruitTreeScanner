import Foundation
import Combine

struct ScanHistoryDeletionArtifact: Equatable, Sendable {
    enum Kind: String, Equatable, Sendable {
        case pointCloud
        case csv
        case resultJSON
        case completionManifest
    }

    enum ResidualReason: Equatable, Sendable {
        case removalFailed(String)
        case notAttemptedAfterPrimaryFailure
    }

    let kind: Kind
    let url: URL
    let reason: ResidualReason
}

struct ScanHistoryRecordDeletionResult: Equatable, Sendable {
    let recordID: String
    let residualArtifacts: [ScanHistoryDeletionArtifact]

    var isComplete: Bool {
        residualArtifacts.isEmpty
    }
}

struct ScanHistoryBatchDeletionResult: Equatable, Sendable {
    let records: [ScanHistoryRecordDeletionResult]

    var isComplete: Bool {
        records.allSatisfy(\.isComplete)
    }

    var failedRecordCount: Int {
        records.lazy.filter { !$0.isComplete }.count
    }
}

enum ScanHistoryLoadFailure: Equatable, Sendable {
    case directoryUnavailable
}

enum ScanHistoryLoadResult: Equatable, Sendable {
    case success([ScanFileRecord])
    case failure(ScanHistoryLoadFailure)
    case cancelled
}

typealias ScanHistoryRecordsLoader = @Sendable () async -> ScanHistoryLoadResult

struct ScanHistoryDirectoryIterator {
    let nextURL: () -> URL?
    let failureDescription: () -> String?

    func next() -> URL? {
        nextURL()
    }
}

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

@MainActor
final class ScanHistoryStore: ObservableObject {
    static let shared = ScanHistoryStore()

    @Published private(set) var scanFiles: [ScanFileRecord] = []
    @Published private(set) var damagedRecords: [ScanFileRecord] = []
    @Published private(set) var loadFailure: ScanHistoryLoadFailure?
    @Published private(set) var isLoading = false

    static let didUpdateNotification = Notification.Name("ScanHistoryStoreDidUpdate")
    private let recordsLoader: ScanHistoryRecordsLoader
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    private convenience init() {
        self.init(
            recordsLoader: {
                await Self.performDiskRead {
                    Self.readRecordsFromDisk()
                }
            },
            automaticallyLoads: true
        )
    }

    init(
        recordsLoader: @escaping ScanHistoryRecordsLoader,
        automaticallyLoads: Bool = false
    ) {
        self.recordsLoader = recordsLoader
        if automaticallyLoads {
            loadRecords()
        }
    }

    @discardableResult
    func loadRecords(postNotification: Bool = false) -> Task<Void, Never> {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        isLoading = true
        let recordsLoader = recordsLoader
        let task = Task { [weak self, generation, postNotification] in
            let result = await recordsLoader()
            guard !Task.isCancelled else {
                self?.finishCancelledLoad(generation: generation)
                return
            }
            self?.applyLoadedRecords(
                result,
                generation: generation,
                postNotification: postNotification
            )
        }
        loadTask = task
        return task
    }

    func reloadRecords(postNotification: Bool = false) async {
        let task = loadRecords(postNotification: postNotification)
        await withTaskCancellationHandler {
            await task.value
        } onCancel: {
            task.cancel()
        }
    }

    private func finishCancelledLoad(generation: Int) {
        guard loadGeneration == generation else { return }
        loadTask = nil
        isLoading = false
    }

    private func applyLoadedRecords(
        _ result: ScanHistoryLoadResult,
        generation: Int,
        postNotification: Bool
    ) {
        guard loadGeneration == generation else { return }
        loadTask = nil
        isLoading = false

        switch result {
        case .success(let records):
            if scanFiles != records {
                scanFiles = records
            }
            let invalidRecords = records.filter { $0.persistenceState == .invalid }
            if damagedRecords != invalidRecords {
                damagedRecords = invalidRecords
            }
            loadFailure = nil
            if postNotification {
                NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
            }
        case .failure(let failure):
            loadFailure = failure
        case .cancelled:
            break
        }
    }

    nonisolated static func performDiskRead(
        _ operation: @escaping @Sendable () -> ScanHistoryLoadResult
    ) async -> ScanHistoryLoadResult {
        let worker = Task.detached(priority: .utility, operation: operation)
        return await withTaskCancellationHandler {
            await worker.value
        } onCancel: {
            worker.cancel()
        }
    }

    nonisolated private static func readRecordsFromDisk() -> ScanHistoryLoadResult {
        let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans")

        return readRecords(
            at: scansDir,
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
            recordBuilder: makeRecord
        )
    }

    nonisolated static func readRecords(
        at scansDirectory: URL,
        directoryExists: (String) -> Bool,
        contentsOfDirectory: (URL) throws -> [URL],
        recordBuilder: (URL) -> ScanFileRecord?
    ) -> ScanHistoryLoadResult {
        readRecords(
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

    nonisolated static func readRecords(
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

    nonisolated private static func makeRecord(from url: URL) -> ScanFileRecord? {
        guard let result = PLYParserHelper.parsePLYFile(at: url) else { return nil }
        let fileSizeBytes = (try? url.resourceValues(forKeys: [.fileSizeKey]).fileSize) ?? 0
        return ScanFileRecord(
            id: url.lastPathComponent,
            treeID: result.treeID,
            fileURL: url,
            scanDate: result.scanDate,
            fruitCount: result.fruitCount,
            yieldKg: result.yieldKg,
            gpsLat: result.gpsLat,
            gpsLon: result.gpsLon,
            fruitType: result.fruitType,
            confidence: result.confidence,
            fileSizeBytes: fileSizeBytes,
            persistenceState: result.persistenceState,
            persistenceFailureReason: result.persistenceFailureReason
        )
    }

    func deleteRecord(_ record: ScanFileRecord) {
        deleteRecords([record])
    }

    func deleteRecords(_ records: [ScanFileRecord]) {
        let recordsToDelete = records
        Task { [weak self] in
            _ = await self?.deleteRecordsWithResult(recordsToDelete)
        }
    }

    func deleteRecordsWithResult(_ records: [ScanFileRecord]) async -> ScanHistoryBatchDeletionResult {
        let recordsToDelete = records
        let result = await Task.detached(priority: .utility) {
            ScanHistoryBatchDeletionResult(
                records: recordsToDelete.map { Self.deleteFilesWithResult(for: $0) }
            )
        }.value
        if result.failedRecordCount > 0 {
            Log.general.error(
                "Failed to fully delete \(result.failedRecordCount) scan record(s); structured result identifies residual files"
            )
        }
        loadRecords(postNotification: true)
        return result
    }

    @discardableResult
    nonisolated static func deleteFiles(
        for record: ScanFileRecord,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) -> Bool {
        deleteFilesWithResult(
            for: record,
            fileExists: fileExists,
            removeItem: removeItem
        ).isComplete
    }

    nonisolated static func deleteFilesWithResult(
        for record: ScanFileRecord,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) -> ScanHistoryRecordDeletionResult {
        let baseName = record.fileURL.deletingPathExtension().lastPathComponent
        let companionArtifacts: [(ScanHistoryDeletionArtifact.Kind, URL)] = [
            (.csv, record.fileURL.deletingPathExtension().appendingPathExtension("csv")),
            (
                .resultJSON,
                record.fileURL.deletingLastPathComponent()
                    .appendingPathComponent("\(baseName)_result.json")
            ),
            (
                .completionManifest,
                record.fileURL.deletingLastPathComponent()
                    .appendingPathComponent("\(baseName)_complete.json")
            )
        ]
        var residualArtifacts: [ScanHistoryDeletionArtifact] = []

        if fileExists(record.fileURL.path) {
            do {
                try removeItem(record.fileURL)
            } catch {
                residualArtifacts.append(
                    ScanHistoryDeletionArtifact(
                        kind: .pointCloud,
                        url: record.fileURL,
                        reason: .removalFailed(error.localizedDescription)
                    )
                )
                for (kind, url) in companionArtifacts where fileExists(url.path) {
                    residualArtifacts.append(
                        ScanHistoryDeletionArtifact(
                            kind: kind,
                            url: url,
                            reason: .notAttemptedAfterPrimaryFailure
                        )
                    )
                }
                return ScanHistoryRecordDeletionResult(
                    recordID: record.id,
                    residualArtifacts: residualArtifacts
                )
            }
        }

        for (kind, url) in companionArtifacts where fileExists(url.path) {
            do {
                try removeItem(url)
            } catch {
                residualArtifacts.append(
                    ScanHistoryDeletionArtifact(
                        kind: kind,
                        url: url,
                        reason: .removalFailed(error.localizedDescription)
                    )
                )
            }
        }
        return ScanHistoryRecordDeletionResult(
            recordID: record.id,
            residualArtifacts: residualArtifacts
        )
    }

    func notifyRecordsUpdated() {
        loadRecords(postNotification: true)
    }
}

struct ScanFileRecord: Identifiable, Equatable, Sendable {
    let id: String
    let treeID: String
    let fileURL: URL
    let scanDate: Date
    let fruitCount: Int
    let yieldKg: Float
    let gpsLat: Double
    let gpsLon: Double
    let fruitType: String
    let confidence: String
    let fileSizeBytes: Int
    let persistenceState: ScanPersistenceState
    let persistenceFailureReason: String?

    init(id: String, treeID: String, fileURL: URL, scanDate: Date, fruitCount: Int = 0, yieldKg: Float = 0, gpsLat: Double = 0, gpsLon: Double = 0, fruitType: String = "", confidence: String = "", fileSizeBytes: Int = 0, persistenceState: ScanPersistenceState = .complete, persistenceFailureReason: String? = nil) {
        self.id = id
        self.treeID = treeID
        self.fileURL = fileURL
        self.scanDate = scanDate
        self.fruitCount = max(0, fruitCount)
        self.yieldKg = Self.nonNegativeFinite(yieldKg)
        let coordinate = Self.coordinate(latitude: gpsLat, longitude: gpsLon)
        self.gpsLat = coordinate.latitude
        self.gpsLon = coordinate.longitude
        self.fruitType = fruitType
        self.confidence = confidence
        self.fileSizeBytes = fileSizeBytes
        self.persistenceState = persistenceState
        self.persistenceFailureReason = persistenceFailureReason
    }

    private static func nonNegativeFinite(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }

    private static func coordinate(
        latitude: Double,
        longitude: Double
    ) -> (latitude: Double, longitude: Double) {
        guard latitude.isFinite,
              longitude.isFinite,
              (-90...90).contains(latitude),
              (-180...180).contains(longitude)
        else {
            return (0, 0)
        }
        return (latitude, longitude)
    }
}
