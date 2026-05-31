import Foundation

struct ScanRecord: Identifiable {
    let id: UUID
    let treeID: String
    let fruitType: String
    let scanDate: Date
    let fruitCount: Int
    let yieldKg: Float
    let gpsLat: Double
    let gpsLon: Double
    let fileURL: URL?

    init(
        id: UUID,
        treeID: String,
        fruitType: String,
        scanDate: Date,
        fruitCount: Int,
        yieldKg: Float,
        gpsLat: Double,
        gpsLon: Double,
        fileURL: URL? = nil
    ) {
        self.id = id
        self.treeID = treeID
        self.fruitType = fruitType
        self.scanDate = scanDate
        self.fruitCount = fruitCount
        self.yieldKg = yieldKg
        self.gpsLat = gpsLat
        self.gpsLon = gpsLon
        self.fileURL = fileURL
    }
}
