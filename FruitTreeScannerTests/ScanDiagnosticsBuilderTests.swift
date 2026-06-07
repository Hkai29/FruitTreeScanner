import XCTest
@testable import FruitTreeScanner

final class ScanDiagnosticsBuilderTests: XCTestCase {
    func testZeroYieldReasonsIncludesModelReasonWhenModelIsNotCoreML() {
        var diagnostics = baselineDiagnostics()
        diagnostics.imageModelStatus = "Fallback"

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )

        XCTAssertTrue(reasons.contains("模型未加载"))
    }

    func testZeroYieldReasonsIncludesDepthReasonWhenDepthUnavailable() {
        var diagnostics = baselineDiagnostics()
        diagnostics.depthAvailable = false

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )

        XCTAssertTrue(reasons.contains("深度不可用"))
    }

    func testZeroYieldReasonsIncludesPointCloudReasonWhenPointCountIsTooLow() {
        var diagnostics = baselineDiagnostics()
        diagnostics.pointCloudPointCount = 12

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )

        XCTAssertTrue(reasons.contains("点云数量不足"))
    }

    func testZeroYieldReasonsDistinguishesConfidenceFilteredAndUnmappedLabels() {
        var confidenceFiltered = baselineDiagnostics()
        confidenceFiltered.imageObservationCount = 4
        confidenceFiltered.imageConfidenceFilteredCount = 4
        confidenceFiltered.imageMappedFruitCount = 0

        let confidenceReasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: confidenceFiltered,
            pointCloudMinimum: 30
        )
        XCTAssertTrue(confidenceReasons.contains("候选被置信度过滤"))
        XCTAssertFalse(confidenceReasons.contains("模型标签未映射到水果类别"))

        var unmapped = baselineDiagnostics()
        unmapped.imageObservationCount = 4
        unmapped.imageConfidenceFilteredCount = 1
        unmapped.imageMappedFruitCount = 0

        let unmappedReasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: unmapped,
            pointCloudMinimum: 30
        )
        XCTAssertTrue(unmappedReasons.contains("候选被置信度过滤"))
        XCTAssertTrue(unmappedReasons.contains("模型标签未映射到水果类别"))
    }

    func testZeroYieldReasonsIncludesFusionFailureWhenImageAndCloudCandidatesExist() {
        var diagnostics = baselineDiagnostics()
        diagnostics.imageDetectionCount = 3
        diagnostics.pointCloudCandidateCount = 5
        diagnostics.fusedFruitCount = 0

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )

        XCTAssertTrue(reasons.contains("融合验证失败"))
    }

    func testZeroYieldReasonsIncludesCloudOnlyConservativeWhenApplicable() {
        var diagnostics = baselineDiagnostics()
        diagnostics.cloudOnlyConservativeMode = true
        diagnostics.fusedFruitCount = 0
        diagnostics.imageObservationCount = 3

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )
        XCTAssertTrue(reasons.contains("cloudOnly 保守模式未接受候选"))
    }

    func testZeroYieldReasonsSkipsCloudOnlyWhenNoImageDetections() {
        var diagnostics = baselineDiagnostics()
        diagnostics.cloudOnlyConservativeMode = true
        diagnostics.fusedFruitCount = 0
        diagnostics.imageObservationCount = 0

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )
        XCTAssertTrue(reasons.contains("图像检测无结果"))
        XCTAssertFalse(reasons.contains("cloudOnly 保守模式未接受候选"))
    }

    func testZeroYieldNoteWithEmptyReasonsReturnsFallback() {
        let note = ScanDiagnosticsBuilder.zeroYieldNote(reasons: [], fallback: "默认提示")
        XCTAssertEqual(note, "默认提示")
    }

    func testZeroYieldNoteWithMultipleReasonsJoinsThem() {
        let note = ScanDiagnosticsBuilder.zeroYieldNote(
            reasons: ["模型未加载", "深度不可用"],
            fallback: "默认"
        )
        XCTAssertEqual(note, "⚠️ 模型未加载；深度不可用")
    }

    func testZeroYieldReasonsNoFramesProcessed() {
        var diagnostics = baselineDiagnostics()
        diagnostics.imageFramesProcessed = 0

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )
        XCTAssertTrue(reasons.contains("未处理图像检测帧"))
    }

    func testZeroYieldReasonsNoCloudCandidates() {
        var diagnostics = baselineDiagnostics()
        diagnostics.pointCloudCandidateCount = 0

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )
        XCTAssertTrue(reasons.contains("点云聚类无候选"))
    }

    func testZeroYieldReasonsAllTriggered() {
        var diagnostics = ScanYieldDiagnostics()
        diagnostics.pointCloudPointCount = 5
        diagnostics.imageDetectionCount = 2
        diagnostics.pointCloudCandidateCount = 1
        diagnostics.fusedFruitCount = 0
        diagnostics.depthAvailable = false
        diagnostics.imageFramesProcessed = 0
        diagnostics.imageObservationCount = 0
        diagnostics.imageMappedFruitCount = 0
        diagnostics.imageModelStatus = "Fallback"

        let reasons = ScanDiagnosticsBuilder.zeroYieldReasons(
            diagnostics: diagnostics,
            pointCloudMinimum: 30
        )
        XCTAssertTrue(reasons.contains("模型未加载"))
        XCTAssertTrue(reasons.contains("深度不可用"))
        XCTAssertTrue(reasons.contains("点云数量不足"))
        XCTAssertTrue(reasons.contains("未处理图像检测帧"))
        XCTAssertTrue(reasons.contains("图像检测无结果"))
        XCTAssertTrue(reasons.contains("融合验证失败"))
    }

    private func baselineDiagnostics() -> ScanYieldDiagnostics {
        var diagnostics = ScanYieldDiagnostics()
        diagnostics.pointCloudPointCount = 120
        diagnostics.imageDetectionCount = 1
        diagnostics.deduplicatedImageDetectionCount = 1
        diagnostics.pointCloudCandidateCount = 1
        diagnostics.fusedFruitCount = 0
        diagnostics.depthAvailable = true
        diagnostics.imageFramesProcessed = 2
        diagnostics.imageObservationCount = 1
        diagnostics.imageMappedFruitCount = 1
        diagnostics.imageModelStatus = "CoreML"
        diagnostics.imageModelName = "FruitsDetector.mlmodelc"
        return diagnostics
    }
}

