import XCTest
@testable import FruitTreeScanner

final class YieldEstimatorTests: XCTestCase {

    private var estimator: YieldEstimator!

    override func setUp() {
        estimator = YieldEstimator()
    }

    override func tearDown() {
        estimator = nil
    }

    func testEstimateRouteBFewPoints() {
        var points: [ColoredPoint] = []
        for i in 0..<5 {
            points.append(ColoredPoint(pos: SIMD3<Float>(Float(i) * 0.01, 0, 1), r: 0.8, g: 0.3, b: 0.1))
        }
        let (fruits, result) = estimator.estimateRouteB(
            points: points,
            fruitCategory: .apple,
            nVisual: nil
        )
        XCTAssertTrue(fruits.isEmpty, "点数不足应返回空")
        XCTAssertNotNil(result.note, "应有说明")
    }

    func testEstimateRouteBNoVisualCorrection() {
        var points: [ColoredPoint] = []
        let center = SIMD3<Float>(0.5, 0.5, 1.0)
        let radius: Float = 0.04
        for i in 0..<30 {
            let angle = Float(i) / 30.0 * 2 * Float.pi
            let px = center.x + radius * cos(angle)
            let py = center.y + radius * sin(angle)
            points.append(ColoredPoint(pos: SIMD3<Float>(px, py, center.z), r: 0.8, g: 0.3, b: 0.1))
        }

        let (_, result) = estimator.estimateRouteB(
            points: points,
            fruitCategory: .apple,
            nVisual: nil
        )
        XCTAssertEqual(result.correctionK, 1.0, "nVisual=nil 时 k 应为 1.0")
    }

    func testFuseBothNil() {
        let (finalKg, confidence, method, _) = estimator.fuse(yieldA: nil, yieldBCorrected: nil)
        XCTAssertEqual(finalKg, 0, "双 nil 应返回 0")
        XCTAssertEqual(confidence, "low")
        XCTAssertEqual(method, "none")
    }

    func testFuseOnlyA() {
        let (finalKg, _, method, _) = estimator.fuse(yieldA: 10, yieldBCorrected: nil)
        XCTAssertEqual(finalKg, 10, "仅 A 时应返回 A 的值")
        XCTAssertEqual(method, "A_only")
    }

    func testFuseOnlyB() {
        let (finalKg, _, method, _) = estimator.fuse(yieldA: nil, yieldBCorrected: 15)
        XCTAssertEqual(finalKg, 15, "仅 B 时应返回 B 的值")
        XCTAssertEqual(method, "B_only")
    }

    func testFuseBothClose() {
        let (finalKg, _, method, _) = estimator.fuse(yieldA: 10, yieldBCorrected: 10.5)
        XCTAssertEqual(method, "weighted_AB", "差异小应加权平均")
        XCTAssertGreaterThan(finalKg, 0)
    }

    func testFuseBothFar() {
        let (_, _, method, _) = estimator.fuse(yieldA: 5, yieldBCorrected: 20)
        XCTAssertTrue(method == "flagged" || method == "average_AB", "差异大应标记或取均值")
    }

    func testRegressionCoefAccess() {
        let c = estimator.regressionCoef
        XCTAssertEqual(c.count, 6, "回归系数应有6个元素")
    }

    func testRunOffSeasonSkipsRouteB() {
        var points: [ColoredPoint] = []
        let center = SIMD3<Float>(0.5, 0.5, 1.0)
        let radius: Float = 0.04
        for i in 0..<30 {
            let angle = Float(i) / 30.0 * 2 * Float.pi
            points.append(ColoredPoint(
                pos: SIMD3<Float>(center.x + radius * cos(angle), center.y + radius * sin(angle), center.z),
                r: 0.8, g: 0.3, b: 0.1
            ))
        }

        let (fruits, result) = estimator.run(
            points: points,
            fruitCategory: .apple,
            nVisual: 5,
            dbhCm: 15, heightM: 3, crownVolM3: 5, dEW: 3, dNS: 3,
            season: .off
        )

        XCTAssertTrue(fruits.isEmpty, "off-season 应跳过路线B")
        XCTAssertEqual(result.fruitCategory, "")
        XCTAssertEqual(result.nLidar, 0)
    }

