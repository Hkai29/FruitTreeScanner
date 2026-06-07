import Foundation
import simd

enum ScanYieldEstimateHelpers {
    struct VisibleEstimateCorrection {
        let visibleCount: Float
        let visibleYieldKg: Float
        let note: String
    }

    struct VisibleYieldEstimate {
        let yieldKg: Float
        let meanDiameterCm: Float
        let meanVolumeCm3: Float
    }

    static func estimateQuality(
        for validatedFruits: [ValidatedFruit]
    ) -> (confidence: String, methodUsed: String, sourceDescription: String) {
        if validatedFruits.contains(where: { $0.source == .fused }) {
            let confidence = weightedEvidence(for: validatedFruits) >= 5 ? "high" : "medium"
            return (confidence, "fusion_visual_calibrated", "RGB+LiDAR 融合检测")
        }

        if validatedFruits.contains(where: { $0.source == .imageOnly }) {
            return ("medium", "image_visual_calibrated", "视觉检测估计")
        }

        return ("low", "cloud_only_calibrated", "点云候选估计")
    }

    static func computeYieldFromValidatedFruits(
        _ validatedFruits: [ValidatedFruit],
        candidates: [FruitCandidate],
        paramsByCategory: [String: FruitVarietyParams],
        defaultParams: FruitVarietyParams
    ) -> VisibleYieldEstimate {
        guard !validatedFruits.isEmpty else {
            return VisibleYieldEstimate(yieldKg: 0, meanDiameterCm: 0, meanVolumeCm3: 0)
        }

        var totalWeightKg: Float = 0
        var weightedDiameterSum: Float = 0
        var weightedVolumeSum: Float = 0
        var measuredWeight: Float = 0
        var usedCandidateIDs = Set<UUID>()

        for fruit in validatedFruits {
            let availableCandidates = candidates.filter { !usedCandidateIDs.contains($0.id) }
            let matchedCandidate = availableCandidates
                .map { c in (candidate: c, dist: simd_distance(c.position, fruit.position)) }
                .filter { $0.dist < 0.1 }
                .min(by: { $0.dist < $1.dist })
                .map { $0.candidate }

            if let candidate = matchedCandidate {
                let radiusCm = candidate.diameter * 100 / 2
                let volumeCm3 = (4.0 / 3.0) * Float.pi * pow(radiusCm, 3)
                let density = fruit.category.flatMap { paramsByCategory[$0.rawValue] }?.density ?? defaultParams.density
                let weightG = volumeCm3 * density
                let sourceWeight = fruit.source.countWeight
                totalWeightKg += weightG / 1000 * sourceWeight
                weightedDiameterSum += candidate.diameter * 100 * sourceWeight
                weightedVolumeSum += volumeCm3 * sourceWeight
                measuredWeight += sourceWeight
                usedCandidateIDs.insert(candidate.id)
            } else {
                let avgG = fruit.category.flatMap { paramsByCategory[$0.rawValue] }?.averageWeightG ?? defaultParams.averageWeightG
                totalWeightKg += avgG / 1000 * fruit.source.countWeight
            }
        }

        let meanDiameter = measuredWeight > 0 ? weightedDiameterSum / measuredWeight : 0
        let meanVolume = measuredWeight > 0 ? weightedVolumeSum / measuredWeight : 0
        return VisibleYieldEstimate(
            yieldKg: totalWeightKg,
            meanDiameterCm: meanDiameter,
            meanVolumeCm3: meanVolume
        )
    }

    private static func weightedEvidence(for validatedFruits: [ValidatedFruit]) -> Float {
        validatedFruits.reduce(0) { total, fruit in
            total + fruit.source.countWeight * max(fruit.confidence, 0)
        }
    }
}
