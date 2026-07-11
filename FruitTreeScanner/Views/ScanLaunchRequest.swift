import Foundation

struct ScanLaunchRequest: Identifiable {
    let id = UUID()
    let treeID: String
    let selectedFruitCategory: FruitCategory
    let season: Season
    let gps: GPSRecorder
    let plotId: UUID?
    let tagIds: [UUID]

    init(
        treeID: String,
        selectedFruitCategory: FruitCategory = FruitCategory.scanCategory(for: SettingsStore.shared.fruitType),
        season: Season,
        gps: GPSRecorder,
        plotId: UUID? = nil,
        tagIds: [UUID] = []
    ) {
        self.treeID = treeID
        self.selectedFruitCategory = selectedFruitCategory
        self.season = season
        self.gps = gps
        self.plotId = plotId
        self.tagIds = tagIds
    }
}