    func testRunNilFruitCategorySkipsRouteB() {
        var points: [ColoredPoint] = []
        let center = SIMD3<Float>(0.5, 0.5, 1.0)
        let radius: Float = 0.04
        for i in 0..<30 {
            let angle = Float(i) / 30.0 * 2 * Float.pi
            points.append(ColoredPoint(
                pos: SIMD3<Float>(center.x + radius * cos(angle), center.y + radius * sin(angle), center.z),
                r: 0.8, g: 0.3, b: 0.1
            ))
        }

        let (fruits, _) = estimator.run(
            points: points,
            fruitCategory: nil,
            nVisual: 5,
            season: .mature
        )

        XCTAssertTrue(fruits.isEmpty, "nil fruitCategory 应跳过路线B")
    }

    func testFuseFarDifferenceManualReview() {
        let (_, confidence, method, note) = estimator.fuse(yieldA: 5, yieldBCorrected: 20)
        XCTAssertEqual(confidence, "manual_review")
        XCTAssertEqual(method, "flagged")
        XCTAssertTrue(note.contains("需人工复核"))
    }

    func testFuseMediumDifferenceAverage() {
        let (finalKg, confidence, method, _) = estimator.fuse(yieldA: 10, yieldBCorrected: 14)
        XCTAssertEqual(confidence, "medium")
        XCTAssertEqual(method, "average_AB")
        let expectedMean = (10 + 14) / 2.0
        XCTAssertEqual(Double(finalKg), Double(expectedMean), accuracy: 0.1)
    }

    func testRunReturnsCorrectConfidenceForSeasonMatureWithCategory() {
        var points: [ColoredPoint] = []
        let center = SIMD3<Float>(0.5, 0.5, 1.0)
        let radius: Float = 0.04
        for i in 0..<40 {
            let angle = Float(i) / 40.0 * 2 * Float.pi
            points.append(ColoredPoint(
                pos: SIMD3<Float>(center.x + radius * cos(angle), center.y + radius * sin(angle), center.z),
                r: 0.8, g: 0.3, b: 0.1
            ))
        }

        let (_, result) = estimator.run(
            points: points,
            fruitCategory: .apple,
            nVisual: nil,
            season: .mature
        )

        XCTAssertFalse(result.methodUsed.isEmpty)
        XCTAssertFalse(result.confidence.isEmpty)
    }

    func testRegressionCoefDefaults() {
        let c = estimator.regressionCoef
        for i in 0..<6 {
            XCTAssertEqual(c[i], 0, "未训练时回归系数 \(i) 应为 0")
        }
        XCTAssertFalse(estimator.regressionTrained)
    }

    func testScanYieldEstimateQualityKeepsSourceBasedRouting() {
        let fusedHigh = [
            makeFruit(confidence: 0.9, source: .fused),
            makeFruit(confidence: 0.9, source: .fused),
            makeFruit(confidence: 0.9, source: .fused),
            makeFruit(confidence: 0.9, source: .fused),
            makeFruit(confidence: 0.9, source: .fused),
            makeFruit(confidence: 0.9, source: .fused)
        ]
        let fusedQuality = ScanYieldEstimateHelpers.estimateQuality(for: fusedHigh)
        XCTAssertEqual(fusedQuality.confidence, "high")
        XCTAssertEqual(fusedQuality.methodUsed, "fusion_visual_calibrated")
        XCTAssertEqual(fusedQuality.sourceDescription, "RGB+LiDAR 融合检测")

        let imageQuality = ScanYieldEstimateHelpers.estimateQuality(
            for: [makeFruit(confidence: 0.8, source: .imageOnly)]
        )
        XCTAssertEqual(imageQuality.confidence, "medium")
        XCTAssertEqual(imageQuality.methodUsed, "image_visual_calibrated")
        XCTAssertEqual(imageQuality.sourceDescription, "视觉检测估计")

        let cloudQuality = ScanYieldEstimateHelpers.estimateQuality(
            for: [makeFruit(confidence: 0.8, source: .cloudOnly)]
        )
        XCTAssertEqual(cloudQuality.confidence, "low")
        XCTAssertEqual(cloudQuality.methodUsed, "cloud_only_calibrated")
        XCTAssertEqual(cloudQuality.sourceDescription, "点云候选估计")
    }

