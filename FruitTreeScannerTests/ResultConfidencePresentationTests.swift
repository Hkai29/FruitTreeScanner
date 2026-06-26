import XCTest
@testable import FruitTreeScanner

final class ResultConfidencePresentationTests: XCTestCase {
    func testKnownConfidenceLabelsStayStable() {
        XCTAssertEqual(ResultConfidencePresentation("high").label, "高置信度")
        XCTAssertEqual(ResultConfidencePresentation("medium").label, "中等置信度")
        XCTAssertEqual(ResultConfidencePresentation("manual_review").label, "需人工复核")
    }

    func testUnknownConfidenceFallsBackToLowLabel() {
        XCTAssertEqual(ResultConfidencePresentation("low").label, "低置信度")
        XCTAssertEqual(ResultConfidencePresentation("").label, "低置信度")
        XCTAssertEqual(ResultConfidencePresentation("unknown").label, "低置信度")
        XCTAssertEqual(ResultConfidencePresentation("VERY_HIGH").label, "低置信度")
    }

    func testConfidenceColorAccessDoesNotCrash() {
        _ = ResultConfidencePresentation("high").color
        _ = ResultConfidencePresentation("medium").color
        _ = ResultConfidencePresentation("manual_review").color
        _ = ResultConfidencePresentation("low").color
        _ = ResultConfidencePresentation("").color
        _ = ResultConfidencePresentation("unknown").color
    }

    func testResultReviewPolicyIsConservativeForUntrustedValues() {
        XCTAssertFalse(ResultReviewPolicy.needsReview("high"))
        XCTAssertFalse(ResultReviewPolicy.needsReview("medium"))
        XCTAssertTrue(ResultReviewPolicy.needsReview("low"))
        XCTAssertTrue(ResultReviewPolicy.needsReview("manual_review"))
        XCTAssertTrue(ResultReviewPolicy.needsReview(""))
        XCTAssertTrue(ResultReviewPolicy.needsReview("unknown"))
    }

    func testResultValueFormatterKeepsExistingUnitsAndPrecision() {
        XCTAssertEqual(ResultValueFormatter.finalYieldKg(12.34), "12.3")
        XCTAssertEqual(ResultValueFormatter.correctionFactor(1.234), "×1.23")
        XCTAssertEqual(ResultValueFormatter.kilograms(3.456), "3.46 kg")
        XCTAssertEqual(ResultValueFormatter.centimeters(8.76), "8.8 cm")
        XCTAssertEqual(ResultValueFormatter.cubicMeters(1.2345), "1.235 m³")
        XCTAssertEqual(ResultValueFormatter.meters(2.345), "2.35 m")
        XCTAssertEqual(ResultValueFormatter.dbscanEps(0.0456), "0.046 m")
        XCTAssertEqual(ResultValueFormatter.occlusionK(1.234), "1.23")
    }

    func testResultValueFormatterZeroValues() {
        XCTAssertEqual(ResultValueFormatter.finalYieldKg(0), "0.0")
        XCTAssertEqual(ResultValueFormatter.kilograms(0), "0.00 kg")
        XCTAssertEqual(ResultValueFormatter.cubicMeters(0), "0.000 m³")
        XCTAssertEqual(ResultValueFormatter.correctionFactor(0), "×0.00")
    }

    func testResultValueFormatterLargeValues() {
        XCTAssertEqual(ResultValueFormatter.finalYieldKg(9999.99), "10000.0")
        XCTAssertEqual(ResultValueFormatter.kilograms(1234.567), "1234.57 kg")
        XCTAssertEqual(ResultValueFormatter.meters(999.99), "999.99 m")
    }
}

final class ScanHUDValueFormatterTests: XCTestCase {
    func testPointCountFormatterKeepsExistingCompactLabels() {
        XCTAssertEqual(ScanHUDValueFormatter.pointCount(999), "999")
        XCTAssertEqual(ScanHUDValueFormatter.pointCount(1_000), "1.0K")
        XCTAssertEqual(ScanHUDValueFormatter.pointCount(1_500), "1.5K")
        XCTAssertEqual(ScanHUDValueFormatter.pointCount(1_000_000), "1.0M")
    }

    func testPointDensityFormatterKeepsExistingWholeNumberDisplay() {
        XCTAssertEqual(ScanHUDValueFormatter.pointDensity(123.4), "123")
    }
}

@MainActor
final class ScanHUDStateTests: XCTestCase {
    func testDefaultStateMatchesDefaultSnapshot() {
        let state = ScanHUDState()
        let snapshot = ScanHUDSnapshot()

        XCTAssertEqual(state.pointCount, snapshot.pointCount)
        XCTAssertEqual(state.coveragePercent, snapshot.coveragePercent)
        XCTAssertEqual(state.visionModelStatus, snapshot.visionModelStatus)
        XCTAssertEqual(state.exportablePointStatus, snapshot.exportablePointStatus)
        XCTAssertEqual(state.fusionStatus, snapshot.fusionStatus)
    }

    func testUpdateOnlyChangesPassedFields() {
        let state = ScanHUDState()
        state.update(pointCount: 42)

        XCTAssertEqual(state.pointCount, 42)
        XCTAssertEqual(state.coveragePercent, 0)
        XCTAssertEqual(state.visionModelStatus, "--")
        XCTAssertEqual(state.exportablePointStatus, "NoCloud")
        XCTAssertEqual(state.fusionStatus, "等待扫描")
    }

    func testUpdatePreservesPreviousFieldValues() {
        let state = ScanHUDState()
        state.update(pointCount: 10, visionModelStatus: "active")
        state.update(coveragePercent: 75)

        XCTAssertEqual(state.pointCount, 10)
        XCTAssertEqual(state.coveragePercent, 75)
        XCTAssertEqual(state.visionModelStatus, "active")
    }

    func testResetForNewScanRestoresDefaultSnapshot() {
        let state = ScanHUDState()
        state.update(
            pointCount: 999,
            coveragePercent: 50,
            visionModelStatus: "tracking",
            exportablePointStatus: "Ready",
            fusionStatus: "done"
        )

        state.resetForNewScan()

        XCTAssertEqual(state.pointCount, 0)
        XCTAssertEqual(state.coveragePercent, 0)
        XCTAssertEqual(state.visionModelStatus, "--")
        XCTAssertEqual(state.exportablePointStatus, "NoCloud")
        XCTAssertEqual(state.fusionStatus, "等待扫描")
    }
}
