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

    // MARK: - Point-cloud candidate contracts (original implementation baseline)

    func testPointCloudPipelineExplicitFilterOverridesCategoryAndKeepsPointOrder() async {
        let points = filterContractPoints()
        let result = await PointCloudCandidatePipeline().run(pipelineInput(
            points: points, category: .blueberry, filter: ColorFilter(rMin: 0.6)
        ))

        XCTAssertEqual(result.colorFilteredPoints.map(\.pos), [points[0].pos, points[2].pos])
        XCTAssertEqual(result.clusteringPoints.map(\.pos), [points[0].pos, points[2].pos])
        XCTAssertEqual(result.denoising.samples.map(\.r), [points[0].r, points[2].r])
        XCTAssertEqual(result.denoising.stats.originalCount, 2)
        XCTAssertEqual(result.denoising.stats.retainedCount, 2)
        XCTAssertEqual(result.denoising.stats.threshold, 0)
        XCTAssertTrue(result.candidates.isEmpty)
    }

    func testPointCloudPipelineCategoryFallbackAndNilFilterRetainEstablishedPoints() async {
        let points = filterContractPoints()
        let category = await PointCloudCandidatePipeline().run(pipelineInput(points: points, category: .blueberry))
        XCTAssertEqual(category.colorFilteredPoints.map(\.pos), [points[1].pos])
        XCTAssertEqual(category.clusteringPoints.map(\.pos), [points[1].pos])

        let unfiltered = await PointCloudCandidatePipeline().run(pipelineInput(points: points))
        XCTAssertEqual(unfiltered.colorFilteredPoints.map(\.pos), points.map(\.pos))
        XCTAssertEqual(unfiltered.clusteringPoints.map(\.r), points.map(\.r))
        XCTAssertEqual(unfiltered.denoising.stats.originalCount, 3)
        XCTAssertEqual(unfiltered.denoising.stats.removedCount, 0)
    }

    func testPointCloudPipelineDenoisingStartsAtMaxConfiguredMinimum() async {
        let config = ClusterConfig(minPoints: 1, minDiameter: 0.01, maxDiameter: 0.30, baseEps: 0.10)
        for (multiplier, floor) in [(5, 3), (3, 5)] {
            var experiment = PointCloudExperimentConfig()
            experiment.denoisingMinPointMultiplier = multiplier
            experiment.denoisingMinPointFloor = floor
            experiment.denoisingNeighborCount = 1
            experiment.denoisingStdMultiplier = 1

            let belowPoints = denoisingBoundaryPoints(inlierCount: 3)
            let below = await PointCloudCandidatePipeline().run(pipelineInput(
                points: belowPoints, config: config, experiment: experiment
            ))
            XCTAssertEqual(below.clusteringPoints.map(\.pos), belowPoints.map(\.pos))
            XCTAssertEqual(below.denoising.stats.originalCount, 4)
            XCTAssertEqual(below.denoising.stats.retainedCount, 4)
            XCTAssertEqual(below.denoising.stats.meanNeighborDistance, 0)
            XCTAssertEqual(below.denoising.stats.neighborDistanceStd, 0)
            XCTAssertEqual(below.denoising.stats.threshold, 0)

            let atPoints = denoisingBoundaryPoints(inlierCount: 4)
            let at = await PointCloudCandidatePipeline().run(pipelineInput(
                points: atPoints, config: config, experiment: experiment
            ))
            XCTAssertEqual(at.colorFilteredPoints.map(\.pos), atPoints.map(\.pos))
            XCTAssertEqual(at.clusteringPoints.map(\.r), atPoints.prefix(4).map(\.r))
            XCTAssertEqual(at.denoising.stats.originalCount, 5)
            XCTAssertEqual(at.denoising.stats.retainedCount, 4)
            XCTAssertEqual(at.denoising.stats.meanNeighborDistance, 2, accuracy: 0.00001)
            XCTAssertEqual(at.denoising.stats.neighborDistanceStd, 4, accuracy: 0.00001)
            XCTAssertEqual(at.denoising.stats.threshold, 6, accuracy: 0.00001)
            XCTAssertEqual(at.denoising.stats.removalRatio, 0.2, accuracy: 0.00001)
        }
    }

    func testGenericDenoisingKPlusOneGuardAndOrderedNumericStatistics() {
        let positions = [SIMD3<Float>(0, 0, 0), SIMD3<Float>(10, 0, 0), SIMD3<Float>(0, 0, 0)]
        let small = PointCloudDenoiser.statisticalOutlierRemovalDetailed(
            samples: [0, 1], k: 1, stdMultiplier: 1, position: { positions[$0] }
        )
        XCTAssertEqual(small.samples, [0, 1])
        XCTAssertEqual(small.stats.originalCount, 2)
        XCTAssertEqual(small.stats.retainedCount, 2)
        XCTAssertEqual(small.stats.threshold, 0)

        let denoised = PointCloudDenoiser.statisticalOutlierRemovalDetailed(
            samples: [0, 1, 2], k: 1, stdMultiplier: 1, position: { positions[$0] }
        )
        XCTAssertEqual(denoised.samples, [0, 2])
        XCTAssertEqual(denoised.stats.originalCount, 3)
        XCTAssertEqual(denoised.stats.retainedCount, 2)
        // Neighbor means are [0, 10, 0]; population mean/std are 10/3 and sqrt(200/9).
        XCTAssertEqual(denoised.stats.meanNeighborDistance, 3.3333333333, accuracy: 0.00001)
        XCTAssertEqual(denoised.stats.neighborDistanceStd, 4.7140452079, accuracy: 0.00001)
        XCTAssertEqual(denoised.stats.threshold, 8.0473785412, accuracy: 0.00001)
    }

    func testPointCloudPipelineAsyncMinimumAndOctahedronGeometry() async throws {
        let points = octahedronPoints(center: SIMD3<Float>(0, 0, 1), radius: 0.03)
        let config = ClusterConfig(minPoints: 6, minDiameter: 0.01, maxDiameter: 0.30,
            baseEps: 0.10, sphericityThreshold: 0.35)
        for incomplete in [[], Array(points.prefix(5))] {
            let output = await PointCloudCandidatePipeline().run(pipelineInput(points: incomplete, config: config))
            XCTAssertEqual(output.clusteringPoints.map(\.pos), incomplete.map(\.pos))
            XCTAssertEqual(output.denoising.stats.retainedCount, incomplete.count)
            XCTAssertTrue(output.candidates.isEmpty)
        }

        let output = await PointCloudCandidatePipeline().run(pipelineInput(points: points, config: config))
        XCTAssertEqual(output.candidates.count, 1)
        let candidate = try XCTUnwrap(output.candidates.first)
        XCTAssertEqual(candidate.pointCount, 6)
        XCTAssertEqual(candidate.position.x, 0, accuracy: 0.00001)
        XCTAssertEqual(candidate.position.y, 0, accuracy: 0.00001)
        XCTAssertEqual(candidate.position.z, 1, accuracy: 0.00001)
        XCTAssertEqual(candidate.diameter, 0.06, accuracy: 0.00001)
        XCTAssertEqual(candidate.sphericity, 1, accuracy: 0.00001)
        XCTAssertEqual(candidate.averageColor.x, 0.8, accuracy: 0.00001)
        XCTAssertEqual(candidate.averageColor.y, 0.3, accuracy: 0.00001)
        XCTAssertEqual(candidate.averageColor.z, 0.1, accuracy: 0.00001)
        XCTAssertEqual(candidate.points, points.map(\.pos))
    }

    func testKDTreeNearestMembershipAndInclusiveRadiusBoundary() {
        let tree = KDTree(points: [-2, 0, 1, 3].map { SIMD3<Float>(Float($0), 0, 0) })
        XCTAssertEqual(Set(tree.kNearest(center: .zero, k: 2)), Set([1, 2]))
        XCTAssertEqual(tree.rangeQuery(center: .zero, radius: 1).sorted(), [1, 2])
        XCTAssertEqual(tree.kNearest(center: .zero, k: 0), [])
        XCTAssertEqual(KDTree(points: []).rangeQuery(center: .zero, radius: 1), [])
    }

    // Typed Domain contract: no Core builder snapshot is needed for the pure pipeline.
    func testDomainPointCloudInputRunsCompleteCandidatePipelineWithoutCoreSnapshot() async throws {
        let points = octahedronPoints(center: SIMD3<Float>(0, 0, 1), radius: 0.03)
        let output = await PointCloudCandidatePipeline().run(PointCloudCandidateInput(
            points: points, colorFilter: nil,
            clusterConfig: ClusterConfig(minPoints: 6, minDiameter: 0.01, maxDiameter: 0.30,
                baseEps: 0.10, sphericityThreshold: 0.35),
            experimentConfiguration: PointCloudExperimentConfig()
        ))

        XCTAssertEqual(output.colorFilteredPoints.map(\.pos), points.map(\.pos))
        XCTAssertEqual(output.denoising.stats.originalCount, 6)
        XCTAssertEqual(output.denoising.stats.retainedCount, 6)
        XCTAssertEqual(output.candidates.count, 1)
        let candidate = try XCTUnwrap(output.candidates.first)
        XCTAssertEqual(candidate.pointCount, 6)
        XCTAssertEqual(candidate.diameter, 0.06, accuracy: 0.00001)
        XCTAssertEqual(candidate.sphericity, 1, accuracy: 0.00001)
        XCTAssertEqual(candidate.points, points.map(\.pos))
    }

    private func pipelineInput(
        points: [ColoredPoint],
        category: FruitCategory? = nil,
        filter: ColorFilter? = nil,
        config: ClusterConfig = .default,
        experiment: PointCloudExperimentConfig = .init()
    ) -> ScanFusionYieldBuilder.Input {
        var configuration = FruitScanExperimentConfig.default
        configuration.pointCloud = experiment
        return ScanFusionYieldBuilder.Input(
            points: points, savedDetections: [], imageDiagnostics: ImageDetectionDiagnostics(),
            fruitType: "苹果", fruitCategory: category, paramsSnapshot: [:],
            defaultParams: FruitVarietyParams(category: .apple), clusterConfig: config,
            fusionConfig: .default, colorFilter: filter, experimentConfiguration: configuration
        )
    }

    private func filterContractPoints() -> [ColoredPoint] {
        [
            ColoredPoint(pos: SIMD3<Float>(0, 0, 1), r: 0.8, g: 0.2, b: 0.1),
            ColoredPoint(pos: SIMD3<Float>(1, 0, 1), r: 0.1, g: 0.1, b: 0.8),
            ColoredPoint(pos: SIMD3<Float>(2, 0, 1), r: 0.7, g: 0.2, b: 0.1)
        ]
    }

    private func denoisingBoundaryPoints(inlierCount: Int) -> [ColoredPoint] {
        (0..<inlierCount).map { index in
            ColoredPoint(pos: .zero, r: 0.7 + Float(index) / 100, g: 0.3, b: 0.1)
        } + [ColoredPoint(pos: SIMD3<Float>(10, 0, 0), r: 0.8, g: 0.3, b: 0.1)]
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
