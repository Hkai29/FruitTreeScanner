import Foundation

struct FruitVarietyParams: Codable, Identifiable, Equatable, Sendable {
    let id: UUID
    let category: String
    var diamMin: Float
    var diamMax: Float
    var averageWeightG: Float
    var density: Float
    var clusterEps: Float
    var sphericityThreshold: Float
    var isCustomized: Bool

    init(category: FruitCategory) {
        self.id = UUID()
        self.category = category.rawValue
        self.diamMin = category.diamMin
        self.diamMax = category.diamMax
        self.averageWeightG = category.averageWeightG
        self.density = category.density
        self.clusterEps = category.clusterEps
        self.sphericityThreshold = category.sphericityThreshold
        self.isCustomized = false
    }

    var fruitCategory: FruitCategory? {
        FruitCategory(rawValue: category)
    }

}
