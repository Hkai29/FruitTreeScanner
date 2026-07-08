// SimpleFruitGeometryCategories.swift
// Fruit category normalization and shape model selection for geometry estimates.

import Foundation

extension SimpleFruitGeometryEstimator {
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

    static func isSmallFruitCategory(_ fruitCategoryName: String?) -> Bool {
        guard let normalized = fruitCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines).lowercased() else {
            return false
        }
        return smallFruitCategories.contains(normalized)
    }

    static func usesRoundSpherePrior(_ normalizedCategoryName: String?) -> Bool {
        guard let normalizedCategoryName else { return false }
        return sphereIfRoundCategories.contains(normalizedCategoryName)
    }

    static func diameterRangeMeters(for normalizedCategoryName: String?) -> ClosedRange<Float>? {
        guard let normalizedCategoryName else { return nil }
        if let category = FruitCategory(rawValue: normalizedCategoryName) {
            return category.sizeRange
        }
        switch normalizedCategoryName {
        case "citrus":
            return FruitCategory.orange.sizeRange
        case "tomato":
            return 0.04...0.10
        default:
            return nil
        }
    }

    static func normalizedCategoryName(_ fruitCategoryName: String?) -> (displayName: String, normalized: String?) {
        guard let rawName = fruitCategoryName?.trimmingCharacters(in: .whitespacesAndNewlines),
              !rawName.isEmpty else {
            return ("unknown", nil)
        }
        let normalized = rawName.lowercased()
        return (rawName, knownCategoryNames.contains(normalized) ? normalized : nil)
    }

    static func selectedShapeModel(
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
}
