// FruitModels.swift
// 共享类型定义 - 多模态融合产量估算

import Foundation

// MARK: - 水果类别
enum FruitCategory: String, CaseIterable, Codable {
    case apple = "apple"
    case orange = "orange"
    case mandarin = "mandarin"
    case pomelo = "pomelo"
    case pear = "pear"
    case peach = "peach"
    case cherry = "cherry"
    case grape = "grape"
    case persimmon = "persimmon"
    case mango = "mango"
    case kiwi = "kiwi"
    case plum = "plum"
    case pomegranate = "pomegranate"
    case loquat = "loquat"
    case lychee = "lychee"
    case longan = "longan"
    case bayberry = "bayberry"
    case jujube = "jujube"
    case hawthorn = "hawthorn"
    case fig = "fig"
    case papaya = "papaya"
    case chestnut = "chestnut"
    case mulberry = "mulberry"
    case blueberry = "blueberry"
    case strawberry = "strawberry"
    case coconut = "coconut"

    var displayName: String {
        switch self {
        case .apple: return "苹果"
        case .orange: return "橙子"
        case .mandarin: return "柑橘"
        case .pomelo: return "柚子"
        case .pear: return "梨"
        case .peach: return "桃子"
        case .cherry: return "樱桃"
        case .grape: return "葡萄"
        case .persimmon: return "柿子"
        case .mango: return "芒果"
        case .kiwi: return "猕猴桃"
        case .plum: return "李子"
        case .pomegranate: return "石榴"
        case .loquat: return "枇杷"
        case .lychee: return "荔枝"
        case .longan: return "龙眼"
        case .bayberry: return "杨梅"
        case .jujube: return "枣"
        case .hawthorn: return "山楂"
        case .fig: return "无花果"
        case .papaya: return "木瓜"
        case .chestnut: return "板栗"
        case .mulberry: return "桑葚"
        case .blueberry: return "蓝莓"
        case .strawberry: return "草莓"
        case .coconut: return "椰子"
        }
    }

    var sizeRange: ClosedRange<Float> {
        switch self {
        case .grape: return 0.015...0.03
        case .blueberry: return 0.012...0.025
        case .mulberry: return 0.02...0.04
        case .bayberry: return 0.015...0.03
        case .cherry: return 0.02...0.04
        case .strawberry: return 0.02...0.05
        case .jujube: return 0.02...0.04
        case .hawthorn: return 0.02...0.04
        case .loquat: return 0.03...0.05
        case .lychee: return 0.03...0.05
        case .longan: return 0.02...0.035
        case .plum: return 0.04...0.07
        case .kiwi: return 0.05...0.08
        case .apple: return 0.06...0.10
        case .mandarin: return 0.05...0.09
        case .orange: return 0.06...0.11
        case .peach: return 0.06...0.10
        case .persimmon: return 0.06...0.12
        case .fig: return 0.04...0.08
        case .chestnut: return 0.03...0.05
        case .pomegranate: return 0.08...0.14
        case .pear: return 0.07...0.12
        case .mango: return 0.08...0.18
        case .papaya: return 0.10...0.30
        case .pomelo: return 0.10...0.25
        case .coconut: return 0.12...0.25
        }
    }

    var density: Float {
        switch self {
        case .apple:  return 0.85
        case .orange: return 0.88
        case .mandarin: return 0.86
        case .pomelo: return 0.75
        case .pear:   return 0.93
        case .peach:  return 0.91
        case .cherry: return 0.82
        case .grape:  return 0.95
        case .persimmon: return 0.80
        case .mango:  return 0.92
        case .kiwi:   return 0.96
        case .plum:   return 0.90
        case .pomegranate: return 0.87
        case .loquat: return 0.88
        case .lychee: return 0.93
        case .longan: return 0.90
        case .bayberry: return 0.85
        case .jujube: return 0.82
        case .hawthorn: return 0.84
        case .fig: return 0.88
        case .papaya: return 0.90
        case .chestnut: return 0.95
        case .mulberry: return 0.80
        case .blueberry: return 0.83
        case .strawberry: return 0.85
        case .coconut: return 0.70
        }
    }

    var averageWeightG: Float {
        switch self {
        case .apple:  return 200
        case .orange: return 280
        case .mandarin: return 150
        case .pomelo: return 1000
        case .pear:   return 180
        case .peach:  return 150
        case .cherry: return 8
        case .grape:  return 5
        case .persimmon: return 200
        case .mango:  return 300
        case .kiwi:   return 80
        case .plum:   return 50
        case .pomegranate: return 350
        case .loquat: return 40
        case .lychee: return 25
        case .longan: return 12
        case .bayberry: return 15
        case .jujube: return 10
        case .hawthorn: return 10
        case .fig: return 60
        case .papaya: return 500
        case .chestnut: return 15
        case .mulberry: return 3
        case .blueberry: return 2
        case .strawberry: return 15
        case .coconut: return 1500
        }
    }

    var sphericityThreshold: Float {
        switch self {
        case .apple, .orange, .mandarin, .cherry, .grape, .plum,
             .pomegranate, .lychee, .longan, .blueberry, .coconut: return 0.5
        case .pear: return 0.3
        case .peach, .persimmon, .pomelo: return 0.4
        case .mango, .papaya: return 0.25
        case .kiwi, .loquat, .bayberry, .jujube, .hawthorn,
             .chestnut, .mulberry, .strawberry: return 0.45
        case .fig: return 0.35
        }
    }

    var clusterEps: Float { 0.05 }

    var diamMin: Float {
        switch self {
        case .grape, .cherry, .blueberry, .mulberry, .bayberry: return 0.012
        case .longan, .jujube, .hawthorn, .chestnut: return 0.018
        case .loquat, .lychee: return 0.025
        case .plum: return 0.03
        default: return 0.03
        }
    }

    var diamMax: Float {
        switch self {
        case .mango, .papaya: return 0.20
        case .pomegranate: return 0.16
        case .pomelo, .coconut: return 0.25
        default: return 0.15
        }
    }
}

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

    static func make(selectedCategory: FruitCategory, detections: [DetectedFruit]) -> FruitCategoryVerificationSummary {
        let suggestion = FruitCategoryVerification.suggestion(from: detections)
        let mismatch = FruitCategoryVerification.mismatch(
            selectedCategory: selectedCategory,
            detections: detections
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

    static func suggestion(from detections: [DetectedFruit]) -> FruitCategorySuggestion? {
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
        detections: [DetectedFruit]
    ) -> FruitCategoryMismatch? {
        guard let suggestion = suggestion(from: detections), suggestion.category != selectedCategory else {
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

    private static func rankedEvidence(from detections: [DetectedFruit]) -> [Evidence] {
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
