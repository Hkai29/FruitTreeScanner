import XCTest
@testable import FruitTreeScanner

final class YieldEstimatorTests: XCTestCase {

    func testCalibrationContextTracksParametersAndModelNotRandomIDs() throws {
        let params = FruitVarietyParams(category: .apple)
        func context(_ value: FruitVarietyParams, model: String = "model-A") throws -> String {
            try XCTUnwrap(YieldCalibrationContext.make(parameters: ["apple": value], cluster: .default, fusion: .default, color: nil, modelFingerprint: model))
        }
        let original = try context(params)
        XCTAssertEqual(original, try context(FruitVarietyParams(category: .apple)))
        XCTAssertNotEqual(original, try context(params, model: "model-B"))
        var changed = params
        changed.density += 0.1
        let changedContext = try context(changed)
        XCTAssertNotEqual(original, changedContext)
        var record = CalibrationRecord(id: UUID(), treeID: "T", scanDate: Date(), estimatedFruitCount: 10, manualFruitCount: 15, estimatedYieldKg: 1, actualYieldKg: 2, fruitType: "apple")
        record.algorithmRevision = YieldAlgorithmRevision.current
        record.calibrationContext = original
        let matched = YieldCalibrationCorrector.correction(from: [record], fruitCategory: .apple, fruitType: "apple", requiredAlgorithmRevision: YieldAlgorithmRevision.current, requiredContext: original)
        XCTAssertEqual(matched.yieldSampleCount, 1)
        let changedResult = YieldCalibrationCorrector.correction(from: [record], fruitCategory: .apple, fruitType: "apple", requiredAlgorithmRevision: YieldAlgorithmRevision.current, requiredContext: changedContext)
        XCTAssertEqual(changedResult, .neutral)
    }

    func testCalibrationRevisionExcludesLegacyWithoutDeletingIt() throws {
        let legacy = CalibrationRecord(id: UUID(), treeID: "T", scanDate: Date(), estimatedFruitCount: 10, manualFruitCount: 20, estimatedYieldKg: 1, actualYieldKg: 2, fruitType: "apple")
        let data = try JSONEncoder().encode(legacy)
        let restored = try JSONDecoder().decode(CalibrationRecord.self, from: data)
        XCTAssertNil(restored.algorithmRevision)
        let excluded = YieldCalibrationCorrector.correction(from: [restored], fruitCategory: .apple, fruitType: "apple", requiredAlgorithmRevision: YieldAlgorithmRevision.current)
        XCTAssertEqual(excluded, .neutral)
        var current = restored
        current.algorithmRevision = YieldAlgorithmRevision.current
        let accepted = YieldCalibrationCorrector.correction(from: [restored, current], fruitCategory: .apple, fruitType: "apple", requiredAlgorithmRevision: YieldAlgorithmRevision.current)
        XCTAssertEqual(accepted.yieldSampleCount, 1)
        XCTAssertEqual(accepted.yieldFactor, 2)
    }

    func testMergedFusionKeepsSourceCandidateIdentity() {
        let first = UUID(), second = UUID()
        let fruits = [first, second].map { id in
            ValidatedFruit(category: .apple, position: SIMD3<Float>(0, 0, -2), confidence: 1, source: .fused, sourceCandidateIDs: [id])
        }
        let merged = ValidatedFruit.deduplicate3D(fruits)
        XCTAssertEqual(merged.count, 1)
        XCTAssertEqual(Set(merged[0].sourceCandidateIDs), Set([first, second]))
    }

    func testArchitectureAuditMassRematchingDependsOnFruitOrder() {
        let candidates = [(Float(0), Float(0.06)), (Float(0.18), Float(0.10))].map { x, diameter in
            FruitCandidate(position: SIMD3<Float>(x, 0, -2), diameter: diameter, sphericity: 0.9, pointCount: 40, averageColor: SIMD3<Float>(1, 0, 0))
        }
        let fruits = [Float(0.085), Float(0)].enumerated().map { index, x in
            ValidatedFruit(category: .apple, position: SIMD3<Float>(x, 0, -2), confidence: 1, source: .fused, sourceCandidateIDs: [candidates[1 - index].id])
        }
        let params = FruitVarietyParams(category: .apple)
        func estimate(_ fruits: [ValidatedFruit]) -> ScanYieldEstimateHelpers.VisibleYieldEstimate {
            ScanYieldEstimateHelpers.computeYieldFromValidatedFruits(fruits, candidates: candidates, paramsByCategory: ["apple": params], defaultParams: params)
        }
        let a = estimate(fruits), b = estimate(Array(fruits.reversed()))
        print("ARCH_AUDIT rematch forwardKg=\(a.yieldKg) reverseKg=\(b.yieldKg) measured=\(a.massEstimates.count)/\(b.massEstimates.count)")
        // 显式候选关联应使结果不受果实排列顺序影响。
        XCTAssertEqual(a.massEstimates.count, 2)
        XCTAssertEqual(b.massEstimates.count, 2)
        XCTAssertEqual(a.yieldKg, b.yieldKg, accuracy: 0.000001)
    }

