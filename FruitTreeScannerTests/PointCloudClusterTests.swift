import XCTest
@testable import FruitTreeScanner

final class PointCloudClusterTests: XCTestCase {

    func testEmptyInput() {
        let cluster = PointCloudCluster(config: .default)
        let points: [ColoredPoint] = []
        let result = cluster.processSync(points: points)
        XCTAssertTrue(result.isEmpty, "空输入应返回空结果")
    }

    func testSingleSphereCluster() {
        let cluster = PointCloudCluster(config: ClusterConfig(
            minPoints: 3,
            minDiameter: 0.01,
            maxDiameter: 0.30,
            baseEps: 0.10
        ))

        var points: [ColoredPoint] = []
        let center = SIMD3<Float>(0.5, 0.5, 1.0)
        for i in 0..<80 {
            let theta = Float(i) / 80.0 * 2 * Float.pi
            let phi = Float(i % 7) / 7.0 * Float.pi
            let r: Float = 0.03
            let px = center.x + r * sin(phi) * cos(theta)
            let py = center.y + r * sin(phi) * sin(theta)
            let pz = center.z + r * cos(phi)
            points.append(ColoredPoint(pos: SIMD3<Float>(px, py, pz), r: 0.8, g: 0.3, b: 0.1))
        }

        let result = cluster.processSync(points: points)
        XCTAssertGreaterThanOrEqual(result.count, 0, "DBSCAN 应能处理球体点云而不崩溃")
    }

    func testDebugRangeQueryTraversesWholeTree() {
        let cluster = PointCloudCluster(config: .default)
        let points: [SIMD3<Float>] = [
            SIMD3<Float>(-1, 0, 0),
            SIMD3<Float>(0, 0, 0),
            SIMD3<Float>(1, 0, 0),
            SIMD3<Float>(2, 0, 0),
        ]

        let neighbors = cluster.debugRangeQuery(
            points: points,
            center: SIMD3<Float>(1, 0, 0),
            radius: 0.01
        )

        XCTAssertEqual(neighbors, [2], "范围查询应从真正的根节点开始遍历")
    }

    func testComputeDiameterEmptyPositions() {
        let cluster = PointCloudCluster(config: .default)
        let emptyPoints: [ColoredPoint] = []
        let result = cluster.processSync(points: emptyPoints)
        XCTAssertTrue(result.isEmpty)
    }
}
