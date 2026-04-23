// FruitCounter.swift
// 水果产量计数统计

import Foundation

/// 水果产量计数器
/// 根据验证来源计算加权计数
class FruitCounter {

    // MARK: - 权重配置

    /// 各验证来源的计数权重
    private enum SourceWeight {
        static let fused: Double = 1.0      // 最可靠
        static let imageOnly: Double = 0.5  // 可能是遮挡区域
        static let cloudOnly: Double = 0.3  // 可能是误检
    }

    // MARK: - 公开接口

    /// 计算加权产量结果
    /// - Parameter validatedFruits: 融合验证后的水果列表
    /// - Returns: 产量结果，包含各类水果计数和总计
    func count(_ validatedFruits: [ValidatedFruit]) -> FruitCountResult {
        let categoryCounts = countByCategory(validatedFruits)
        return FruitCountResult(fruitCounts: categoryCounts, validatedFruits: validatedFruits)
    }

    /// 按水果类别分组统计
    /// - Parameter validatedFruits: 融合验证后的水果列表
    /// - Returns: 各类水果的加权计数
    func countByCategory(_ validatedFruits: [ValidatedFruit]) -> [FruitCategory: Int] {
        var counts: [FruitCategory: Double] = [:]

        // 初始化所有类别
        for category in FruitCategory.allCases {
            counts[category] = 0
        }

        // 遍历每个水果，根据来源计算加权贡献
        for fruit in validatedFruits {
            guard let category = fruit.category else { continue }

            let weight = weightForSource(fruit.source)
            counts[category, default: 0] += weight
        }

        // 四舍五入得到最终计数
        return counts.mapValues { Int($0.rounded()) }
    }

    // MARK: - 私有方法

    /// 获取验证来源对应的权重
    /// - Parameter source: 验证来源
    /// - Returns: 权重值
    private func weightForSource(_ source: ValidationSource) -> Double {
        switch source {
        case .fused:
            return SourceWeight.fused
        case .imageOnly:
            return SourceWeight.imageOnly
        case .cloudOnly:
            return SourceWeight.cloudOnly
        }
    }
}