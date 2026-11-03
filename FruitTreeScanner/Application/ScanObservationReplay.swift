import Foundation
import CoreFoundation
import simd

struct ScanObservationReplayRecord: Sendable {
    let identity: ScanEvidenceIdentity
    let producer: ReplayProducerDTO
    let input: ScanFusionYieldBuilder.Input
    let goldenData: Data
    let exportRevision: String
}

enum ScanObservationReplay {
    struct Report: Sendable {
        let result: YieldResult
        let differences: [String]
        var matchesGolden: Bool { differences.isEmpty }
    }

    /// Replays detection outputs, not CoreML inference or physical LiDAR.
    static func run(_ record: ScanObservationReplayRecord) async throws -> Report {
        guard record.producer.algorithmRevision == YieldAlgorithmRevision.current else { throw ScanReplayError.algorithmMismatch }
        let worker = Task.detached(priority: .utility) {
            try Task.checkCancellation()
            guard record.producer.sourcesSHA256 == (try ScanReplayBuildIdentity.current().sourcesSHA256) else {
                throw ScanReplayError.algorithmMismatch
            }
            try validateForExecution(record.input)
            let (result, _) = await ScanFusionYieldBuilder.build(from: record.input)
            try Task.checkCancellation()
            let actual = try ScanResultExportService.replayGoldenData(for: result)
            return Report(result: result, differences: try differences(expected: record.goldenData, actual: actual))
        }
        return try await withTaskCancellationHandler { try await worker.value } onCancel: { worker.cancel() }
    }

