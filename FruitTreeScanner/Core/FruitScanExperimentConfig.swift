// FruitScanExperimentConfig.swift
// Central default parameters for scan-yield fusion experiments.

import Foundation

struct FruitScanExperimentConfig: Sendable {
    var detector: FruitDetectorExperimentConfig = .default
    var fusion: FusionExperimentConfig = .default
    var clustering: ClusterExperimentConfig = .default
    var pointCloud: PointCloudExperimentConfig = .default
    var depth: DepthExperimentConfig = .default
    var occlusion: OcclusionExperimentConfig = .default
    var candidateMerge: CandidateMergeExperimentConfig = .default

    static let `default` = FruitScanExperimentConfig()
}

struct FruitDetectorExperimentConfig: Sendable {
    var imageDetectionInterval: Int = 10
    var minConfidence: Float = 0.5

    static let `default` = FruitDetectorExperimentConfig()
}

struct FusionExperimentConfig: Sendable {
    var sizeTolerance: Float = 0.35
    var sphericityThreshold: Float = 0.5
    var minimumStableDetections: Int = 1
    var stableDetectionTimeWindow: TimeInterval = 3.5
    var nearestCandidateDistance: Float = 0.15
    var frustumSupportRatio: Float = 0.25
    var projectedBoxExpansionFraction: Float = 0.12
    var relaxedDistanceMultiplier: Float = 3.0
    var relaxedDistanceCap: Float = 0.30
    var rejectedDepthCandidateMinimumDistance: Float = 0.08
    var rejectedDepthCandidateMaximumDistance: Float = 0.24

    static let `default` = FusionExperimentConfig()
}

struct ClusterExperimentConfig: Sendable {
    var minPoints: Int = 3
    var minDiameter: Float = 0.015
    var maxDiameter: Float = 0.20
    var baseEps: Float = 0.1
    var sphericityThreshold: Float = 0.5

    static let `default` = ClusterExperimentConfig()
}

struct PointCloudExperimentConfig: Sendable {
    var denoisingMinPointMultiplier: Int = 12
    var denoisingMinPointFloor: Int = 50
    var denoisingNeighborCount: Int = 12
    var denoisingStdMultiplier: Float = 1.5

    static let `default` = PointCloudExperimentConfig()
}

struct DepthExperimentConfig: Sendable {
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
}

struct OcclusionExperimentConfig: Sendable {
    var lidarPenetrationMeters: Float = 0.4

    static let `default` = OcclusionExperimentConfig()
}

struct CandidateMergeExperimentConfig: Sendable {
    var diameterSimilarityThreshold: Float = 0.55
    var minMergeDistance: Float = 0.035
    var diameterMergeDistanceMultiplier: Float = 0.75
    var maxMergeDistance: Float = 0.08
    var maxPointSamples: Int = 256
    var minimumCandidateWeightSphericity: Float = 0.05

    static let `default` = CandidateMergeExperimentConfig()
}

// TODO: Thread this config through the remaining fusion and yield services once
// experiment profiles can be injected without changing today's default scan
// behavior or diagnostics.
