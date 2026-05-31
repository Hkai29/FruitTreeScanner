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

        let (fruits, result) = estimator.estimateRouteB(
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
        let (finalKg, confidence, method, _) = estimator.fuse(yieldA: 10, yieldBCorrected: nil)
        XCTAssertEqual(finalKg, 10, "仅 A 时应返回 A 的值")
        XCTAssertEqual(method, "A_only")
    }

    func testFuseOnlyB() {
        let (finalKg, confidence, method, _) = estimator.fuse(yieldA: nil, yieldBCorrected: 15)
        XCTAssertEqual(finalKg, 15, "仅 B 时应返回 B 的值")
        XCTAssertEqual(method, "B_only")
    }

    func testFuseBothClose() {
        let (finalKg, _, method, _) = estimator.fuse(yieldA: 10, yieldBCorrected: 10.5)
        XCTAssertEqual(method, "weighted_AB", "差异小应加权平均")
        XCTAssertGreaterThan(finalKg, 0)
    }

    func testFuseBothFar() {
        let (_, confidence, method, _) = estimator.fuse(yieldA: 5, yieldBCorrected: 20)
        XCTAssertTrue(method == "flagged" || method == "average_AB", "差异大应标记或取均值")
    }

    func testRegressionCoefAccess() {
        let c = estimator.regressionCoef
        XCTAssertEqual(c.count, 6, "回归系数应有6个元素")
    }
}
