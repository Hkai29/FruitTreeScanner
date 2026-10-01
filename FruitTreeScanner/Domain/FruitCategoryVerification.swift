import Foundation

extension FruitCategory {
    /// The categories supported by the current user-facing scan workflow.
    static let scanSupportedCategories: [FruitCategory] = [
        .apple, .orange, .pear, .persimmon, .grape, .strawberry
    ]

    static func scanCategory(for rawValue: String) -> FruitCategory {
        guard let category = FruitCategory(rawValue: rawValue),
              scanSupportedCategories.contains(category) else {
            return .apple
        }
        return category
    }
}

struct FruitCategorySuggestion: Sendable, Equatable {
    let category: FruitCategory
    let confidence: Float
    let supportingFrameCount: Int
    let competingCategory: FruitCategory?
}

struct FruitCategoryMismatch: Sendable, Equatable, Identifiable {
    let selectedCategory: FruitCategory
    let dominantDetectedCategory: FruitCategory
    let supportingFrameCount: Int
    let confidence: Float

    var id: String { "\(selectedCategory.rawValue)-\(dominantDetectedCategory.rawValue)" }
}

struct FruitCategoryVerificationSummary: Sendable, Equatable {
    var selectedCategory: FruitCategory
    var detectedCategoryCounts: [String: Int]
    var nonTargetDetectionCount: Int
    var dominantNonTargetCategory: FruitCategory?
    var categoryMismatchDetected: Bool
    var automaticSuggestion: FruitCategorySuggestion?

    static func make(selectedCategory: FruitCategory, observations: [Observation]) -> FruitCategoryVerificationSummary {
        make(selectedCategory: selectedCategory, evidence: observations.map(FruitCategoryObservation.init))
    }

    static func make(selectedCategory: FruitCategory, evidence detections: [FruitCategoryObservation]) -> FruitCategoryVerificationSummary {
        let suggestion = FruitCategoryVerification.suggestion(evidence: detections)
        let mismatch = FruitCategoryVerification.mismatch(
            selectedCategory: selectedCategory,
            evidence: detections
        )
        var counts: [String: Int] = [:]
        for detection in detections where FruitCategory.scanSupportedCategories.contains(detection.category) {
            counts[detection.category.rawValue, default: 0] += 1
        }
        let nonTargetCount = detections.filter { $0.category != selectedCategory }.count
        return FruitCategoryVerificationSummary(
            selectedCategory: selectedCategory,
            detectedCategoryCounts: counts,
            nonTargetDetectionCount: nonTargetCount,
            dominantNonTargetCategory: mismatch?.dominantDetectedCategory,
            categoryMismatchDetected: mismatch != nil,
            automaticSuggestion: suggestion
        )
    }
}

enum FruitCategoryVerification {
    private static let minimumSupportingFrames = 3
    private static let minimumAverageConfidence: Float = 0.75

    static func suggestion(observations: [Observation]) -> FruitCategorySuggestion? {
        suggestion(evidence: observations.map(FruitCategoryObservation.init))
    }

    static func suggestion(evidence detections: [FruitCategoryObservation]) -> FruitCategorySuggestion? {
        let evidence = rankedEvidence(from: detections)
        guard let dominant = evidence.first,
              dominant.frameCount >= minimumSupportingFrames,
              dominant.averageConfidence >= minimumAverageConfidence,
              dominant.frameCount > (evidence.dropFirst().first?.frameCount ?? 0) else {
            return nil
        }
        return FruitCategorySuggestion(
            category: dominant.category,
            confidence: dominant.averageConfidence,
            supportingFrameCount: dominant.frameCount,
            competingCategory: evidence.dropFirst().first?.category
        )
    }

    static func mismatch(
        selectedCategory: FruitCategory,
        observations: [Observation]
    ) -> FruitCategoryMismatch? {
        mismatch(selectedCategory: selectedCategory, evidence: observations.map(FruitCategoryObservation.init))
    }

    static func mismatch(
        selectedCategory: FruitCategory,
        evidence detections: [FruitCategoryObservation]
    ) -> FruitCategoryMismatch? {
        guard let suggestion = suggestion(evidence: detections), suggestion.category != selectedCategory else {
            return nil
        }
        let selectedFrames = rankedEvidence(from: detections)
            .first(where: { $0.category == selectedCategory })?.frameCount ?? 0
        guard suggestion.supportingFrameCount > selectedFrames else { return nil }
        return FruitCategoryMismatch(
            selectedCategory: selectedCategory,
            dominantDetectedCategory: suggestion.category,
            supportingFrameCount: suggestion.supportingFrameCount,
            confidence: suggestion.confidence
        )
    }

    private struct Evidence {
        let category: FruitCategory
        let frameCount: Int
        let averageConfidence: Float
    }

    private static func rankedEvidence(from detections: [FruitCategoryObservation]) -> [Evidence] {
        let supported = detections.filter { FruitCategory.scanSupportedCategories.contains($0.category) }
        let grouped = Dictionary(grouping: supported, by: \.category)
        return grouped.compactMap { category, values in
            let perFrame = Dictionary(grouping: values, by: \.timestamp).compactMap { _, frameValues in
                frameValues.map(\.confidence).max()
            }
            guard !perFrame.isEmpty else { return nil }
            return Evidence(
                category: category,
                frameCount: perFrame.count,
                averageConfidence: perFrame.reduce(0, +) / Float(perFrame.count)
            )
        }.sorted {
            $0.frameCount == $1.frameCount
                ? $0.averageConfidence > $1.averageConfidence
                : $0.frameCount > $1.frameCount
        }
    }
}

/// Category verification needs no spatial evidence or pixel-buffer sampling.
struct FruitCategoryObservation: Sendable {
    let category: FruitCategory
    let timestamp: TimeInterval
    let confidence: Float

    init(category: FruitCategory, timestamp: TimeInterval, confidence: Float) {
        self.category = category
        self.timestamp = timestamp
        self.confidence = confidence
    }

    init(_ observation: Observation) {
        category = observation.category
        timestamp = observation.timestamp
        confidence = observation.confidence
    }
}
