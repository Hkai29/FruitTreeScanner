import Foundation

// MARK: - Data Models

struct Plot: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var displayOrder: Int
    var createdAt: Date

    init(name: String, colorHex: String = "#007AFF", displayOrder: Int = 0) {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.displayOrder = displayOrder
        self.createdAt = Date()
    }
}

struct GroupTag: Identifiable, Codable, Equatable, Sendable {
    let id: UUID
    var name: String
    var colorHex: String
    var createdAt: Date

    init(name: String, colorHex: String = "#34C759") {
        self.id = UUID()
        self.name = name
        self.colorHex = colorHex
        self.createdAt = Date()
    }
}

enum ScanStatus: String, Codable, CaseIterable, Sendable {
    case notScanned = "未扫描"
    case scanned = "已扫描"
    case reviewing = "复查中"
    case completed = "已完成"
}

struct TreeAssignment: Identifiable, Codable, Equatable, Sendable {
    var id: String { treeId }
    let treeId: String
    var plotId: UUID?
    var tagIds: [UUID]
    var status: ScanStatus

    init(treeId: String, plotId: UUID? = nil, tagIds: [UUID] = [], status: ScanStatus = .notScanned) {
        self.treeId = treeId
        self.plotId = plotId
        self.tagIds = tagIds
        self.status = status
    }
}

private struct TagStoreSnapshot: Sendable {
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

    private enum StorageKeys {
        static let plots = "TagStore.plots"
        static let tags = "TagStore.tags"
        static let assignments = "TagStore.assignments"
    }

    private var saveTask: Task<Void, Never>?
    private var saveGeneration = 0

    private init() {
        loadData()
    }

    // MARK: - Persistence

    private func loadData() {
        do {
            plots = try UserDefaults.standard.getObject(forKey: StorageKeys.plots) ?? []
        } catch {
            #if DEBUG
            print("[TagStore] Failed to load plots: \(error)")
            #endif
            plots = []
        }
        do {
            tags = try UserDefaults.standard.getObject(forKey: StorageKeys.tags) ?? []
        } catch {
            #if DEBUG
            print("[TagStore] Failed to load tags: \(error)")
            #endif
            tags = []
        }
        do {
            assignments = try UserDefaults.standard.getObject(forKey: StorageKeys.assignments) ?? []
        } catch {
            #if DEBUG
            print("[TagStore] Failed to load assignments: \(error)")
            #endif
            assignments = []
        }
    }

    private func persistChanges() {
        saveGeneration += 1
        let generation = saveGeneration
        let snapshot = TagStoreSnapshot(plots: plots, tags: tags, assignments: assignments)
        saveTask?.cancel()
        saveTask = Task.detached(priority: .utility) { [weak self] in
            do {
                try Task.checkCancellation()
                try Self.writeSnapshot(snapshot)
                try Task.checkCancellation()
                await self?.finishPersisting(generation: generation)
            } catch is CancellationError {
            } catch {
                #if DEBUG
                print("[TagStore] Failed to save data: \(error)")
                #endif
            }
        }
        notifyUpdate()
    }

    private func finishPersisting(generation: Int) {
        if saveGeneration == generation {
            saveTask = nil
        }
    }

    nonisolated private static func writeSnapshot(_ snapshot: TagStoreSnapshot) throws {
        try UserDefaults.standard.setObject(snapshot.plots, forKey: StorageKeys.plots)
        try Task.checkCancellation()
        try UserDefaults.standard.setObject(snapshot.tags, forKey: StorageKeys.tags)
        try Task.checkCancellation()
        try UserDefaults.standard.setObject(snapshot.assignments, forKey: StorageKeys.assignments)
    }

    private func notifyUpdate() {
        NotificationCenter.default.post(name: Self.didUpdateNotification, object: nil)
    }

    // MARK: - Plot Operations

    func addPlot(name: String, colorHex: String = "#007AFF") {
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

    func addTag(name: String, colorHex: String = "#34C759") {
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

// MARK: - UserDefaults Extension

extension UserDefaults {
    func setObject<T: Codable>(_ object: T, forKey key: String) throws {
        let data = try JSONEncoder().encode(object)
        set(data, forKey: key)
    }

    func getObject<T: Codable>(forKey key: String) throws -> T? {
        guard let data = data(forKey: key) else { return nil }
        return try JSONDecoder().decode(T.self, from: data)
    }
}
