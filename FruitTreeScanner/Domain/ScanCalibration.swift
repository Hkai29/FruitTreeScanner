import Foundation

enum YieldAlgorithmRevision {
    static let current = "fusion-geometry-evidence-v2-20260906"
}

struct YieldCalibrationCorrection: Equatable, Sendable {
    let countFactor: Float
    let yieldFactor: Float
    let countSampleCount: Int
    let yieldSampleCount: Int

    static let neutral = YieldCalibrationCorrection(
        countFactor: 1,
        yieldFactor: 1,
        countSampleCount: 0,
        yieldSampleCount: 0
    )

    var hasEvidence: Bool {
        countSampleCount > 0 || yieldSampleCount > 0
    }
}
