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

    func testVisualLidarRatioRaisesKWhenVisualExceedsLidar() {
        let baseline = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 1000,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 1.0
        )
        let ratioSupported = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 1000,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 1.0,
            visualDetectionCount: 10,
            lidarDetectionCount: 5
        )

        XCTAssertEqual(baseline.k, 1.0, accuracy: 0.01)
        XCTAssertGreaterThan(
            ratioSupported.k,
            baseline.k,
            "二维检测多于 LiDAR 聚类时，应按论文中的 n_visual / n_lidar 证据上调 K"
        )
        XCTAssertEqual(ratioSupported.k, 2.0, accuracy: 0.01)
        XCTAssertEqual(ratioSupported.method, "density_weighted_shell_visual_lidar_ratio")
    }

    func testVisualLidarRatioDoesNotReduceGeometricCorrection() {
        let baseline = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 5,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 0.3
        )
        let ratioSupported = OcclusionCorrector.correctionFactorDetailed(
            visibleCount: 5,
            crownRadiusM: 1.5,
            crownDepthM: 0.4,
            lidarPenetrationM: 0.4,
            scanAngleCoverage: 0.3,
            visualDetectionCount: 4,
            lidarDetectionCount: 8
        )

        XCTAssertEqual(
            ratioSupported.k,
            baseline.k,
            accuracy: 0.001,
            "二维检测未超过 LiDAR 聚类时，比率证据不应降低几何遮挡校正"
        )
        XCTAssertEqual(ratioSupported.method, "density_weighted_shell")
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

    func testScanAngleCoverageRequiresSupportedAngleBins() {
        var points: [ColoredPoint] = []
        for i in 0..<120 {
            let angle = (-Float.pi / 6) + Float(i) / 119.0 * (Float.pi / 3)
            let radius: Float = 1.0
            points.append(ColoredPoint(
                pos: SIMD3<Float>(radius * cos(angle), 0, radius * sin(angle)),
                r: 0.5, g: 0.5, b: 0.5
            ))
        }
        points.append(ColoredPoint(pos: SIMD3<Float>(-1, 0, 0), r: 0.5, g: 0.5, b: 0.5))

        let coverage = OcclusionCorrector.estimateScanAngleCoverage(from: points)

        XCTAssertLessThan(
            coverage,
            0.45,
            "单个离群角度点不应显著抬高扫描角覆盖率"
        )
    }
}
