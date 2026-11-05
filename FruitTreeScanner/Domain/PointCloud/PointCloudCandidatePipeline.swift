import Foundation

struct PointCloudCandidateInput: Sendable {
    let points: [ColoredPoint]
    let colorFilter: ColorFilter?
    let clusterConfig: ClusterConfig
    let experimentConfiguration: PointCloudExperimentConfig
}

struct PointCloudCandidatePipelineOutput {
    let colorFilteredPoints: [ColoredPoint]
    let clusteringPoints: [ColoredPoint]
    let denoising: PointCloudDenoisingResult<ColoredPoint>
    let candidates: [FruitCandidate]
}

struct PointCloudCandidatePipeline {
    func run(_ input: PointCloudCandidateInput) async -> PointCloudCandidatePipelineOutput {
        // 点云分支依次执行颜色筛选、离群点抑制和有界聚类。
        let colorFilteredPoints = Self.colorFilteredPoints(from: input)
        let denoising = Self.denoiseClusteringPoints(
            colorFilteredPoints,
            clusterConfig: input.clusterConfig,
            experimentConfig: input.experimentConfiguration
        )
        let clusteringPoints = denoising.samples
        let clusterer = PointCloudCluster(config: input.clusterConfig)
        let candidates = await clusterer.process(points: clusteringPoints)

        return PointCloudCandidatePipelineOutput(
            colorFilteredPoints: colorFilteredPoints,
            clusteringPoints: clusteringPoints,
            denoising: denoising,
            candidates: candidates
        )
    }

    private static func colorFilteredPoints(from input: PointCloudCandidateInput) -> [ColoredPoint] {
        guard let filter = input.colorFilter else {
            return input.points
        }
        return input.points.filter { filter.matches(r: $0.r, g: $0.g, b: $0.b) }
    }

    private static func denoiseClusteringPoints(
        _ points: [ColoredPoint],
        clusterConfig: ClusterConfig,
        experimentConfig: PointCloudExperimentConfig
    ) -> PointCloudDenoisingResult<ColoredPoint> {
        // 小样本跳过去噪，避免邻域统计在点数不足时误删有效果实点。
        let minimumDenoisingPointCount = max(
            clusterConfig.minPoints * experimentConfig.denoisingMinPointMultiplier,
            experimentConfig.denoisingMinPointFloor
        )
        guard points.count >= minimumDenoisingPointCount else {
            return PointCloudDenoiser.unchangedResult(samples: points)
        }
        return PointCloudDenoiser.statisticalOutlierRemovalDetailed(
            samples: points,
            k: experimentConfig.denoisingNeighborCount,
            stdMultiplier: experimentConfig.denoisingStdMultiplier,
            position: { $0.pos }
        )
    }
}
