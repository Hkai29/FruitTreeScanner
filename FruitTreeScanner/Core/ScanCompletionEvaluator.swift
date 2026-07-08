import Foundation

struct ScanCompletionEvaluator {
    struct Metrics {
        let voxelCount: Int
        let scanDuration: TimeInterval
        let angleCoverage: Float
        let angleUniformity: Float
        let oppositeSideCoverage: Float
        let verticalCoverage: Float
        let discoveryTrend: VoxelDiscoveryTrend
        let discoveryRate: Float

        init(
            voxelCount: Int,
            scanDuration: TimeInterval,
            angleCoverage: Float,
            angleUniformity: Float = 1,
            oppositeSideCoverage: Float? = nil,
            verticalCoverage: Float = 1,
            discoveryTrend: VoxelDiscoveryTrend,
            discoveryRate: Float
        ) {
            self.voxelCount = voxelCount
            self.scanDuration = scanDuration
            self.angleCoverage = angleCoverage
            self.angleUniformity = angleUniformity
            self.oppositeSideCoverage = oppositeSideCoverage ?? angleCoverage
            self.verticalCoverage = verticalCoverage
            self.discoveryTrend = discoveryTrend
            self.discoveryRate = discoveryRate
        }
    }

    func evaluate(_ metrics: Metrics) -> ScanCompletion {
        let timeScore = calculateTimeScore(duration: metrics.scanDuration)
        let voxelScore = calculateVoxelScore(count: metrics.voxelCount)
        let angleCoverageScore = calculateAngleCoverageScore(metrics.angleCoverage)
        let angleUniformityScore = calculateAngleUniformityScore(metrics.angleUniformity)
        let oppositeSideScore = calculateOppositeSideScore(metrics.oppositeSideCoverage)
        let verticalCoverageScore = calculateVerticalCoverageScore(metrics.verticalCoverage)
        let stabilityScore = calculateStabilityScore(
            trend: metrics.discoveryTrend,
            rate: metrics.discoveryRate
        )

        return ScanCompletion(
            overall: min(
                timeScore * 0.16 +
                    voxelScore * 0.25 +
                    angleCoverageScore * 0.18 +
                    angleUniformityScore * 0.11 +
                    oppositeSideScore * 0.05 +
                    verticalCoverageScore * 0.10 +
                    stabilityScore * 0.15,
                1.0
            ),
            timeScore: timeScore,
            voxelScore: voxelScore,
            angleCoverageScore: angleCoverageScore,
            angleUniformityScore: angleUniformityScore,
            oppositeSideScore: oppositeSideScore,
            verticalCoverageScore: verticalCoverageScore,
            stabilityScore: stabilityScore,
            voxelCount: metrics.voxelCount,
            scanDuration: metrics.scanDuration,
            discoveryTrend: metrics.discoveryTrend
        )
    }

    private func calculateTimeScore(duration: TimeInterval) -> Float {
        if duration < 10 { return Float(duration / 10.0 * 0.3) }
        if duration < 30 { return Float(0.3 + (duration - 10) / 20.0 * 0.2) }
        if duration < 60 { return Float(0.5 + (duration - 30) / 30.0 * 0.3) }
        if duration < 120 { return Float(0.8 + (duration - 60) / 60.0 * 0.2) }
        return 1.0
    }

    private func calculateVoxelScore(count: Int) -> Float {
        if count < 50 { return Float(count) / 50 * 0.2 }
        if count < 200 { return 0.2 + Float(count - 50) / 150 * 0.3 }
        if count < 500 { return 0.5 + Float(count - 200) / 300 * 0.3 }
        return min(0.8 + Float(count - 500) / 500 * 0.2, 1.0)
    }

    private func calculateAngleCoverageScore(_ coverage: Float) -> Float {
        let clamped = min(max(coverage, 0), 1)
        if clamped < 0.25 { return clamped / 0.25 * 0.25 }
        if clamped < 0.50 { return 0.25 + (clamped - 0.25) / 0.25 * 0.35 }
        if clamped < 0.75 { return 0.60 + (clamped - 0.50) / 0.25 * 0.25 }
        return min(0.85 + (clamped - 0.75) / 0.25 * 0.15, 1.0)
    }

    private func calculateAngleUniformityScore(_ uniformity: Float) -> Float {
        min(max(uniformity, 0), 1)
    }

    private func calculateOppositeSideScore(_ coverage: Float) -> Float {
        let clamped = min(max(coverage, 0), 1)
        if clamped < 0.25 { return clamped / 0.25 * 0.35 }
        if clamped < 0.65 { return 0.35 + (clamped - 0.25) / 0.40 * 0.45 }
        return min(0.80 + (clamped - 0.65) / 0.35 * 0.20, 1.0)
    }

    private func calculateVerticalCoverageScore(_ coverage: Float) -> Float {
        let clamped = min(max(coverage, 0), 1)
        if clamped < 0.35 { return clamped / 0.35 * 0.40 }
        if clamped < 0.70 { return 0.40 + (clamped - 0.35) / 0.35 * 0.40 }
        return min(0.80 + (clamped - 0.70) / 0.30 * 0.20, 1.0)
    }

    private func calculateStabilityScore(trend: VoxelDiscoveryTrend, rate: Float) -> Float {
        switch trend {
        case .collecting:
            return 0.3
        case .increasing:
            return 0.5 + min(rate / 50, 1.0) * 0.2
        case .decreasing:
            return 0.6 + min(rate / 30, 1.0) * 0.2
        case .stable:
            return 0.8 + min(rate / 10, 1.0) * 0.2
        }
    }
}
