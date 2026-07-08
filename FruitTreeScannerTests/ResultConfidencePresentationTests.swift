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

    func testPostScanWorkflowAdviceKeepsExistingRoutingText() {
        var high = YieldResult()
        high.confidence = "high"
        high.yieldFinalKg = 12.3
        high.nLidar = 8

        let highAdvice = ResultPostScanWorkflowAdvice(result: high)
        XCTAssertEqual(highAdvice.confidenceText, "高置信度")
        XCTAssertEqual(highAdvice.nextStepText, "保存并继续")
        XCTAssertEqual(highAdvice.primaryAdvice, "结果可直接入库；建议补充地块和状态标签后继续下一棵。")
        XCTAssertEqual(highAdvice.reviewFocus, "抽查树冠轮廓、果实密集区和冠幅估算，确认符合田间记录。")

        var low = YieldResult()
        low.confidence = "low"
        low.yieldFinalKg = 0

        let lowAdvice = ResultPostScanWorkflowAdvice(result: low)
        XCTAssertEqual(lowAdvice.nextStepText, "复扫或人工复核")
        XCTAssertEqual(lowAdvice.primaryAdvice, "建议保留本次记录作为原始点云，并从主干到树冠背面补扫一次。")
        XCTAssertEqual(lowAdvice.reviewFocus, "优先检查 LiDAR 深度、点云数量、图像帧和果实是否清晰可见。")
    }

    func testAlgorithmParametersPresentationKeepsExistingLabels() {
        var result = YieldResult()
        result.clusterEps = 0.01
        result.colorFilterDesc = "N/A"
        result.occlusionK = 1.0
        result.methodUsed = "weighted_AB"

        var presentation = ResultAlgorithmParametersPresentation(result: result)
        XCTAssertEqual(presentation.clusterSensitivityLabel, "精细")
        XCTAssertEqual(presentation.colorFilterDisplay, "未启用")
        XCTAssertEqual(presentation.colorFilterDetail, "本次未使用颜色范围过滤，主要依赖模型和几何特征。")
        XCTAssertEqual(presentation.occlusionDisplay, "未放大")
        XCTAssertEqual(presentation.methodDisplayName, "双路线加权")
        XCTAssertEqual(presentation.methodDetail, "综合冠层结构和可见果实体积，两条路线一致性越高置信度越高。")

        result.clusterEps = 0.03
        result.colorFilterDesc = "HSV"
        result.occlusionK = 1.234
        result.methodUsed = "flagged"

        presentation = ResultAlgorithmParametersPresentation(result: result)
        XCTAssertEqual(presentation.clusterSensitivityLabel, "标准")
        XCTAssertEqual(presentation.colorFilterDisplay, "已启用")
        XCTAssertEqual(presentation.colorFilterDetail, "结合当前果类成熟色范围筛选候选点；技术范围：HSV。")
        XCTAssertEqual(presentation.occlusionDisplay, "补偿 ×1.23")
        XCTAssertEqual(presentation.methodDisplayName, "人工复核")
        XCTAssertEqual(presentation.methodDetail, "两条估算路线差异较大，建议结合现场抽样复核。")

        result.clusterEps = 0.08
        result.methodUsed = ""
        presentation = ResultAlgorithmParametersPresentation(result: result)
        XCTAssertEqual(presentation.clusterSensitivityLabel, "宽松")
        XCTAssertEqual(presentation.methodDisplayName, "未形成估算")

        result.methodUsed = "fusion_visual_calibrated_coverage_review"
        presentation = ResultAlgorithmParametersPresentation(result: result)
        XCTAssertEqual(presentation.methodDisplayName, "覆盖不足复核")
        XCTAssertTrue(presentation.methodDetail.contains("扫描角度"))

        result.methodUsed = "fusion_visual_calibrated_coverage_limited"
        presentation = ResultAlgorithmParametersPresentation(result: result)
        XCTAssertEqual(presentation.methodDisplayName, "有限覆盖估算")
        XCTAssertTrue(presentation.methodDetail.contains("扫描覆盖有限"))

        result.methodUsed = "tracked_image_visual_calibrated"
        presentation = ResultAlgorithmParametersPresentation(result: result)
        XCTAssertEqual(presentation.methodDisplayName, "多帧视觉估计")
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
