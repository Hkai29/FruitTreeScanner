// FruitScanExperimentConfig.swift
// Runtime parameters that supplement the resolved FruitScanConfig/ClusterConfig.

import Foundation

struct FruitScanExperimentConfig: Equatable, Sendable, Encodable {
    var fusion: FusionExperimentConfig = .default
    var pointCloud: PointCloudExperimentConfig = .default
    var depth: DepthExperimentConfig = .default
    var occlusion: OcclusionExperimentConfig = .default
    var candidateMerge: CandidateMergeExperimentConfig = .default

    static let `default` = FruitScanExperimentConfig()
}

struct FusionExperimentConfig: Equatable, Sendable, Encodable {
    var nearestCandidateDistance: Float = 0.15
    var frustumSupportRatio: Float = 0.25
    var projectedBoxExpansionFraction: Float = 0.12
    var relaxedDistanceMultiplier: Float = 3.0
    var relaxedDistanceCap: Float = 0.30
    var rejectedDepthCandidateMinimumDistance: Float = 0.08
    var rejectedDepthCandidateMaximumDistance: Float = 0.24

    static let `default` = FusionExperimentConfig()
}

struct PointCloudExperimentConfig: Equatable, Sendable, Encodable {
    var denoisingMinPointMultiplier: Int = 12
    var denoisingMinPointFloor: Int = 50
    var denoisingNeighborCount: Int = 12
    var denoisingStdMultiplier: Float = 1.5

    static let `default` = PointCloudExperimentConfig()
}

struct DepthExperimentConfig: Equatable, Sendable, Encodable {
    var projectionSampleGrid: Int = 9
    var minimumReliableConfidence: UInt8 = 1
    /// Sparse outdoor canopies rarely fill a large fraction of the LiDAR map.
    /// Sample broadly and accept a frame once it contains a small, bounded set
    /// of reliable returns; the Metal shader still validates every written point.
    var captureQualitySampleGrid: Int = 9
    var captureQualitySampleMargin: Float = 0.08
    var minimumCaptureValidSampleCount: Int = 4
    var minimumCaptureValidSampleRatio: Float = 0.04
    /// One coherent neighbour keeps thin branches and fruit boundaries while
    /// still rejecting isolated flying pixels.
    var minimumStableDepthNeighborCount: Int = 1

    static let `default` = DepthExperimentConfig()

    // Experimental profiles may tighten the confidence gate, never admit Low.
    var reliableConfidence: UInt8 { min(max(minimumReliableConfidence, 1), 2) }
    // Keep per-observation and per-frame sampling within the established bounds.
    var boundedProjectionGrid: Int { min(max(projectionSampleGrid, 1), 9) }
    var boundedCaptureGrid: Int { min(max(captureQualitySampleGrid, 2), 9) }
}

struct OcclusionExperimentConfig: Equatable, Sendable, Encodable {
    var lidarPenetrationMeters: Float = 0.4

    static let `default` = OcclusionExperimentConfig()
}

struct CandidateMergeExperimentConfig: Equatable, Sendable, Encodable {
    var diameterSimilarityThreshold: Float = 0.55
    var minMergeDistance: Float = 0.035
    var diameterMergeDistanceMultiplier: Float = 0.75
    var maxMergeDistance: Float = 0.08
    var maxPointSamples: Int = 256
    var minimumCandidateWeightSphericity: Float = 0.05

    static let `default` = CandidateMergeExperimentConfig()

    var boundedPointSamples: Int { min(max(maxPointSamples, 0), 256) }
}
