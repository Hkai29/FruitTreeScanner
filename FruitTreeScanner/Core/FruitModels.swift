// FruitModels.swift
// 共享类型定义 - 多模态融合产量估算

import Foundation
import simd
import CoreGraphics

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

    var colorFilter: ColorFilter {
        switch self {
        case .apple:  return ColorFilter(rMin: 0.25, gMin: 0.22, bMax: 0.42)
        case .orange: return ColorFilter(rMin: 0.50, gMin: 0.28, gMax: 0.55, bMax: 0.25)
        case .mandarin: return ColorFilter(rMin: 0.50, gMin: 0.28, gMax: 0.55, bMax: 0.25)
        case .pomelo: return ColorFilter(rMin: 0.45, gMin: 0.35, gMax: 0.60, bMax: 0.30)
        case .pear:   return ColorFilter(rMin: 0.38, gMin: 0.35, bMax: 0.32)
        case .peach:  return ColorFilter(rMin: 0.50, gMin: 0.22, bMax: 0.35)
        case .cherry: return ColorFilter(rMin: 0.40, gMax: 0.25, bMax: 0.25)
        case .grape:  return ColorFilter(rMin: 0.20, gMax: 0.25, bMin: 0.20)
        case .persimmon: return ColorFilter(rMin: 0.50, gMin: 0.20, gMax: 0.45, bMax: 0.25)
        case .mango:  return ColorFilter(rMin: 0.55, gMin: 0.40, bMax: 0.30)
        case .kiwi:   return ColorFilter(rMax: 0.40, gMin: 0.30, bMax: 0.30)
        case .plum:   return ColorFilter(rMin: 0.25, gMax: 0.20, bMin: 0.15)
        case .pomegranate: return ColorFilter(rMin: 0.40, gMax: 0.30, bMax: 0.25)
        case .loquat: return ColorFilter(rMin: 0.50, gMin: 0.30, gMax: 0.55, bMax: 0.25)
        case .lychee: return ColorFilter(rMin: 0.50, gMax: 0.35, bMax: 0.25)
        case .longan: return ColorFilter(rMin: 0.35, gMin: 0.25, gMax: 0.45, bMax: 0.25)
        case .bayberry: return ColorFilter(rMin: 0.30, gMax: 0.20, bMax: 0.20)
        case .jujube: return ColorFilter(rMin: 0.45, gMax: 0.30, bMax: 0.20)
        case .hawthorn: return ColorFilter(rMin: 0.50, gMax: 0.25, bMax: 0.20)
        case .fig:    return ColorFilter(rMin: 0.35, gMin: 0.20, gMax: 0.50, bMax: 0.25)
        case .papaya: return ColorFilter(rMin: 0.55, gMin: 0.35, gMax: 0.55, bMax: 0.25)
        case .chestnut: return ColorFilter(rMin: 0.25, gMin: 0.15, gMax: 0.35, bMax: 0.20)
        case .mulberry: return ColorFilter(rMin: 0.20, gMax: 0.15, bMin: 0.15)
        case .blueberry: return ColorFilter(rMax: 0.25, gMax: 0.20, bMin: 0.25)
        case .strawberry: return ColorFilter(rMin: 0.50, gMax: 0.30, bMax: 0.25)
        case .coconut: return ColorFilter(rMin: 0.30, gMin: 0.25, gMax: 0.45, bMax: 0.25)
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

struct ColorFilter {
    var rMin: Float = 0; var rMax: Float = 1
    var gMin: Float = 0; var gMax: Float = 1
    var bMin: Float = 0; var bMax: Float = 1

    init(rMin: Float = 0, rMax: Float = 1,
         gMin: Float = 0, gMax: Float = 1,
         bMin: Float = 0, bMax: Float = 1) {
        self.rMin = rMin; self.rMax = rMax
        self.gMin = gMin; self.gMax = gMax
        self.bMin = bMin; self.bMax = bMax
    }

    func matches(r: Float, g: Float, b: Float) -> Bool {
        r >= rMin && r <= rMax &&
        g >= gMin && g <= gMax &&
        b >= bMin && b <= bMax
    }

    var description: String {
        var parts: [String] = []
        if rMin > 0 { parts.append("R≥\(String(format: "%.2f", rMin))") }
        if rMax < 1 { parts.append("R≤\(String(format: "%.2f", rMax))") }
        if gMin > 0 { parts.append("G≥\(String(format: "%.2f", gMin))") }
        if gMax < 1 { parts.append("G≤\(String(format: "%.2f", gMax))") }
        if bMin > 0 { parts.append("B≥\(String(format: "%.2f", bMin))") }
        if bMax < 1 { parts.append("B≤\(String(format: "%.2f", bMax))") }
        return parts.joined(separator: ", ")
    }
}

// MARK: - COCO 类别映射 (用于 YOLOv8 COCO 预训练模型 fallback)

/// COCO 数据集中水果类别的类别 ID
enum COCOFruit: Int, CaseIterable {
    case apple = 77
    case orange = 78
    case banana = 52

    var fruitCategory: FruitCategory? {
        switch self {
        case .apple: return .apple
        case .orange: return .orange
        case .banana: return .pear
        }
    }
}

// MARK: - 自定义训练模型类别映射 (0-25)

/// 自定义 YOLOv8 模型输出的类别 ID，与 FruitCategory.allCases 顺序一致
enum CustomFruitID: Int, CaseIterable {
    case apple = 0
    case orange = 1
    case mandarin = 2
    case pomelo = 3
    case pear = 4
    case peach = 5
    case cherry = 6
    case grape = 7
    case persimmon = 8
    case mango = 9
    case kiwi = 10
    case plum = 11
    case pomegranate = 12
    case loquat = 13
    case lychee = 14
    case longan = 15
    case bayberry = 16
    case jujube = 17
    case hawthorn = 18
    case fig = 19
    case papaya = 20
    case chestnut = 21
    case mulberry = 22
    case blueberry = 23
    case strawberry = 24
    case coconut = 25

    var fruitCategory: FruitCategory {
        return FruitCategory.allCases[self.rawValue]
    }
}

extension FruitCategory {
    /// 从 COCO 类别 ID 获取 FruitCategory
    static func fromCOCO(_ cocoID: Int) -> FruitCategory? {
        return COCOFruit(rawValue: cocoID)?.fruitCategory
    }

    /// 从自定义训练模型类别 ID (0-25) 获取 FruitCategory
    static func fromCustomModel(_ id: Int) -> FruitCategory? {
        return CustomFruitID(rawValue: id)?.fruitCategory
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

        if v < 0.10 || v > 0.98 { return false }
        if s < 0.06 { return false }

        // 红色范围（苹果、樱桃、桃、石榴、山楂、杨梅、草莓、荔枝）
        if (h >= 0 && h <= 25) || (h >= 335 && h <= 360) {
            if s >= 0.18 && v >= 0.18 { return true }
        }
        // 橙色范围（橙子、柿子、枇杷、木瓜、柑橘）
        if h >= 15 && h <= 50 {
            if s >= 0.25 && v >= 0.25 { return true }
        }
        // 黄绿色范围（梨、青苹果、芒果、猕猴桃、柚子、无花果、龙眼）
        if h >= 45 && h <= 95 {
            if s >= 0.10 && v >= 0.25 { return true }
        }
        // 深绿色范围（青苹果、未成熟果实）
        if h >= 80 && h <= 150 {
            if s >= 0.12 && v >= 0.12 && v <= 0.70 { return true }
        }
        // 蓝紫色范围（蓝莓、葡萄、桑葚）
        if h >= 240 && h <= 300 {
            if s >= 0.12 && v >= 0.12 { return true }
        }
        // 紫红色范围（葡萄、李子、深色樱桃、杨梅）
        if h >= 300 && h <= 340 {
            if s >= 0.12 && v >= 0.12 { return true }
        }
        // 褐色范围（猕猴桃、板栗、椰子、龙眼、枣）
        if h >= 10 && h <= 50 {
            if s >= 0.10 && s <= 0.55 && v >= 0.15 && v <= 0.55 { return true }
        }
        // 深红/暗红范围（红枣、山楂干、深色杨梅）
        if (h >= 0 && h <= 20) || (h >= 340 && h <= 360) {
            if s >= 0.30 && v >= 0.12 && v <= 0.50 { return true }
        }

        return false
    }
}

// MARK: - 图像检测结果
struct DetectedFruit: Identifiable {
    let id: UUID
    let category: FruitCategory
    let boundingBox: CGRect
    let confidence: Float
    let timestamp: TimeInterval
    let cameraTransform: simd_float4x4?
    let cameraIntrinsics: simd_float3x3?
    let imageSize: CGSize?

    init(category: FruitCategory, boundingBox: CGRect, confidence: Float, timestamp: TimeInterval = Date().timeIntervalSince1970, cameraTransform: simd_float4x4? = nil, cameraIntrinsics: simd_float3x3? = nil, imageSize: CGSize? = nil) {
        self.id = UUID()
        self.category = category
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.timestamp = timestamp
        self.cameraTransform = cameraTransform
        self.cameraIntrinsics = cameraIntrinsics
        self.imageSize = imageSize
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

    // 是否符合果实物理特征（球形度阈值按类别适配）
    func isValidFruit(expectedCategory: FruitCategory? = nil) -> Bool {
        let threshold = expectedCategory?.sphericityThreshold ?? 0.5
        return sphericity > threshold && pointCount >= 5
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

    init(id: UUID = UUID(), category: FruitCategory?, position: SIMD3<Float>, confidence: Float, source: ValidationSource) {
        self.id = id
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

    var countWeight: Float {
        switch self {
        case .fused:
            return 1.0
        case .imageOnly:
            return 0.5
        case .cloudOnly:
            return 0.3
        }
    }
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
        self.totalCount = fruitCounts.values.reduce(0, +)
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
    var sizeTolerance: Float = 0.35
    var sphericityThreshold: Float = 0.5       // 球形度阈值

    static let `default` = FruitScanConfig()
}

// MARK: - 聚类配置
struct ClusterConfig {
    var minPoints: Int = 3
    var minDiameter: Float = 0.015
    var maxDiameter: Float = 0.20
    var baseEps: Float = 0.1                   // 基础邻域半径（米）
    var sphericityThreshold: Float = 0.5       // 最小球形度阈值

    static let `default` = ClusterConfig()
}
