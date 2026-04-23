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
                let filename = url.deletingPathExtension().lastPathComponent
                let parts = filename.split(separator: "_")
                guard parts.count >= 4, parts[0] == "tree" else { return nil }

                let treeID = String(parts[1])
                let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

                return ScanFileRecord(
                    id: url.lastPathComponent,
                    treeID: treeID,
                    fileURL: url,
                    scanDate: creationDate
                )
            }
            .sorted { $0.scanDate > $1.scanDate }
    }

    func deleteRecord(_ record: ScanFileRecord) {
        try? FileManager.default.removeItem(at: record.fileURL)
        loadRecords()
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }
}

struct ScanFileRecord: Identifiable, Equatable {
    let id: String
    let treeID: String
    let fileURL: URL
    let scanDate: Date
}