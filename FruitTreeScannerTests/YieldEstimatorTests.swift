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

        let trackedQuality = ScanYieldEstimateHelpers.estimateQuality(
            for: [makeFruit(confidence: 0.8, source: .trackedImage)]
        )
        XCTAssertEqual(trackedQuality.confidence, "medium")
        XCTAssertEqual(trackedQuality.methodUsed, "tracked_image_visual_calibrated")
        XCTAssertEqual(trackedQuality.sourceDescription, "多帧视觉轨迹估计")

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

    func testGeometryDimensionsIgnoreSingleOutlierForVolumeEstimate() {
        var points = denseCuboidSurfacePoints(lengthM: 0.10, widthM: 0.08, heightM: 0.06)
        points.append(SIMD3<Float>(1.2, 0, 0))

        let estimate = SimpleFruitGeometryEstimator.estimate(
            points: points,
            fruitCategory: .pear,
            densityGPerCm3: 1,
            highConfidenceRatio: 1,
            validDepthRatio: 1
        )

        XCTAssertEqual(estimate.lengthCm, 10, accuracy: 0.5)
        XCTAssertEqual(estimate.widthCm, 8, accuracy: 0.5)
        XCTAssertEqual(estimate.heightCm, 6, accuracy: 0.5)
        XCTAssertEqual(estimate.selectedVolumeCm3, 251.33, accuracy: 20)
        XCTAssertLessThan(estimate.lengthCm, 12, "单个离群点不应把果实长度放大到包围盒范围")
    }

    func testPartialRoundFruitUsesSphereFitToAvoidOcclusionUnderestimate() {
        let points = partialSphereSurfacePoints(center: SIMD3<Float>(0, 0, 0), radiusM: 0.05)

        let estimate = SimpleFruitGeometryEstimator.estimate(
            points: points,
            fruitCategory: .apple,
            densityGPerCm3: 1,
            highConfidenceRatio: 0.9,
            validDepthRatio: 0.7
        )

        XCTAssertEqual(estimate.equivalentDiameterCm, 10, accuracy: 0.25)
        XCTAssertEqual(estimate.lengthCm, 10, accuracy: 0.25)
        XCTAssertEqual(estimate.heightCm, 10, accuracy: 0.25)
        XCTAssertEqual(estimate.selectedVolumeCm3, 523.6, accuracy: 8)
        XCTAssertEqual(estimate.shapeModelUsed, .sphere)
    }

    func testSphereFitRejectsPlanarRoundFruitEvidence() {
        let points = planarCirclePoints(center: SIMD3<Float>(0, 0, 0), radiusM: 0.05)

        let estimate = SimpleFruitGeometryEstimator.estimate(
            points: points,
            fruitCategory: .apple,
            densityGPerCm3: 1,
            highConfidenceRatio: 0.9,
            validDepthRatio: 0.7
        )

        XCTAssertLessThan(estimate.heightCm, 0.01)
        XCTAssertEqual(estimate.shapeModelUsed, .unavailable)
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

    func testResearchCSVUsesStableDecimalFormatting() {
        let estimate = FruitMassEstimate(
            id: UUID(),
            fruitCategory: "apple",
            lengthCm: 1.25,
            widthCm: 2.5,
            heightCm: 3.75,
            equivalentDiameterCm: 2.25,
            sphereVolumeCm3: 4.5,
            ellipsoidVolumeCm3: 5.25,
            selectedVolumeCm3: 5.25,
            densityGPerCm3: 0.95,
            estimatedWeightG: 12.3456,
            confidenceScore: 0.75,
            pointCount: 12,
            highConfidenceRatio: 0.8,
            validDepthRatio: 0.9,
            shapeModelUsed: .sphere,
            warningFlags: [],
            createdAt: Date(timeIntervalSince1970: 0)
        )

        let csv = ResearchCSVExporter.makeCSV(
            estimates: [estimate],
            groundTruthByID: [estimate.id: FruitMassEstimateGroundTruth(trueWeightG: 12.3, trueVolumeCm3: 45.6)]
        )

        XCTAssertTrue(csv.contains("1.2500"))
        XCTAssertTrue(csv.contains("12.3456"))
        XCTAssertTrue(csv.contains("12.3000,45.6000"))
        XCTAssertFalse(csv.contains("12,3456"))
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

    func testVisibleYieldEstimateDownWeightsLowConfidenceFusedEvidence() {
        let candidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 1),
            diameter: 0.10,
            sphericity: 0.9,
            pointCount: 40,
            averageColor: SIMD3<Float>(0.8, 0.2, 0.1)
        )
        let highConfidenceFruit = ValidatedFruit(
            category: .apple,
            position: SIMD3<Float>(0, 0, 1),
            confidence: 1.0,
            source: .fused
        )
        let lowConfidenceFruit = ValidatedFruit(
            category: .apple,
            position: SIMD3<Float>(0, 0, 1),
            confidence: 0.5,
            source: .fused
        )
        let params = [FruitCategory.apple.rawValue: FruitVarietyParams(category: .apple)]
        let defaultParams = FruitVarietyParams(category: .apple)

        let highEstimate = ScanYieldEstimateHelpers.computeYieldFromValidatedFruits(
            [highConfidenceFruit],
            candidates: [candidate],
            paramsByCategory: params,
            defaultParams: defaultParams
        )
        let lowEstimate = ScanYieldEstimateHelpers.computeYieldFromValidatedFruits(
            [lowConfidenceFruit],
            candidates: [candidate],
            paramsByCategory: params,
            defaultParams: defaultParams
        )

        XCTAssertGreaterThan(highEstimate.yieldKg, 0)
        XCTAssertEqual(lowEstimate.yieldKg, highEstimate.yieldKg * 0.5, accuracy: 0.001)
        XCTAssertEqual(lowEstimate.meanDiameterCm, highEstimate.meanDiameterCm, accuracy: 0.001)
    }

    func testROICandidateMassEstimateUsesDiameterInsteadOfPlanarDepthSamples() {
        let candidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 1),
            diameter: 0.10,
            sphericity: 0.9,
            pointCount: 49,
            averageColor: SIMD3<Float>(0.8, 0.2, 0.1),
            points: cuboidPoints(lengthM: 0.01, widthM: 0.01, heightM: 0),
            sourceCategory: .apple
        )

        let estimate = SimpleFruitGeometryEstimator.estimate(
            candidate: candidate,
            fruitCategory: .apple,
            densityGPerCm3: 1,
            highConfidenceRatio: 0.9,
            validDepthRatio: 1
        )

        XCTAssertEqual(estimate.equivalentDiameterCm, 10, accuracy: 0.001)
        XCTAssertEqual(estimate.shapeModelUsed, .sphere)
        XCTAssertTrue(estimate.warningFlags.contains(.usingSphereBaseline))
    }

    func testROICandidateMassEstimateUsesDepthSupportRatioForQuality() {
        let candidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 1),
            diameter: 0.10,
            sphericity: 0.9,
            pointCount: 49,
            averageColor: SIMD3<Float>(0.8, 0.2, 0.1),
            sourceCategory: .apple,
            depthSupportRatio: 0.2
        )

        let estimate = SimpleFruitGeometryEstimator.estimate(
            candidate: candidate,
            fruitCategory: .apple,
            densityGPerCm3: 1,
            highConfidenceRatio: 0.9,
            validDepthRatio: 1
        )

        XCTAssertEqual(estimate.validDepthRatio, 0.2, accuracy: 0.001)
        XCTAssertTrue(estimate.warningFlags.contains(.lowValidDepthRatio))
        XCTAssertLessThanOrEqual(estimate.confidenceScore, 0.55)
    }

    func testYieldEstimateMatchesROICandidateByCategoryBeforeDistance() {
        let appleFruit = ValidatedFruit(
            category: .apple,
            position: SIMD3<Float>(0, 0, 1),
            confidence: 0.9,
            source: .fused
        )
        let nearerOrangeCandidate = FruitCandidate(
            position: SIMD3<Float>(0, 0, 1),
            diameter: 0.06,
            sphericity: 0.9,
            pointCount: 49,
            averageColor: SIMD3<Float>(0.95, 0.48, 0.1),
            sourceCategory: .orange
        )
        let appleCandidate = FruitCandidate(
            position: SIMD3<Float>(0.02, 0, 1),
            diameter: 0.10,
            sphericity: 0.9,
            pointCount: 49,
            averageColor: SIMD3<Float>(0.8, 0.2, 0.1),
            sourceCategory: .apple
        )

        let visibleEstimate = ScanYieldEstimateHelpers.computeYieldFromValidatedFruits(
            [appleFruit],
            candidates: [nearerOrangeCandidate, appleCandidate],
            paramsByCategory: [
                FruitCategory.apple.rawValue: FruitVarietyParams(category: .apple),
                FruitCategory.orange.rawValue: FruitVarietyParams(category: .orange)
            ],
            defaultParams: FruitVarietyParams(category: .apple)
        )

        XCTAssertEqual(visibleEstimate.massEstimates.count, 1)
        XCTAssertEqual(visibleEstimate.massEstimates[0].equivalentDiameterCm, 10, accuracy: 0.001)
        XCTAssertEqual(visibleEstimate.massEstimates[0].fruitCategory, "apple")
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

    private func denseCuboidSurfacePoints(lengthM: Float, widthM: Float, heightM: Float) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for xIndex in 0...10 {
            let x = lengthM * Float(xIndex) / 10
            for yIndex in 0...8 {
                let y = widthM * Float(yIndex) / 8
                for zIndex in 0...6 {
                    let z = heightM * Float(zIndex) / 6
                    let isSurface = xIndex == 0 || xIndex == 10 ||
                        yIndex == 0 || yIndex == 8 ||
                        zIndex == 0 || zIndex == 6
                    if isSurface {
                        points.append(SIMD3<Float>(x, y, z))
                    }
                }
            }
        }
        return points
    }

    private func partialSphereSurfacePoints(center: SIMD3<Float>, radiusM: Float) -> [SIMD3<Float>] {
        var points: [SIMD3<Float>] = []
        for polarIndex in 0...8 {
            let phi = Float(polarIndex) / 8 * Float.pi
            for azimuthIndex in 0..<16 {
                let theta = Float(azimuthIndex) / 16 * 2 * Float.pi
                let x = radiusM * sin(phi) * cos(theta)
                let y = radiusM * cos(phi)
                let z = radiusM * sin(phi) * sin(theta)
                guard z >= -0.001 else { continue }
                points.append(center + SIMD3<Float>(x, y, z))
            }
        }
        return points
    }

    private func planarCirclePoints(center: SIMD3<Float>, radiusM: Float) -> [SIMD3<Float>] {
        (0..<48).map { index in
            let theta = Float(index) / 48 * 2 * Float.pi
            return center + SIMD3<Float>(
                radiusM * cos(theta),
                radiusM * sin(theta),
                0
            )
        }
    }
}
