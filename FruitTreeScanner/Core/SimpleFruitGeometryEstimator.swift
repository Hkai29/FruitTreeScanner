// SimpleFruitGeometryEstimator.swift
// Baseline sphere/ellipsoid geometry for per-fruit LiDAR mass estimation.

import Foundation
import simd

enum SimpleFruitGeometryEstimator {
    static func estimate(
        points: [SIMD3<Float>],
        fruitCategory: FruitCategory?,
        densityGPerCm3: Float,
        highConfidenceRatio: Float,
        validDepthRatio: Float,
        createdAt: Date = Date()
    ) -> FruitMassEstimate {
        estimate(
            points: points,
            fruitCategoryName: fruitCategory?.rawValue,
            densityGPerCm3: densityGPerCm3,
            highConfidenceRatio: highConfidenceRatio,
            validDepthRatio: validDepthRatio,
            createdAt: createdAt
        )
    }

    static func estimate(
        points: [SIMD3<Float>],
        fruitCategoryName: String?,
        densityGPerCm3: Float,
        highConfidenceRatio: Float,
        validDepthRatio: Float,
        createdAt: Date = Date()
    ) -> FruitMassEstimate {
        let filteredPoints = points.filter(isUsablePoint)
        let categoryName = normalizedCategoryName(fruitCategoryName)
        let dimensions = dimensionsCm(from: filteredPoints, normalizedCategoryName: categoryName.normalized)
        return makeEstimate(
            fruitCategoryName: categoryName.displayName,
            normalizedCategoryName: categoryName.normalized,
            lengthCm: dimensions.length,
            widthCm: dimensions.width,
            heightCm: dimensions.height,
            densityGPerCm3: densityGPerCm3,
            pointCount: filteredPoints.count,
            highConfidenceRatio: highConfidenceRatio,
            validDepthRatio: validDepthRatio,
            createdAt: createdAt,
            forceSphereBaseline: false
        )
    }

    static func estimateFromDiameter(
        diameterM: Float,
        fruitCategory: FruitCategory?,
        densityGPerCm3: Float,
        pointCount: Int,
        highConfidenceRatio: Float,
        validDepthRatio: Float,
        createdAt: Date = Date()
    ) -> FruitMassEstimate {
        estimateFromDiameter(
            diameterM: diameterM,
            fruitCategoryName: fruitCategory?.rawValue,
            densityGPerCm3: densityGPerCm3,
            pointCount: pointCount,
            highConfidenceRatio: highConfidenceRatio,
            validDepthRatio: validDepthRatio,
            createdAt: createdAt
        )
    }

    static func estimateFromDiameter(
        diameterM: Float,
        fruitCategoryName: String?,
        densityGPerCm3: Float,
        pointCount: Int,
        highConfidenceRatio: Float,
        validDepthRatio: Float,
        createdAt: Date = Date()
    ) -> FruitMassEstimate {
        let categoryName = normalizedCategoryName(fruitCategoryName)
        let diameterCm = diameterM.isFinite ? max(0, diameterM * 100) : 0
        return makeEstimate(
            fruitCategoryName: categoryName.displayName,
            normalizedCategoryName: categoryName.normalized,
            lengthCm: diameterCm,
            widthCm: diameterCm,
            heightCm: diameterCm,
            densityGPerCm3: densityGPerCm3,
            pointCount: max(pointCount, 0),
            highConfidenceRatio: highConfidenceRatio,
            validDepthRatio: validDepthRatio,
            createdAt: createdAt,
            forceSphereBaseline: true
        )
    }

