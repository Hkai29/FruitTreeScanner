import Foundation
import os
import simd

struct PointCloudCandidatePipelineOutput {
    let colorFilteredPoints: [ColoredPoint]
    let clusteringPoints: [ColoredPoint]
    let denoising: PointCloudDenoisingResult<ColoredPoint>
    let candidates: [FruitCandidate]
}

struct PointCloudCandidatePipeline {
    func run(_ input: ScanFusionYieldBuilder.Input) async -> PointCloudCandidatePipelineOutput {
        let colorFilteredPoints = Self.colorFilteredPoints(from: input)
        let denoising = Self.denoiseClusteringPoints(
            colorFilteredPoints,
            clusterConfig: input.clusterConfig
        )
        let clusteringPoints = denoising.samples
        let clusterer = PointCloudCluster(config: input.clusterConfig)
        let candidates = await clusterer.processInMemory(
            position: clusteringPoints.map { $0.pos },
            colors: clusteringPoints.map { SIMD3<Float>($0.r, $0.g, $0.b) }
        )

        return PointCloudCandidatePipelineOutput(
            colorFilteredPoints: colorFilteredPoints,
            clusteringPoints: clusteringPoints,
            denoising: denoising,
            candidates: candidates
        )
    }

    private static func colorFilteredPoints(from input: ScanFusionYieldBuilder.Input) -> [ColoredPoint] {
        guard let filter = input.colorFilter ?? input.fruitCategory?.colorFilter else {
            return input.points
        }
        return input.points.filter { filter.matches(r: $0.r, g: $0.g, b: $0.b) }
    }

