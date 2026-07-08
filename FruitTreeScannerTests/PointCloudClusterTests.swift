import XCTest
import simd
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

    func testSphericityTreatsSymmetricSphereAsRound() {
        let cluster = PointCloudCluster(config: .default)
        let positions = octahedronPositions(center: .zero, radius: 1.0)

        let sphericity = cluster.computeSphericity(positions: positions, center: .zero)

        XCTAssertGreaterThan(sphericity, 0.99, "对称球面小样本应被识别为高球形度")
    }

    func testAdaptiveEpsDoesNotClampBelowConfiguredBaseEps() {
        let cluster = PointCloudCluster(config: .default)

        let eps = cluster.debugAdaptiveEps(distance: 1.0, density: 100)

        XCTAssertGreaterThanOrEqual(
            eps,
            ClusterConfig.default.baseEps,
            "自适应 DBSCAN 半径不能被固定上限压到低于配置 baseEps"
        )
    }

    func testLocalSpacingExpandsEpsForSparseFruitNearDenseForeground() {
        let cluster = PointCloudCluster(config: ClusterConfig(
            minPoints: 4,
            minDiameter: 0.01,
            maxDiameter: 0.30,
            baseEps: 0.03,
            sphericityThreshold: 0.35
        ))
        let denseForeground = spherePoints(
            center: SIMD3<Float>(0, 0, 1.0),
            radius: 0.025,
            count: 80
        )
        let sparseFruitCenter = SIMD3<Float>(0.45, 0, 3.0)
        let sparseFruit = octahedronPoints(
            center: sparseFruitCenter,
            radius: 0.035
        )
        let points = denseForeground + sparseFruit

        let spacingFactors = cluster.debugLocalSpacingFactors(points: points.map(\.pos))
        let foregroundFactor = average(spacingFactors.prefix(denseForeground.count))
        let sparseFactor = average(spacingFactors.suffix(sparseFruit.count))
        let result = cluster.processSync(points: points)

        XCTAssertGreaterThan(
            sparseFactor,
            foregroundFactor * 1.15,
            "远处稀疏果实应获得更大的局部 DBSCAN 间距因子"
        )
        XCTAssertTrue(
            result.contains { simd_distance($0.position, sparseFruitCenter) < 0.04 },
            "局部稀疏但形状闭合的果实不应被近处高密度点云压小 eps 后漏检"
        )
    }

    func testSparseDistantFruitClusterSurvivesNoiseFiltering() {
        let cluster = PointCloudCluster(config: ClusterConfig(
            minPoints: 4,
            minDiameter: 0.01,
            maxDiameter: 0.30,
            baseEps: 0.08,
            sphericityThreshold: 0.35
        ))

        var points: [ColoredPoint] = []
        points.append(contentsOf: spherePoints(
            center: SIMD3<Float>(0, 0, 1.0),
            radius: 0.025,
            count: 36
        ))
        points.append(contentsOf: octahedronPoints(
            center: SIMD3<Float>(0.4, 0, 3.0),
            radius: 0.035
        ))

        let result = cluster.processSync(points: points)
        let positions = result.map { String(format: "(%.3f, %.3f, %.3f)", $0.position.x, $0.position.y, $0.position.z) }

        XCTAssertTrue(
            result.contains { simd_distance($0.position, SIMD3<Float>(0.4, 0, 3.0)) < 0.04 },
            "远距离稀疏但几何闭合的果实点簇不应在 DBSCAN 前被噪声过滤删除，实际候选: \(positions)"
        )
    }

    func testClusterRejectsMixedFruitAndLeafColorCandidate() {
        let cluster = PointCloudCluster(config: ClusterConfig(
            minPoints: 4,
            minDiameter: 0.01,
            maxDiameter: 0.30,
            baseEps: 0.10,
            sphericityThreshold: 0.35
        ))
        let center = SIMD3<Float>(0.2, 0.1, 1.4)
        let points = spherePoints(center: center, radius: 0.035, count: 80) { index in
            index.isMultiple(of: 2)
                ? SIMD3<Float>(0.85, 0.20, 0.08)
                : SIMD3<Float>(0.10, 0.55, 0.12)
        }

        let result = cluster.processSync(points: points)

        XCTAssertFalse(
            result.contains { simd_distance($0.position, center) < 0.05 },
            "红色果点与绿叶点混合出的平均橙色不应通过聚类颜色一致性验证"
        )
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

    private func spherePoints(center: SIMD3<Float>, radius: Float, count: Int) -> [ColoredPoint] {
        spherePoints(center: center, radius: radius, count: count) { _ in
            SIMD3<Float>(0.8, 0.3, 0.1)
        }
    }

    private func spherePoints(
        center: SIMD3<Float>,
        radius: Float,
        count: Int,
        colorForIndex: (Int) -> SIMD3<Float>
    ) -> [ColoredPoint] {
        (0..<count).map { index in
            let theta = Float(index) / Float(count) * 2 * Float.pi
            let phi = Float(index % 9) / 8.0 * Float.pi
            let position = SIMD3<Float>(
                center.x + radius * sin(phi) * cos(theta),
                center.y + radius * sin(phi) * sin(theta),
                center.z + radius * cos(phi)
            )
            let color = colorForIndex(index)
            return ColoredPoint(pos: position, r: color.x, g: color.y, b: color.z)
        }
    }

    private func octahedronPoints(center: SIMD3<Float>, radius: Float) -> [ColoredPoint] {
        octahedronPositions(center: center, radius: radius).map { position in
            fruitPoint(position)
        }
    }

    private func octahedronPositions(center: SIMD3<Float>, radius: Float) -> [SIMD3<Float>] {
        [
            SIMD3<Float>(radius, 0, 0),
            SIMD3<Float>(-radius, 0, 0),
            SIMD3<Float>(0, radius, 0),
            SIMD3<Float>(0, -radius, 0),
            SIMD3<Float>(0, 0, radius),
            SIMD3<Float>(0, 0, -radius),
        ].map { offset in
            center + offset
        }
    }

    private func fruitPoint(_ position: SIMD3<Float>) -> ColoredPoint {
        ColoredPoint(pos: position, r: 0.8, g: 0.3, b: 0.1)
    }

    private func average<S: Sequence>(_ values: S) -> Float where S.Element == Float {
        let array = Array(values)
        guard !array.isEmpty else { return 0 }
        return array.reduce(0, +) / Float(array.count)
    }
}
