import Foundation

// MARK: - 校准记录

struct CalibrationRecord: Codable, Identifiable {
    let id: UUID
    let treeID: String
    let scanDate: Date
    let estimatedFruitCount: Int
    let manualFruitCount: Int?
    let estimatedYieldKg: Double
    let actualYieldKg: Double?
    let fruitType: String

    var countError: Double? {
        guard let manual = manualFruitCount, manual > 0 else { return nil }
        return Double(estimatedFruitCount - manual) / Double(manual) * 100
    }

    var yieldError: Double? {
        guard let actual = actualYieldKg, actual > 0 else { return nil }
        return (estimatedYieldKg - actual) / actual * 100
    }
}

