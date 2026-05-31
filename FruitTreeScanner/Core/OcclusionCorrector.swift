// OcclusionCorrector.swift
// 基于冠层几何结构的遮挡校正
// 改进模型：径向密度加权 + 多角度扫描补偿 + 置信区间

import Foundation
import simd

struct OcclusionCorrector {

    struct CorrectionResult {
        let k: Float
        let kLow: Float
        let kHigh: Float
        let visibleRatio: Float
        let scanAngleCoverage: Float
        let method: String

        var description: String {
            String(format: "k=%.2f [%.2f,%.2f], visible=%.1f%%, angle=%.0f°, %@",
                   k, kLow, kHigh, visibleRatio * 100, scanAngleCoverage * 360, method)
        }
    }

    static func estimateCrownRadius(from points: [ColoredPoint]) -> Float {
        guard !points.isEmpty else { return 1.5 }
        let positions = points.map { $0.pos }
        let centroid = computeCentroid(positions)
        let dists = positions.map { simd_distance($0, centroid) }.sorted()
        guard !dists.isEmpty else { return 1.5 }
        let idx90 = max(0, Int(Float(dists.count) * 0.90) - 1)
        return max(dists[idx90], 0.3)
    }

    static func estimateCrownDepth(from points: [ColoredPoint]) -> Float {
        guard points.count > 100 else { return 0.4 }
        let positions = points.map { $0.pos }
        let centroid = computeCentroid(positions)
        let dists = positions.map { simd_distance($0, centroid) }.sorted()

        let rMin = dists.first ?? 0
        let rMax = dists.last ?? 1
        let binWidth = (rMax - rMin) / 10
        guard binWidth > 0.01 else { return 0.4 }

        var binCounts = [Int](repeating: 0, count: 10)
        for d in dists {
            let bin = min(Int((d - rMin) / binWidth), 9)
            binCounts[bin] += 1
        }

        let outerBinCount = binCounts[9]
        let threshold = max(outerBinCount / 4, 5)
        var dropRadius = rMin
        for i in stride(from: 9, through: 0, by: -1) {
            if binCounts[i] < threshold {
                dropRadius = rMin + Float(i) * binWidth
                break
            }
        }

        let crownDepth = rMax - dropRadius
        return max(min(crownDepth, 1.5), 0.2)
    }

    static func estimateScanAngleCoverage(from points: [ColoredPoint]) -> Float {
        guard points.count > 50 else { return 0.25 }
        let positions = points.map { $0.pos }
        let centroid = computeCentroid(positions)

        let angles = positions.map { atan2($0.z - centroid.z, $0.x - centroid.x) }
        let sortedAngles = angles.sorted()

        var maxGap: Float = 0
        for i in 0..<sortedAngles.count {
            let next = (i + 1) % sortedAngles.count
            var gap = sortedAngles[next] - sortedAngles[i]
            if next == 0 { gap += 2 * Float.pi }
            maxGap = max(maxGap, gap)
        }

        let coverage = 1.0 - maxGap / (2 * Float.pi)
        return max(min(coverage, 1.0), 0.1)
    }

    private static func computeCentroid(_ positions: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !positions.isEmpty else { return SIMD3<Float>(0, 0, 0) }
        var sum = SIMD3<Float>(0, 0, 0)
        for pos in positions { sum += pos }
        return sum / Float(positions.count)
    }

    static func correctionFactor(
        visibleCount: Int,
        crownRadiusM: Float = 1.5,
        crownDepthM: Float = 0.4,
        lidarPenetrationM: Float = 0.4
    ) -> Float {
        correctionFactorDetailed(
            visibleCount: visibleCount,
            crownRadiusM: crownRadiusM,
            crownDepthM: crownDepthM,
            lidarPenetrationM: lidarPenetrationM,
            scanAngleCoverage: 0.5
        ).k
    }

    static func correctionFactorDetailed(
        visibleCount: Int,
        crownRadiusM: Float = 1.5,
        crownDepthM: Float = 0.4,
        lidarPenetrationM: Float = 0.4,
        scanAngleCoverage: Float = 0.5
    ) -> CorrectionResult {
        guard visibleCount > 0 else {
            return CorrectionResult(k: 1.0, kLow: 1.0, kHigh: 1.0,
                                    visibleRatio: 1.0, scanAngleCoverage: scanAngleCoverage,
                                    method: "no_fruit")
        }

        let visibleDepth = min(lidarPenetrationM, crownDepthM)

        let totalVolume = (4.0 / 3.0) * Float.pi * pow(crownRadiusM, 3)
        let innerRadius = max(0, crownRadiusM - visibleDepth)
        let _ = totalVolume - (4.0 / 3.0) * Float.pi * pow(innerRadius, 3)

        let densityWeightedVisibleFraction = computeDensityWeightedVisibleFraction(
            crownRadius: crownRadiusM,
            visibleDepth: visibleDepth
        )

        let angleFactor = scanAngleCoverage

        let visibleRatio = densityWeightedVisibleFraction * angleFactor

        let k = 1.0 / max(visibleRatio, 0.1)
        let kClamped = min(max(k, 1.0), 3.0)

        let uncertainty: Float = 0.15 + 0.10 * (1.0 - scanAngleCoverage)
        let kLow = min(max(kClamped * (1.0 - uncertainty), 1.0), 3.0)
        let kHigh = min(kClamped * (1.0 + uncertainty), 3.0)

        return CorrectionResult(
            k: kClamped,
            kLow: kLow,
            kHigh: kHigh,
            visibleRatio: visibleRatio,
            scanAngleCoverage: scanAngleCoverage,
            method: "density_weighted_shell"
        )
    }

    private static func computeDensityWeightedVisibleFraction(
        crownRadius: Float,
        visibleDepth: Float
    ) -> Float {
        let nShells = 20
        let shellThickness = crownRadius / Float(nShells)

        var totalWeightedVolume: Float = 0
        var visibleWeightedVolume: Float = 0

        for i in 0..<nShells {
            let rInner = Float(i) * shellThickness
            let rOuter = Float(i + 1) * shellThickness
            let rMid = (rInner + rOuter) / 2

            let shellVol = (4.0 / 3.0) * Float.pi * (pow(rOuter, 3) - pow(rInner, 3))

            let normalizedR = rMid / crownRadius
            let densityWeight: Float
            if normalizedR < 0.3 {
                densityWeight = 0.1
            } else if normalizedR < 0.6 {
                densityWeight = 0.3 + (normalizedR - 0.3) / 0.3 * 0.5
            } else if normalizedR < 0.85 {
                densityWeight = 0.8 + (normalizedR - 0.6) / 0.25 * 0.2
            } else {
                densityWeight = 1.0 - (normalizedR - 0.85) / 0.15 * 0.3
            }

            totalWeightedVolume += shellVol * densityWeight

            let depthFromSurface = crownRadius - rMid
            if depthFromSurface <= visibleDepth {
                let attenuation = 1.0 - depthFromSurface / (visibleDepth + 0.01) * 0.3
                visibleWeightedVolume += shellVol * densityWeight * attenuation
            }
        }

        guard totalWeightedVolume > 0 else { return 0.5 }
        return visibleWeightedVolume / totalWeightedVolume
    }
}
