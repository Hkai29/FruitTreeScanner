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
        let massEstimates: [FruitMassEstimate]
    }

    static func estimateQuality(
        for validatedFruits: [ValidatedFruit]
    ) -> (confidence: String, methodUsed: String, sourceDescription: String) {
        if validatedFruits.contains(where: { $0.source == .fused }) {
            let confidence = weightedEvidence(for: validatedFruits) >= 5 ? "high" : "medium"
            return (confidence, "fusion_visual_calibrated", "RGB+LiDAR 融合检测")
        }

        if validatedFruits.contains(where: { $0.source == .trackedImage }) {
            return ("medium", "tracked_image_visual_calibrated", "多帧视觉轨迹估计")
        }

        if validatedFruits.contains(where: { $0.source == .imageOnly }) {
            return ("medium", "image_visual_calibrated", "视觉检测估计")
        }

        return ("low", "cloud_only_calibrated", "点云候选估计")
    }

    static func adjustQualityForCoverageRisk(
        confidence: String,
        methodUsed: String,
        sourceDescription: String,
        correctionK: Float,
        scanAngleCoverage: Float
    ) -> (confidence: String, methodUsed: String, sourceDescription: String, noteSuffix: String) {
        let safeK = correctionK.isFinite ? min(max(correctionK, 1), 3) : 1
        let safeCoverage = scanAngleCoverage.isFinite ? min(max(scanAngleCoverage, 0), 1) : 0
        guard safeK >= 1.25 else {
            return (confidence, methodUsed, sourceDescription, "")
        }

        let coverageDegrees = safeCoverage * 360
        if safeCoverage < 0.35 && safeK >= 1.35 {
            return (
                "manual_review",
                methodUsed + "_coverage_review",
                sourceDescription,
                String(format: "；扫描角度覆盖约%.0f°，遮挡校正较强，建议补扫另一侧后复核", coverageDegrees)
            )
        }

        if safeCoverage < 0.55 && safeK >= 1.75 {
            return (
                "manual_review",
                methodUsed + "_coverage_review",
                sourceDescription,
                String(format: "；扫描角度覆盖约%.0f°，遮挡校正偏强，建议现场复核", coverageDegrees)
            )
        }

        guard confidence == "high", safeCoverage < 0.55 else {
            return (confidence, methodUsed, sourceDescription, "")
        }

        return (
            "medium",
            methodUsed + "_coverage_limited",
            sourceDescription,
            String(format: "；扫描角度覆盖约%.0f°，结果已按有限覆盖降为中等置信度", coverageDegrees)
        )
    }

    static func computeYieldFromValidatedFruits(
        _ validatedFruits: [ValidatedFruit],
        candidates: [FruitCandidate],
        paramsByCategory: [String: FruitVarietyParams],
        defaultParams: FruitVarietyParams
    ) -> VisibleYieldEstimate {
        guard !validatedFruits.isEmpty else {
            return VisibleYieldEstimate(yieldKg: 0, meanDiameterCm: 0, meanVolumeCm3: 0, massEstimates: [])
        }

        var totalWeightKg: Float = 0
        var weightedDiameterSum: Float = 0
        var weightedVolumeSum: Float = 0
        var measuredWeight: Float = 0
        var usedCandidateIDs = Set<UUID>()
        var massEstimates: [FruitMassEstimate] = []

        for fruit in validatedFruits {
            let availableCandidates = candidates.filter {
                !usedCandidateIDs.contains($0.id) &&
                candidate($0, isCompatibleWith: fruit)
            }
            let matchedCandidate = availableCandidates
                .map { c in (candidate: c, dist: simd_distance(c.position, fruit.position)) }
                .filter { $0.dist < 0.1 }
                .min(by: { $0.dist < $1.dist })
                .map { $0.candidate }

            if let candidate = matchedCandidate {
                let params = fruit.category.flatMap { paramsByCategory[$0.rawValue] } ?? defaultParams
                let evidenceWeight = FruitCounter.evidenceWeight(for: fruit)
                let massEstimate = SimpleFruitGeometryEstimator.estimate(
                    candidate: candidate,
                    fruitCategory: fruit.category ?? params.fruitCategory,
                    densityGPerCm3: params.density,
                    highConfidenceRatio: fruit.confidence,
                    validDepthRatio: 1
                )
                totalWeightKg += massEstimate.estimatedWeightG / 1000 * evidenceWeight
                weightedDiameterSum += massEstimate.equivalentDiameterCm * evidenceWeight
                weightedVolumeSum += massEstimate.selectedVolumeCm3 * evidenceWeight
                measuredWeight += evidenceWeight
                usedCandidateIDs.insert(candidate.id)
                massEstimates.append(massEstimate)
            } else {
                let avgG = fruit.category.flatMap { paramsByCategory[$0.rawValue] }?.averageWeightG ?? defaultParams.averageWeightG
                totalWeightKg += avgG / 1000 * FruitCounter.evidenceWeight(for: fruit)
            }
        }

        let meanDiameter = measuredWeight > 0 ? weightedDiameterSum / measuredWeight : 0
        let meanVolume = measuredWeight > 0 ? weightedVolumeSum / measuredWeight : 0
        return VisibleYieldEstimate(
            yieldKg: totalWeightKg,
            meanDiameterCm: meanDiameter,
            meanVolumeCm3: meanVolume,
            massEstimates: massEstimates
        )
    }

    private static func weightedEvidence(for validatedFruits: [ValidatedFruit]) -> Float {
        validatedFruits.reduce(0) { total, fruit in
            total + FruitCounter.evidenceWeight(for: fruit)
        }
    }

    private static func candidate(
        _ candidate: FruitCandidate,
        isCompatibleWith fruit: ValidatedFruit
    ) -> Bool {
        guard let sourceCategory = candidate.sourceCategory,
              let fruitCategory = fruit.category else {
            return true
        }
        return sourceCategory == fruitCategory
    }
}
