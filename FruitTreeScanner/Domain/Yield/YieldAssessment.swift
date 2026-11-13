import Foundation

/// Frozen numerical inputs. Admission remains owned by FusionEvidencePipeline;
/// arbitrary validated or image-only fruit cannot enter this assessment.
struct YieldAssessmentInput {
    let points: [ColoredPoint]
    let targetFruitPoints: [ColoredPoint]
    let reliableEvidence: [ReliableYieldEvidence]
    let evidenceObservations: [Observation]
    let candidates: [FruitCandidate]
    let paramsByCategory: [String: FruitVarietyParams]
    let defaultParams: FruitVarietyParams
    let defaultCategory: FruitCategory
    let occlusionConfiguration: OcclusionExperimentConfig
    let calibration: YieldCalibrationCorrection
    let validationSourceReliability: Float
}

struct VisibleYieldAssessment {
    let calibratedCount: Int
    let calibrationBaseYieldKg: Float
    let finalYieldKg: Float
    let confidence: String
    let methodUsed: String
    let sourceDescription: String
    let noteSuffix: String
}

struct YieldAssessment {
    enum Outcome {
        case visible(VisibleYieldAssessment)
        case zero
    }

    let countResult: FruitCountResult
    let validatedFruits: [ValidatedFruit]
    let weightedVisibleCount: Float
    let visibleYield: ScanYieldEstimateHelpers.VisibleYieldEstimate
    let occlusion: YieldOcclusionCorrection
    let outcome: Outcome
}

struct UncalibratedSeasonYieldAssessment {
    let countResult: FruitCountResult
    let canopyGeometry: CanopyGeometryEstimate?
    let finalYieldKg: Float
    let reason: ZeroYieldReason
}

enum YieldAssessmentEvaluator {
    static func assess(_ input: YieldAssessmentInput) -> YieldAssessment {
        let fruitCounter = FruitCounter()
        let validatedFruits = input.reliableEvidence.map(\.validatedFruit)
        let countResult = fruitCounter.count(input.reliableEvidence, defaultCategory: input.defaultCategory)
        let weightedVisibleCount = fruitCounter.weightedTotal(input.reliableEvidence)
        let visibleYield = ScanYieldEstimateHelpers.computeYieldFromReliableEvidence(
            input.reliableEvidence,
            candidates: input.candidates,
            paramsByCategory: input.paramsByCategory,
            defaultParams: input.defaultParams
        )
        let visibleCountForCorrection = weightedVisibleCount > 0
            ? max(Int(weightedVisibleCount.rounded()), 1)
            : 0
        let occlusion = YieldOcclusionCalculator.makeOcclusionCorrection(
            points: input.points,
            fruitColoredPoints: input.targetFruitPoints,
            detections: input.evidenceObservations,
            validatedFruits: validatedFruits,
            validationSourceReliability: input.validationSourceReliability,
            visibleCountForCorrection: visibleCountForCorrection,
            weightedVisibleCount: weightedVisibleCount,
            configuration: input.occlusionConfiguration
        )

        let outcome: YieldAssessment.Outcome
        // Use unrounded evidence weight: a category count rounded to zero still
        // has visible evidence. Keep both count rounding stages separate.
        if weightedVisibleCount > 0 {
            let finalYieldKg = visibleYield.yieldKg
                * occlusion.correction
                * input.calibration.yieldFactor
            let calibratedCount = max(
                Int((Float(occlusion.correctedCount) * input.calibration.countFactor).rounded()),
                0
            )
            let quality = ScanYieldEstimateHelpers.estimateQuality(
                for: validatedFruits, massEstimate: visibleYield
            )
            let adjustedQuality = ScanYieldEstimateHelpers.adjustQualityForCoverageRisk(
                confidence: quality.confidence,
                methodUsed: quality.methodUsed,
                sourceDescription: quality.sourceDescription,
                correctionK: occlusion.correction,
                scanAngleCoverage: occlusion.scanAngleCoverage
            )
            outcome = .visible(VisibleYieldAssessment(
                calibratedCount: calibratedCount,
                calibrationBaseYieldKg: visibleYield.yieldKg * occlusion.correction,
                finalYieldKg: finalYieldKg,
                confidence: adjustedQuality.confidence,
                methodUsed: adjustedQuality.methodUsed,
                sourceDescription: adjustedQuality.sourceDescription,
                noteSuffix: adjustedQuality.noteSuffix
            ))
        } else {
            outcome = .zero
        }
        return YieldAssessment(
            countResult: countResult,
            validatedFruits: validatedFruits,
            weightedVisibleCount: weightedVisibleCount,
            visibleYield: visibleYield,
            occlusion: occlusion,
            outcome: outcome
        )
    }

    /// Separate early entry: an untrained season needs canopy facts and an
    /// empty count, without constructing normal clustering/fusion/mass inputs.
    static func assessUncalibratedSeason(
        points: [ColoredPoint],
        defaultCategory: FruitCategory
    ) -> UncalibratedSeasonYieldAssessment {
        let canopyGeometry = CanopyGeometryEstimator.estimate(points: points)
        let countResult = FruitCounter().count([] as [ReliableYieldEvidence], defaultCategory: defaultCategory)
        return UncalibratedSeasonYieldAssessment(
            countResult: countResult, canopyGeometry: canopyGeometry, finalYieldKg: 0,
            reason: .uncalibratedSeason
        )
    }
}
