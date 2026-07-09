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
        let boundsCenter = horizontalBoundsCenter(positions)

        let centroidCoverage = scanAngleCoverage(positions: positions, center: centroid)
        let boundsCoverage = scanAngleCoverage(positions: positions, center: boundsCenter)
        return min(centroidCoverage, boundsCoverage)
    }

    private static func scanAngleCoverage(
        positions: [SIMD3<Float>],
        center: SIMD3<Float>
    ) -> Float {
        let radialDistances = positions.map { point in
            hypot(point.x - center.x, point.z - center.z)
        }
        let sortedRadii = radialDistances.sorted()
        let medianRadius = sortedRadii[sortedRadii.count / 2]
        let minimumUsableRadius = max(medianRadius * 0.20, 0.05)

        let binCount = 36
        var binCounts = [Int](repeating: 0, count: binCount)
        for point in positions {
            let dx = point.x - center.x
            let dz = point.z - center.z
            guard hypot(dx, dz) >= minimumUsableRadius else { continue }

            var normalizedAngle = (atan2(dz, dx) + Float.pi) / (2 * Float.pi)
            if normalizedAngle >= 1 {
                normalizedAngle = 0
            }
            let bin = min(max(Int(floor(normalizedAngle * Float(binCount))), 0), binCount - 1)
            binCounts[bin] += 1
        }

        let minimumBinSupport = max(2, Int(ceil(Float(positions.count) * 0.005)))
        let occupiedBins = binCounts.map { $0 >= minimumBinSupport }
        guard occupiedBins.contains(true) else { return 0.25 }

        var longestEmptyRun = 0
        var currentEmptyRun = 0
        for i in 0..<(binCount * 2) {
            if occupiedBins[i % binCount] {
                currentEmptyRun = 0
            } else {
                currentEmptyRun += 1
                longestEmptyRun = min(max(longestEmptyRun, currentEmptyRun), binCount)
            }
        }

        let coverage = 1.0 - Float(longestEmptyRun) / Float(binCount)
        return max(min(coverage, 1.0), 0.1)
    }

    private static func horizontalBoundsCenter(_ positions: [SIMD3<Float>]) -> SIMD3<Float> {
        guard var minX = positions.first?.x,
              var maxX = positions.first?.x,
              var minZ = positions.first?.z,
              var maxZ = positions.first?.z else {
            return .zero
        }

        for point in positions.dropFirst() {
            minX = min(minX, point.x)
            maxX = max(maxX, point.x)
            minZ = min(minZ, point.z)
            maxZ = max(maxZ, point.z)
        }

        return SIMD3<Float>((minX + maxX) * 0.5, 0, (minZ + maxZ) * 0.5)
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
        lidarPenetrationM: Float = FruitScanExperimentConfig.default.occlusion.lidarPenetrationMeters
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
        lidarPenetrationM: Float = FruitScanExperimentConfig.default.occlusion.lidarPenetrationMeters,
        scanAngleCoverage: Float = 0.5,
        visualDetectionCount: Int? = nil,
        lidarDetectionCount: Int? = nil
    ) -> CorrectionResult {
        guard visibleCount > 0 else {
            return CorrectionResult(k: 1.0, kLow: 1.0, kHigh: 1.0,
                                    visibleRatio: 1.0, scanAngleCoverage: scanAngleCoverage,
                                    method: "no_fruit")
        }

        let visibleDepth = min(lidarPenetrationM, crownDepthM)

        let densityWeightedVisibleFraction = computeDensityWeightedVisibleFraction(
            crownRadius: crownRadiusM,
            visibleDepth: visibleDepth
        )

        let angleFactor = scanAngleCoverage

        let visibleRatio = densityWeightedVisibleFraction * angleFactor

        let geometricK = 1.0 / max(visibleRatio, 0.1)
        let geometricKClamped = min(max(geometricK, 1.0), 3.0)
        let evidenceReliability = min(Float(visibleCount) / 1000.0, 1.0) * min(max(scanAngleCoverage, 0), 1)
        let geometrySupportedK = 1.0 + (geometricKClamped - 1.0) * (1.0 - evidenceReliability)
        let ratioSupportedK = visualLidarRatioSupportedK(
            visualDetectionCount: visualDetectionCount,
            lidarDetectionCount: lidarDetectionCount,
            scanAngleCoverage: scanAngleCoverage
        )
        let kClamped = min(max(geometrySupportedK, ratioSupportedK), 3.0)

        let uncertainty: Float = 0.15 + 0.10 * (1.0 - scanAngleCoverage)
        let kLow = min(max(kClamped * (1.0 - uncertainty), 1.0), 3.0)
        let kHigh = min(kClamped * (1.0 + uncertainty), 3.0)
        let method = ratioSupportedK > geometrySupportedK
            ? "density_weighted_shell_visual_lidar_ratio"
            : "density_weighted_shell"

        return CorrectionResult(
            k: kClamped,
            kLow: kLow,
            kHigh: kHigh,
            visibleRatio: visibleRatio,
            scanAngleCoverage: scanAngleCoverage,
            method: method
        )
    }

    private static func visualLidarRatioSupportedK(
        visualDetectionCount: Int?,
        lidarDetectionCount: Int?,
        scanAngleCoverage: Float
    ) -> Float {
        guard let visualDetectionCount,
              let lidarDetectionCount,
              visualDetectionCount > 0,
              lidarDetectionCount > 0,
              visualDetectionCount > lidarDetectionCount else {
            return 1.0
        }

        let observedRatio = Float(visualDetectionCount) / Float(lidarDetectionCount)
        let ratioK = min(max(observedRatio, 1.0), 3.0)
        let countReliability = min(Float(min(visualDetectionCount, lidarDetectionCount)) / 5.0, 1.0)
        let angleReliability = min(max(scanAngleCoverage, 0), 1)
        let reliability = countReliability * angleReliability
        return 1.0 + (ratioK - 1.0) * reliability
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
