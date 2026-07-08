import XCTest
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
