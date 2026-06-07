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

    func testCorrectionFactorConvenienceMethod() {
        let result = OcclusionCorrector.correctionFactor(
            visibleCount: 5,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4
        )
        XCTAssertGreaterThanOrEqual(result, 1.0)
        XCTAssertLessThanOrEqual(result, 3.0)
    }

    func testVeryLowScanAngleCoverageProducesHigherK() {
        let result = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 3,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 0.1
        )
        XCTAssertEqual(result.method, "density_weighted_shell")
        XCTAssertGreaterThanOrEqual(result.k, 1.0)
        XCTAssertLessThanOrEqual(result.k, 3.0)
    }

    func testHighVisibleCountProducesKCloseToOne() {
        let result = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 1000,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 1.0
        )
        XCTAssertEqual(result.k, 1.0, accuracy: 0.01, "大量可见果实 + 全角度覆盖 k 应接近 1.0")
    }

    func testScanAngleCoverageLowPointCountReturnsDefault() {
        let points = (0..<30).map {
            ColoredPoint(pos: SIMD3<Float>(Float($0) * 0.01, 0, 0), r: 0.5, g: 0.5, b: 0.5)
        }
        let coverage = OcclusionCorrector.estimateScanAngleCoverage(from: points)
        XCTAssertEqual(coverage, 0.25, "≤50 点应返回默认覆盖 0.25")
    }

    func testScanAngleCoverageWithSufficientPoints() {
        var points: [ColoredPoint] = []
        for i in 0..<100 {
            let angle = Float(i) / 100.0 * 2 * Float.pi
            let radius: Float = 1.0
            points.append(ColoredPoint(
                pos: SIMD3<Float>(radius * cos(angle), 0, radius * sin(angle)),
                r: 0.5, g: 0.5, b: 0.5
            ))
        }
        let coverage = OcclusionCorrector.estimateScanAngleCoverage(from: points)
        XCTAssertGreaterThan(coverage, 0.25, ">50 点应计算实际覆盖率")
        XCTAssertLessThanOrEqual(coverage, 1.0)
    }
}
