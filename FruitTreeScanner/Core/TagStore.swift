import Foundation

private struct TagStoreSnapshot: Codable, Sendable {
    let plots: [Plot]
    let tags: [GroupTag]
    let assignments: [TreeAssignment]
}

// MARK: - TagStore

@MainActor
final class TagStore: ObservableObject {
    static let shared = TagStore()

    @Published private(set) var plots: [Plot] = []
    @Published private(set) var tags: [GroupTag] = []
    @Published private(set) var assignments: [TreeAssignment] = []

    static let didUpdateNotification = Notification.Name("TagStoreDidUpdate")
    nonisolated static let snapshotUserDefaultsKey = "TagStore.snapshot.v1"

    private enum StorageKeys {
        static let snapshot = TagStore.snapshotUserDefaultsKey
        // Legacy keys are retained only to migrate installations that used the
        // earlier three-record layout.
        static let plots = "TagStore.plots"
        static let tags = "TagStore.tags"
        static let assignments = "TagStore.assignments"
    }

    private let defaults: UserDefaults
    private let commitDelayNanoseconds: @Sendable (Int) -> UInt64
    private var saveTask: Task<Void, Never>?
    private var saveGeneration = 0

    init(
        defaults: UserDefaults = .standard,
        commitDelayNanoseconds: @escaping @Sendable (Int) -> UInt64 = { _ in 0 }
    ) {
        self.defaults = defaults
        self.commitDelayNanoseconds = commitDelayNanoseconds
        loadData()
    }

    // MARK: - Persistence

    private func loadData() {
        if defaults.object(forKey: StorageKeys.snapshot) != nil {
            do {
                guard let snapshot: TagStoreSnapshot = try defaults.getObject(
                    forKey: StorageKeys.snapshot
                ) else {
                    Log.general.error("Tag store snapshot exists but is not encoded data")
                    return
                }
                plots = snapshot.plots
                tags = snapshot.tags
                assignments = snapshot.assignments
            } catch {
                Log.general.error("Failed to read tag store snapshot: \(error.localizedDescription)")
            }
            return
        }

        // One-time migration from the legacy independently-written keys.
        do {
            plots = try defaults.getObject(forKey: StorageKeys.plots) ?? []
        } catch {
            plots = []
        }
        do {
            tags = try defaults.getObject(forKey: StorageKeys.tags) ?? []
        } catch {
            tags = []
        }
        do {
            assignments = try defaults.getObject(forKey: StorageKeys.assignments) ?? []
        } catch {
            assignments = []
        }

        if !plots.isEmpty || !tags.isEmpty || !assignments.isEmpty {
            persistChanges()
        }
    }

    private func persistChanges() {
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = TagStoreSnapshot(plots: plots, tags: tags, assignments: assignments)
        let commitDelayNanoseconds = commitDelayNanoseconds(generation)
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try Task.checkCancellation()
                let encoded = try JSONEncoder().encode(snapshot)
                try Task.checkCancellation()
                if commitDelayNanoseconds > 0 {
                    await Task.detached {
                        try? await Task.sleep(nanoseconds: commitDelayNanoseconds)
                    }.value
                }
                await self?.commitSnapshot(encoded, generation: generation)
            } catch is CancellationError {
                await self?.finishPersisting(generation: generation)
            } catch {
                Log.general.error("Failed to save tag store snapshot: \(error.localizedDescription)")
                await self?.finishPersisting(generation: generation)
            }
        }
        notifyUpdate()
    }

    private func commitSnapshot(_ encoded: Data, generation: Int) {
        guard saveGeneration == generation else { return }
        defaults.set(encoded, forKey: StorageKeys.snapshot)
        saveTask = nil
    }

    private func finishPersisting(generation: Int) {
        if saveGeneration == generation {
            saveTask = nil
        }
    }

    func waitForPendingSave() async {
        if let saveTask {
            await saveTask.value
        }
    }

    var hasPendingSave: Bool {
        saveTask != nil
    }

    private func notifyUpdate() {
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }

    // MARK: - Plot Operations

    func addPlot(name: String, colorHex: String = TagPalette.defaultPlotColor) {
        let maxOrder = plots.map { $0.displayOrder }.max() ?? -1
        let displayOrder = maxOrder + 1
        let plot = Plot(name: name, colorHex: colorHex, displayOrder: displayOrder)
        plots.append(plot)
        persistChanges()
    }

    func updatePlot(_ plot: Plot) {
        guard let index = plots.firstIndex(where: { $0.id == plot.id }) else { return }
        plots[index] = plot
        persistChanges()
    }

    func deletePlot(id: UUID) {
        plots.removeAll { $0.id == id }
        // Clear plotId from assignments
        for i in assignments.indices {
            if assignments[i].plotId == id {
                assignments[i].plotId = nil
            }
        }
        persistChanges()
    }

    func movePlot(from source: IndexSet, to destination: Int) {
        plots.move(fromOffsets: source, toOffset: destination)
        for i in plots.indices {
            plots[i].displayOrder = i
        }
        persistChanges()
    }

    // MARK: - Tag Operations

    func addTag(name: String, colorHex: String = TagPalette.defaultTagColor) {
        let tag = GroupTag(name: name, colorHex: colorHex)
        tags.append(tag)
        persistChanges()
    }

    func updateTag(_ tag: GroupTag) {
        guard let index = tags.firstIndex(where: { $0.id == tag.id }) else { return }
        tags[index] = tag
        persistChanges()
    }

    func deleteTag(id: UUID) {
        tags.removeAll { $0.id == id }
        // Remove tagId from assignments
        for i in assignments.indices {
            assignments[i].tagIds.removeAll { $0 == id }
        }
        persistChanges()
    }

    // MARK: - Assignment Operations

    func getAssignment(treeId: String) -> TreeAssignment? {
        assignments.first { $0.treeId == treeId }
    }

    func createOrUpdateAssignment(treeId: String, plotId: UUID?, tagIds: [UUID], status: ScanStatus) {
        if let index = assignments.firstIndex(where: { $0.treeId == treeId }) {
            assignments[index].plotId = plotId
            assignments[index].tagIds = tagIds
            assignments[index].status = status
        } else {
            let assignment = TreeAssignment(treeId: treeId, plotId: plotId, tagIds: tagIds, status: status)
            assignments.append(assignment)
        }
        persistChanges()
    }

    func updateAssignmentStatus(treeId: String, status: ScanStatus) {
        guard let index = assignments.firstIndex(where: { $0.treeId == treeId }) else { return }
        assignments[index].status = status
        persistChanges()
    }

    // MARK: - Query Methods

    func treeCount(forPlotId plotId: UUID) -> Int {
        assignments.filter { $0.plotId == plotId }.count
    }

    func treeCount(forTagId tagId: UUID) -> Int {
        assignments.filter { $0.tagIds.contains(tagId) }.count
    }

    func statusCount(forStatus status: ScanStatus) -> Int {
        assignments.filter { $0.status == status }.count
    }

    func getPlot(id: UUID) -> Plot? {
        plots.first { $0.id == id }
    }

    func getTag(id: UUID) -> GroupTag? {
        tags.first { $0.id == id }
    }

    func filteredAssignments(plotId: UUID?, tagIds: [UUID], status: ScanStatus?) -> [TreeAssignment] {
        assignments.filter { assignment in
            if let plotId = plotId, assignment.plotId != plotId {
                return false
            }
            if !tagIds.isEmpty {
                let hasMatchingTag = tagIds.contains { assignment.tagIds.contains($0) }
                if !hasMatchingTag { return false }
            }
            if let status = status, assignment.status != status {
                return false
            }
            return true
        }
    }
}
