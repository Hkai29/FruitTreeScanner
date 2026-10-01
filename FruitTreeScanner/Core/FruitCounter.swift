// FruitCounter.swift
// 水果产量计数统计

import Foundation

/// 水果产量计数器
/// 根据验证来源计算加权计数
class FruitCounter {

    // MARK: - 公开接口

    /// 计算加权产量结果
    /// - Parameter validatedFruits: 融合验证后的水果列表
    /// - Returns: 产量结果，包含各类水果计数和总计
    func count(_ validatedFruits: [ValidatedFruit], defaultCategory: FruitCategory = .apple) -> FruitCountResult {
        let categoryCounts = countByCategory(validatedFruits, defaultCategory: defaultCategory)
        return FruitCountResult(fruitCounts: categoryCounts, validatedFruits: validatedFruits)
    }

    func weightedTotal(_ validatedFruits: [ValidatedFruit]) -> Float {
        validatedFruits.reduce(0) { total, fruit in
            total + Self.evidenceWeight(for: fruit)
        }
    }

    /// Reliable-yield entry point accepts only evidence created at fusion admission.
    func count(_ evidence: [ReliableYieldEvidence], defaultCategory: FruitCategory = .apple) -> FruitCountResult {
        count(evidence.map(\.validatedFruit), defaultCategory: defaultCategory)
    }

    func weightedTotal(_ evidence: [ReliableYieldEvidence]) -> Float {
        weightedTotal(evidence.map(\.validatedFruit))
    }

    static func evidenceWeight(for fruit: ValidatedFruit) -> Float {
        let confidence = min(max(fruit.confidence, 0), 1)
        return fruit.source.countWeight * confidence
    }

    func countByCategory(_ validatedFruits: [ValidatedFruit], defaultCategory: FruitCategory = .apple) -> [FruitCategory: Int] {
        var counts: [FruitCategory: Double] = [:]

        for category in FruitCategory.allCases {
            counts[category] = 0
        }

        for fruit in validatedFruits {
            let category = fruit.category ?? defaultCategory
            let weight = Double(Self.evidenceWeight(for: fruit))
            counts[category, default: 0] += weight
        }

        return counts.mapValues { Int($0.rounded()) }
    }
}
