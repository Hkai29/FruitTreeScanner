// FruitEstimationQualityScorer.swift
// Heuristic confidence and warning scoring for per-fruit geometry estimates.

import Foundation

struct FruitEstimationQualityResult: Sendable, Equatable {
    let confidenceScore: Float
    let warningFlags: [FruitMassEstimateWarningFlag]
}

enum FruitEstimationQualityScorer {
    static let minimumReliablePointCount = 15

    static func score(
        pointCount: Int,
        highConfidenceRatio: Float,
        validDepthRatio: Float,
        lengthCm: Float,
        widthCm: Float,
        heightCm: Float,
        fruitCategory: String?
    ) -> FruitEstimationQualityResult {
        var score: Float = 1.0
        var warnings: Set<FruitMassEstimateWarningFlag> = []

        if pointCount < minimumReliablePointCount {
            warnings.insert(.tooFewPoints)
            score *= max(0.2, Float(pointCount) / Float(minimumReliablePointCount))
        } else if pointCount < 40 {
            score *= 0.8
        }

        if highConfidenceRatio < 0.4 {
            warnings.insert(.lowDepthConfidence)
            score *= max(0.35, highConfidenceRatio / 0.4)
        }

        if validDepthRatio < 0.5 {
            warnings.insert(.lowValidDepthRatio)
            score *= max(0.35, validDepthRatio / 0.5)
        }

        if hasSuspiciousDimensions(lengthCm: lengthCm, widthCm: widthCm, heightCm: heightCm) {
            warnings.insert(.suspiciousDimensions)
            score *= 0.45
        }

        if SimpleFruitGeometryEstimator.isSmallFruitCategory(fruitCategory) {
            warnings.insert(.smallFruitLowLiDARReliability)
            score *= 0.75
        }

        if warnings.contains(.suspiciousDimensions) {
            score = min(score, 0.4)
        }
        if warnings.contains(.tooFewPoints) {
            score = min(score, 0.45)
        }
        if warnings.contains(.lowDepthConfidence) || warnings.contains(.lowValidDepthRatio) {
            score = min(score, 0.55)
        }
        if warnings.contains(.smallFruitLowLiDARReliability) {
            score = min(score, 0.7)
        }

        return FruitEstimationQualityResult(
            confidenceScore: clamp(score),
            warningFlags: warnings.sorted { $0.rawValue < $1.rawValue }
        )
    }

    private static func hasSuspiciousDimensions(lengthCm: Float, widthCm: Float, heightCm: Float) -> Bool {
        let dimensions = [lengthCm, widthCm, heightCm]
        guard dimensions.allSatisfy({ $0.isFinite && $0 > 0 }) else { return true }

        let maxDimension = dimensions.max() ?? 0
        let minDimension = dimensions.min() ?? 0
        guard minDimension > 0 else { return true }

        let equivalentDiameter = dimensions.reduce(0, +) / 3
        return equivalentDiameter < 0.5 || equivalentDiameter > 40 || maxDimension / minDimension > 4
    }

    private static func clamp(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
