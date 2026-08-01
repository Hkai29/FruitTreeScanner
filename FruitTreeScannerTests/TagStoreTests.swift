import SwiftUI
import UIKit
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

    func testCorruptCurrentSnapshotDoesNotRestoreOrOverwriteLegacyRecords() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let legacyPlot = Plot(name: "Legacy Plot")
        let legacyTag = GroupTag(name: "Legacy Tag")
        let legacyAssignment = TreeAssignment(
            treeId: "TREE-LEGACY",
            plotId: legacyPlot.id,
            tagIds: [legacyTag.id],
            status: .completed
        )
        try seedLegacy(
            plots: [legacyPlot],
            tags: [legacyTag],
            assignments: [legacyAssignment],
            in: defaults
        )
        let corruptSnapshot = Data([0xFF, 0x00, 0x7F])
        defaults.set(corruptSnapshot, forKey: TagStore.snapshotUserDefaultsKey)

        let store = TagStore(defaults: defaults)
        await store.waitForPendingSave()

        XCTAssertTrue(store.plots.isEmpty)
        XCTAssertTrue(store.tags.isEmpty)
        XCTAssertTrue(store.assignments.isEmpty)
        XCTAssertEqual(defaults.data(forKey: TagStore.snapshotUserDefaultsKey), corruptSnapshot)
    }

    func testWrongTypeCurrentSnapshotDoesNotFallBackToLegacyRecords() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        try seedLegacy(plots: [Plot(name: "Legacy Plot")], in: defaults)
        defaults.set("unsupported", forKey: TagStore.snapshotUserDefaultsKey)

        let store = TagStore(defaults: defaults)
        await store.waitForPendingSave()

        XCTAssertTrue(store.plots.isEmpty)
        XCTAssertTrue(store.tags.isEmpty)
        XCTAssertTrue(store.assignments.isEmpty)
        XCTAssertEqual(defaults.string(forKey: TagStore.snapshotUserDefaultsKey), "unsupported")
    }

    func testExplicitWriteAfterCorruptSnapshotCreatesOnlyNewState() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        try seedLegacy(plots: [Plot(name: "Legacy Plot")], in: defaults)
        defaults.set(Data([0xFF, 0x00, 0x7F]), forKey: TagStore.snapshotUserDefaultsKey)

        let store = TagStore(defaults: defaults)
        store.addPlot(name: "New Plot")
        await store.waitForPendingSave()

        XCTAssertEqual(store.plots.map(\.name), ["New Plot"])
        let persisted: PersistedSnapshot = try persistedSnapshot(from: defaults)
        XCTAssertEqual(persisted.plots.map(\.name), ["New Plot"])
        XCTAssertTrue(persisted.tags.isEmpty)
        XCTAssertTrue(persisted.assignments.isEmpty)
    }

    func testMissingCurrentSnapshotMigratesLegacyRecords() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let legacyPlot = Plot(name: "Legacy Plot")
        let legacyTag = GroupTag(name: "Legacy Tag")
        let legacyAssignment = TreeAssignment(
            treeId: "TREE-LEGACY",
            plotId: legacyPlot.id,
            tagIds: [legacyTag.id],
            status: .reviewing
        )
        try seedLegacy(
            plots: [legacyPlot],
            tags: [legacyTag],
            assignments: [legacyAssignment],
            in: defaults
        )

        let store = TagStore(defaults: defaults)
        await store.waitForPendingSave()

        XCTAssertEqual(store.plots, [legacyPlot])
        XCTAssertEqual(store.tags, [legacyTag])
        XCTAssertEqual(store.assignments, [legacyAssignment])
        let persisted: PersistedSnapshot = try persistedSnapshot(from: defaults)
        XCTAssertEqual(persisted.plots, [legacyPlot])
        XCTAssertEqual(persisted.tags, [legacyTag])
        XCTAssertEqual(persisted.assignments, [legacyAssignment])
    }

    func testValidCurrentSnapshotTakesPrecedenceOverLegacyRecords() throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }
        let currentPlot = Plot(name: "Current Plot")
        let currentSnapshot = PersistedSnapshot(
            plots: [currentPlot],
            tags: [],
            assignments: []
        )
        defaults.set(
            try JSONEncoder().encode(currentSnapshot),
            forKey: TagStore.snapshotUserDefaultsKey
        )
        try seedLegacy(plots: [Plot(name: "Legacy Plot")], in: defaults)

        let store = TagStore(defaults: defaults)

        XCTAssertEqual(store.plots, [currentPlot])
        XCTAssertTrue(store.tags.isEmpty)
        XCTAssertTrue(store.assignments.isEmpty)
    }

    func testQuickTaggingCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "quick_tagging.title": "Quick Tags",
                "quick_tagging.plot_label": "Plot",
                "quick_tagging.plot_placeholder": "Select Plot",
                "quick_tagging.plot_none": "No Plot",
                "quick_tagging.plot_empty": "No Plots Available",
                "quick_tagging.tags_empty": "No tags yet. Add them later in Plot Tags.",
                "quick_tagging.save": "Save Tags",
                "quick_tagging.saved": "Tags Saved",
                "quick_tagging.save_hint": "Saves the selected plot, tags, and status for this tree.",
                "quick_tagging.tag_hint": "Toggles this tag for the tree.",
                "quick_tagging.status_hint": "Sets the scan status for this tree.",
                "quick_tagging.selected": "Selected",
                "quick_tagging.not_selected": "Not selected",
                "quick_tagging.status.not_scanned": "Not Scanned",
                "quick_tagging.status.scanned": "Scanned",
                "quick_tagging.status.reviewing": "Reviewing",
                "quick_tagging.status.completed": "Completed"
            ],
            "zh": [
                "quick_tagging.title": "快速标记",
                "quick_tagging.plot_label": "地块",
                "quick_tagging.plot_placeholder": "选择地块",
                "quick_tagging.plot_none": "无地块",
                "quick_tagging.plot_empty": "暂无地块",
                "quick_tagging.tags_empty": "暂无标签，可稍后在地块标签中添加。",
                "quick_tagging.save": "保存标记",
                "quick_tagging.saved": "已保存标记",
                "quick_tagging.save_hint": "保存这棵树所选的地块、标签和扫描状态。",
                "quick_tagging.tag_hint": "切换这棵树的标签选择。",
                "quick_tagging.status_hint": "设置这棵树的扫描状态。",
                "quick_tagging.selected": "已选择",
                "quick_tagging.not_selected": "未选择",
                "quick_tagging.status.not_scanned": "未扫描",
                "quick_tagging.status.scanned": "已扫描",
                "quick_tagging.status.reviewing": "复查中",
                "quick_tagging.status.completed": "已完成"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testQuickTaggingStatusLocalizationCoversStablePersistedStatuses() {
        XCTAssertEqual(
            ScanStatus.allCases.map(L10n.QuickTagging.statusLocalizationKey),
            [
                "quick_tagging.status.not_scanned",
                "quick_tagging.status.scanned",
                "quick_tagging.status.reviewing",
                "quick_tagging.status.completed"
            ]
        )
        XCTAssertEqual(
            ScanStatus.allCases.map(\.rawValue),
            ["未扫描", "已扫描", "复查中", "已完成"],
            "Localization must not change the Codable raw values stored in existing snapshots"
        )
    }

    func testQuickTaggingAssignmentRoundTripsWithoutChangingSelectionOrStatus() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        let store = TagStore(defaults: defaults)
        store.addPlot(name: "North Block")
        store.addTag(name: "Priority")

        let plotID = try XCTUnwrap(store.plots.first?.id)
        let tagID = try XCTUnwrap(store.tags.first?.id)
        store.createOrUpdateAssignment(
            treeId: "TREE-QUICK-TAG",
            plotId: plotID,
            tagIds: [tagID],
            status: .reviewing
        )
        await store.waitForPendingSave()

        let reloaded = TagStore(defaults: defaults)
        XCTAssertEqual(
            reloaded.getAssignment(treeId: "TREE-QUICK-TAG"),
            TreeAssignment(
                treeId: "TREE-QUICK-TAG",
                plotId: plotID,
                tagIds: [tagID],
                status: .reviewing
            )
        )
    }

    func testAssignmentWriteNormalizesTreeAndRejectsStaleOrDuplicateReferences() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        let store = TagStore(defaults: defaults)
        store.addPlot(name: "North Block")
        store.addTag(name: "Priority")
        let plotID = try XCTUnwrap(store.plots.first?.id)
        let tagID = try XCTUnwrap(store.tags.first?.id)

        store.createOrUpdateAssignment(
            treeId: "  TREE-001  ",
            plotId: UUID(),
            tagIds: [tagID, tagID, UUID()],
            status: .reviewing
        )

        XCTAssertEqual(
            store.getAssignment(treeId: "TREE-001"),
            TreeAssignment(
                treeId: "TREE-001",
                plotId: nil,
                tagIds: [tagID],
                status: .reviewing
            )
        )
        XCTAssertEqual(store.getAssignment(treeId: " TREE-001 ")?.treeId, "TREE-001")

        store.createOrUpdateAssignment(
            treeId: "TREE-001",
            plotId: plotID,
            tagIds: [tagID],
            status: .completed
        )
        store.createOrUpdateAssignment(
            treeId: "   ",
            plotId: plotID,
            tagIds: [tagID],
            status: .scanned
        )
        await store.waitForPendingSave()

        XCTAssertEqual(store.assignments.count, 1)
        XCTAssertEqual(store.assignments.first?.plotId, plotID)
        XCTAssertEqual(store.assignments.first?.tagIds, [tagID])
        XCTAssertEqual(store.assignments.first?.status, .completed)

        let reloaded = TagStore(defaults: defaults)
        XCTAssertEqual(reloaded.assignments, store.assignments)
    }

    func testLoadingSnapshotRepairsDanglingAndDuplicateAssignments() async throws {
        let defaults = makeDefaults()
        defer { clear(defaults) }

        let plot = Plot(name: "South Block")
        let tag = GroupTag(name: "Trial")
        let stalePlotID = UUID()
        let staleTagID = UUID()
        let snapshot = PersistedSnapshot(
            plots: [plot],
            tags: [tag],
            assignments: [
                TreeAssignment(
                    treeId: " TREE-001 ",
                    plotId: plot.id,
                    tagIds: [tag.id, staleTagID, tag.id],
                    status: .reviewing
                ),
                TreeAssignment(
                    treeId: "TREE-002",
                    plotId: stalePlotID,
                    tagIds: [staleTagID],
                    status: .scanned
                ),
                TreeAssignment(
                    treeId: "TREE-001",
                    plotId: nil,
                    tagIds: [tag.id],
                    status: .completed
                ),
                TreeAssignment(
                    treeId: "   ",
                    plotId: plot.id,
                    tagIds: [tag.id],
                    status: .scanned
                )
            ]
        )
        defaults.set(
            try JSONEncoder().encode(snapshot),
            forKey: TagStore.snapshotUserDefaultsKey
        )

        let store = TagStore(defaults: defaults)
        await store.waitForPendingSave()

        XCTAssertEqual(
            store.assignments,
            [
                TreeAssignment(
                    treeId: "TREE-001",
                    plotId: nil,
                    tagIds: [tag.id],
                    status: .completed
                ),
                TreeAssignment(
                    treeId: "TREE-002",
                    plotId: nil,
                    tagIds: [],
                    status: .scanned
                )
            ]
        )

        let persisted: PersistedSnapshot = try persistedSnapshot(from: defaults)
        XCTAssertEqual(persisted.assignments, store.assignments)
    }

    func testQuickTaggingCardRendersAtAccessibilityTextSize() {
        let card = QuickTaggingCard(
            treeID: "TREE-QUICK-TAG",
            selectedPlotId: .constant(nil),
            selectedTagIds: .constant([]),
            selectedStatus: .constant(.scanned)
        )
        .environment(\.dynamicTypeSize, .accessibility5)

        let rootView = VStack {
            card
            Spacer(minLength: 0)
        }
        .frame(width: 390, height: 844, alignment: .top)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.backgroundColor = .black
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
            .image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "QuickTagging-\(Locale.preferredLanguages.first ?? "unknown")-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()
    }

    func testStartStepContentLayoutPolicyStacksAccessibilitySizesAndKeepsMinimumTarget() {
        let standard = StartStepContentLayoutPolicy(isAccessibilitySize: false)
        XCTAssertEqual(standard.arrangement, .horizontal)
        XCTAssertEqual(standard.minimumControlHeight, Design.Touch.minimumHeight)

        let accessibility = StartStepContentLayoutPolicy(isAccessibilitySize: true)
        XCTAssertEqual(accessibility.arrangement, .vertical)
        XCTAssertEqual(accessibility.minimumControlHeight, Design.Touch.minimumHeight)
    }

    func testTagManagementCopyIsCompleteInEnglishAndChinese() throws {
        let bundles = [
            "en": try localizedBundle(for: "en"),
            "zh": try localizedBundle(for: "zh")
        ]

        for (language, bundle) in bundles {
            let missingKeys = L10n.TagManagement.Key.allCases.filter { key in
                bundle.localizedString(forKey: key.rawValue, value: nil, table: nil) == key.rawValue
            }
            XCTAssertTrue(
                missingKeys.isEmpty,
                "\(language) localization is missing: \(missingKeys.map(\.rawValue).joined(separator: ", "))"
            )
        }

        let english = try XCTUnwrap(bundles["en"])
        let chinese = try XCTUnwrap(bundles["zh"])
        XCTAssertEqual(L10n.TagManagement.text(.navigationTitle, in: english), "Plot & Tag Management")
        XCTAssertEqual(L10n.TagManagement.text(.headerTitle, in: chinese), "地块标签")
        XCTAssertEqual(L10n.TagManagement.treeCount(1, in: english), "1 tree")
        XCTAssertEqual(L10n.TagManagement.treeCount(3, in: english), "3 trees")
        XCTAssertEqual(L10n.TagManagement.treeCount(3, in: chinese), "3 棵树")
        XCTAssertEqual(
            L10n.TagManagement.plotDeletionMessage(treeCount: 1, in: english),
            "This removes the plot assignment from 1 tree without deleting any scan records."
        )
        XCTAssertEqual(
            L10n.TagManagement.plotDeletionMessage(treeCount: 2, in: english),
            "This removes the plot assignment from 2 trees without deleting any scan records."
        )
        XCTAssertEqual(
            L10n.TagManagement.tagDeletionMessage(treeCount: 1, in: english),
            "This removes the tag from 1 tree without deleting any scan records."
        )
        XCTAssertEqual(
            L10n.TagManagement.tagDeletionMessage(treeCount: 2, in: english),
            "This removes the tag from 2 trees without deleting any scan records."
        )
    }

    func testTagManagementDynamicCopyCoversPaletteAndStablePersistedStatuses() throws {
        let english = try localizedBundle(for: "en")
        let chinese = try localizedBundle(for: "zh")

        XCTAssertEqual(L10n.TagManagement.colorName(for: "#6F8F63", in: english), "Green")
        XCTAssertEqual(
            L10n.TagManagement.colorAccessibilityLabel(for: "#34362F", in: chinese),
            "颜色：炭灰色"
        )
        XCTAssertEqual(
            ScanStatus.allCases.map { L10n.TagManagement.statusName(for: $0, in: english) },
            ["Not Scanned", "Scanned", "Reviewing", "Completed"]
        )
        XCTAssertEqual(
            ScanStatus.allCases.map(\.rawValue),
            ["未扫描", "已扫描", "复查中", "已完成"],
            "Localized display names must not change the Codable raw values in persisted snapshots"
        )
    }

    func testTagManagementEditFormRendersAtAccessibilityTextSize() {
        let form = TagEntityEditForm(
            name: .constant("North Plot"),
            selectedColor: .constant("#4D7588"),
            namePlaceholder: L10n.TagManagement.plotPlaceholder
        )
        .environment(\.dynamicTypeSize, .accessibility5)

        let rootView = form
            .frame(width: 390, height: 844, alignment: .top)
            .background(Design.Colors.Dark.bgDeep)
            .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.backgroundColor = .black
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
            .image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "TagManagementEditForm-\(Locale.preferredLanguages.first ?? "unknown")-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()
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

    private func seedLegacy(
        plots: [Plot] = [],
        tags: [GroupTag] = [],
        assignments: [TreeAssignment] = [],
        in defaults: UserDefaults
    ) throws {
        try defaults.setObject(plots, forKey: "TagStore.plots")
        try defaults.setObject(tags, forKey: "TagStore.tags")
        try defaults.setObject(assignments, forKey: "TagStore.assignments")
    }

    private func localizedBundle(for language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
            "Missing \(language) localization bundle"
        )
    }

    private func clear(_ defaults: UserDefaults) {
        defaults.removeObject(forKey: TagStore.snapshotUserDefaultsKey)
        defaults.removeObject(forKey: "TagStore.plots")
        defaults.removeObject(forKey: "TagStore.tags")
        defaults.removeObject(forKey: "TagStore.assignments")
    }
}