    func testArchitectureAuditHighQualityWithoutAnyMeasuredMass() {
        let fruits = (0..<6).map { i in
            ValidatedFruit(category: .apple, position: SIMD3<Float>(Float(i), 0, -2), confidence: 1, source: .fused, measuredDiameter: 0.06)
        }
        let params = FruitVarietyParams(category: .apple)
        let result = ScanYieldEstimateHelpers.computeYieldFromValidatedFruits(fruits, candidates: [], paramsByCategory: ["apple": params], defaultParams: params)
        let quality = ScanYieldEstimateHelpers.estimateQuality(for: fruits, massEstimate: result)
        print("ARCH_AUDIT fallback massKg=\(result.yieldKg) measured=\(result.massEstimates.count) meanDiameter=\(result.meanDiameterCm) confidence=\(quality.confidence)")
        XCTAssertGreaterThan(result.yieldKg, 0)
        XCTAssertTrue(result.massEstimates.isEmpty)
        XCTAssertEqual(result.meanDiameterCm, 0)
        XCTAssertEqual(quality.confidence, "manual_review")
    }

    func testDeepAuditPearMassChangesUnderRigidRotation() {
        var points: [SIMD3<Float>] = []
        for latitude in 1..<20 {
            let theta = Float(latitude) * Float.pi / 20
            for longitude in 0..<40 {
                let phi = Float(longitude) * 2 * Float.pi / 40
                points.append(SIMD3<Float>(0.02 * sin(theta) * cos(phi), 0.05 * cos(theta), 0.02 * sin(theta) * sin(phi)))
            }
        }
        let c = sqrt(Float(0.5))
        let rotated = points.map { SIMD3<Float>(c * ($0.x - $0.y), c * ($0.x + $0.y), $0.z) }
        let a = SimpleFruitGeometryEstimator.estimate(points: points, fruitCategory: .pear, densityGPerCm3: 1, highConfidenceRatio: 1, validDepthRatio: 1)
        let b = SimpleFruitGeometryEstimator.estimate(points: rotated, fruitCategory: .pear, densityGPerCm3: 1, highConfidenceRatio: 1, validDepthRatio: 1)
        print("YIELD_AUDIT rigidRotation originalG=\(a.estimatedWeightG) rotatedG=\(b.estimatedWeightG) ratio=\(b.estimatedWeightG / a.estimatedWeightG)")
        // 同一刚体旋转不应该改变重量。
        XCTAssertEqual(b.estimatedWeightG, a.estimatedWeightG, accuracy: a.estimatedWeightG * 0.01)
        let angle: Float = 0.71
        let rotatedAgain = rotated.map { SIMD3<Float>($0.x, cos(angle) * $0.y - sin(angle) * $0.z, sin(angle) * $0.y + cos(angle) * $0.z) + SIMD3<Float>(25, -30, 40) }
        let moved = SimpleFruitGeometryEstimator.estimate(points: rotatedAgain, fruitCategory: .pear, densityGPerCm3: 1, highConfidenceRatio: 1, validDepthRatio: 1)
        XCTAssertEqual(moved.estimatedWeightG, a.estimatedWeightG, accuracy: a.estimatedWeightG * 0.01)
    }