    func testTenCentimeterSphereVolumeBaseline() {
        let estimate = SimpleFruitGeometryEstimator.estimateFromDiameter(
            diameterM: 0.10,
            fruitCategory: .apple,
            densityGPerCm3: 1,
            pointCount: 40,
            highConfidenceRatio: 1,
            validDepthRatio: 1
        )

        XCTAssertEqual(estimate.sphereVolumeCm3, 523.6, accuracy: 0.2)
        XCTAssertEqual(estimate.selectedVolumeCm3, estimate.sphereVolumeCm3, accuracy: 0.001)
        XCTAssertEqual(estimate.shapeModelUsed, .sphere)
    }

    func testTenEightSixCentimeterEllipsoidVolume() {
        let estimate = SimpleFruitGeometryEstimator.estimate(
            points: cuboidPoints(lengthM: 0.10, widthM: 0.08, heightM: 0.06),
            fruitCategory: .pear,
            densityGPerCm3: 1,
            highConfidenceRatio: 1,
            validDepthRatio: 1
        )

        XCTAssertEqual(estimate.ellipsoidVolumeCm3, 251.33, accuracy: 0.2)
        XCTAssertEqual(estimate.selectedVolumeCm3, estimate.ellipsoidVolumeCm3, accuracy: 0.001)
        XCTAssertEqual(estimate.shapeModelUsed, .ellipsoid)
    }

    func testTooFewPointsWarning() {
        let estimate = SimpleFruitGeometryEstimator.estimate(
            points: [SIMD3<Float>(0, 0, 0)],
            fruitCategory: .apple,
            densityGPerCm3: 1,
            highConfidenceRatio: 1,
            validDepthRatio: 1
        )

        XCTAssertTrue(estimate.warningFlags.contains(.tooFewPoints))
    }

    func testSmallFruitWarning() {
        let estimate = SimpleFruitGeometryEstimator.estimateFromDiameter(
            diameterM: 0.02,
            fruitCategory: .cherry,
            densityGPerCm3: 1,
            pointCount: 40,
            highConfidenceRatio: 1,
            validDepthRatio: 1
        )

        XCTAssertTrue(estimate.warningFlags.contains(.smallFruitLowLiDARReliability))
    }

    func testLowDepthQualityLowersConfidenceAndAddsWarnings() {
        let estimate = SimpleFruitGeometryEstimator.estimate(
            points: cuboidPoints(lengthM: 0.08, widthM: 0.08, heightM: 0.08),
            fruitCategory: .apple,
            densityGPerCm3: 1,
            highConfidenceRatio: 0.2,
            validDepthRatio: 0.3
        )

        XCTAssertTrue(estimate.warningFlags.contains(.lowDepthConfidence))
        XCTAssertTrue(estimate.warningFlags.contains(.lowValidDepthRatio))
        XCTAssertLessThanOrEqual(estimate.confidenceScore, 0.55)
    }

    func testResearchCSVHeaderIncludesEstimateAndGroundTruthFields() {
        let estimate = SimpleFruitGeometryEstimator.estimateFromDiameter(
            diameterM: 0.10,
            fruitCategory: .apple,
            densityGPerCm3: 1,
            pointCount: 40,
            highConfidenceRatio: 1,
            validDepthRatio: 1
        )

        let csv = ResearchCSVExporter.makeCSV(estimates: [estimate])
        let header = csv.components(separatedBy: .newlines)[0]

        XCTAssertTrue(header.contains("estimatedWeightG"))
        XCTAssertTrue(header.contains("confidenceScore"))
        XCTAssertTrue(header.contains("trueWeightG"))
        XCTAssertTrue(header.contains("trueVolumeCm3"))
    }

