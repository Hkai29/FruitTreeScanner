import Foundation
import Combine

@MainActor
final class ScanHistoryStore: ObservableObject {
    static let shared = ScanHistoryStore()

    @Published private(set) var scanFiles: [ScanFileRecord] = []

    static let didUpdateNotification = Notification.Name("ScanHistoryStoreDidUpdate")
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    private init() {
        loadRecords()
    }

    func loadRecords(postNotification: Bool = false) {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        loadTask = Task.detached(priority: .utility) { [weak self, generation, postNotification] in
            let records = Self.readRecordsFromDisk()
            guard !Task.isCancelled else { return }
            await self?.applyLoadedRecords(records, generation: generation, postNotification: postNotification)
        }
    }

    private func applyLoadedRecords(_ records: [ScanFileRecord], generation: Int, postNotification: Bool) {
        guard loadGeneration == generation else { return }
        if scanFiles != records {
            scanFiles = records
        }
        if postNotification {
            NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
        }
    }

    nonisolated private static func readRecordsFromDisk() -> [ScanFileRecord] {
        let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans")

        guard FileManager.default.fileExists(atPath: scansDir.path) else {
            return []
        }

        do {
            let files = try FileManager.default.contentsOfDirectory(
                at: scansDir,
                includingPropertiesForKeys: [.creationDateKey],
                options: .skipsHiddenFiles
            )

            return files
                .filter { $0.pathExtension == "ply" }
                .compactMap { url -> ScanFileRecord? in
                    guard let result = PLYParserHelper.parsePLYFile(at: url) else { return nil }
                    let attributes = try? FileManager.default.attributesOfItem(atPath: url.path)
                    let fileSizeBytes = attributes?[.size] as? Int ?? 0
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
                        fileSizeBytes: fileSizeBytes
                    )
                }
                .sorted { $0.scanDate > $1.scanDate }
        } catch {
            Log.general.error("Failed to read scan history directory: \(error.localizedDescription)")
            return []
        }
    }

    func deleteRecord(_ record: ScanFileRecord) {
        deleteRecords([record])
    }

    func deleteRecords(_ records: [ScanFileRecord]) {
        let recordsToDelete = records
        Task.detached(priority: .utility) { [weak self] in
            let failedCount = recordsToDelete.reduce(into: 0) { count, record in
                if !Self.deleteFiles(for: record) {
                    count += 1
                }
            }
            if failedCount > 0 {
                Log.general.error("Failed to fully delete \(failedCount) scan record(s); some primary or companion files may remain")
            }
            guard !Task.isCancelled else { return }
            await self?.loadRecords(postNotification: true)
        }
    }

    @discardableResult
    nonisolated static func deleteFiles(
        for record: ScanFileRecord,
        fileExists: (String) -> Bool = { FileManager.default.fileExists(atPath: $0) },
        removeItem: (URL) throws -> Void = { try FileManager.default.removeItem(at: $0) }
    ) -> Bool {
        if fileExists(record.fileURL.path) {
            do {
                try removeItem(record.fileURL)
            } catch {
                return false
            }
        }

        var deletedAllAvailableFiles = true
        let csvURL = record.fileURL.deletingPathExtension().appendingPathExtension("csv")
        if fileExists(csvURL.path) {
            do {
                try removeItem(csvURL)
            } catch {
                deletedAllAvailableFiles = false
            }
        }
        let baseName = record.fileURL.deletingPathExtension().lastPathComponent
        let jsonURL = record.fileURL.deletingLastPathComponent()
            .appendingPathComponent("\(baseName)_result.json")
        if fileExists(jsonURL.path) {
            do {
                try removeItem(jsonURL)
            } catch {
                deletedAllAvailableFiles = false
            }
        }
        return deletedAllAvailableFiles
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

    init(id: String, treeID: String, fileURL: URL, scanDate: Date, fruitCount: Int = 0, yieldKg: Float = 0, gpsLat: Double = 0, gpsLon: Double = 0, fruitType: String = "apple", confidence: String = "low", fileSizeBytes: Int = 0) {
        self.id = id
        self.treeID = treeID
        self.fileURL = fileURL
        self.scanDate = scanDate
        self.fruitCount = max(0, fruitCount)
        self.yieldKg = Self.nonNegativeFinite(yieldKg)
        self.gpsLat = Self.latitude(gpsLat)
        self.gpsLon = Self.longitude(gpsLon)
        self.fruitType = fruitType
        self.confidence = confidence
        self.fileSizeBytes = fileSizeBytes
    }

    private static func nonNegativeFinite(_ value: Float) -> Float {
        value.isFinite ? max(0, value) : 0
    }

    private static func latitude(_ value: Double) -> Double {
        guard value.isFinite, (-90...90).contains(value) else { return 0 }
        return value
    }

    private static func longitude(_ value: Double) -> Double {
        guard value.isFinite, (-180...180).contains(value) else { return 0 }
        return value
    }
}
