import Foundation

enum YieldCalibrationContext {
    /// This seed belongs to the legacy context schema, not runtime fusion.
    static let legacyDefaultFusionSphericityThreshold: Float = 0.5
    /// Compatibility for raw estimator callers without a prepared ScanPlan.
    static var bundledModelIdentity: ScanModelIdentity { ScanModelFingerprint.bundledIdentity }

    static var bundledModelFingerprint: String? {
        bundledModelIdentity.fingerprint
    }

    static func make(parameters: [String: FruitVarietyParams], cluster: ClusterConfig, fusion: FruitScanConfig, color: ColorFilter?, modelFingerprint: String? = bundledModelFingerprint, experimentConfiguration: FruitScanExperimentConfig = .default, resourceBudget: ScanResourceBudget = .default, legacyFusionSphericityThreshold: Float) -> String? {
        guard let modelFingerprint else { return nil }
        let encoder = JSONEncoder()
        func object<T: Encodable>(_ value: T) throws -> Any { try JSONSerialization.jsonObject(with: encoder.encode(value), options: [.fragmentsAllowed]) }
        do {
            var params = try object(parameters) as? [String: [String: Any]] ?? [:]
            for key in Array(params.keys) {
                params[key]?.removeValue(forKey: "id")
                params[key]?.removeValue(forKey: "isCustomized")
            }
            // Old contexts included default seeds beside the resolved settings.
            // Retain those keys only in this compatibility encoding. They are no
            // longer independently mutable fields of the runtime experiment.
            var experiment = try object(experimentConfiguration) as? [String: Any] ?? [:]
            let defaults = try object(FruitScanConfig.default) as? [String: Any] ?? [:]
            experiment["detector"] = defaults.filter { ["imageDetectionInterval", "minConfidence"].contains($0.key) }
            experiment["clustering"] = try object(ClusterConfig.default)
            var fusionDefaults = experiment["fusion"] as? [String: Any] ?? [:]
            for key in ["sizeTolerance", "stableDetectionTimeWindow"] {
                fusionDefaults[key] = defaults[key]
            }
            fusionDefaults["sphericityThreshold"] = try object(legacyDefaultFusionSphericityThreshold)
            fusionDefaults["minimumStableDetections"] = defaults["minimumStableDetectionsForYield"]
            experiment["fusion"] = fusionDefaults
            var fusionContext = try object(fusion) as? [String: Any] ?? [:]
            // Encode Float through JSONEncoder, as before; bridging it directly
            // to JSONSerialization can change its decimal representation.
            fusionContext["sphericityThreshold"] = try object(legacyFusionSphericityThreshold)
            var payload: [String: Any] = ["algorithm": YieldAlgorithmRevision.current, "modelSHA256": modelFingerprint,
                "parameters": params, "cluster": try object(cluster), "fusion": fusionContext,
                "color": try object(color), "experiment": experiment]
            // Preserve the established default context bytes. Reduced sampling
            // budgets define a different calibration population.
            if resourceBudget != .default { payload["resourceBudget"] = try object(resourceBudget) }
            let data = try JSONSerialization.data(withJSONObject: payload, options: [.sortedKeys])
            return String(data: data, encoding: .utf8)
        } catch { return nil }
    }
}


// MARK: - 校准记录

struct CalibrationRecord: Codable, Identifiable, Sendable {
    let id: UUID
    let treeID: String
    let scanDate: Date
    let estimatedFruitCount: Int
    let manualFruitCount: Int?
    let estimatedYieldKg: Double
    let actualYieldKg: Double?
    let fruitType: String
    var algorithmRevision: String? = nil
    var calibrationContext: String? = nil

    var countError: Double? {
        guard let manual = manualFruitCount, manual > 0 else { return nil }
        return Double(estimatedFruitCount - manual) / Double(manual) * 100
    }

    var yieldError: Double? {
        guard let actual = actualYieldKg, actual > 0 else { return nil }
        return (estimatedYieldKg - actual) / actual * 100
    }
}

struct CalibrationValidationMetrics: Equatable, Sendable {
    let recordCount: Int
    let countSampleCount: Int
    let yieldSampleCount: Int
    let countMAE: Double?
    let countMAPE: Double?
    let countRMSE: Double?
    let yieldMAE: Double?
    let yieldMAPE: Double?
    let yieldRMSE: Double?

    var hasEvidence: Bool {
        countSampleCount > 0 || yieldSampleCount > 0
    }

    static func make(from records: [CalibrationRecord]) -> CalibrationValidationMetrics {
        let countSamples = records.compactMap(countErrorSample)
        let yieldSamples = records.compactMap(yieldErrorSample)
        let recordsWithEvidence = records.filter {
            countErrorSample($0) != nil || yieldErrorSample($0) != nil
        }

        return CalibrationValidationMetrics(
            recordCount: recordsWithEvidence.count,
            countSampleCount: countSamples.count,
            yieldSampleCount: yieldSamples.count,
            countMAE: meanAbsoluteError(countSamples),
            countMAPE: meanAbsolutePercentageError(countSamples),
            countRMSE: rootMeanSquaredError(countSamples),
            yieldMAE: meanAbsoluteError(yieldSamples),
            yieldMAPE: meanAbsolutePercentageError(yieldSamples),
            yieldRMSE: rootMeanSquaredError(yieldSamples)
        )
    }

