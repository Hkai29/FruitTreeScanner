import Foundation
import simd

struct PointCloudDenoisingStats: Equatable {
    let originalCount: Int
    let retainedCount: Int
    let meanNeighborDistance: Float
    let neighborDistanceStd: Float
    let threshold: Float

    var removedCount: Int {
        max(originalCount - retainedCount, 0)
    }

    var removalRatio: Float {
        guard originalCount > 0 else { return 0 }
        return Float(removedCount) / Float(originalCount)
    }
}

struct PointCloudDenoisingResult<Sample> {
    let samples: [Sample]
    let stats: PointCloudDenoisingStats
}

enum PointCloudDenoiser {

    static func statisticalOutlierRemoval(
        samples: [RendererPointSample],
        k: Int = 12,
        stdMultiplier: Float = 1.5
    ) -> [RendererPointSample] {
        statisticalOutlierRemovalDetailed(
            samples: samples,
            k: k,
            stdMultiplier: stdMultiplier
        ).samples
    }

    static func statisticalOutlierRemovalDetailed(
        samples: [RendererPointSample],
        k: Int = 12,
        stdMultiplier: Float = 1.5
    ) -> PointCloudDenoisingResult<RendererPointSample> {
        statisticalOutlierRemovalDetailed(
            samples: samples,
            k: k,
            stdMultiplier: stdMultiplier,
            position: { $0.position }
        )
    }

    static func statisticalOutlierRemovalDetailed<Sample>(
        samples: [Sample],
        k: Int = 12,
        stdMultiplier: Float = 1.5,
        position: (Sample) -> SIMD3<Float>
    ) -> PointCloudDenoisingResult<Sample> {
        guard samples.count > k + 1 else {
            return unchangedResult(samples: samples)
        }

        let positions = samples.map(position)
        let tree = KDTree(points: positions)

        var meanDistances = [Float](repeating: 0, count: samples.count)
        var globalSum: Double = 0

        for i in 0..<samples.count {
            let neighbors = tree.kNearest(center: positions[i], k: k + 1)
            var distSum: Float = 0
            var count = 0
            for j in neighbors where j != i {
                distSum += simd_distance(positions[i], positions[j])
                count += 1
                if count >= k { break }
            }
            let mean = count > 0 ? distSum / Float(count) : 0
            meanDistances[i] = mean
            globalSum += Double(mean)
        }

        let globalMean = Float(globalSum / Double(samples.count))

        var varianceSum: Double = 0
        for d in meanDistances {
            let diff = Double(d - globalMean)
            varianceSum += diff * diff
        }
        let globalStd = Float(sqrt(varianceSum / Double(samples.count)))

        let threshold = globalMean + stdMultiplier * globalStd

        var result: [Sample] = []
        result.reserveCapacity(samples.count)
        for i in 0..<samples.count {
            if meanDistances[i] <= threshold {
                result.append(samples[i])
            }
        }
        return PointCloudDenoisingResult(
            samples: result,
            stats: PointCloudDenoisingStats(
                originalCount: samples.count,
                retainedCount: result.count,
                meanNeighborDistance: globalMean,
                neighborDistanceStd: globalStd,
                threshold: threshold
            )
        )
    }

    static func unchangedResult<Sample>(
        samples: [Sample]
    ) -> PointCloudDenoisingResult<Sample> {
        PointCloudDenoisingResult(
            samples: samples,
            stats: PointCloudDenoisingStats(
                originalCount: samples.count,
                retainedCount: samples.count,
                meanNeighborDistance: 0,
                neighborDistanceStd: 0,
                threshold: 0
            )
        )
    }
}
