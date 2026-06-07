import Foundation
import simd

enum PointCloudDenoiser {

    static func statisticalOutlierRemoval(
        samples: [RendererPointSample],
        k: Int = 12,
        stdMultiplier: Float = 1.5
    ) -> [RendererPointSample] {
        guard samples.count > k + 1 else { return samples }

        let positions = samples.map { $0.position }
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

        var result: [RendererPointSample] = []
        result.reserveCapacity(samples.count)
        for i in 0..<samples.count {
            if meanDistances[i] <= threshold {
                result.append(samples[i])
            }
        }
        return result
    }
}
