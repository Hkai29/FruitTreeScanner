// FruitModels.swift
// 共享类型定义 - 多模态融合产量估算

import Foundation
import simd

// MARK: - 水果类别
enum FruitCategory: String, CaseIterable, Codable {
    case apple = "apple"
    case orange = "orange"
    case pear = "pear"
    case peach = "peach"
    case cherry = "cherry"

    var displayName: String {
        switch self {
        case .apple: return "苹果"
        case .orange: return "橙子"
        case .pear: return "梨"
        case .peach: return "桃子"
        case .cherry: return "樱桃"
        }
    }

    // 水果物理尺寸范围（米）
    var sizeRange: ClosedRange<Float> {
        switch self {
        case .cherry: return 0.02...0.04
        case .apple: return 0.06...0.10
        case .orange: return 0.06...0.11
        case .peach: return 0.06...0.10
        case .pear: return 0.07...0.12
        }
    }
}

// MARK: - COCO 类别映射 (用于 YOLOv8 COCO 预训练模型)

/// COCO 数据集中水果类别的类别 ID
enum COCOFruit: Int, CaseIterable {
    case apple = 77
    case orange = 78
    case banana = 52
    case broccoli = 39

    /// 映射到 FruitCategory
    var fruitCategory: FruitCategory? {
        switch self {
        case .apple: return .apple
        case .orange: return .orange
        case .banana: return .pear  // 最接近的类别
        case .broccoli: return nil   // 不在目标水果范围内
        }
    }
}

extension FruitCategory {
    /// 从 COCO 类别 ID 获取 FruitCategory
    static func fromCOCO(_ cocoID: Int) -> FruitCategory? {
        return COCOFruit(rawValue: cocoID)?.fruitCategory
    }

    /// RGB 转 HSV
    static func rgbToHSV(_ rgb: SIMD3<Float>) -> SIMD3<Float> {
        let r = rgb.x, g = rgb.y, b = rgb.z
        let maxVal = max(r, max(g, b))
        let minVal = min(r, min(g, b))
        let delta = maxVal - minVal

        var h: Float = 0
        let s: Float = maxVal == 0 ? 0 : delta / maxVal
        let v: Float = maxVal

        if delta != 0 {
            if maxVal == r {
                h = 60 * (((g - b) / delta).truncatingRemainder(dividingBy: 6))
            } else if maxVal == g {
                h = 60 * ((b - r) / delta + 2)
            } else {
                h = 60 * ((r - g) / delta + 4)
            }
        }
        if h < 0 { h += 360 }

        return SIMD3<Float>(h, s, v)
    }

    /// 检查颜色是否可能是果实颜色（基于 HSV 颜色空间）
    /// - 参数: rgb 归一化的 RGB 颜色 (0-1)
    /// - 返回: true 如果颜色在果实颜色范围内
    static func isFruitColor(_ rgb: SIMD3<Float>) -> Bool {
        let hsv = rgbToHSV(rgb)
        let h = hsv.x, s = hsv.y, v = hsv.z

        // 果实颜色范围（HSV）：
        // 红色苹果: H=0-20° 或 340-360°, S=30-100%, V=30-90%
        // 橙色: H=20-45°, S=40-100%, V=40-95%
        // 黄色/绿梨: H=45-90°, S=20-70%, V=40-90%
        // 粉色桃: H=0-40°, S=15-50%, V=60-90%
        // 樱桃: H=0-20°, S=40-100%, V=30-80%

        // 太暗或太亮的排除（非自然物体）
        if v < 0.15 || v > 0.98 { return false }
        // 饱和度太低的排除（灰色、白色物体）
        if s < 0.1 { return false }

        // 红色范围（苹果、樱桃、桃）
        if (h >= 0 && h <= 25) || (h >= 335 && h <= 360) {
            if s >= 0.25 && v >= 0.25 { return true }
        }
        // 橙色范围（橙子）
        if h >= 15 && h <= 50 {
            if s >= 0.35 && v >= 0.35 { return true }
        }
        // 黄绿色范围（梨、青苹果）
        if h >= 45 && h <= 95 {
            if s >= 0.15 && v >= 0.35 { return true }
        }

        return false
    }
}

// MARK: - 图像检测结果
struct DetectedFruit {
    let id: UUID
    let category: FruitCategory
    let boundingBox: CGRect          // 归一化坐标 (0-1)
    let confidence: Float
    let timestamp: TimeInterval

