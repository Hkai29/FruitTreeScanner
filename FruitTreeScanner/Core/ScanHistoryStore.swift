import Foundation
import Combine

@MainActor
final class ScanHistoryStore: ObservableObject {
    static let shared = ScanHistoryStore()

    @Published private(set) var scanFiles: [ScanFileRecord] = []

    static let didUpdateNotification = Notification.Name("ScanHistoryStoreDidUpdate")

    private init() {
        loadRecords()
    }

    func loadRecords() {
        let scansDir = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("scans")

        guard let files = try? FileManager.default.contentsOfDirectory(
            at: scansDir,
            includingPropertiesForKeys: [.creationDateKey],
            options: .skipsHiddenFiles
        ) else {
            scanFiles = []
            return
        }

        scanFiles = files
            .filter { $0.pathExtension == "ply" }
            .compactMap { url -> ScanFileRecord? in
                guard let result = PLYParserHelper.parsePLYFile(at: url) else { return nil }
                return ScanFileRecord(
                    id: url.lastPathComponent,
                    treeID: result.treeID,
                    fileURL: url,
                    scanDate: result.scanDate,
                    fruitCount: result.fruitCount,
                    yieldKg: result.yieldKg,
                    gpsLat: result.gpsLat,
                    gpsLon: result.gpsLon,
                    fruitType: result.fruitType
                )
            }
            .sorted { $0.scanDate > $1.scanDate }
    }

    func deleteRecord(_ record: ScanFileRecord) {
        try? FileManager.default.removeItem(at: record.fileURL)
        let csvURL = record.fileURL.deletingPathExtension().appendingPathExtension("csv")
        try? FileManager.default.removeItem(at: csvURL)
        loadRecords()
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }

    func notifyRecordsUpdated() {
        loadRecords()
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }
}

struct ScanFileRecord: Identifiable, Equatable {
    let id: String
    let treeID: String
    let fileURL: URL
    let scanDate: Date
    let fruitCount: Int
    let yieldKg: Float
    let gpsLat: Double
    let gpsLon: Double
    let fruitType: String

    init(id: String, treeID: String, fileURL: URL, scanDate: Date, fruitCount: Int = 0, yieldKg: Float = 0, gpsLat: Double = 0, gpsLon: Double = 0, fruitType: String = "apple") {
        self.id = id
        self.treeID = treeID
        self.fileURL = fileURL
        self.scanDate = scanDate
        self.fruitCount = fruitCount
        self.yieldKg = yieldKg
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
        self.fruitType = fruitType
    }
}