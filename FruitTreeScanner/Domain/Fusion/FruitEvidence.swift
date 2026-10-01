import Foundation
import simd

// MARK: - 点云聚类候选
struct FruitCandidate: Identifiable, Sendable {
    let id: UUID
    let position: SIMD3<Float>
    let diameter: Float
    let sphericity: Float
    let pointCount: Int
    let averageColor: SIMD3<Float>
    let points: [SIMD3<Float>]
    let sourceCategory: FruitCategory?
    let depthSupportRatio: Float?
    let hasPointCloudEvidence: Bool

    init(
        position: SIMD3<Float>,
        diameter: Float,
        sphericity: Float,
        pointCount: Int,
        averageColor: SIMD3<Float>,
        points: [SIMD3<Float>] = [],
        sourceCategory: FruitCategory? = nil,
        depthSupportRatio: Float? = nil,
        hasPointCloudEvidence: Bool? = nil
    ) {
        self.id = UUID()
        self.position = position
        self.diameter = diameter
        self.sphericity = sphericity
        self.pointCount = pointCount
        self.averageColor = averageColor
        self.points = points
        self.sourceCategory = sourceCategory
        self.depthSupportRatio = depthSupportRatio
        self.hasPointCloudEvidence = hasPointCloudEvidence ?? (sourceCategory == nil && depthSupportRatio == nil)
    }

    func isValidFruit(expectedCategory: FruitCategory? = nil) -> Bool {
        if let expectedCategory, let sourceCategory, sourceCategory != expectedCategory {
            return false
        }
        let threshold = expectedCategory?.sphericityThreshold ?? 0.5
        let minimumPointCount = sourceCategory != nil && depthSupportRatio != nil ? 3 : 5
        return sphericity > threshold && pointCount >= minimumPointCount
    }

    func hasFruitColor() -> Bool {
        FruitCategory.isFruitColor(averageColor)
    }
}

// MARK: - 融合验证结果
struct ValidatedFruit: Identifiable, Sendable {
    let id: UUID
    let category: FruitCategory?
    let position: SIMD3<Float>
    let confidence: Float
    let source: ValidationSource
    let measuredDiameter: Float?
    let sourceCandidateIDs: [UUID]

    init(id: UUID = UUID(), category: FruitCategory?, position: SIMD3<Float>, confidence: Float, source: ValidationSource, measuredDiameter: Float? = nil, sourceCandidateIDs: [UUID] = []) {
        self.id = id
        self.category = category
        self.position = position
        self.confidence = confidence
        self.source = source
        self.measuredDiameter = measuredDiameter.flatMap { $0.isFinite && $0 > 0 ? $0 : nil }
        self.sourceCandidateIDs = sourceCandidateIDs
    }
}

enum ValidationSource: String, Sendable {
    case imageOnly = "image_only"
    case trackedImage = "tracked_image"
    case cloudOnly = "cloud_only"
    case fused = "fused"

    var countWeight: Float {
        switch self {
        case .fused:
            return 1.0
        case .imageOnly:
            return 0.5
        case .trackedImage:
            return 0.75
        case .cloudOnly:
            return 0.3
        }
    }

    var isImageBased: Bool {
        switch self {
        case .imageOnly, .trackedImage, .fused:
            return true
        case .cloudOnly:
            return false
        }
    }
}

// MARK: - 产量结果（用于多模态融合计数）
struct FruitCountResult: Codable, Sendable {
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
struct ValidatedFruitData: Codable, Sendable {
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
