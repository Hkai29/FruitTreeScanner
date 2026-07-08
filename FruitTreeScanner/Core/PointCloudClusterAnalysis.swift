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
        guard isColorConsistent(colors) else {
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
            averageColor: avgColor,
            points: positions
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

    func isColorConsistent(_ colors: [SIMD3<Float>]) -> Bool {
        guard !colors.isEmpty else { return false }

        var fruitColorCount = 0
        var hueVector = SIMD2<Float>(0, 0)
        var hueWeightSum: Float = 0

        for color in colors {
            guard color.x.isFinite, color.y.isFinite, color.z.isFinite else {
                continue
            }
            guard FruitCategory.isFruitColor(color) else {
                continue
            }

            fruitColorCount += 1
            let hsv = FruitCategory.rgbToHSV(color)
            let radians = hsv.x * Float.pi / 180
            let weight = max(hsv.y * hsv.z, 0.001)
            hueVector += SIMD2<Float>(cos(radians), sin(radians)) * weight
            hueWeightSum += weight
        }

        let supportRatio = Float(fruitColorCount) / Float(colors.count)
        guard supportRatio >= 0.60 else {
            return false
        }
        guard hueWeightSum > 0 else {
            return true
        }

        let hueConcentration = simd_length(hueVector) / hueWeightSum
        return hueConcentration >= 0.60
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
        let a11 = matrix.columns.0.x
        let a22 = matrix.columns.1.y
        let a33 = matrix.columns.2.z
        let a12 = matrix.columns.1.x
        let a13 = matrix.columns.2.x
        let a23 = matrix.columns.2.y

        let offDiagonalEnergy = a12 * a12 + a13 * a13 + a23 * a23
        if offDiagonalEnergy < 1e-12 {
            return [a11, a22, a33].sorted()
        }

        let traceMean = (a11 + a22 + a33) / 3.0
        let centered11 = a11 - traceMean
        let centered22 = a22 - traceMean
        let centered33 = a33 - traceMean
        let varianceEnergy = centered11 * centered11
            + centered22 * centered22
            + centered33 * centered33
            + 2.0 * offDiagonalEnergy
        let scale = sqrt(max(varianceEnergy / 6.0, 0))
        guard scale > 1e-12 else {
            return [traceMean, traceMean, traceMean]
        }

        let b11 = centered11 / scale
        let b22 = centered22 / scale
        let b33 = centered33 / scale
        let b12 = a12 / scale
        let b13 = a13 / scale
        let b23 = a23 / scale
        let determinant = b11 * b22 * b33
            + 2.0 * b12 * b13 * b23
            - b11 * b23 * b23
            - b22 * b13 * b13
            - b33 * b12 * b12
        let halfDeterminant = min(max(determinant / 2.0, -1.0), 1.0)
        let angle = acos(halfDeterminant) / 3.0

        let eigen1 = traceMean + 2.0 * scale * cos(angle)
        let eigen3 = traceMean + 2.0 * scale * cos(angle + 2.0 * Float.pi / 3.0)
        let eigen2 = 3.0 * traceMean - eigen1 - eigen3
        return [eigen1, eigen2, eigen3].sorted()
    }
}
