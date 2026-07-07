// FruitDetectionModels.swift
// 图像检测、点云候选和多模态融合共享模型

import CoreGraphics
import Foundation
@preconcurrency import CoreVideo
import simd

// MARK: - 图像检测结果
/// A detection and the AR frame data required to place it in world space.
///
/// `depthMap` is a private, copied depth buffer captured with the RGB frame.
/// Core Video buffers are not formally `Sendable`, but this value never shares
/// ARKit's reusable buffer pool across queues.
struct DetectedFruit: Identifiable, @unchecked Sendable {
    let id: UUID
    let category: FruitCategory
    let boundingBox: CGRect
    let confidence: Float
    let timestamp: TimeInterval
    let cameraTransform: simd_float4x4?
    let cameraIntrinsics: simd_float3x3?
    let imageSize: CGSize?
    let depthMap: CVPixelBuffer?

    var hasAlignedDepthContext: Bool {
        depthMap != nil && cameraTransform != nil && cameraIntrinsics != nil && imageSize != nil
    }

    init(
        category: FruitCategory,
        boundingBox: CGRect,
        confidence: Float,
        timestamp: TimeInterval = Date().timeIntervalSince1970,
        cameraTransform: simd_float4x4? = nil,
        cameraIntrinsics: simd_float3x3? = nil,
        imageSize: CGSize? = nil,
        depthMap: CVPixelBuffer? = nil
    ) {
        self.id = UUID()
        self.category = category
        self.boundingBox = boundingBox
        self.confidence = confidence
        self.timestamp = timestamp
        self.cameraTransform = cameraTransform
        self.cameraIntrinsics = cameraIntrinsics
        self.imageSize = imageSize
        self.depthMap = depthMap
    }
}

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

    init(
        position: SIMD3<Float>,
        diameter: Float,
        sphericity: Float,
        pointCount: Int,
        averageColor: SIMD3<Float>,
        points: [SIMD3<Float>] = [],
        sourceCategory: FruitCategory? = nil,
        depthSupportRatio: Float? = nil
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

    init(id: UUID = UUID(), category: FruitCategory?, position: SIMD3<Float>, confidence: Float, source: ValidationSource) {
        self.id = id
        self.category = category
        self.position = position
        self.confidence = confidence
        self.source = source
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
struct FruitScanConfig: Sendable {
    var imageDetectionInterval: Int = 10
    var minConfidence: Float = 0.5
    var sizeTolerance: Float = 0.35
    var sphericityThreshold: Float = 0.5

    static let `default` = FruitScanConfig()
}

// MARK: - 聚类配置
struct ClusterConfig: Sendable {
    var minPoints: Int = 3
    var minDiameter: Float = 0.015
    var maxDiameter: Float = 0.20
    var baseEps: Float = 0.1
    var sphericityThreshold: Float = 0.5

    static let `default` = ClusterConfig()
}
