import XCTest
@testable import FruitTreeScanner

final class OcclusionCorrectorTests: XCTestCase {

    func testZeroVisibleCount() {
        let result = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 0,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 0.5
        )
        XCTAssertEqual(result.k, 1.0, "无可见果实时 k 应为 1.0")
    }

    func testKClampedToRange() {
        let result = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 5,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 0.5
        )
        XCTAssertGreaterThanOrEqual(result.k, 1.0, "k 应 >= 1.0")
        XCTAssertLessThanOrEqual(result.k, 3.0, "k 应 <= 3.0")
    }

    func testEstimateCrownRadiusEmpty() {
        let radius = OcclusionCorrector.estimateCrownRadius(from: [])
        XCTAssertEqual(radius, 1.5, "空点云应返回默认半径 1.5")
    }

    func testEstimateCrownDepthFewPoints() {
        var points: [ColoredPoint] = []
        for i in 0..<50 {
            points.append(ColoredPoint(pos: SIMD3<Float>(Float(i) * 0.01, 0, 0), r: 0.5, g: 0.5, b: 0.5))
        }
        let depth = OcclusionCorrector.estimateCrownDepth(from: points)
        XCTAssertEqual(depth, 0.4, "点数不足100应返回默认深度 0.4")
    }

    func testScanAngleCoverageEmpty() {
        let coverage = OcclusionCorrector.estimateScanAngleCoverage(from: [])
        XCTAssertEqual(coverage, 0.25, "空点云应返回默认覆盖 0.25")
    }

    func testConfidenceInterval() {
        let result = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 10,
            crownRadiusM: 1.0,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 0.8
        )
        XCTAssertLessThanOrEqual(result.kLow, result.k, "kLow 应 <= k")
        XCTAssertGreaterThanOrEqual(result.kHigh, result.k, "kHigh 应 >= k")
    }
}