    private static func countErrorSample(_ record: CalibrationRecord) -> ValidationErrorSample? {
        guard record.estimatedFruitCount >= 0,
              let manualFruitCount = record.manualFruitCount,
              manualFruitCount > 0 else {
            return nil
        }
        return ValidationErrorSample(
            estimate: Double(record.estimatedFruitCount),
            truth: Double(manualFruitCount)
        )
    }

    private static func yieldErrorSample(_ record: CalibrationRecord) -> ValidationErrorSample? {
        guard record.estimatedYieldKg.isFinite,
              record.estimatedYieldKg >= 0,
              let actualYieldKg = record.actualYieldKg,
              actualYieldKg.isFinite,
              actualYieldKg > 0 else {
            return nil
        }
        return ValidationErrorSample(estimate: record.estimatedYieldKg, truth: actualYieldKg)
    }

    private static func meanAbsoluteError(_ samples: [ValidationErrorSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + abs($1.error) } / Double(samples.count)
    }

    private static func meanAbsolutePercentageError(_ samples: [ValidationErrorSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        return samples.reduce(0) { $0 + $1.absolutePercentageError } / Double(samples.count)
    }

    private static func rootMeanSquaredError(_ samples: [ValidationErrorSample]) -> Double? {
        guard !samples.isEmpty else { return nil }
        let meanSquared = samples.reduce(0) { $0 + $1.error * $1.error } / Double(samples.count)
        return sqrt(meanSquared)
    }
}

private struct ValidationErrorSample {
    let estimate: Double
    let truth: Double

    var error: Double {
        estimate - truth
    }

    var absolutePercentageError: Double {
        abs(error) / truth * 100
    }
}


enum YieldCalibrationCorrector {
    static func correction(
        from records: [CalibrationRecord],
        fruitCategory: FruitCategory?,
        fruitType: String,
        requiredAlgorithmRevision: String? = nil,
        requiredContext: String? = nil
    ) -> YieldCalibrationCorrection {
        let matchingRecords = records.filter {
            record($0, matches: fruitCategory, fruitType: fruitType) &&
                (requiredAlgorithmRevision == nil || $0.algorithmRevision == requiredAlgorithmRevision) &&
                (requiredContext == nil || $0.calibrationContext == requiredContext)
        }
        let countRatios = matchingRecords.compactMap(countRatio)
        let yieldRatios = matchingRecords.compactMap(yieldRatio)

        return YieldCalibrationCorrection(
            countFactor: factor(from: countRatios, minValue: 0.5, maxValue: 1.5),
            yieldFactor: factor(from: yieldRatios, minValue: 0.5, maxValue: 2.0),
            countSampleCount: countRatios.count,
            yieldSampleCount: yieldRatios.count
        )
    }

    private static func record(
        _ record: CalibrationRecord,
        matches fruitCategory: FruitCategory?,
        fruitType: String
    ) -> Bool {
        let normalizedRecordType = record.fruitType.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !normalizedRecordType.isEmpty else { return false }

        if normalizedRecordType == fruitType {
            return true
        }
        guard let fruitCategory else { return false }
        return normalizedRecordType == fruitCategory.rawValue
            || normalizedRecordType == fruitCategory.displayName
    }

    private static func countRatio(_ record: CalibrationRecord) -> Double? {
        guard record.estimatedFruitCount > 0,
              let manualFruitCount = record.manualFruitCount,
              manualFruitCount > 0 else {
            return nil
        }
        return Double(manualFruitCount) / Double(record.estimatedFruitCount)
    }

    private static func yieldRatio(_ record: CalibrationRecord) -> Double? {
        guard record.estimatedYieldKg > 0,
              let actualYieldKg = record.actualYieldKg,
              actualYieldKg > 0 else {
            return nil
        }
        return actualYieldKg / record.estimatedYieldKg
    }

    private static func factor(
        from ratios: [Double],
        minValue: Float,
        maxValue: Float
    ) -> Float {
        let validRatios = ratios
            .filter { $0.isFinite && $0 >= 0.2 && $0 <= 5.0 }
            .sorted()
        guard !validRatios.isEmpty else { return 1 }

        let rawFactor: Double
        if validRatios.count.isMultiple(of: 2) {
            let upperIndex = validRatios.count / 2
            rawFactor = (validRatios[upperIndex - 1] + validRatios[upperIndex]) / 2
        } else {
            rawFactor = validRatios[validRatios.count / 2]
        }

        return min(max(Float(rawFactor), minValue), maxValue)
    }
}