    func testResearchCSVNeutralizesTextFormulaPrefixesWithoutChangingNegativeNumbers() {
        let estimate = FruitMassEstimate(
            id: UUID(),
            fruitCategory: "=CMD()",
            lengthCm: 1,
            widthCm: 2,
            heightCm: 3,
            equivalentDiameterCm: 2,
            sphereVolumeCm3: 4,
            ellipsoidVolumeCm3: 5,
            selectedVolumeCm3: 5,
            densityGPerCm3: 1,
            estimatedWeightG: -12.5,
            confidenceScore: 0.5,
            pointCount: 12,
            highConfidenceRatio: 0.8,
            validDepthRatio: 0.9,
            shapeModelUsed: .sphere,
            warningFlags: [.usingSphereBaseline],
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let csv = ResearchCSVExporter.makeCSV(estimates: [estimate])

        XCTAssertTrue(csv.contains("'=CMD()"))
        XCTAssertTrue(csv.contains("-12.5000"))
    }

    func testResearchCSVOmitsInvalidGroundTruthValues() {
        let negativeID = UUID()
        let zeroID = UUID()
        let negativeEstimate = makeMassEstimate(id: negativeID)
        let zeroEstimate = makeMassEstimate(id: zeroID)

        let csv = ResearchCSVExporter.makeCSV(
            estimates: [negativeEstimate, zeroEstimate],
            groundTruthByID: [
                negativeID: FruitMassEstimateGroundTruth(trueWeightG: -1, trueVolumeCm3: -.infinity),
                zeroID: FruitMassEstimateGroundTruth(trueWeightG: 0, trueVolumeCm3: 0)
            ]
        )
        let rows = csv.components(separatedBy: .newlines).filter { !$0.isEmpty }

        XCTAssertEqual(rows.count, 3)
        XCTAssertTrue(rows[1].hasSuffix(",,"))
        XCTAssertTrue(rows[2].hasSuffix(",0.0000,0.0000"))
        XCTAssertFalse(csv.contains("-1.0000"))
        XCTAssertFalse(csv.lowercased().contains("inf"))
    }

    func testConfidenceScoreIsClampedToUnitRange() {
        let estimate = SimpleFruitGeometryEstimator.estimate(
            points: cuboidPoints(lengthM: 0.08, widthM: 0.08, heightM: 0.08),
            fruitCategory: .apple,
            densityGPerCm3: 1,
            highConfidenceRatio: 8,
            validDepthRatio: -2
        )

        XCTAssertGreaterThanOrEqual(estimate.confidenceScore, 0)
        XCTAssertLessThanOrEqual(estimate.confidenceScore, 1)
    }

    func testCandidateOnlyYieldEstimateCreatesSphereBaselineMassEstimate() {
        let candidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 1),
            diameter: 0.10,
            sphericity: 0.9,
            pointCount: 40,
            averageColor: SIMD3<Float>(0.8, 0.2, 0.1)
        )
        let validatedFruit = ValidatedFruit(
            category: .apple,
            position: SIMD3<Float>(0, 0, 1),
            confidence: 0.9,
            source: .fused
        )

        let visibleEstimate = ScanYieldEstimateHelpers.computeYieldFromValidatedFruits(
            [validatedFruit],
            candidates: [candidate],
            paramsByCategory: [FruitCategory.apple.rawValue: FruitVarietyParams(category: .apple)],
            defaultParams: FruitVarietyParams(category: .apple)
        )

        XCTAssertEqual(visibleEstimate.massEstimates.count, 1)
        XCTAssertEqual(visibleEstimate.massEstimates[0].shapeModelUsed, .sphere)
        XCTAssertTrue(visibleEstimate.massEstimates[0].warningFlags.contains(.usingSphereBaseline))
    }

    private func makeFruit(confidence: Float, source: ValidationSource) -> ValidatedFruit {
        ValidatedFruit(
            category: .apple,
            position: SIMD3<Float>(0, 0, 0),
            confidence: confidence,
            source: source
        )
    }

    private func makeMassEstimate(id: UUID = UUID()) -> FruitMassEstimate {
        FruitMassEstimate(
            id: id,
            fruitCategory: "apple",
            lengthCm: 1,
            widthCm: 2,
            heightCm: 3,
            equivalentDiameterCm: 2,
            sphereVolumeCm3: 4,
            ellipsoidVolumeCm3: 5,
            selectedVolumeCm3: 5,
            densityGPerCm3: 1,
            estimatedWeightG: 12.5,
            confidenceScore: 0.5,
            pointCount: 12,
            highConfidenceRatio: 0.8,
            validDepthRatio: 0.9,
            shapeModelUsed: .sphere,
            warningFlags: [.usingSphereBaseline],
            createdAt: Date(timeIntervalSince1970: 0)
        )
    }

    private func cuboidPoints(lengthM: Float, widthM: Float, heightM: Float) -> [SIMD3<Float>] {
        let corners = [
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(lengthM, 0, 0),
            SIMD3<Float>(0, widthM, 0),
            SIMD3<Float>(0, 0, heightM),
            SIMD3<Float>(lengthM, widthM, 0),
            SIMD3<Float>(lengthM, 0, heightM),
            SIMD3<Float>(0, widthM, heightM),
            SIMD3<Float>(lengthM, widthM, heightM),
        ]
        return Array(repeating: corners, count: 3).flatMap { $0 }
    }
}