final class DiagnosticRecommendationTests: XCTestCase {
    func testRecommendationsForKnownReasons() {
        let reasons = ["模型未加载"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertFalse(recs.isEmpty)
        XCTAssertTrue(recs.contains(where: { $0.contains("CoreML") }))
    }

    func testRecommendationsForDepthUnavailable() {
        let reasons = ["深度不可用"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("LiDAR") }))
    }

    func testRecommendationsForLowPointCloud() {
        let reasons = ["点云数量不足"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("点云") || $0.contains("扫描") }))
    }

    func testRecommendationsForNoImageFrames() {
        let reasons = ["未处理图像检测帧"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("摄像头") || $0.contains("AI") }))
    }

    func testRecommendationsForNoImageDetections() {
        let reasons = ["图像检测无结果"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("光线") || $0.contains("光照") }))
    }

    func testRecommendationsForConfidenceFiltered() {
        let reasons = ["候选被置信度过滤"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("置信度") || $0.contains("拍摄") }))
    }

    func testRecommendationsForUnmappedLabels() {
        let reasons = ["模型标签未映射到水果类别"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("fruit_mapping.json") || $0.contains("水果品类") }))
    }

    func testRecommendationsForNoCloudCandidates() {
        let reasons = ["点云聚类无候选"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("DBSCAN") || $0.contains("点云密度") }))
    }

    func testRecommendationsForFusionFailure() {
        let reasons = ["融合验证失败"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("匹配") || $0.contains("抖动") }))
    }

    func testRecommendationsForCloudOnlyConservative() {
        let reasons = ["cloudOnly 保守模式未接受候选"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertTrue(recs.contains(where: { $0.contains("保守模式") || $0.contains("光照") }))
    }

    func testRecommendationsForMultipleReasonsDedup() {
        let reasons = ["模型未加载", "深度不可用", "点云数量不足"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertEqual(recs.count, 6)
    }

    func testRecommendationsForUnknownReasonReturnsFallback() {
        let reasons = ["未知原因"]
        let recs = DiagnosticRecommendation.recommendations(for: reasons)
        XCTAssertEqual(recs.count, 1)
        XCTAssertTrue(recs[0].contains("CoreML"))
    }

    func testRecommendationsForEmptyReasonsReturnsFallback() {
        let recs = DiagnosticRecommendation.recommendations(for: [])
        XCTAssertEqual(recs.count, 1)
        XCTAssertTrue(recs[0].contains("CoreML"))
    }
}
