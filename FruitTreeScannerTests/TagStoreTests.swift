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
