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

    func testCalibrationWorkspaceCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "calibration.workspace.title": "Algorithm Calibration",
                "calibration.workspace.subtitle": "Tune yield estimates using measured fruit size, clustering thresholds, and error records.",
                "calibration.workspace.close": "Close",
                "calibration.workspace.add_record_accessibility": "Add Calibration Record",
                "calibration.workspace.delete_title": "Delete Calibration Record",
                "calibration.workspace.delete_message": "This calibration record will be removed from this device. The original scan record will not be deleted.",
                "calibration.workspace.parameters_title": "Algorithm Parameters",
                "calibration.workspace.minimum_cluster_points": "Minimum Cluster Points",
                "calibration.workspace.maximum_cluster_diameter": "Maximum Cluster Diameter (m)",
                "calibration.workspace.minimum_sphericity": "Minimum Sphericity",
                "calibration.workspace.hue_range": "HSV Hue Range",
                "calibration.workspace.statistics_title": "Error Statistics",
                "calibration.workspace.statistics_empty": "No calibration data yet",
                "calibration.workspace.count_mape": "Fruit Count MAPE",
                "calibration.workspace.yield_mape": "Yield MAPE",
                "calibration.workspace.record_count": "Calibrations",
                "calibration.workspace.records_title": "Calibration Records",
                "calibration.workspace.records_empty_title": "No Calibration Records",
                "calibration.workspace.records_empty_message": "Add a manual fruit count or actual weight to compare estimation errors here.",
                "calibration.workspace.add_record": "Add Record",
                "calibration.workspace.tree_format": "Tree #%@",
                "calibration.workspace.estimated": "Estimated",
                "calibration.workspace.actual": "Actual",
                "calibration.workspace.delete_record_accessibility": "Delete Calibration Record",
                "calibration.workspace.count_error": "Count",
                "calibration.workspace.yield_error": "Yield",
                "calibration.workspace.fruit_count.one": "%d fruit",
                "calibration.workspace.fruit_count.other": "%d fruits",
                "calibration.workspace.yield_format": "%.1f kg",
                "calibration.workspace.count_yield_format": "%@ / %@"
            ],
            "zh": [
                "calibration.workspace.title": "算法校准",
                "calibration.workspace.subtitle": "用实测果径、聚类阈值和误差记录调准产量估算。",
                "calibration.workspace.close": "关闭",
                "calibration.workspace.add_record_accessibility": "添加校准记录",
                "calibration.workspace.delete_title": "删除校准记录",
                "calibration.workspace.delete_message": "这条校准记录会从本机移除，扫描原始记录不会被删除。",
                "calibration.workspace.parameters_title": "算法参数",
                "calibration.workspace.minimum_cluster_points": "最小聚类点数",
                "calibration.workspace.maximum_cluster_diameter": "最大聚类直径 (m)",
                "calibration.workspace.minimum_sphericity": "最小球形度",
                "calibration.workspace.hue_range": "HSV 色调范围",
                "calibration.workspace.statistics_title": "误差统计",
                "calibration.workspace.statistics_empty": "暂无校准数据",
                "calibration.workspace.count_mape": "果数 MAPE",
                "calibration.workspace.yield_mape": "产量 MAPE",
                "calibration.workspace.record_count": "校准次数",
                "calibration.workspace.records_title": "校准记录",
                "calibration.workspace.records_empty_title": "暂无校准记录",
                "calibration.workspace.records_empty_message": "添加人工计数或实际重量后，这里会显示误差对比。",
                "calibration.workspace.add_record": "添加记录",
                "calibration.workspace.tree_format": "树 #%@",
                "calibration.workspace.estimated": "估算",
                "calibration.workspace.actual": "实际",
                "calibration.workspace.delete_record_accessibility": "删除校准记录",
                "calibration.workspace.count_error": "计数",
                "calibration.workspace.yield_error": "产量",
                "calibration.workspace.fruit_count.one": "%d 个",
                "calibration.workspace.fruit_count.other": "%d 个",
                "calibration.workspace.yield_format": "%.1f kg",
                "calibration.workspace.count_yield_format": "%@ / %@"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let bundle = try localizedBundle(language: language)
            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    bundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testCalibrationWorkspaceFormatsDynamicRecordValuesInEachLanguage() throws {
        let englishBundle = try localizedBundle(language: "en")
        let chineseBundle = try localizedBundle(language: "zh")

        XCTAssertEqual(
            L10n.CalibrationWorkspace.treeTitle("TREE-17", in: englishBundle),
            "Tree #TREE-17"
        )
        XCTAssertEqual(L10n.CalibrationWorkspace.fruitCount(1, in: englishBundle), "1 fruit")
        XCTAssertEqual(L10n.CalibrationWorkspace.fruitCount(24, in: englishBundle), "24 fruits")
        XCTAssertEqual(
            L10n.CalibrationWorkspace.countAndYield(
                count: 24,
                yieldKilograms: 3.5,
                locale: Locale(identifier: "en_US"),
                in: englishBundle
            ),
            "24 fruits / 3.5 kg"
        )

        XCTAssertEqual(
            L10n.CalibrationWorkspace.treeTitle("TREE-17", in: chineseBundle),
            "树 #TREE-17"
        )
        XCTAssertEqual(L10n.CalibrationWorkspace.fruitCount(1, in: chineseBundle), "1 个")
        XCTAssertEqual(L10n.CalibrationWorkspace.fruitCount(24, in: chineseBundle), "24 个")
        XCTAssertEqual(
            L10n.CalibrationWorkspace.countAndYield(
                count: 24,
                yieldKilograms: 3.5,
                locale: Locale(identifier: "zh_CN"),
                in: chineseBundle
            ),
            "24 个 / 3.5 kg"
        )
    }

    @MainActor
    func testCalibrationWorkspaceComponentsRenderAtAccessibilityTextSize() {
        let record = CalibrationRecord(
            id: UUID(uuidString: "B4B4B4B4-B4B4-4B4B-8B4B-B4B4B4B4B4B4")!,
            treeID: "TREE-17",
            scanDate: Date(timeIntervalSince1970: 1_780_000_000),
            estimatedFruitCount: 24,
            manualFruitCount: 22,
            estimatedYieldKg: 3.5,
            actualYieldKg: 3.25,
            fruitType: FruitCategory.apple.rawValue
        )

        assertAccessibleRender(
            CalibrationParametersCard(
                maxDiameter: .constant(0.12),
                minClusterPoints: .constant(24),
                sphericity: .constant(0.5),
                onCommitMinClusterPoints: {},
                onCommitMaxDiameter: {},
                onCommitSphericity: {}
            ),
            name: "CalibrationParameters-Accessibility3"
        )
        assertAccessibleRender(
            CalibrationStatisticsCard(records: [record]),
            name: "CalibrationStatistics-Accessibility3"
        )
        assertAccessibleRender(
            CalibrationRecordsSection(records: [record], onAdd: {}, onDelete: { _ in }),
            name: "CalibrationRecords-Accessibility3"
        )
    }

    private func localizedBundle(language: String) throws -> Bundle {
        let url = try XCTUnwrap(
            Bundle.main.url(forResource: language, withExtension: "lproj"),
            "Missing \(language).lproj in app bundle"
        )
        return try XCTUnwrap(Bundle(url: url))
    }

    @MainActor
    private func assertAccessibleRender<Content: View>(
        _ content: Content,
        name: String,
        file: StaticString = #filePath,
        line: UInt = #line
    ) {
        let rootView = content
            .padding(16)
            .frame(width: 390, height: 844, alignment: .top)
            .background(Design.Colors.Dark.bgDeep)
            .environment(\.dynamicTypeSize, .accessibility3)
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
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            didDraw = hostingController.view.drawHierarchy(
                in: hostingController.view.bounds,
                afterScreenUpdates: true
            )
        }

        XCTAssertTrue(didDraw, file: file, line: line)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844), file: file, line: line)
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()
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
