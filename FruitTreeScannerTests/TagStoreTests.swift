import XCTest
@testable import FruitTreeScanner

@MainActor
final class TagStoreTests: XCTestCase {
    func testRapidSavesKeepLatestSnapshotAndDoNotClearLatestSaveTask() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        let store = TagStore(
            defaults: defaults,
            commitDelayNanoseconds: { generation in
                switch generation {
                case 1, 4:
                    return 50_000_000
                case 2, 3:
                    return 150_000_000
                default:
                    return 0
                }
            }
        )
        store.addPlot(name: "A")
        store.addTag(name: "B")

        try await Task.sleep(nanoseconds: 80_000_000)
        XCTAssertTrue(store.hasPendingSave)
        await store.waitForPendingSave()

        let persisted: PersistedSnapshot = try persistedSnapshot(from: defaults)
        XCTAssertEqual(persisted.plots.map(\.name), ["A"])
        XCTAssertEqual(persisted.tags.map(\.name), ["B"])

        store.addPlot(name: "C")
        store.addTag(name: "D")
        await store.waitForPendingSave()
        try await Task.sleep(nanoseconds: 180_000_000)

        let afterLateStaleSave: PersistedSnapshot = try persistedSnapshot(from: defaults)
        XCTAssertEqual(afterLateStaleSave.plots.map(\.name), ["A", "C"])
        XCTAssertEqual(afterLateStaleSave.tags.map(\.name), ["B", "D"])
    }

    func testSingleSaveUsesExistingSnapshotKeyAndCodableFormat() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        let store = TagStore(defaults: defaults)
        store.addPlot(name: "North Block")
        await store.waitForPendingSave()

        XCTAssertNotNil(defaults.data(forKey: TagStore.snapshotUserDefaultsKey))
        let reloaded = TagStore(defaults: defaults)
        XCTAssertEqual(reloaded.plots.map(\.name), ["North Block"])
    }

    private struct PersistedSnapshot: Codable {
        let plots: [Plot]
        let tags: [GroupTag]
        let assignments: [TreeAssignment]
    }

    private func persistedSnapshot(from defaults: UserDefaults) throws -> PersistedSnapshot {
        let data = try XCTUnwrap(defaults.data(forKey: TagStore.snapshotUserDefaultsKey))
        return try JSONDecoder().decode(PersistedSnapshot.self, from: data)
    }

    private func makeDefaults() -> UserDefaults {
        UserDefaults(suiteName: "TagStoreTests.\(UUID().uuidString)")!
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: TagStore.snapshotUserDefaultsKey)
    }
}