    func testDeepAuditRepeatedObservationsInflateOcclusionMultiplier() {
        let a = OcclusionCorrector.correctionFactorDetailed(visibleCount: 10, crownRadiusM: 0.3, crownDepthM: 0.4, lidarPenetrationM: 0.5, scanAngleCoverage: 1, visualDetectionCount: 20, lidarDetectionCount: 10)
        let b = OcclusionCorrector.correctionFactorDetailed(visibleCount: 10, crownRadiusM: 0.3, crownDepthM: 0.4, lidarPenetrationM: 0.5, scanAngleCoverage: 1, visualDetectionCount: 30, lidarDetectionCount: 10)
        print("YIELD_AUDIT repeatedFrames twoObservationsK=\(a.k) threeObservationsK=\(b.k) ratio=\(b.k / a.k)")
        XCTAssertEqual(b.k, a.k, accuracy: 0.0001)
    }

    func testDeepAuditNearbySmallStrawberriesMergedWithoutMeasuredSize() {
        let fruits = [Float(0), 0.022].map { x in
            ValidatedFruit(category: .strawberry, position: SIMD3<Float>(x, 0, -2), confidence: 0.99, source: .fused, measuredDiameter: 0.02)
        }
        let result = ValidatedFruit.deduplicate3D(fruits)
        print("YIELD_AUDIT adjacentStrawberries separationM=0.022 input=2 output=\(result.count)")
        XCTAssertEqual(result.count, 2)
        let duplicate = ValidatedFruit(category: .strawberry, position: SIMD3<Float>(0.003, 0, -2), confidence: 0.98, source: .fused, measuredDiameter: 0.02)
        let withRepeatedObservation = ValidatedFruit.deduplicate3D(fruits + [duplicate])
        XCTAssertEqual(withRepeatedObservation.count, 2)
        XCTAssertTrue(withRepeatedObservation.allSatisfy { $0.measuredDiameter == 0.02 })
    }

    func testRegressionWorldTranslationMustNotEraseMeasuredFruit() {
        var points: [SIMD3<Float>] = []
        for x: Float in [-0.02, 0.02] {
            for y: Float in [-0.05, 0.05] {
                for z: Float in [-0.02, 0.02] { points.append(SIMD3<Float>(x, y, z)) }
            }
        }
        let a = SimpleFruitGeometryEstimator.estimate(points: points, fruitCategory: .pear, densityGPerCm3: 1, highConfidenceRatio: 1, validDepthRatio: 1)
        let b = SimpleFruitGeometryEstimator.estimate(points: points.map { $0 + SIMD3<Float>(25, 0, 0) }, fruitCategory: .pear, densityGPerCm3: 1, highConfidenceRatio: 1, validDepthRatio: 1)
        print("DEEP_REVIEW translated mass origin=\(a.estimatedWeightG) shifted=\(b.estimatedWeightG)")
        XCTAssertEqual(a.estimatedWeightG, b.estimatedWeightG, accuracy: 0.01, "A world origin change must not change fruit mass")
    }

    func testRegressionMixedCandidateMustPreserveMeasuredGeometry() throws {
        var points: [SIMD3<Float>] = []
        for _ in 0..<10 {
            for x: Float in [-0.02, 0.02] {
                for y: Float in [-0.05, 0.05] {
                    for z: Float in [-0.02, 0.02] { points.append(SIMD3<Float>(x, y, 2 + z)) }
                }
            }
        }
        let cloud = FruitCandidate(position: SIMD3<Float>(0, 0, 2), diameter: 0.10,
            sphericity: 0.8, pointCount: points.count, averageColor: SIMD3<Float>(1, 0.7, 0), points: points)
        let roi = FruitCandidate(position: cloud.position, diameter: cloud.diameter,
            sphericity: cloud.sphericity, pointCount: 8, averageColor: cloud.averageColor,
            points: [], sourceCategory: .pear, depthSupportRatio: 0.8)
        let merged = try XCTUnwrap(CandidateCombiner.combine(pointCloudCandidates: [cloud], detectionDepthCandidates: [roi]).first)
        let before = SimpleFruitGeometryEstimator.estimate(candidate: cloud, fruitCategory: .pear, densityGPerCm3: 1)
        let after = SimpleFruitGeometryEstimator.estimate(candidate: merged, fruitCategory: .pear, densityGPerCm3: 1)
        print("DEEP_REVIEW mixed geometry before=\(before.estimatedWeightG)g after=\(after.estimatedWeightG)g points=\(merged.points.count) depthSupport=\(String(describing: merged.depthSupportRatio))")
        XCTAssertEqual(after.estimatedWeightG, before.estimatedWeightG, accuracy: before.estimatedWeightG * 0.05,
                       "Adding agreeing category evidence must not replace measured ellipsoid geometry with a sphere")
    }

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
