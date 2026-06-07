// SimpleFruitGeometryEstimator.swift
// Baseline sphere/ellipsoid geometry for per-fruit LiDAR mass estimation.

import Foundation
import simd

enum SimpleFruitGeometryEstimator {
    private static let maxAbsCoordinateMeters: Float = 20
    private static let sphereIfRoundCategories: Set<String> = [
        "apple",
        "orange",
        "mandarin",
        "citrus",
        "tomato",
    ]
    private static let ellipsoidPreferredCategories: Set<String> = [
        "pear",
        "mango",
        "peach",
        "pomelo",
        "grapefruit",
        "pomegranate",
        "persimmon",
    ]
    private static let smallFruitCategories: Set<String> = [
        "strawberry",
        "blueberry",
        "grape",
        "cherry",
        "mulberry",
    ]
    private static let knownCategoryNames: Set<String> = {
        Set(FruitCategory.allCases.map(\.rawValue))
            .union(sphereIfRoundCategories)
            .union(ellipsoidPreferredCategories)
            .union(smallFruitCategories)
    }()

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
        let dimensions = dimensionsCm(from: filteredPoints)
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
        if !candidate.points.isEmpty {
            return estimate(
                points: candidate.points,
                fruitCategory: fruitCategory,
                densityGPerCm3: densityGPerCm3,
                highConfidenceRatio: qualityHint,
                validDepthRatio: validDepthRatio,
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
            validDepthRatio: validDepthRatio,
            createdAt: createdAt
        )
    }

    static func isSmallFruitCategory(_ fruitCategoryName: String?) -> Bool {
        guard let normalized = fruitCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return smallFruitCategories.contains(normalized)
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

    private static func isUsablePoint(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite &&
            point.y.isFinite &&
            point.z.isFinite &&
            abs(point.x) <= maxAbsCoordinateMeters &&
            abs(point.y) <= maxAbsCoordinateMeters &&
            abs(point.z) <= maxAbsCoordinateMeters
    }

    private static func dimensionsCm(from points: [SIMD3<Float>]) -> (length: Float, width: Float, height: Float) {
        guard let first = points.first else { return (0, 0, 0) }
        var minPoint = first
        var maxPoint = first
        for point in points.dropFirst() {
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }
        let extent = maxPoint - minPoint
        return (
            max(0, extent.x * 100),
            max(0, extent.y * 100),
            max(0, extent.z * 100)
        )
    }

    private static func selectedShapeModel(
        normalizedCategoryName: String?,
        lengthCm: Float,
        widthCm: Float,
        heightCm: Float,
        forceSphereBaseline: Bool
    ) -> FruitShapeModelUsed {
        let dimensions = [lengthCm, widthCm, heightCm]
        guard dimensions.allSatisfy({ $0.isFinite && $0 > 0 }) else {
            return .unavailable
        }
        if forceSphereBaseline {
            return .sphere
        }

        guard let normalizedCategoryName else {
            return .ellipsoid
        }
        if ellipsoidPreferredCategories.contains(normalizedCategoryName) {
            return .ellipsoid
        }
        if sphereIfRoundCategories.contains(normalizedCategoryName) {
            return axesAreClose(lengthCm: lengthCm, widthCm: widthCm, heightCm: heightCm) ? .sphere : .ellipsoid
        }
        return .ellipsoid
    }

    private static func axesAreClose(lengthCm: Float, widthCm: Float, heightCm: Float) -> Bool {
        let dimensions = [lengthCm, widthCm, heightCm]
        guard let minDimension = dimensions.min(), let maxDimension = dimensions.max(), minDimension > 0 else {
            return false
        }
        return maxDimension / minDimension <= 1.2
    }

    private static func averageDiameter(lengthCm: Float, widthCm: Float, heightCm: Float) -> Float {
        guard lengthCm.isFinite, widthCm.isFinite, heightCm.isFinite else { return 0 }
        return max(0, (lengthCm + widthCm + heightCm) / 3)
    }

    private static func sphereVolume(equivalentDiameterCm: Float) -> Float {
        guard equivalentDiameterCm.isFinite, equivalentDiameterCm > 0 else { return 0 }
        let radius = equivalentDiameterCm / 2
        return (4.0 / 3.0) * Float.pi * pow(radius, 3)
    }

    private static func ellipsoidVolume(lengthCm: Float, widthCm: Float, heightCm: Float) -> Float {
        guard lengthCm.isFinite, widthCm.isFinite, heightCm.isFinite,
              lengthCm > 0, widthCm > 0, heightCm > 0 else { return 0 }
        return (4.0 / 3.0) * Float.pi * (lengthCm / 2) * (widthCm / 2) * (heightCm / 2)
    }

    private static func normalizedCategoryName(_ fruitCategoryName: String?) -> (displayName: String, normalized: String?) {
        guard let rawName = fruitCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return ("unknown", nil)
        }
        let normalized = rawName.lowercased()
        return (rawName, knownCategoryNames.contains(normalized) ? normalized : nil)
    }

    private static func sanitizedDensity(_ density: Float) -> Float {
        guard density.isFinite, density > 0 else { return 1.0 }
        return density
    }

    private static func clampedRatio(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
