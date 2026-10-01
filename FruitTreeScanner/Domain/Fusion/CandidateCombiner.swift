import simd

enum CandidateCombiner {
    static func combine(
        pointCloudCandidates: [FruitCandidate],
        detectionDepthCandidates: [FruitCandidate],
        configuration: CandidateMergeExperimentConfig = .default
    ) -> [FruitCandidate] {
        // 合并点云与 ROI 深度证据时沿用统一的物理距离和尺寸约束。
        mergeCandidateEvidence(pointCloudCandidates + detectionDepthCandidates, configuration: configuration)
    }

    static func mergeDetectionDepthCandidates(
        _ candidates: [FruitCandidate],
        configuration: CandidateMergeExperimentConfig = .default
    ) -> [FruitCandidate] {
        mergeCandidateEvidence(candidates, configuration: configuration)
    }

    static func averageDepthSupportRatio(_ candidates: [FruitCandidate]) -> Float {
        let ratios = candidates.compactMap(\.depthSupportRatio).filter { $0.isFinite }
        guard !ratios.isEmpty else { return 0 }
        let average = ratios.reduce(0, +) / Float(ratios.count)
        return min(max(average, 0), 1)
    }

    private struct CandidateTrack {
        let configuration: CandidateMergeExperimentConfig
        var totalWeight: Float
        var weightedPosition: SIMD3<Float>
        var weightedDiameter: Float
        var weightedColor: SIMD3<Float>
        var maxSphericity: Float
        var pointCount: Int
        var points: [SIMD3<Float>]
        var sourceCategory: FruitCategory?
        var weightedDepthSupport: Float
        var depthSupportWeight: Float
        var hasPointCloudEvidence: Bool

        init(seed: FruitCandidate, configuration: CandidateMergeExperimentConfig) {
            self.configuration = configuration
            let weight = Self.weight(for: seed, configuration: configuration)
            totalWeight = weight
            weightedPosition = seed.position * weight
            weightedDiameter = seed.diameter * weight
            weightedColor = seed.averageColor * weight
            maxSphericity = seed.sphericity
            pointCount = seed.pointCount
            points = Array(seed.points.prefix(configuration.boundedPointSamples))
            sourceCategory = seed.sourceCategory
            hasPointCloudEvidence = seed.hasPointCloudEvidence
            if let depthSupportRatio = seed.depthSupportRatio {
                weightedDepthSupport = Self.clampedRatio(depthSupportRatio) * weight
                depthSupportWeight = weight
            } else {
                weightedDepthSupport = 0
                depthSupportWeight = 0
            }
        }

        var center: SIMD3<Float> {
            guard totalWeight > 0 else { return .zero }
            return weightedPosition / totalWeight
        }

        mutating func add(_ candidate: FruitCandidate) {
            // 加权累积避免低点数候选把高支持候选中心明显拉偏。
            let weight = Self.weight(for: candidate, configuration: configuration)
            weightedPosition += candidate.position * weight
            weightedDiameter += candidate.diameter * weight
            weightedColor += candidate.averageColor * weight
            totalWeight += weight
            maxSphericity = max(maxSphericity, candidate.sphericity)
            pointCount += candidate.pointCount

            let remainingCapacity = configuration.boundedPointSamples - points.count
            if remainingCapacity > 0 {
                points.append(contentsOf: candidate.points.prefix(remainingCapacity))
            }
            if sourceCategory == nil {
                sourceCategory = candidate.sourceCategory
            }
            if candidate.hasPointCloudEvidence {
                hasPointCloudEvidence = true
            }
            if let depthSupportRatio = candidate.depthSupportRatio {
                weightedDepthSupport += Self.clampedRatio(depthSupportRatio) * weight
                depthSupportWeight += weight
            }
        }

