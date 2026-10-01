// Legacy category checks copy only scalar evidence; they never sample depth buffers.
extension FruitCategoryVerificationSummary {
    static func make(selectedCategory: FruitCategory, detections: [DetectedFruit]) -> FruitCategoryVerificationSummary {
        make(selectedCategory: selectedCategory, evidence: detections.map(FruitCategoryObservation.init))
    }
}

extension FruitCategoryVerification {
    static func suggestion(from detections: [DetectedFruit]) -> FruitCategorySuggestion? {
        suggestion(evidence: detections.map(FruitCategoryObservation.init))
    }

    static func mismatch(
        selectedCategory: FruitCategory,
        detections: [DetectedFruit]
    ) -> FruitCategoryMismatch? {
        mismatch(selectedCategory: selectedCategory, evidence: detections.map(FruitCategoryObservation.init))
    }
}

extension FruitCategoryObservation {
    init(_ detection: DetectedFruit) {
        self.init(category: detection.category, timestamp: detection.timestamp, confidence: detection.confidence)
    }
}
