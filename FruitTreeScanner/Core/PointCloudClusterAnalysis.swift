// PointCloudClusterAnalysis.swift
// Candidate scoring and shape analysis for clustered point clouds.

import simd

extension PointCloudCluster {
    func analyzeCluster(_ clusterPoints: [ClusterPoint]) -> FruitCandidate? {
        guard clusterPoints.count >= config.minPoints else { return nil }

        let positions = clusterPoints.map { $0.pos }
        let center = computeCentroid(positions)
        let diameter = computeDiameter(positions: positions, center: center)

        guard diameter >= config.minDiameter, diameter <= config.maxDiameter else {
            return nil
        }

        let sphericity = computeSphericity(positions: positions, center: center)
        guard sphericity > config.sphericityThreshold else {
            return nil
        }

        let colors = clusterPoints.map { $0.color }
        let avgColor = computeAverageColor(colors)
        guard FruitCategory.isFruitColor(avgColor) else {
            return nil
        }

        guard isShapeRegular(positions, center: center, radius: diameter / 2.0) else {
            return nil
        }

        return FruitCandidate(
            position: center,
            diameter: diameter,
            sphericity: sphericity,
            pointCount: clusterPoints.count,
            averageColor: avgColor
        )
    }

    func isShapeRegular(_ positions: [SIMD3<Float>], center: SIMD3<Float>, radius: Float) -> Bool {
        guard radius > 0, !positions.isEmpty else { return false }

        var distSum: Float = 0
        var distSqSum: Float = 0
        for pos in positions {
            let d = simd_distance(pos, center)
            distSum += d
            distSqSum += d * d
        }
        let n = Float(positions.count)
        let avgDist = distSum / n
        let variance = distSqSum / n - avgDist * avgDist
        let stdDev = sqrt(max(variance, 0))

        return stdDev < radius * 0.3
    }

    func computeAverageColor(_ colors: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !colors.isEmpty else { return SIMD3<Float>(0.5, 0.5, 0.5) }
        var sumR: Float = 0, sumG: Float = 0, sumB: Float = 0
        for color in colors {
            sumR += color.x
            sumG += color.y
            sumB += color.z
        }
        let count = Float(colors.count)
        return SIMD3<Float>(sumR / count, sumG / count, sumB / count)
    }

    func computeCentroid(_ positions: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !positions.isEmpty else { return SIMD3<Float>(0, 0, 0) }
        var sum = SIMD3<Float>(0, 0, 0)
        for pos in positions {
            sum += pos
        }
        return sum / Float(positions.count)
    }

    func computeDiameter(positions: [SIMD3<Float>], center: SIMD3<Float>) -> Float {
        guard !positions.isEmpty else { return 0 }
        var dists = positions.map { simd_distance($0, center) }
        let idx90 = max(0, Int(Float(dists.count) * 0.90) - 1)
        let val = nthElement(&dists, n: idx90)
        return val * 2.0
    }

    private func nthElement(_ arr: inout [Float], n: Int) -> Float {
        guard !arr.isEmpty else { return 0 }
        var lo = 0, hi = arr.count - 1
        while lo < hi {
            let pivot = arr[(lo + hi) / 2]
            var i = lo, j = hi
            while i <= j {
                while arr[i] < pivot { i += 1 }
                while arr[j] > pivot { j -= 1 }
                if i <= j {
                    arr.swapAt(i, j)
                    i += 1
                    j -= 1
                }
            }
            if n <= j { hi = j }
            else if n >= i { lo = i }
            else { break }
        }
        return arr[n]
    }

    func computeSphericity(positions: [SIMD3<Float>], center: SIMD3<Float>) -> Float {
        let n = Float(positions.count)
        guard n > 1 else { return 1.0 }

        var cov = simd_float3x3()
        var m01: Float = 0, m02: Float = 0, m12: Float = 0

        for pos in positions {
            let d = pos - center
            cov.columns.0.x += d.x * d.x
            cov.columns.1.y += d.y * d.y
            cov.columns.2.z += d.z * d.z
            m01 += d.x * d.y
            m02 += d.x * d.z
            m12 += d.y * d.z
        }

        let denom = n - 1
        cov.columns.0.x /= denom
        cov.columns.1.y /= denom
        cov.columns.2.z /= denom
        cov.columns.1.x = m01 / denom
        cov.columns.2.x = m02 / denom
        cov.columns.2.y = m12 / denom
        cov.columns.0.y = cov.columns.1.x
        cov.columns.0.z = cov.columns.2.x
        cov.columns.1.z = cov.columns.2.y

        let eigenvalues = computeEigenvalues(cov)

        guard eigenvalues.count == 3 else { return 0.0 }

        let lambdaMin = eigenvalues.min() ?? 0
        let lambdaMax = eigenvalues.max() ?? 1

        if lambdaMax < 1e-6 { return 0.0 }

        return lambdaMin / lambdaMax
    }

    func computeEigenvalues(_ matrix: simd_float3x3) -> [Float] {
        var eigenvalues: [Float] = []
        var eigenvectors: [SIMD3<Float>] = []

        for _ in 0..<3 {
            var current = SIMD3<Float>(1, 0, 0)

            for v in eigenvectors {
                current -= simd_dot(current, v) * v
            }
            let initNorm = simd_length(current)
            if initNorm < 1e-6 { break }
            current /= initNorm

            var prevLambda: Float = 0
            for iter in 0..<50 {
                var next: SIMD3<Float> = matrix * current
                for v in eigenvectors {
                    next -= simd_dot(next, v) * v
                }
                let norm = simd_length(next)
                if norm < 1e-6 { break }
                current = next / norm

                let lambda = simd_dot(current, matrix * current)
                if iter > 0 && abs(lambda - prevLambda) < 1e-4 { break }
                prevLambda = lambda
            }

            let lambda = simd_dot(current, matrix * current)
            eigenvalues.append(lambda)
            eigenvectors.append(current)
        }

        return eigenvalues.sorted()
    }
}