        func mergedCandidate() -> FruitCandidate {
            let safeWeight = max(totalWeight, 1e-6)
            // 混入独立点云证据后不再伪装为纯 ROI-depth 候选。
            let depthSupportRatio = !hasPointCloudEvidence && depthSupportWeight > 0
                ? weightedDepthSupport / depthSupportWeight
                : nil
            return FruitCandidate(
                position: weightedPosition / safeWeight,
                diameter: weightedDiameter / safeWeight,
                sphericity: maxSphericity,
                pointCount: max(pointCount, points.count),
                averageColor: weightedColor / safeWeight,
                points: points,
                sourceCategory: sourceCategory,
                depthSupportRatio: depthSupportRatio,
                hasPointCloudEvidence: hasPointCloudEvidence
            )
        }

        private static func weight(for candidate: FruitCandidate, configuration: CandidateMergeExperimentConfig) -> Float {
            let minimumSphericity = configuration.minimumCandidateWeightSphericity
            return max(Float(max(candidate.pointCount, candidate.points.count)), 1) * max(candidate.sphericity, minimumSphericity)
        }

        private static func clampedRatio(_ ratio: Float) -> Float {
            guard ratio.isFinite else { return 0 }
            return min(max(ratio, 0), 1)
        }
    }

    private static func mergeCandidateEvidence(
        _ candidates: [FruitCandidate],
        configuration: CandidateMergeExperimentConfig
    ) -> [FruitCandidate] {
        guard candidates.count > 1 else { return candidates }

        // 先处理支持度高的候选，使其成为后续弱候选的稳定合并中心。
        let sorted = candidates.sorted {
            if $0.pointCount == $1.pointCount {
                return $0.sphericity > $1.sphericity
            }
            return $0.pointCount > $1.pointCount
        }
        var tracks: [CandidateTrack] = []

        for candidate in sorted {
            var nearestTrackIndex: Int?
            var nearestDistance = Float.infinity
            for index in tracks.indices {
                guard shouldMergeDepthCandidate(candidate, into: tracks[index], experimentConfig: configuration) else { continue }
                let distance = simd_distance(tracks[index].center, candidate.position)
                // Strict comparison keeps the first eligible track on a tie.
                if nearestTrackIndex == nil || distance < nearestDistance {
                    nearestTrackIndex = index
                    nearestDistance = distance
                }
            }

            if let trackIndex = nearestTrackIndex {
                tracks[trackIndex].add(candidate)
                continue
            }

            tracks.append(CandidateTrack(seed: candidate, configuration: configuration))
        }

        return tracks.map { $0.mergedCandidate() }
    }

    private static func shouldMergeDepthCandidate(
        _ candidate: FruitCandidate,
        into track: CandidateTrack,
        experimentConfig: CandidateMergeExperimentConfig
    ) -> Bool {
        guard categoriesAreCompatible(candidate.sourceCategory, track.sourceCategory) else {
            return false
        }

        // Match against the same normalized geometry as the final candidate.
        // Comparison does not materialize points, colors, support, or a new UUID.
        let safeWeight = max(track.totalWeight, 1e-6)
        let trackPosition = track.weightedPosition / safeWeight
        let trackDiameter = track.weightedDiameter / safeWeight
        let largerDiameter = max(candidate.diameter, trackDiameter)
        guard largerDiameter > 0 else { return false }

        let diameterSimilarity = min(candidate.diameter, trackDiameter) / largerDiameter
        guard diameterSimilarity >= experimentConfig.diameterSimilarityThreshold else { return false }

        let averageDiameter = (candidate.diameter + trackDiameter) * 0.5
        let mergeDistance = max(
            experimentConfig.minMergeDistance,
            min(
                averageDiameter * experimentConfig.diameterMergeDistanceMultiplier,
                experimentConfig.maxMergeDistance
            )
        )
        return simd_distance(candidate.position, trackPosition) < mergeDistance
    }

    private static func categoriesAreCompatible(
        _ lhs: FruitCategory?,
        _ rhs: FruitCategory?
    ) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }
}
