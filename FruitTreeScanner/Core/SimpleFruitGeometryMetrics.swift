// SimpleFruitGeometryMetrics.swift
// Point filtering, dimension measurement, and volume math for geometry estimates.

import Foundation
import simd

extension SimpleFruitGeometryEstimator {
    private static let maxAbsCoordinateMeters: Float = 20

    static func isUsablePoint(_ point: SIMD3<Float>) -> Bool {
        point.x.isFinite &&
            point.y.isFinite &&
            point.z.isFinite &&
            abs(point.x) <= maxAbsCoordinateMeters &&
            abs(point.y) <= maxAbsCoordinateMeters &&
            abs(point.z) <= maxAbsCoordinateMeters
    }

    static func dimensionsCm(from points: [SIMD3<Float>]) -> (length: Float, width: Float, height: Float) {
        return (
            robustExtentCm(points.map(\.x)),
            robustExtentCm(points.map(\.y)),
            robustExtentCm(points.map(\.z))
        )
    }

    static func dimensionsCm(
        from points: [SIMD3<Float>],
        normalizedCategoryName: String?
    ) -> (length: Float, width: Float, height: Float) {
        let robustDimensions = dimensionsCm(from: points)
        guard let fittedDiameterCm = occlusionAwareSphereDiameterCm(
            from: points,
            robustDimensions: robustDimensions,
            normalizedCategoryName: normalizedCategoryName
        ) else {
            return robustDimensions
        }
        return (fittedDiameterCm, fittedDiameterCm, fittedDiameterCm)
    }

    private static func occlusionAwareSphereDiameterCm(
        from points: [SIMD3<Float>],
        robustDimensions: (length: Float, width: Float, height: Float),
        normalizedCategoryName: String?
    ) -> Float? {
        guard usesRoundSpherePrior(normalizedCategoryName),
              points.count >= 24,
              let fit = fitSphere(to: points),
              fit.radiusM.isFinite,
              fit.radiusM > 0 else {
            return nil
        }

        let robustDiameterM = averageDiameter(
            lengthCm: robustDimensions.length,
            widthCm: robustDimensions.width,
            heightCm: robustDimensions.height
        ) / 100
        guard robustDiameterM > 0 else { return nil }

        let fittedDiameterM = fit.radiusM * 2
        let categoryRange = diameterRangeMeters(for: normalizedCategoryName)
        let expandedRange = categoryRange.map {
            ($0.lowerBound * 0.8)...($0.upperBound * 1.2)
        }
        if let expandedRange, !expandedRange.contains(fittedDiameterM) {
            return nil
        }

        let fittedDiameterCm: Float
        if let categoryRange {
            let upper = categoryRange.upperBound * 1.05
            fittedDiameterCm = min(max(fittedDiameterM, categoryRange.lowerBound), upper) * 100
        } else {
            fittedDiameterCm = fittedDiameterM * 100
        }

        let maxRobustAxisCm = max(robustDimensions.length, robustDimensions.width, robustDimensions.height)
        guard fittedDiameterCm >= maxRobustAxisCm * 0.9,
              fittedDiameterCm <= max(maxRobustAxisCm * 1.8, maxRobustAxisCm + 2.5) else {
            return nil
        }

        return fittedDiameterCm
    }

    private struct SphereFit {
        let radiusM: Float
    }

    private static func fitSphere(to points: [SIMD3<Float>]) -> SphereFit? {
        var normal = Array(repeating: Array(repeating: Double(0), count: 4), count: 4)
        var rhs = Array(repeating: Double(0), count: 4)
        var centroid = SIMD3<Double>(0, 0, 0)
        var minPoint = SIMD3<Float>(Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude, Float.greatestFiniteMagnitude)
        var maxPoint = SIMD3<Float>(-Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude, -Float.greatestFiniteMagnitude)

        for point in points {
            let x = Double(point.x)
            let y = Double(point.y)
            let z = Double(point.z)
            let row = [x, y, z, 1]
            let target = -(x * x + y * y + z * z)
            for i in 0..<4 {
                rhs[i] += row[i] * target
                for j in 0..<4 {
                    normal[i][j] += row[i] * row[j]
                }
            }
            centroid += SIMD3<Double>(x, y, z)
            minPoint = simd_min(minPoint, point)
            maxPoint = simd_max(maxPoint, point)
        }

        guard let solution = solveLinearSystem(matrix: normal, rhs: rhs) else { return nil }
        let center = SIMD3<Double>(
            -solution[0] / 2,
            -solution[1] / 2,
            -solution[2] / 2
        )
        let radiusSquared = simd_length_squared(center) - solution[3]
        guard radiusSquared.isFinite, radiusSquared > 0 else { return nil }

        let radius = sqrt(radiusSquared)
        let pointCount = Double(points.count)
        centroid /= pointCount

        let extents = maxPoint - minPoint
        let meaningfulAxisCount = [extents.x, extents.y, extents.z]
            .filter { Double($0) >= radius * 0.35 }
            .count
        guard meaningfulAxisCount >= 3 else { return nil }

        let centerOffset = simd_length(center - centroid)
        guard centerOffset <= radius * 1.25 else { return nil }

        var residualSum = 0.0
        for point in points {
            let pointDouble = SIMD3<Double>(Double(point.x), Double(point.y), Double(point.z))
            let distance = simd_length(pointDouble - center)
            let residual = distance - radius
            residualSum += residual * residual
        }
        let residual = sqrt(residualSum / pointCount) / radius
        guard residual.isFinite, residual <= 0.12 else { return nil }

        return SphereFit(radiusM: Float(radius))
    }

