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
                guard parts.count >= 5,
                      parts[parts.count - 2].hasPrefix("lat"),
                      parts[parts.count - 1].hasPrefix("lon") else { return nil }

                let treeID = parts[0..<parts.count - 4].joined(separator: "_")
                let creationDate = (try? url.resourceValues(forKeys: [.creationDateKey]))?.creationDate ?? Date()

                // Parse GPS from filename: lat30.5728_lon114.2525 (no parentheses)
                var gpsLat: Double = 0
                var gpsLon: Double = 0
                let latStr = String(parts[parts.count - 2])
                let lonStr = String(parts[parts.count - 1])
                if let latVal = Double(latStr.dropFirst(3)) {
                    gpsLat = latVal
                }
                if let lonVal = Double(lonStr.dropFirst(3)) {
                    gpsLon = lonVal
                }

                // Look for corresponding CSV file with yield data
                let csvURL = url.deletingPathExtension().appendingPathExtension("csv")
                var fruitCount = 0
                var yieldKg: Float = 0
                if let csvContent = try? String(contentsOf: csvURL, encoding: .utf8) {
                    let lines = csvContent.split(separator: "\n")
                    if lines.count >= 2 {
                        let values = lines[1].split(separator: ",")
                        if values.count >= 5 {
                            fruitCount = Int(values[3]) ?? 0
                            yieldKg = Float(values[4]) ?? 0
                        }
                    }
                }

                return ScanFileRecord(
                    id: url.lastPathComponent,
                    treeID: treeID,
                    fileURL: url,
                    scanDate: creationDate,
                    fruitCount: fruitCount,
                    yieldKg: yieldKg,
                    gpsLat: gpsLat,
                    gpsLon: gpsLon
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
    let fruitCount: Int
    let yieldKg: Float
    let gpsLat: Double
    let gpsLon: Double

    init(id: String, treeID: String, fileURL: URL, scanDate: Date, fruitCount: Int = 0, yieldKg: Float = 0, gpsLat: Double = 0, gpsLon: Double = 0) {
        self.id = id
        self.treeID = treeID
        self.fileURL = fileURL
        self.scanDate = scanDate
        self.fruitCount = fruitCount
        self.yieldKg = yieldKg
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
    }
}