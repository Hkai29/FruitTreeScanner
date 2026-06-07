import Foundation

struct ScanCompletionEvaluator {
    struct Metrics {
        let voxelCount: Int
        let scanDuration: TimeInterval
        let discoveryTrend: VoxelDiscoveryTrend
        let discoveryRate: Float
    }

    func evaluate(_ metrics: Metrics) -> ScanCompletion {
        let timeScore = calculateTimeScore(duration: metrics.scanDuration)
        let voxelScore = calculateVoxelScore(count: metrics.voxelCount)
        let stabilityScore = calculateStabilityScore(
            trend: metrics.discoveryTrend,
            rate: metrics.discoveryRate
        )

        return ScanCompletion(
            overall: min(timeScore * 0.3 + voxelScore * 0.4 + stabilityScore * 0.3, 1.0),
            timeScore: timeScore,
            voxelScore: voxelScore,
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