    private static func solveLinearSystem(matrix: [[Double]], rhs: [Double]) -> [Double]? {
        let count = rhs.count
        var augmented = matrix
        for row in 0..<count {
            augmented[row].append(rhs[row])
        }

        for column in 0..<count {
            var pivotRow = column
            var pivotMagnitude = abs(augmented[column][column])
            for row in (column + 1)..<count {
                let magnitude = abs(augmented[row][column])
                if magnitude > pivotMagnitude {
                    pivotMagnitude = magnitude
                    pivotRow = row
                }
            }
            guard pivotMagnitude > 1e-10 else { return nil }
            if pivotRow != column {
                augmented.swapAt(pivotRow, column)
            }

            let pivot = augmented[column][column]
            for valueIndex in column...(count) {
                augmented[column][valueIndex] /= pivot
            }

            for row in 0..<count where row != column {
                let factor = augmented[row][column]
                guard factor != 0 else { continue }
                for valueIndex in column...(count) {
                    augmented[row][valueIndex] -= factor * augmented[column][valueIndex]
                }
            }
        }

        return augmented.map { $0[count] }
    }

    private static func robustExtentCm(_ values: [Float]) -> Float {
        let sorted = values.filter(\.isFinite).sorted()
        guard let minValue = sorted.first, let maxValue = sorted.last else { return 0 }
        let rawExtent = maxValue - minValue
        guard sorted.count >= 20 else {
            return max(0, rawExtent * 100)
        }

        // Use the central 90% span to match the paper's outlier-resistant diameter estimate.
        let lower = percentile(sortedValues: sorted, fraction: 0.05)
        let upper = percentile(sortedValues: sorted, fraction: 0.95)
        let robustExtent = upper - lower
        let extent = robustExtent > 0 ? robustExtent : rawExtent
        return max(0, extent * 100)
    }

    private static func percentile(sortedValues: [Float], fraction: Float) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        let clampedFraction = min(max(fraction, 0), 1)
        let position = clampedFraction * Float(sortedValues.count - 1)
        let lowerIndex = Int(floor(position))
        let upperIndex = Int(ceil(position))
        guard lowerIndex != upperIndex else {
            return sortedValues[lowerIndex]
        }
        let t = position - Float(lowerIndex)
        return sortedValues[lowerIndex] + (sortedValues[upperIndex] - sortedValues[lowerIndex]) * t
    }

    static func axesAreClose(lengthCm: Float, widthCm: Float, heightCm: Float) -> Bool {
        let dimensions = [lengthCm, widthCm, heightCm]
        guard let minDimension = dimensions.min(), let maxDimension = dimensions.max(), minDimension > 0 else {
            return false
        }
        return maxDimension / minDimension <= 1.2
    }

    static func averageDiameter(lengthCm: Float, widthCm: Float, heightCm: Float) -> Float {
        guard lengthCm.isFinite, widthCm.isFinite, heightCm.isFinite else { return 0 }
        return max(0, (lengthCm + widthCm + heightCm) / 3)
    }

    static func sphereVolume(equivalentDiameterCm: Float) -> Float {
        guard equivalentDiameterCm.isFinite, equivalentDiameterCm > 0 else { return 0 }
        let radius = equivalentDiameterCm / 2
        return (4.0 / 3.0) * Float.pi * pow(radius, 3)
    }

    static func ellipsoidVolume(lengthCm: Float, widthCm: Float, heightCm: Float) -> Float {
        guard lengthCm.isFinite, widthCm.isFinite, heightCm.isFinite,
              lengthCm > 0, widthCm > 0, heightCm > 0 else { return 0 }
        return (4.0 / 3.0) * Float.pi * (lengthCm / 2) * (widthCm / 2) * (heightCm / 2)
    }

    static func sanitizedDensity(_ density: Float) -> Float {
        guard density.isFinite, density > 0 else { return 1.0 }
        return density
    }

    static func clampedRatio(_ value: Float) -> Float {
        guard value.isFinite else { return 0 }
        return min(max(value, 0), 1)
    }
}