    private static func denoiseClusteringPoints(
        _ points: [ColoredPoint],
        clusterConfig: ClusterConfig
    ) -> PointCloudDenoisingResult<ColoredPoint> {
        let experimentConfig = FruitScanExperimentConfig.default.pointCloud
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

struct DetectionDepthCandidatePipelineOutput {
    let rawCandidates: [FruitCandidate]
    let candidates: [FruitCandidate]
    let fusionCandidates: [FruitCandidate]
}

struct DetectionDepthCandidatePipeline {
    func run(_ input: ScanFusionYieldBuilder.Input) -> DetectionDepthCandidatePipelineOutput {
        let rawCandidates = DetectionDepthCandidateBuilder.makeCandidates(
            from: input.savedDetections,
            clusterConfig: input.clusterConfig
        )
        let candidates = CandidateCombiner.mergeDetectionDepthCandidates(rawCandidates)
        let fusionCandidates = ScanFusionCategoryFilter.candidates(
            candidates,
            targetCategory: input.fruitCategory
        )

        return DetectionDepthCandidatePipelineOutput(
            rawCandidates: rawCandidates,
            candidates: candidates,
            fusionCandidates: fusionCandidates
        )
    }
}

enum ScanFusionCategoryFilter {
    struct DetectionFilterResult {
        let detections: [DetectedFruit]
        let filteredBySelectedFruitTypeCount: Int
    }

    static func detections(
        _ detections: [DetectedFruit],
        targetCategory: FruitCategory?
    ) -> [DetectedFruit] {
        detectionFilterResult(detections, targetCategory: targetCategory).detections
    }

    static func detectionFilterResult(
        _ detections: [DetectedFruit],
        targetCategory: FruitCategory?
    ) -> DetectionFilterResult {
        guard let targetCategory else {
            return DetectionFilterResult(
                detections: detections,
                filteredBySelectedFruitTypeCount: 0
            )
        }
        let filtered = detections.filter { $0.category == targetCategory }
        return DetectionFilterResult(
            detections: filtered,
            filteredBySelectedFruitTypeCount: detections.count - filtered.count
        )
    }

    static func candidates(
        _ candidates: [FruitCandidate],
        targetCategory: FruitCategory?
    ) -> [FruitCandidate] {
        guard let targetCategory else { return candidates }
        return candidates.filter { candidate in
            candidate.sourceCategory == nil || candidate.sourceCategory == targetCategory
        }
    }
}

struct FusionEvidencePipelineOutput {
    let validatedFruits: [ValidatedFruit]
    let deduplicatedDetectionCount: Int
    let evidenceDetections: [DetectedFruit]
    let cloudOnlyConservativeMode: Bool
}

struct FusionEvidencePipeline {
    let fusionConfig: FruitScanConfig

    func run(
        detections: [DetectedFruit],
        candidates: [FruitCandidate]
    ) -> FusionEvidencePipelineOutput {
        guard !detections.isEmpty else {
            return conservativeOutput()
        }

        let alignedDetections = detections.filter(\.hasAlignedDepthContext)
        guard !alignedDetections.isEmpty else {
            Log.fusion.warning("Skipping \(detections.count) image detections because none carried aligned depth context")
            return conservativeOutput()
        }

        let stableEvidenceDetections = DetectionDeduplicator.stableEvidenceDetections(
            alignedDetections,
            minimumObservations: fusionConfig.minimumStableDetectionsForYield,
            minimumConfidence: fusionConfig.minConfidence,
            timeWindow: fusionConfig.stableDetectionTimeWindow
        )
        guard !stableEvidenceDetections.isEmpty else {
            return conservativeOutput()
        }

        let deduplicatedDetections = DetectionDeduplicator.deduplicate2D(stableEvidenceDetections)
        let fusionValidator = FusionValidator(config: fusionConfig)
        let validationResults = fusionValidator.validate(
            detections: deduplicatedDetections,
            candidates: candidates
        )
        if validationResults.isEmpty {
            return conservativeOutput(deduplicatedDetectionCount: deduplicatedDetections.count)
        }

        let reliableFruits = ValidatedFruit.deduplicate3D(
            validationResults.filter { $0.source == .fused }
        )
        guard !reliableFruits.isEmpty else {
            return conservativeOutput(
                deduplicatedDetectionCount: deduplicatedDetections.count,
                evidenceDetections: stableEvidenceDetections
            )
        }

        return FusionEvidencePipelineOutput(
            validatedFruits: reliableFruits,
            deduplicatedDetectionCount: deduplicatedDetections.count,
            evidenceDetections: stableEvidenceDetections,
            cloudOnlyConservativeMode: false
        )
    }

    private func conservativeOutput(
        deduplicatedDetectionCount: Int = 0,
        evidenceDetections: [DetectedFruit] = []
    ) -> FusionEvidencePipelineOutput {
        FusionEvidencePipelineOutput(
            validatedFruits: [],
            deduplicatedDetectionCount: deduplicatedDetectionCount,
            evidenceDetections: evidenceDetections,
            cloudOnlyConservativeMode: true
        )
    }
}

enum CandidateCombiner {
    static func combine(
        pointCloudCandidates: [FruitCandidate],
        detectionDepthCandidates: [FruitCandidate]
    ) -> [FruitCandidate] {
        mergeCandidateEvidence(pointCloudCandidates + detectionDepthCandidates)
    }

    static func mergeDetectionDepthCandidates(_ candidates: [FruitCandidate]) -> [FruitCandidate] {
        mergeCandidateEvidence(candidates)
    }

    static func averageDepthSupportRatio(_ candidates: [FruitCandidate]) -> Float {
        let ratios = candidates.compactMap(\.depthSupportRatio).filter { $0.isFinite }
        guard !ratios.isEmpty else { return 0 }
        let average = ratios.reduce(0, +) / Float(ratios.count)
        return min(max(average, 0), 1)
    }

    private struct CandidateTrack {
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

        init(seed: FruitCandidate) {
            let weight = Self.weight(for: seed)
            totalWeight = weight
            weightedPosition = seed.position * weight
            weightedDiameter = seed.diameter * weight
            weightedColor = seed.averageColor * weight
            maxSphericity = seed.sphericity
            pointCount = seed.pointCount
            points = Array(seed.points.prefix(Self.maxPointSamples))
            sourceCategory = seed.sourceCategory
            hasPointCloudEvidence = seed.sourceCategory == nil && seed.depthSupportRatio == nil
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
            let weight = Self.weight(for: candidate)
            weightedPosition += candidate.position * weight
            weightedDiameter += candidate.diameter * weight
            weightedColor += candidate.averageColor * weight
            totalWeight += weight
            maxSphericity = max(maxSphericity, candidate.sphericity)
            pointCount += candidate.pointCount

            let remainingCapacity = Self.maxPointSamples - points.count
            if remainingCapacity > 0 {
                points.append(contentsOf: candidate.points.prefix(remainingCapacity))
            }
            if sourceCategory == nil {
                sourceCategory = candidate.sourceCategory
            }
            if candidate.sourceCategory == nil && candidate.depthSupportRatio == nil {
                hasPointCloudEvidence = true
            }
            if let depthSupportRatio = candidate.depthSupportRatio {
                weightedDepthSupport += Self.clampedRatio(depthSupportRatio) * weight
                depthSupportWeight += weight
            }
        }

        func mergedCandidate() -> FruitCandidate {
            let safeWeight = max(totalWeight, 1e-6)
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
                depthSupportRatio: depthSupportRatio
            )
        }

        private static let maxPointSamples = FruitScanExperimentConfig.default.candidateMerge.maxPointSamples

        private static func weight(for candidate: FruitCandidate) -> Float {
            let minimumSphericity = FruitScanExperimentConfig.default.candidateMerge.minimumCandidateWeightSphericity
            return max(Float(max(candidate.pointCount, candidate.points.count)), 1) * max(candidate.sphericity, minimumSphericity)
        }

        private static func clampedRatio(_ ratio: Float) -> Float {
            guard ratio.isFinite else { return 0 }
            return min(max(ratio, 0), 1)
        }
    }

    private static func mergeCandidateEvidence(_ candidates: [FruitCandidate]) -> [FruitCandidate] {
        guard candidates.count > 1 else { return candidates }

        let sorted = candidates.sorted {
            if $0.pointCount == $1.pointCount {
                return $0.sphericity > $1.sphericity
            }
            return $0.pointCount > $1.pointCount
        }
        var tracks: [CandidateTrack] = []

        for candidate in sorted {
            let mergeableTrackIndices = tracks.indices.filter { index in
                shouldMergeDepthCandidate(candidate, into: tracks[index].mergedCandidate())
            }

            if let trackIndex = mergeableTrackIndices.min(by: { lhs, rhs in
                simd_distance(tracks[lhs].center, candidate.position) < simd_distance(tracks[rhs].center, candidate.position)
            }) {
                tracks[trackIndex].add(candidate)
                continue
            }

            tracks.append(CandidateTrack(seed: candidate))
        }

        return tracks.map { $0.mergedCandidate() }
    }

    private static func shouldMergeDepthCandidate(
        _ candidate: FruitCandidate,
        into trackCandidate: FruitCandidate
    ) -> Bool {
        guard categoriesAreCompatible(candidate.sourceCategory, trackCandidate.sourceCategory) else {
            return false
        }

        let largerDiameter = max(candidate.diameter, trackCandidate.diameter)
        guard largerDiameter > 0 else { return false }

        let diameterSimilarity = min(candidate.diameter, trackCandidate.diameter) / largerDiameter
        let experimentConfig = FruitScanExperimentConfig.default.candidateMerge
        guard diameterSimilarity >= experimentConfig.diameterSimilarityThreshold else { return false }

        let averageDiameter = (candidate.diameter + trackCandidate.diameter) * 0.5
        let mergeDistance = max(
            experimentConfig.minMergeDistance,
            min(
                averageDiameter * experimentConfig.diameterMergeDistanceMultiplier,
                experimentConfig.maxMergeDistance
            )
        )
        return simd_distance(candidate.position, trackCandidate.position) < mergeDistance
    }

    private static func categoriesAreCompatible(
        _ lhs: FruitCategory?,
        _ rhs: FruitCategory?
    ) -> Bool {
        guard let lhs, let rhs else { return true }
        return lhs == rhs
    }
}