    /// The file codec preserves original values, including rejected evidence.
    /// This separate execution contract rejects unsupported arithmetic/resource
    /// domains; it never clamps input or changes the production estimator.
    static func validateForExecution(_ input: ScanFusionYieldBuilder.Input) throws {
        func require(_ condition: Bool) throws {
            guard condition else { throw ScanReplayError.invalidArchive }
        }
        func bounded(_ value: Float, _ range: ClosedRange<Float>) -> Bool {
            value.isFinite && range.contains(value)
        }
        func position(_ value: SIMD3<Float>) -> Bool {
            (0..<3).allSatisfy { bounded(value[$0], -10_000...10_000) }
        }
        func parameters(_ value: FruitVarietyParams) -> Bool {
            bounded(value.diamMin, 0.000001...100) && bounded(value.diamMax, value.diamMin...100)
                && bounded(value.averageWeightG, 0...1_000_000) && bounded(value.density, 0...1_000_000)
                && bounded(value.clusterEps, 0.000001...100) && bounded(value.sphericityThreshold, 0...1)
        }
        try require((1...ScanReplayLimits.maximumPoints).contains(input.points.count)
            && input.observations.count <= ScanReplayLimits.maximumObservations && input.paramsSnapshot.count <= 128)
        for point in input.points {
            try Task.checkCancellation()
            try require(position(point.pos) && bounded(point.r, 0...1) && bounded(point.g, 0...1) && bounded(point.b, 0...1))
        }
        try require(parameters(input.defaultParams) && input.paramsSnapshot.values.allSatisfy(parameters))
        let cluster = input.clusterConfig
        let cloud = input.experimentConfiguration.pointCloud
        try require((1...ScanReplayLimits.maximumPoints).contains(cluster.minPoints)
            && (0...ScanReplayLimits.maximumPoints).contains(cloud.denoisingMinPointMultiplier)
            && (0...ScanReplayLimits.maximumPoints).contains(cloud.denoisingMinPointFloor)
            && (0...256).contains(cloud.denoisingNeighborCount)
            && !cluster.minPoints.multipliedReportingOverflow(by: cloud.denoisingMinPointMultiplier).overflow
            && bounded(cloud.denoisingStdMultiplier, 0...100)
            && bounded(cluster.minDiameter, 0.000001...100)
            && bounded(cluster.maxDiameter, cluster.minDiameter...100)
            && bounded(cluster.baseEps, 0.000001...100) && bounded(cluster.sphericityThreshold, 0...1))
        let fusion = input.fusionConfig
        try require((1...ScanReplayLimits.maximumPoints).contains(fusion.imageDetectionInterval)
            && (1...ScanReplayLimits.maximumObservations).contains(fusion.minimumStableDetectionsForYield)
            && bounded(fusion.minConfidence, 0...1) && bounded(fusion.sizeTolerance, 0...100)
            && fusion.stableDetectionTimeWindow.isFinite && (0...1_000_000_000).contains(fusion.stableDetectionTimeWindow))
        let experiment = input.experimentConfiguration
        let distances = experiment.fusion
        try require([distances.nearestCandidateDistance, distances.relaxedDistanceCap,
                     distances.rejectedDepthCandidateMinimumDistance, distances.rejectedDepthCandidateMaximumDistance]
            .allSatisfy { bounded($0, 0...10_000) }
            && bounded(distances.frustumSupportRatio, 0...1)
            && bounded(distances.projectedBoxExpansionFraction, 0...100)
            && bounded(distances.relaxedDistanceMultiplier, 0...100)
            && bounded(experiment.occlusion.lidarPenetrationMeters, 0.000001...10_000))
        let merge = experiment.candidateMerge
        try require(bounded(merge.diameterSimilarityThreshold, 0...1)
            && bounded(merge.minMergeDistance, 0...10_000) && bounded(merge.maxMergeDistance, 0...10_000)
            && bounded(merge.diameterMergeDistanceMultiplier, 0...100)
            && bounded(merge.minimumCandidateWeightSphericity, 0...1))
        let calibration = input.calibrationCorrection
        try require(bounded(calibration.countFactor, 0...100) && bounded(calibration.yieldFactor, 0...100)
            && (0...1_000_000_000).contains(calibration.countSampleCount)
            && (0...1_000_000_000).contains(calibration.yieldSampleCount))
        if let filter = input.colorFilter {
            try require([filter.rMin, filter.rMax, filter.gMin, filter.gMax, filter.bMin, filter.bMax]
                .allSatisfy { bounded($0, 0...1) })
            if let hsv = filter.hsvFilter {
                try require(bounded(hsv.hMin, 0...360) && bounded(hsv.hMax, 0...360)
                    && bounded(hsv.sMin, 0...1) && bounded(hsv.vMin, 0...1))
            }
            if let lab = filter.labFilter {
                try require([lab.lMin, lab.lMax, lab.aMin, lab.aMax, lab.bMin, lab.bMax]
                    .allSatisfy { bounded($0, -1_000...1_000) })
            }
        }
        let diagnostics = input.imageDiagnostics
        try require([diagnostics.queuedFrameCount, diagnostics.processedFrameCount, diagnostics.observationCount,
                     diagnostics.confidenceFilteredCount, diagnostics.unmappedObservationCount, diagnostics.mappedFruitCount,
                     diagnostics.fallbackFrameCount].allSatisfy { (0...1_000_000_000).contains($0) })
        if let verification = input.categoryVerification {
            try require(verification.detectedCategoryCounts.count <= 128
                && verification.detectedCategoryCounts.values.allSatisfy { (0...1_000_000_000).contains($0) }
                && (0...1_000_000_000).contains(verification.nonTargetDetectionCount))
            if let suggestion = verification.automaticSuggestion {
                try require(bounded(suggestion.confidence, 0...1)
                    && (0...1_000_000_000).contains(suggestion.supportingFrameCount))
            }
        }
        for observation in input.observations {
            try Task.checkCancellation()
            let box = observation.boundingBox
            try require([box.origin.x, box.origin.y, box.width, box.height].allSatisfy { $0.isFinite && abs($0) <= 2 }
                && box.width >= 0 && box.height >= 0 && bounded(observation.confidence, 0...1)
                && observation.timestamp.isFinite && abs(observation.timestamp) <= 1_000_000_000_000
                && observation.roiDepthSamples.count <= ScanReplayLimits.maximumDepthSamples
                && observation.projectionDepthSamples.count <= ScanReplayLimits.maximumDepthSamples)
            for sample in observation.roiDepthSamples {
                try require((0..<9).contains(sample.row) && (0..<9).contains(sample.column)
                    && bounded(sample.normalizedImageX, 0...1) && bounded(sample.normalizedImageY, 0...1)
                    && bounded(sample.depthMeters, 0...100))
            }
            try require(observation.projectionDepthSamples.allSatisfy { bounded($0, 0...100) })
            if let size = observation.imageSize {
                try require(size.width.isFinite && size.height.isFinite
                    && (1...100_000).contains(size.width) && (1...100_000).contains(size.height))
            }
            if let intrinsics = observation.cameraIntrinsics {
                try require((0..<3).allSatisfy { column in
                    (0..<3).allSatisfy { bounded(intrinsics[column][$0], -100_000...100_000) }
                } && bounded(intrinsics[0][0], 1...100_000) && bounded(intrinsics[1][1], 1...100_000)
                    && intrinsics[0][1] == 0 && intrinsics[0][2] == 0 && intrinsics[1][0] == 0
                    && intrinsics[1][2] == 0 && intrinsics[2][2] == 1)
            }
            if let transform = observation.cameraTransform {
                try require(position(SIMD3(transform[3].x, transform[3].y, transform[3].z))
                    && transform[3].w == 1 && (0..<3).allSatisfy { transform[$0].w == 0 })
                let rotation = (0..<3).map { SIMD3(transform[$0].x, transform[$0].y, transform[$0].z) }
                try require(rotation.allSatisfy { position($0) && abs(simd_length_squared($0) - 1) <= 0.01 }
                    && abs(simd_dot(rotation[0], rotation[1])) <= 0.01
                    && abs(simd_dot(rotation[0], rotation[2])) <= 0.01
                    && abs(simd_dot(rotation[1], rotation[2])) <= 0.01)
            }
        }
    }

