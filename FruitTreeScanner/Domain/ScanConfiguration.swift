import Foundation

// MARK: - 扫描配置
struct FruitScanConfig: Sendable, Encodable {
    var imageDetectionInterval: Int = 10
    var minConfidence: Float = 0.5
    var sizeTolerance: Float = 0.35
    var minimumStableDetectionsForYield: Int = 1
    var stableDetectionTimeWindow: TimeInterval = 3.5

    static let `default` = FruitScanConfig()
}

// MARK: - 聚类配置
struct ClusterConfig: Sendable, Encodable {
    var minPoints: Int = 3
    var minDiameter: Float = 0.015
    var maxDiameter: Float = 0.20
    var baseEps: Float = 0.1
    var sphericityThreshold: Float = 0.5

    static let `default` = ClusterConfig()
}

enum Season: Sendable {
    case mature
    case off

    var supportsYieldEstimation: Bool {
        self == .mature
    }
}
