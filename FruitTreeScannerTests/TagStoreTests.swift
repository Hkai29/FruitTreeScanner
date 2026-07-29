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

    func testPlotDeletionRequestDefersCascadeUntilConfirmationAndExplainsImpact() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        let store = TagStore(defaults: defaults)
        store.addPlot(name: "北区")
        store.addTag(name: "试验组")
        let plot = try XCTUnwrap(store.plots.first)
        let tag = try XCTUnwrap(store.tags.first)
        store.createOrUpdateAssignment(
            treeId: "T001",
            plotId: plot.id,
            tagIds: [tag.id],
            status: .scanned
        )
        store.createOrUpdateAssignment(
            treeId: "T002",
            plotId: plot.id,
            tagIds: [tag.id],
            status: .reviewing
        )

        let request = TagManagementDeletionRequest.plot(
            plot,
            affectedTreeCount: store.treeCount(forPlotId: plot.id)
        )

        XCTAssertEqual(request.title, "删除地块“北区”？")
        XCTAssertEqual(request.confirmationTitle, "删除地块")
        XCTAssertEqual(
            request.message,
            "该操作会取消 2 棵树的地块归属，但不会删除扫描记录。"
        )
        XCTAssertNotNil(store.getPlot(id: plot.id))
        XCTAssertTrue(store.assignments.allSatisfy { $0.plotId == plot.id })

        request.confirm(in: store)
        await store.waitForPendingSave()

        XCTAssertNil(store.getPlot(id: plot.id))
        XCTAssertTrue(store.assignments.allSatisfy { $0.plotId == nil })
        XCTAssertTrue(store.assignments.allSatisfy { $0.tagIds == [tag.id] })
        XCTAssertEqual(store.assignments.map(\.status), [.scanned, .reviewing])

        let reloaded = TagStore(defaults: defaults)
        XCTAssertNil(reloaded.getPlot(id: plot.id))
        XCTAssertTrue(reloaded.assignments.allSatisfy { $0.plotId == nil })
    }

    func testTagDeletionRequestRemovesOnlyConfirmedTagAndPreservesOtherMetadata() throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        let store = TagStore(defaults: defaults)
        store.addPlot(name: "南区")
        store.addTag(name: "灌溉组")
        store.addTag(name: "保留标签")
        let plot = try XCTUnwrap(store.plots.first)
        let targetTag = try XCTUnwrap(store.tags.first)
        let retainedTag = try XCTUnwrap(store.tags.last)
        store.createOrUpdateAssignment(
            treeId: "T003",
            plotId: plot.id,
            tagIds: [targetTag.id, retainedTag.id],
            status: .notScanned
        )

        let request = TagManagementDeletionRequest.tag(
            targetTag,
            affectedTreeCount: store.treeCount(forTagId: targetTag.id)
        )

        XCTAssertEqual(request.title, "删除标签“灌溉组”？")
        XCTAssertEqual(request.confirmationTitle, "删除标签")
        XCTAssertEqual(
            request.message,
            "该操作会从 1 棵树移除此标签，但不会删除扫描记录。"
        )
        XCTAssertNotNil(store.getTag(id: targetTag.id))
        XCTAssertEqual(store.getAssignment(treeId: "T003")?.tagIds, [targetTag.id, retainedTag.id])

        request.confirm(in: store)

        XCTAssertNil(store.getTag(id: targetTag.id))
        XCTAssertNotNil(store.getTag(id: retainedTag.id))
        XCTAssertEqual(store.getAssignment(treeId: "T003")?.plotId, plot.id)
        XCTAssertEqual(store.getAssignment(treeId: "T003")?.tagIds, [retainedTag.id])
        XCTAssertEqual(store.getAssignment(treeId: "T003")?.status, .notScanned)
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
