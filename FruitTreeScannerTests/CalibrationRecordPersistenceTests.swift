import XCTest
import SwiftUI
import UIKit
@testable import FruitTreeScanner

final class CalibrationRecordPersistenceTests: XCTestCase {
    func testMissingCalibrationRecordFileLoadsAsEmpty() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("missing")
            .appendingPathExtension("json")

        XCTAssertEqual(try CalibrationRecordPersistence.load(from: url).count, 0)
    }

    func testCalibrationRecordRoundTripKeepsValues() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("records")
            .appendingPathExtension("json")
        let record = CalibrationRecord(
            id: UUID(uuidString: "A3A3A3A3-A3A3-4A3A-8A3A-A3A3A3A3A3A3")!,
            treeID: "T-01",
            scanDate: Date(timeIntervalSince1970: 1_780_000_000),
            estimatedFruitCount: 42,
            manualFruitCount: 40,
            estimatedYieldKg: 8.5,
            actualYieldKg: 8.0,
            fruitType: "apple"
        )

        try CalibrationRecordPersistence.save([record], to: url)

        let loaded = try CalibrationRecordPersistence.load(from: url)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, record.id)
        XCTAssertEqual(loaded[0].treeID, "T-01")
        XCTAssertEqual(loaded[0].estimatedFruitCount, 42)
        XCTAssertEqual(loaded[0].manualFruitCount, 40)
        XCTAssertEqual(loaded[0].estimatedYieldKg, 8.5, accuracy: 0.000_1)
        let actualYieldKg = try XCTUnwrap(loaded[0].actualYieldKg)
        XCTAssertEqual(actualYieldKg, 8.0, accuracy: 0.000_1)
        XCTAssertEqual(loaded[0].fruitType, "apple")
    }

    func testCorruptCalibrationRecordFileThrowsWithoutChangingBytes() throws {
        let url = temporaryDirectory().appendingPathComponent("corrupt.json")
        let corruptData = Data("{not valid json".utf8)
        try corruptData.write(to: url)

        XCTAssertThrowsError(try CalibrationRecordPersistence.load(from: url))
        XCTAssertEqual(try Data(contentsOf: url), corruptData)
    }

    func testStaleCalibrationGenerationCannotOverwriteNewerRecords() async throws {
        let url = temporaryDirectory().appendingPathComponent("records.json")
        let old = makeRecord(fruitType: "apple", estimatedCount: 1, manualCount: 1, estimatedYield: 1, actualYield: 1)
        let newer = makeRecord(fruitType: "pear", estimatedCount: 2, manualCount: 2, estimatedYield: 2, actualYield: 2)
        let controller = CalibrationRecordPersistenceController(url: url)

        let newerSaved = await controller.save([newer], generation: 2)
        let staleSaved = await controller.save([old], generation: 1)
        XCTAssertTrue(newerSaved)
        XCTAssertFalse(staleSaved)
        XCTAssertEqual(try CalibrationRecordPersistence.load(from: url).map(\.id), [newer.id])
    }

    @MainActor
    func testSaveRevisionRemainsMonotonicWhenCalibrationViewIsRecreated() async throws {
        let url = temporaryDirectory().appendingPathComponent("records.json")
        let firstViewRecord = makeRecord(
            fruitType: "apple",
            estimatedCount: 1,
            manualCount: 1,
            estimatedYield: 1,
            actualYield: 1
        )
        let reopenedViewRecord = makeRecord(
            fruitType: "pear",
            estimatedCount: 2,
            manualCount: 2,
            estimatedYield: 2,
            actualYield: 2
        )
        let revisions = CalibrationSaveRevisionSource()
        let controller = CalibrationRecordPersistenceController(url: url)

        let firstViewRevisions = (0..<3).map { _ in revisions.nextRevision() }
        let firstViewSaved = await controller.save(
            [firstViewRecord],
            generation: try XCTUnwrap(firstViewRevisions.last)
        )

        let reopenedViewFirstRevision = revisions.nextRevision()
        let reopenedViewSaved = await controller.save(
            [reopenedViewRecord],
            generation: reopenedViewFirstRevision
        )

        XCTAssertTrue(firstViewSaved)
        XCTAssertGreaterThan(reopenedViewFirstRevision, try XCTUnwrap(firstViewRevisions.last))
        XCTAssertTrue(reopenedViewSaved)
        XCTAssertEqual(
            try CalibrationRecordPersistence.load(from: url).map(\.id),
            [reopenedViewRecord.id]
        )
    }

    func testRapidCalibrationAddAddDeletePersistsLatestSnapshot() async throws {
        let url = temporaryDirectory().appendingPathComponent("records.json")
        let a = makeRecord(fruitType: "apple", estimatedCount: 1, manualCount: 1, estimatedYield: 1, actualYield: 1)
        let b = makeRecord(fruitType: "pear", estimatedCount: 2, manualCount: 2, estimatedYield: 2, actualYield: 2)
        let controller = CalibrationRecordPersistenceController(url: url)

        _ = await controller.save([a], generation: 1)
        _ = await controller.save([a, b], generation: 2)
        _ = await controller.save([b], generation: 3)

        XCTAssertEqual(try CalibrationRecordPersistence.load(from: url).map(\.id), [b.id])
    }

    func testCalibrationWriteFailurePreservesExistingCompleteFileAndReportsError() async throws {
        let url = temporaryDirectory().appendingPathComponent("records.json")
        let existing = makeRecord(fruitType: "apple", estimatedCount: 1, manualCount: 1, estimatedYield: 1, actualYield: 1)
        let replacement = makeRecord(fruitType: "pear", estimatedCount: 2, manualCount: 2, estimatedYield: 2, actualYield: 2)
        try CalibrationRecordPersistence.save([existing], to: url)
        let controller = CalibrationRecordPersistenceController(url: url) { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }

        let saved = await controller.save([replacement], generation: 1)
        let error = await controller.lastErrorDescription
        XCTAssertFalse(saved)
        XCTAssertNotNil(error)
        XCTAssertEqual(try CalibrationRecordPersistence.load(from: url).map(\.id), [existing.id])
    }

    func testCalibrationSaveResultDistinguishesSupersededAndWriteFailure() async {
        let record = makeRecord(
            fruitType: "apple",
            estimatedCount: 1,
            manualCount: 1,
            estimatedYield: 1,
            actualYield: 1
        )
        let controller = CalibrationRecordPersistenceController(
            url: temporaryDirectory().appendingPathComponent("records.json")
        ) { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }

        let failure = await controller.saveResult([record], generation: 2)
        let superseded = await controller.saveResult([record], generation: 1)

        guard case .failed = failure else {
            return XCTFail("Expected a write failure, got \(failure)")
        }
        XCTAssertEqual(superseded, .superseded)
    }

    @MainActor
    func testCalibrationControllerLoadFailurePreservesRecordsAndBlocksMutation() async {
        let existing = makeRecord(
            fruitType: "apple",
            estimatedCount: 1,
            manualCount: 1,
            estimatedYield: 1,
            actualYield: 1
        )
        let added = makeRecord(
            fruitType: "pear",
            estimatedCount: 2,
            manualCount: 2,
            estimatedYield: 2,
            actualYield: 2
        )
        let controller = CalibrationRecordsController(
            records: [existing],
            state: .ready,
            loader: { .failure("unreadable") },
            saver: { _, _ in .saved },
            revisionProvider: { 1 }
        )

        controller.load()
        await controller.waitForLoading()
        controller.add(added)

        XCTAssertEqual(controller.state, .loadFailed)
        XCTAssertFalse(controller.state.canModify)
        XCTAssertEqual(controller.records.map(\.id), [existing.id])
    }

    @MainActor
    func testCalibrationControllerAddFailureRestoresPreviousSnapshot() async {
        let existing = makeRecord(
            fruitType: "apple",
            estimatedCount: 1,
            manualCount: 1,
            estimatedYield: 1,
            actualYield: 1
        )
        let added = makeRecord(
            fruitType: "pear",
            estimatedCount: 2,
            manualCount: 2,
            estimatedYield: 2,
            actualYield: 2
        )
        let controller = CalibrationRecordsController(
            records: [existing],
            state: .ready,
            loader: { .success([]) },
            saver: { _, _ in .failed("disk full") },
            revisionProvider: { 1 }
        )

        controller.add(added)
        XCTAssertEqual(controller.state, .saving(.add))
        await controller.waitForSaving()

        XCTAssertEqual(controller.state, .saveFailed(.add))
        XCTAssertEqual(controller.records.map(\.id), [existing.id])
    }

    @MainActor
    func testCalibrationControllerSuccessfulAddKeepsPersistedSnapshot() async {
        let added = makeRecord(
            fruitType: "apple",
            estimatedCount: 12,
            manualCount: 10,
            estimatedYield: 6,
            actualYield: 5
        )
        let controller = CalibrationRecordsController(
            records: [],
            state: .ready,
            loader: { .success([]) },
            saver: { records, revision in
                records.map(\.id) == [added.id] && revision == 7 ? .saved : .failed("wrong snapshot")
            },
            revisionProvider: { 7 }
        )

        controller.add(added)
        await controller.waitForSaving()

        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(controller.records.map(\.id), [added.id])
    }

    @MainActor
    func testCalibrationControllerDeleteFailureRestoresOriginalOrder() async {
        let first = makeRecord(
            fruitType: "apple",
            estimatedCount: 1,
            manualCount: 1,
            estimatedYield: 1,
            actualYield: 1
        )
        let second = makeRecord(
            fruitType: "pear",
            estimatedCount: 2,
            manualCount: 2,
            estimatedYield: 2,
            actualYield: 2
        )
        let controller = CalibrationRecordsController(
            records: [first, second],
            state: .ready,
            loader: { .success([]) },
            saver: { _, _ in .failed("read only") },
            revisionProvider: { 1 }
        )

        controller.delete(first)
        XCTAssertEqual(controller.records.map(\.id), [second.id])
        await controller.waitForSaving()

        XCTAssertEqual(controller.state, .saveFailed(.delete))
        XCTAssertEqual(controller.records.map(\.id), [first.id, second.id])
    }

    @MainActor
    func testCalibrationControllerSupersededSaveReloadsAuthoritativeDiskState() async {
        let stale = makeRecord(
            fruitType: "apple",
            estimatedCount: 1,
            manualCount: 1,
            estimatedYield: 1,
            actualYield: 1
        )
        let added = makeRecord(
            fruitType: "pear",
            estimatedCount: 2,
            manualCount: 2,
            estimatedYield: 2,
            actualYield: 2
        )
        let authoritative = makeRecord(
            fruitType: "orange",
            estimatedCount: 3,
            manualCount: 3,
            estimatedYield: 3,
            actualYield: 3
        )
        let controller = CalibrationRecordsController(
            records: [stale],
            state: .ready,
            loader: { .success([authoritative]) },
            saver: { _, _ in .superseded },
            revisionProvider: { 1 }
        )

        controller.add(added)
        await controller.waitForSaving()
        await controller.waitForLoading()

        XCTAssertEqual(controller.state, .ready)
        XCTAssertEqual(controller.records.map(\.id), [authoritative.id])
    }

    func testCalibrationPersistenceStatesProvideActionableAnnouncements() {
        XCTAssertNil(CalibrationRecordsState.ready.accessibilityAnnouncement)
        XCTAssertEqual(
            CalibrationRecordsState.loading.accessibilityAnnouncement,
            L10n.Calibration.loadingRecords
        )
        XCTAssertTrue(
            CalibrationRecordsState.loadFailed.accessibilityAnnouncement?.contains(
                L10n.Calibration.loadFailedMessage
            ) == true
        )
        XCTAssertTrue(
            CalibrationRecordsState.saveFailed(.delete).accessibilityAnnouncement?.contains(
                L10n.Calibration.deleteSaveFailedMessage
            ) == true
        )
    }

    func testCalibrationLocalizationKeysExistInEnglishAndChinese() throws {
        let requiredKeys = [
            "calibration.navigation_title",
            "calibration.header_title",
            "calibration.header_subtitle",
            "calibration.action.close",
            "calibration.action.add_record",
            "calibration.action.retry",
            "calibration.action.dismiss",
            "calibration.accessibility.add_record",
            "calibration.accessibility.delete_record_format",
            "calibration.delete.title",
            "calibration.delete.message",
            "calibration.parameters.title",
            "calibration.parameters.minimum_cluster_points",
            "calibration.parameters.maximum_cluster_diameter",
            "calibration.parameters.minimum_sphericity",
            "calibration.parameters.hsv_range",
            "calibration.statistics.title",
            "calibration.statistics.empty",
            "calibration.statistics.count_mape",
            "calibration.statistics.yield_mape",
            "calibration.statistics.record_count",
            "calibration.records.title",
            "calibration.records.empty_title",
            "calibration.records.empty_message",
            "calibration.records.loading",
            "calibration.records.saving_add",
            "calibration.records.saving_delete",
            "calibration.records.load_failed_title",
            "calibration.records.load_failed_message",
            "calibration.records.retry_hint",
            "calibration.records.save_failed_title",
            "calibration.records.add_save_failed_message",
            "calibration.records.delete_save_failed_message",
            "calibration.record.title_format",
            "calibration.record.estimated",
            "calibration.record.actual",
            "calibration.record.count_error",
            "calibration.record.yield_error",
            "calibration.record.count_yield_format",
            "calibration.record.count_only_format",
            "calibration.record.yield_only_format",
            "calibration.add.navigation_title",
            "calibration.add.recent_section",
            "calibration.add.recent_picker",
            "calibration.add.recent_hint",
            "calibration.add.recent_summary_format",
            "calibration.add.basic_section",
            "calibration.add.tree_id_placeholder",
            "calibration.add.fruit_type",
            "calibration.add.estimate_section",
            "calibration.add.estimated_count_placeholder",
            "calibration.add.estimated_yield_placeholder",
            "calibration.add.actual_section",
            "calibration.add.actual_hint",
            "calibration.add.manual_count_placeholder",
            "calibration.add.actual_yield_placeholder",
            "calibration.add.input_hint",
            "calibration.unit.fruit",
            "calibration.unit.kilogram"
        ]

        for language in ["en", "zh"] {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            for key in requiredKeys {
                let value = localizedBundle.localizedString(forKey: key, value: nil, table: nil)
                XCTAssertFalse(value.isEmpty, "\(language) localization is empty for \(key)")
                XCTAssertNotEqual(value, key, "\(language) localization is missing for \(key)")
            }
        }

        let englishBundle = try XCTUnwrap(
            Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let chineseBundle = try XCTUnwrap(
            Bundle.main.path(forResource: "zh", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        XCTAssertEqual(
            englishBundle.localizedString(forKey: "calibration.records.load_failed_message", value: nil, table: nil),
            "The local calibration file couldn’t be read. The existing file wasn’t modified. Try again."
        )
        XCTAssertEqual(
            chineseBundle.localizedString(forKey: "calibration.records.delete_save_failed_message", value: nil, table: nil),
            "无法保存删除操作，原记录已恢复。请检查存储空间后重试。"
        )
    }

    @MainActor
    func testCalibrationRecordsRenderAtAccessibilityTextSize() {
        let record = makeRecord(
            fruitType: "apple",
            estimatedCount: 128,
            manualCount: 120,
            estimatedYield: 24.5,
            actualYield: 23.0
        )
        let rootView = ScrollView {
            VStack(spacing: Design.Space.lg) {
                CalibrationStatisticsCard(records: [record])
                CalibrationRecordsSection(
                    records: [record],
                    state: .saveFailed(.delete),
                    onAdd: {},
                    onRetry: {},
                    onDismissSaveFailure: {},
                    onDelete: { _ in }
                )
            }
            .padding(Design.Space.lg)
        }
        .environment(\.dynamicTypeSize, .accessibility5)
        .frame(width: 390, height: 844, alignment: .top)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            didDraw = hostingController.view.drawHierarchy(
                in: hostingController.view.bounds,
                afterScreenUpdates: true
            )
        }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "Calibration-DeleteFailure-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()

        let form = AddCalibrationRecordForm(
            recentRecords: [],
            treeID: .constant("TREE-LONG-IDENTIFIER-17"),
            estimatedFruitCount: .constant("128"),
            estimatedYieldKg: .constant("24.5"),
            manualFruitCount: .constant("120"),
            actualYieldKg: .constant("23.0"),
            selectedFruitCategory: .constant(.apple),
            onSelectRecentScan: { _ in }
        )
        .environment(\.dynamicTypeSize, .accessibility5)
        .frame(width: 390, height: 844, alignment: .top)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.colorScheme, .dark)

        let formController = UIHostingController(rootView: form)
        formController.overrideUserInterfaceStyle = .dark
        let formWindow = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        formWindow.rootViewController = formController
        formWindow.makeKeyAndVisible()
        formController.view.frame = formWindow.bounds
        formController.view.setNeedsLayout()
        formController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDrawForm = false
        let formImage = UIGraphicsImageRenderer(bounds: formWindow.bounds).image { _ in
            didDrawForm = formController.view.drawHierarchy(
                in: formController.view.bounds,
                afterScreenUpdates: true
            )
        }

        XCTAssertTrue(didDrawForm)
        let formAttachment = XCTAttachment(image: formImage)
        formAttachment.name = "Calibration-AddForm-AX5"
        formAttachment.lifetime = .keepAlways
        add(formAttachment)
        formWindow.resignKey()
    }

    func testYieldCalibrationCorrectionUsesMatchingFruitTypeMedianRatios() {
        let records = [
            makeRecord(fruitType: "苹果", estimatedCount: 10, manualCount: 8, estimatedYield: 5, actualYield: 4),
            makeRecord(fruitType: "apple", estimatedCount: 20, manualCount: 18, estimatedYield: 9, actualYield: 8.1),
            makeRecord(fruitType: "橙子", estimatedCount: 10, manualCount: 30, estimatedYield: 1, actualYield: 3),
        ]

        let correction = YieldCalibrationCorrector.correction(
            from: records,
            fruitCategory: .apple,
            fruitType: "apple"
        )

        XCTAssertEqual(correction.countSampleCount, 2)
        XCTAssertEqual(correction.yieldSampleCount, 2)
        XCTAssertEqual(correction.countFactor, 0.85, accuracy: 0.001)
        XCTAssertEqual(correction.yieldFactor, 0.85, accuracy: 0.001)
    }

    func testYieldCalibrationCorrectionClampsExtremeRatios() {
        let records = [
            makeRecord(fruitType: "苹果", estimatedCount: 1, manualCount: 4, estimatedYield: 1, actualYield: 4),
        ]

        let correction = YieldCalibrationCorrector.correction(
            from: records,
            fruitCategory: .apple,
            fruitType: "苹果"
        )

        XCTAssertEqual(correction.countFactor, 1.5, accuracy: 0.001)
        XCTAssertEqual(correction.yieldFactor, 2.0, accuracy: 0.001)
    }

    func testYieldCalibrationCorrectionReturnsNeutralWithoutMatchingEvidence() {
        let records = [
            makeRecord(fruitType: "橙子", estimatedCount: 10, manualCount: 8, estimatedYield: 4, actualYield: 3.5),
            makeRecord(fruitType: "苹果", estimatedCount: 0, manualCount: 8, estimatedYield: 0, actualYield: 3.5),
        ]

        let correction = YieldCalibrationCorrector.correction(
            from: records,
            fruitCategory: .apple,
            fruitType: "apple"
        )

        XCTAssertEqual(correction, .neutral)
    }

    func testCalibrationValidationMetricsUsesAbsoluteErrorsWithoutCancellation() throws {
        let records = [
            makeRecord(fruitType: "apple", estimatedCount: 12, manualCount: 10, estimatedYield: 6, actualYield: 5),
            makeRecord(fruitType: "apple", estimatedCount: 8, manualCount: 10, estimatedYield: 4, actualYield: 5),
        ]

        let metrics = CalibrationValidationMetrics.make(from: records)

        XCTAssertEqual(metrics.recordCount, 2)
        XCTAssertEqual(metrics.countSampleCount, 2)
        XCTAssertEqual(metrics.yieldSampleCount, 2)
        XCTAssertEqual(try XCTUnwrap(metrics.countMAE), 2, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.countMAPE), 20, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.countRMSE), 2, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.yieldMAE), 1, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.yieldMAPE), 20, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.yieldRMSE), 1, accuracy: 0.000_1)
    }

    func testCalibrationValidationMetricsSkipsInvalidGroundTruthSamples() throws {
        let records = [
            makeRecord(fruitType: "apple", estimatedCount: 12, manualCount: nil, estimatedYield: 6, actualYield: nil),
            makeRecord(fruitType: "apple", estimatedCount: 12, manualCount: 0, estimatedYield: 6, actualYield: 0),
            makeRecord(fruitType: "apple", estimatedCount: 10, manualCount: 8, estimatedYield: .nan, actualYield: 5),
            makeRecord(fruitType: "apple", estimatedCount: 9, manualCount: 9, estimatedYield: 4, actualYield: 5),
        ]

        let metrics = CalibrationValidationMetrics.make(from: records)

        XCTAssertTrue(metrics.hasEvidence)
        XCTAssertEqual(metrics.recordCount, 2)
        XCTAssertEqual(metrics.countSampleCount, 2)
        XCTAssertEqual(metrics.yieldSampleCount, 1)
        XCTAssertEqual(try XCTUnwrap(metrics.countMAE), 1, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.yieldMAE), 1, accuracy: 0.000_1)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRecord(
        fruitType: String,
        estimatedCount: Int,
        manualCount: Int?,
        estimatedYield: Double,
        actualYield: Double?
    ) -> CalibrationRecord {
        CalibrationRecord(
            id: UUID(),
            treeID: "T-\(UUID().uuidString)",
            scanDate: Date(timeIntervalSince1970: 1_780_000_000),
            estimatedFruitCount: estimatedCount,
            manualFruitCount: manualCount,
            estimatedYieldKg: estimatedYield,
            actualYieldKg: actualYield,
            fruitType: fruitType
        )
    }
}