    static func estimate(
        candidate: FruitCandidate,
        fruitCategory: FruitCategory?,
        densityGPerCm3: Float,
        highConfidenceRatio: Float? = nil,
        validDepthRatio: Float = 1,
        createdAt: Date = Date()
    ) -> FruitMassEstimate {
        let qualityHint = highConfidenceRatio ?? candidate.sphericity
        let effectiveValidDepthRatio = candidate.depthSupportRatio ?? validDepthRatio
        if let sourceCategory = candidate.sourceCategory {
            return estimateFromDiameter(
                diameterM: candidate.diameter,
                fruitCategory: fruitCategory ?? sourceCategory,
                densityGPerCm3: densityGPerCm3,
                pointCount: candidate.pointCount,
                highConfidenceRatio: qualityHint,
                validDepthRatio: effectiveValidDepthRatio,
                createdAt: createdAt
            )
        }

        if !candidate.points.isEmpty {
            return estimate(
                points: candidate.points,
                fruitCategory: fruitCategory,
                densityGPerCm3: densityGPerCm3,
                highConfidenceRatio: qualityHint,
                validDepthRatio: effectiveValidDepthRatio,
                createdAt: createdAt
            )
        }

        // TODO: Replace this compatibility path when per-candidate point membership is available upstream.
        return estimateFromDiameter(
            diameterM: candidate.diameter,
            fruitCategory: fruitCategory,
            densityGPerCm3: densityGPerCm3,
            pointCount: candidate.pointCount,
            highConfidenceRatio: qualityHint,
            validDepthRatio: effectiveValidDepthRatio,
            createdAt: createdAt
        )
    }

    private static func makeEstimate(
        fruitCategoryName: String,
        normalizedCategoryName: String?,
        lengthCm: Float,
        widthCm: Float,
        heightCm: Float,
        densityGPerCm3: Float,
        pointCount: Int,
        highConfidenceRatio: Float,
        validDepthRatio: Float,
        createdAt: Date,
        forceSphereBaseline: Bool
    ) -> FruitMassEstimate {
        let equivalentDiameterCm = averageDiameter(lengthCm: lengthCm, widthCm: widthCm, heightCm: heightCm)
        let sphereVolumeCm3 = sphereVolume(equivalentDiameterCm: equivalentDiameterCm)
        let ellipsoidVolumeCm3 = ellipsoidVolume(lengthCm: lengthCm, widthCm: widthCm, heightCm: heightCm)
        let modelUsed = selectedShapeModel(
            normalizedCategoryName: normalizedCategoryName,
            lengthCm: lengthCm,
            widthCm: widthCm,
            heightCm: heightCm,
            forceSphereBaseline: forceSphereBaseline
        )
        let selectedVolumeCm3: Float
        switch modelUsed {
        case .sphere:
            selectedVolumeCm3 = sphereVolumeCm3
        case .ellipsoid:
            selectedVolumeCm3 = ellipsoidVolumeCm3
        case .unavailable:
            selectedVolumeCm3 = 0
        }

        let density = sanitizedDensity(densityGPerCm3)
        var quality = FruitEstimationQualityScorer.score(
            pointCount: pointCount,
            highConfidenceRatio: clampedRatio(highConfidenceRatio),
            validDepthRatio: clampedRatio(validDepthRatio),
            lengthCm: lengthCm,
            widthCm: widthCm,
            heightCm: heightCm,
            fruitCategory: normalizedCategoryName
        )
        var warnings = Set(quality.warningFlags)
        if modelUsed == .sphere {
            warnings.insert(.usingSphereBaseline)
        } else if modelUsed == .ellipsoid {
            warnings.insert(.usingEllipsoidBaseline)
        }
        if normalizedCategoryName == nil {
            warnings.insert(.unknownFruitCategory)
            quality = FruitEstimationQualityResult(
                confidenceScore: min(quality.confidenceScore, 0.65),
                warningFlags: quality.warningFlags
            )
        }

        return FruitMassEstimate(
            id: UUID(),
            fruitCategory: fruitCategoryName,
            lengthCm: lengthCm,
            widthCm: widthCm,
            heightCm: heightCm,
            equivalentDiameterCm: equivalentDiameterCm,
            sphereVolumeCm3: sphereVolumeCm3,
            ellipsoidVolumeCm3: ellipsoidVolumeCm3,
            selectedVolumeCm3: selectedVolumeCm3,
            densityGPerCm3: density,
            estimatedWeightG: selectedVolumeCm3 * density,
            confidenceScore: min(max(quality.confidenceScore, 0), 1),
            pointCount: pointCount,
            highConfidenceRatio: clampedRatio(highConfidenceRatio),
            validDepthRatio: clampedRatio(validDepthRatio),
            shapeModelUsed: modelUsed,
            warningFlags: warnings.sorted { $0.rawValue < $1.rawValue },
            createdAt: createdAt
        )
    }
}
