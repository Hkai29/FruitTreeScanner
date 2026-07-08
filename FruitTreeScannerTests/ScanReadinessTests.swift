import XCTest
@testable import FruitTreeScanner

final class ScanReadinessTests: XCTestCase {
    func testOnlyReadyDoesNotBlockScanning() {
        XCTAssertFalse(ScanReadiness.ready.blocksScanning)
        XCTAssertTrue(ScanReadiness.checking.blocksScanning)
        XCTAssertTrue(ScanReadiness.arUnsupported.blocksScanning)
        XCTAssertTrue(ScanReadiness.metalUnavailable.blocksScanning)
        XCTAssertTrue(ScanReadiness.lidarUnavailable.blocksScanning)
        XCTAssertTrue(ScanReadiness.cameraDenied.blocksScanning)
        XCTAssertTrue(ScanReadiness.cameraRestricted.blocksScanning)
    }

    func testCameraDeniedTextStaysStable() {
        XCTAssertEqual(ScanReadiness.cameraDenied.title, "相机权限未开启")
        XCTAssertEqual(
            ScanReadiness.cameraDenied.message,
            "扫描需要相机画面和 LiDAR 深度帧。请在系统设置中允许相机权限。"
        )
    }

    func testMetalUnavailableTextStaysStable() {
        XCTAssertEqual(ScanReadiness.metalUnavailable.title, "图形渲染不可用")
        XCTAssertEqual(
            ScanReadiness.metalUnavailable.message,
            "扫描画面需要 Metal 图形渲染支持。请重启 App，或换用支持 Metal 的设备后再试。"
        )
    }

    func testLidarUnavailableTextStaysStable() {
        XCTAssertEqual(ScanReadiness.lidarUnavailable.title, "当前设备没有 LiDAR 深度")
        XCTAssertEqual(
            ScanReadiness.lidarUnavailable.message,
            "扫描需要 LiDAR sceneDepth 才能生成有效点云。请使用支持 LiDAR 的 iPhone 或 iPad。"
        )
    }

    func testReadyHasNoBlockingText() {
        XCTAssertEqual(ScanReadiness.ready.title, "")
        XCTAssertEqual(ScanReadiness.ready.message, "")
    }
}

final class ScanCompletionEvaluatorTests: XCTestCase {
    func testAngleCoverageContributesToCompletionScore() {
        let evaluator = ScanCompletionEvaluator()
        let narrow = evaluator.evaluate(.init(
            voxelCount: 500,
            scanDuration: 60,
            angleCoverage: 0.18,
            discoveryTrend: .stable,
            discoveryRate: 8
        ))
        let broad = evaluator.evaluate(.init(
            voxelCount: 500,
            scanDuration: 60,
            angleCoverage: 0.82,
            discoveryTrend: .stable,
            discoveryRate: 8
        ))

        XCTAssertLessThan(narrow.angleCoverageScore, broad.angleCoverageScore)
        XCTAssertLessThan(narrow.overall, broad.overall)
    }

    func testCompletionHintRequestsOppositeSideWhenAngleCoverageIsLow() {
        let completion = ScanCompletion(
            overall: 0.55,
            timeScore: 0.7,
            voxelScore: 0.8,
            angleCoverageScore: 0.2,
            angleUniformityScore: 0.9,
            stabilityScore: 0.8,
            voxelCount: 120,
            scanDuration: 35,
            discoveryTrend: .stable
        )

        XCTAssertEqual(completion.statusHint, "补扫树冠另一侧")
    }

    func testAngleUniformityContributesToCompletionScore() {
        let evaluator = ScanCompletionEvaluator()
        let skewed = evaluator.evaluate(.init(
            voxelCount: 600,
            scanDuration: 70,
            angleCoverage: 0.9,
            angleUniformity: 0.35,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))
        let balanced = evaluator.evaluate(.init(
            voxelCount: 600,
            scanDuration: 70,
            angleCoverage: 0.9,
            angleUniformity: 0.95,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))

        XCTAssertLessThan(skewed.angleUniformityScore, balanced.angleUniformityScore)
        XCTAssertLessThan(skewed.overall, balanced.overall)
        XCTAssertEqual(skewed.statusHint, "补扫稀疏视角")
    }

    func testOppositeSideCoverageContributesGentlyToCompletionScore() {
        let evaluator = ScanCompletionEvaluator()
        let oneSided = evaluator.evaluate(.init(
            voxelCount: 600,
            scanDuration: 70,
            angleCoverage: 0.70,
            angleUniformity: 0.82,
            oppositeSideCoverage: 0.12,
            verticalCoverage: 0.86,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))
        let pairedSides = evaluator.evaluate(.init(
            voxelCount: 600,
            scanDuration: 70,
            angleCoverage: 0.70,
            angleUniformity: 0.82,
            oppositeSideCoverage: 0.92,
            verticalCoverage: 0.86,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))

        XCTAssertLessThan(oneSided.oppositeSideScore, pairedSides.oppositeSideScore)
        XCTAssertLessThan(oneSided.overall, pairedSides.overall)
        XCTAssertGreaterThan(oneSided.overall, 0.65, "对侧覆盖不足应提示补扫，但不应让受限果园行扫描直接失败")
    }

    func testCompletionHintRequestsBackSideWhenCoverageIsMostlyOneSided() {
        let evaluator = ScanCompletionEvaluator()
        let oneSided = evaluator.evaluate(.init(
            voxelCount: 360,
            scanDuration: 55,
            angleCoverage: 0.62,
            angleUniformity: 0.78,
            oppositeSideCoverage: 0.08,
            verticalCoverage: 0.82,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))

        XCTAssertEqual(oneSided.statusHint, "补扫树冠背面")
    }

    func testVerticalCoverageGentlyContributesToCompletionScore() {
        let evaluator = ScanCompletionEvaluator()
        let middleOnly = evaluator.evaluate(.init(
            voxelCount: 700,
            scanDuration: 80,
            angleCoverage: 0.86,
            angleUniformity: 0.86,
            verticalCoverage: 0.25,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))
        let fullHeight = evaluator.evaluate(.init(
            voxelCount: 700,
            scanDuration: 80,
            angleCoverage: 0.86,
            angleUniformity: 0.86,
            verticalCoverage: 0.95,
            discoveryTrend: .stable,
            discoveryRate: 4
        ))

        XCTAssertLessThan(middleOnly.verticalCoverageScore, fullHeight.verticalCoverageScore)
        XCTAssertLessThan(middleOnly.overall, fullHeight.overall)
        XCTAssertGreaterThan(middleOnly.overall, 0.65, "垂直覆盖不足应提示补扫，但不应把现场可用扫描直接打成失败")
    }

    func testCompletionHintRequestsVerticalCoverageOnlyAfterHorizontalCoverageIsUseful() {
        let completion = ScanCompletion(
            overall: 0.72,
            timeScore: 0.9,
            voxelScore: 0.9,
            angleCoverageScore: 0.70,
            angleUniformityScore: 0.85,
            verticalCoverageScore: 0.32,
            stabilityScore: 0.8,
            voxelCount: 180,
            scanDuration: 65,
            discoveryTrend: .stable
        )

        XCTAssertEqual(completion.statusHint, "放慢补扫树冠上下层")
    }
}
