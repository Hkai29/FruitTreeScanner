import Foundation
import Combine

@MainActor
final class ScanHistoryStore: ObservableObject {
    static let shared = ScanHistoryStore()

    @Published private(set) var scanRecords: [ScanRecord] = []

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
            scanRecords = []
            return
        }

        scanRecords = files
            .filter { $0.pathExtension == "ply" }
            .compactMap { url -> ScanRecord? in
                let filename = url.deletingPathExtension().lastPathComponent
                let parts = filename.split(separator: "_")
                guard parts.count >= 4, parts[0] == "tree" else { return nil }

                let treeID = String(parts[1])
                let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

                return ScanRecord(
                    id: url.lastPathComponent,
                    treeID: treeID,
                    fileURL: url,
                    scanDate: creationDate,
                    fruitType: "apple",
                    fruitCount: 0,
                    yieldKg: 0
                )
            }
            .sorted { $0.scanDate > $1.scanDate }
    }

    func deleteRecord(_ record: ScanRecord) {
        try? FileManager.default.removeItem(at: record.fileURL)
        loadRecords()
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }
}

struct ScanRecord: Identifiable, Equatable {
    let id: String
    let treeID: String
    let fileURL: URL
    let scanDate: Date
    var fruitType: String
    var fruitCount: Int
    var yieldKg: Double
}