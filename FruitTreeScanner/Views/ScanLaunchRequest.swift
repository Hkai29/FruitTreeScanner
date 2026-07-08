import Foundation

struct ScanLaunchRequest: Identifiable {
    let id = UUID()
    let treeID: String
    let season: Season
    let gps: GPSRecorder
    let plotId: UUID?
    let tagIds: [UUID]

    init(
        treeID: String,
        season: Season,
        gps: GPSRecorder,
        plotId: UUID? = nil,
        tagIds: [UUID] = []
    ) {
        self.treeID = treeID
        self.season = season
        self.gps = gps
        self.plotId = plotId
        self.tagIds = tagIds
    }
}