    init(category: FruitCategory, boundingBox: CGRect, confidence: Float, timestamp: TimeInterval = Date().timeIntervalSince1970) {
        self.id = UUID()
        self.category = category
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.timestamp = timestamp
    }
}

// MARK: - 点云聚类候选
struct FruitCandidate: Identifiable {
    let id: UUID
    let position: SIMD3<Float>       // 3D 中心位置（米）
    let diameter: Float               // 估算直径（米）
    let sphericity: Float             // 球形度 (0-1)，协方差矩阵特征值比
    let pointCount: Int              // 包含的点数
    let averageColor: SIMD3<Float>   // 平均 RGB 颜色（归一化 0-1）

    init(position: SIMD3<Float>, diameter: Float, sphericity: Float, pointCount: Int, averageColor: SIMD3<Float>) {
        self.id = UUID()
        self.position = position
        self.diameter = diameter
        self.sphericity = sphericity
        self.pointCount = pointCount
        self.averageColor = averageColor
    }

    // 是否符合果实物理特征
    func isValidFruit() -> Bool {
        return sphericity > 0.5 && pointCount >= 5
    }

    // 是否具有果实颜色（基于 HSV 颜色空间）
    func hasFruitColor() -> Bool {
        return FruitCategory.isFruitColor(averageColor)
    }
}

// MARK: - 融合验证结果
struct ValidatedFruit: Identifiable {
    let id: UUID
    let category: FruitCategory?
    let position: SIMD3<Float>
    let confidence: Float
    let source: ValidationSource

    init(category: FruitCategory?, position: SIMD3<Float>, confidence: Float, source: ValidationSource) {
        self.id = UUID()
        self.category = category
        self.position = position
        self.confidence = confidence
        self.source = source
    }
}

enum ValidationSource: String {
    case imageOnly = "image_only"      // 只有图像检测
    case cloudOnly = "cloud_only"      // 只有点云聚类
    case fused = "fused"              // 两者都验证通过
}

// MARK: - 产量结果（用于多模态融合计数）
struct FruitCountResult: Codable {
    let fruitCounts: [String: Int]
    let totalCount: Int
    let validatedFruits: [ValidatedFruitData]
    let timestamp: Date

    var fruitCountsEnum: [FruitCategory: Int] {
        var result: [FruitCategory: Int] = [:]
        for (key, value) in fruitCounts {
            if let category = FruitCategory(rawValue: key) {
                result[category] = value
            }
        }
        return result
    }

    init(fruitCounts: [FruitCategory: Int], validatedFruits: [ValidatedFruit]) {
        var counts: [String: Int] = [:]
        for (category, count) in fruitCounts {
            counts[category.rawValue] = count
        }
        self.fruitCounts = counts
        self.totalCount = validatedFruits.count
        self.validatedFruits = validatedFruits.map { ValidatedFruitData(from: $0) }
        self.timestamp = Date()
    }
}

// Codable 版本（用于 JSON 序列化）
struct ValidatedFruitData: Codable {
    let id: String
    let category: String?
    let positionX: Float
    let positionY: Float
    let positionZ: Float
    let confidence: Float
    let source: String

    init(from fruit: ValidatedFruit) {
        self.id = fruit.id.uuidString
        self.category = fruit.category?.rawValue
        self.positionX = fruit.position.x
        self.positionY = fruit.position.y
        self.positionZ = fruit.position.z
        self.confidence = fruit.confidence
        self.source = fruit.source.rawValue
    }
}

// MARK: - 扫描配置
struct FruitScanConfig {
    var imageDetectionInterval: Int = 10      // 每 N 帧检测一次
    var minConfidence: Float = 0.5           // 最低置信度
    var sizeTolerance: Float = 0.2            // 尺寸匹配容差 (±20%)
    var sphericityThreshold: Float = 0.5       // 球形度阈值

    static let `default` = FruitScanConfig()
}

// MARK: - 聚类配置
struct ClusterConfig {
    var minPoints: Int = 5                     // 最小点数
    var minDiameter: Float = 0.02              // 最小直径（米）= 2cm（支持樱桃等小水果）
    var maxDiameter: Float = 0.15              // 最大直径（米）
    var baseEps: Float = 0.1                   // 基础邻域半径（米）

    static let `default` = ClusterConfig()
}
