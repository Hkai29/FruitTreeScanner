import Foundation

struct RecordExport: Codable, Sendable {
    let treeID: String
    let fruitType: String
    let scanDate: String
    let fruitCount: Int
    let yieldKg: Float
    let gpsLat: Double
    let gpsLon: Double
    let clusterEps: Float?
    let clusterMinPoints: Int?
    let colorFilterDesc: String?
    let occlusionK: Float?
    let pointCloudSize: Int?
    let confidence: String?
    let methodUsed: String?
}

struct ScanExport: Codable, Sendable {
    let exportDate: String
    let totalTrees: Int
    let totalFruits: Int
    let totalYieldKg: Float
    let records: [RecordExport]
}