    static func goldenData(from metadata: [String: Any]) throws -> Data {
        var result = metadata
        for key in ["schemaVersion", "exportRevision", "scanID", "sourceFilename", "treeID", "fruitType",
                    "gpsLat", "gpsLon", "timestamp", "scanClassification", "observationReplay"] {
            result.removeValue(forKey: key)
        }
        for key in ["fruitMassEstimates", "validatedFruits"] {
            if let entries = result[key] as? [[String: Any]] {
                let normalized = try entries.map { entry -> (String, [String: Any]) in
                    var value = entry
                    value.removeValue(forKey: "id")
                    value.removeValue(forKey: "createdAt")
                    let data = try JSONSerialization.data(withJSONObject: value, options: [.sortedKeys])
                    return (String(decoding: data, as: UTF8.self), value)
                }
                result[key] = normalized.sorted { $0.0 < $1.0 }.map(\.1)
            }
        }
        return try JSONSerialization.data(withJSONObject: result, options: [.sortedKeys])
    }

    /// Compares every persisted non-envelope field. Float differences are
    /// bounded by abs 1e-5 + relative 1e-5; strings, booleans and counts are exact.
    static func differences(expected: Data, actual: Data) throws -> [String] {
        var result: [String] = []
        func compare(_ expected: Any, _ actual: Any, path: String) {
            guard result.count < 32 else { return }
            if let lhs = expected as? [String: Any], let rhs = actual as? [String: Any] {
                for key in Set(lhs.keys).union(rhs.keys).sorted() {
                    guard result.count < 32 else { return }
                    guard let l = lhs[key], let r = rhs[key] else { result.append(path + "." + key); continue }
                    compare(l, r, path: path + "." + key)
                }
            } else if let lhs = expected as? [Any], let rhs = actual as? [Any] {
                guard lhs.count == rhs.count else { result.append(path + ".count"); return }
                for index in lhs.indices { compare(lhs[index], rhs[index], path: path + "[\(index)]") }
            } else if let lhs = expected as? NSNumber, let rhs = actual as? NSNumber {
                let leftBoolean = CFGetTypeID(lhs) == CFBooleanGetTypeID()
                let rightBoolean = CFGetTypeID(rhs) == CFBooleanGetTypeID()
                if leftBoolean || rightBoolean {
                    if leftBoolean != rightBoolean || lhs != rhs { result.append(path) }
                } else if ["f", "d"].contains(String(cString: lhs.objCType))
                            || ["f", "d"].contains(String(cString: rhs.objCType)) {
                    let l = lhs.doubleValue, r = rhs.doubleValue
                    if !l.isFinite || !r.isFinite || abs(l - r) > 0.00001 + 0.00001 * max(abs(l), abs(r)) { result.append(path) }
                } else if lhs != rhs { result.append(path) }
            } else if let lhs = expected as? String, let rhs = actual as? String {
                if lhs != rhs { result.append(path) }
            } else if !(expected is NSNull && actual is NSNull) { result.append(path) }
        }
        compare(try JSONSerialization.jsonObject(with: expected), try JSONSerialization.jsonObject(with: actual), path: "result")
        return result
    }
}
