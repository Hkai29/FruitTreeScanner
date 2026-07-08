// FruitMassEstimate.swift
// Research-facing per-fruit mass estimate model.

import Foundation

enum FruitShapeModelUsed: String, Codable, Sendable {
    case sphere
    case ellipsoid
    case unavailable
}

enum FruitMassEstimateWarningFlag: String, Codable, Sendable, CaseIterable {
    case tooFewPoints
    case lowDepthConfidence
    case lowValidDepthRatio
    case smallFruitLowLiDARReliability
    case usingSphereBaseline
    case usingEllipsoidBaseline
    case suspiciousDimensions
    case unknownFruitCategory
}

struct FruitMassEstimate: Identifiable, Codable, Sendable, Equatable {
    let id: UUID
    let fruitCategory: String
    let lengthCm: Float
    let widthCm: Float
    let heightCm: Float
    let equivalentDiameterCm: Float
    let sphereVolumeCm3: Float
    let ellipsoidVolumeCm3: Float
    let selectedVolumeCm3: Float
    let densityGPerCm3: Float
    let estimatedWeightG: Float
    let confidenceScore: Float
    let pointCount: Int
    let highConfidenceRatio: Float
    let validDepthRatio: Float
    let shapeModelUsed: FruitShapeModelUsed
    let warningFlags: [FruitMassEstimateWarningFlag]
    let createdAt: Date
}
