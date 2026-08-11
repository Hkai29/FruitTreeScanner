import SwiftUI
import UIKit
import XCTest
@testable import FruitTreeScanner

final class ResultConfidencePresentationTests: XCTestCase {
    func testResultSummaryLayoutKeepsCompactThreeColumnArrangement() {
        let policy = ResultSummaryLayoutPolicy(isAccessibilitySize: false)

        XCTAssertEqual(policy.headerArrangement, .horizontal)
        XCTAssertEqual(policy.primaryMetricArrangement, .horizontal)
        XCTAssertEqual(policy.summaryColumnCount, 3)
        XCTAssertFalse(policy.allowsPillValueWrapping)
    }

    func testResultSummaryLayoutStacksCriticalContentAtAccessibilitySizes() {
        let policy = ResultSummaryLayoutPolicy(isAccessibilitySize: true)

        XCTAssertEqual(policy.headerArrangement, .vertical)
        XCTAssertEqual(policy.primaryMetricArrangement, .vertical)
        XCTAssertEqual(policy.summaryColumnCount, 1)
        XCTAssertTrue(policy.allowsPillValueWrapping)
    }

    @MainActor
    func testResultSummaryRendersAtLargestAccessibilityTextSize() {
        var result = makeReliabilityResult(confidence: "medium", yieldKg: 10_000, fusedCount: 12)
        result.pointCloudSize = 125_000
        result.methodUsed = "fusion_visual_calibrated_coverage_limited"
        result.note = "保留完整诊断信息并结合田间记录复核。"

        let rootView = ScrollView {
            ResultSummaryHeader(
                treeID: "ORCHARD-NORTH-ROW-12-TREE-108",
                result: result
            )
        }
        .frame(width: 390, height: 844, alignment: .top)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.dynamicTypeSize, .accessibility5)
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
        attachment.name = "ResultSummary-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()
    }

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

    func testReliabilityPresentationTreatsFusedHighConfidenceResultAsUsable() {
        let result = makeReliabilityResult(confidence: "high", fusedCount: 2)

        let presentation = ResultReliabilityPresentation(result: result)

        XCTAssertEqual(presentation.level, .reliable)
        XCTAssertEqual(presentation.title, "结果可靠，可用于估产")
        XCTAssertEqual(presentation.recommendedAction, "可以保存并导出")
        XCTAssertNil(presentation.diagnosticHint)
    }

    func testReliabilityPresentationShowsNoReliableEstimateWithoutFusedFruit() {
        let result = makeReliabilityResult(
            confidence: "low",
            yieldKg: 0,
            fusedCount: 0,
            imageOnlyCount: 2,
            cloudOnlyCount: 1
        )

        let presentation = ResultReliabilityPresentation(result: result)

        XCTAssertEqual(presentation.level, .noReliableEstimate)
        XCTAssertEqual(presentation.title, "无可靠估产")
        XCTAssertEqual(presentation.recommendedAction, "当前没有足够 RGB+LiDAR 融合证据")
        XCTAssertTrue(presentation.summary.contains("RGB+LiDAR"))
    }

    func testReliabilityPresentationPrioritizesZeroYieldReason() {
        var result = makeReliabilityResult(confidence: "high", fusedCount: 1)
        result.diagnostics.zeroYieldReasons = ["点云数量不足", "融合验证失败"]

        let presentation = ResultReliabilityPresentation(result: result)

        XCTAssertEqual(presentation.level, .unreliable)
        XCTAssertEqual(presentation.title, "结果不可靠，建议复扫")
        XCTAssertEqual(presentation.summary, "点云数量不足")
        XCTAssertEqual(presentation.diagnosticHint, "主要原因：点云数量不足")
    }

    func testReliabilityPresentationPromptsFruitTypeCheckWhenSelectedTypeFiltered() {
        var result = makeReliabilityResult(confidence: "high", fusedCount: 1)
        result.diagnostics.filteredBySelectedFruitTypeCount = 3

        let presentation = ResultReliabilityPresentation(result: result)

        XCTAssertEqual(presentation.level, .review)
        XCTAssertEqual(presentation.recommendedAction, "请确认选择的果类是否正确")
        XCTAssertEqual(presentation.diagnosticHint, "部分识别结果与当前果类选择不匹配。")
    }

    func testReliabilityPresentationHintsUnmappedRecognitionLabels() {
        var result = makeReliabilityResult(confidence: "high", fusedCount: 1)
        result.diagnostics.imageUnmappedLabels = ["unknown_fruit"]

        let presentation = ResultReliabilityPresentation(result: result)

        XCTAssertEqual(presentation.level, .review)
        XCTAssertEqual(presentation.recommendedAction, "请检查识别类别映射并结合诊断复核")
        XCTAssertEqual(presentation.diagnosticHint, "检测到未映射识别类别，详细标签见诊断区域。")
    }

    func testReliabilityPresentationDoesNotMutateYieldResultValues() {
        var result = makeReliabilityResult(confidence: "medium", yieldKg: 4.25, fusedCount: 1)
        result.nLidar = 7
        result.methodUsed = "fusion_visual_calibrated"
        result.diagnostics.validationSourceReliability = 0.62

        let yieldBefore = result.yieldFinalKg
        let countBefore = result.nLidar
        let methodBefore = result.methodUsed
        let diagnosticsBefore = result.diagnostics

        _ = ResultReliabilityPresentation(result: result)

        XCTAssertEqual(result.yieldFinalKg, yieldBefore)
        XCTAssertEqual(result.nLidar, countBefore)
        XCTAssertEqual(result.methodUsed, methodBefore)
        XCTAssertEqual(result.diagnostics, diagnosticsBefore)
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

    private func makeReliabilityResult(
        confidence: String,
        yieldKg: Float = 3.4,
        fusedCount: Int,
        imageOnlyCount: Int = 0,
        cloudOnlyCount: Int = 0
    ) -> YieldResult {
        var result = YieldResult()
        result.confidence = confidence
        result.yieldFinalKg = yieldKg
        result.nLidar = fusedCount
        result.diagnostics.depthAvailable = true
        result.diagnostics.pointCloudPointCount = 2_000
        result.diagnostics.fusedValidationCount = fusedCount
        result.diagnostics.validatedFruitCount = fusedCount + imageOnlyCount + cloudOnlyCount
        result.diagnostics.imageOnlyFruitCount = imageOnlyCount
        result.diagnostics.cloudOnlyFruitCount = cloudOnlyCount
        result.diagnostics.validationSourceReliability = fusedCount > 0 ? 0.82 : 0
        result.validatedFruits = (0..<fusedCount).map { index in
            ValidatedFruitData(
                from: ValidatedFruit(
                    category: .apple,
                    position: SIMD3<Float>(Float(index), 0, 0),
                    confidence: 0.9,
                    source: .fused
                )
            )
        }
        return result
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
