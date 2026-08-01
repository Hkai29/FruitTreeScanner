import Combine
import Foundation

struct StartScanSelectionSnapshot: Equatable, Sendable {
    let plotId: UUID?
    let tagIds: [UUID]
}

enum StartScanSelectionPolicy {
    static func snapshot(
        selectedPlotId: UUID?,
        selectedTagIds: Set<UUID>,
        availablePlots: [Plot],
        availableTags: [GroupTag]
    ) -> StartScanSelectionSnapshot {
        let availablePlotIDs = Set(availablePlots.map(\.id))
        let plotId = selectedPlotId.flatMap {
            availablePlotIDs.contains($0) ? $0 : nil
        }
        let tagIds = availableTags.compactMap {
            selectedTagIds.contains($0.id) ? $0.id : nil
        }
        return StartScanSelectionSnapshot(plotId: plotId, tagIds: tagIds)
    }
}

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

@MainActor
final class ScanLaunchSubmissionGate: ObservableObject {
    @Published private(set) var isSubmitting = false

    /// Keeps request delivery inside the originating UI action so it cannot outlive the entry view.
    @discardableResult
    func submit<Request>(
        makeRequest: () -> Request?,
        deliver: (Request) -> Void
    ) -> Bool {
        guard !isSubmitting, let request = makeRequest() else {
            return false
        }

        isSubmitting = true
        deliver(request)
        return true
    }
}
