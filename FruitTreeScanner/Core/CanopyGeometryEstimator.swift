import Foundation
import simd

struct CanopyGeometryEstimate: Equatable, Sendable {
    let treeHeightM: Float
    let crownWidthM: Float
    let crownDepthM: Float
    let outerCrownVolumeM3: Float
    let crownVolumeM3: Float
    let effectiveVolumeCoefficient: Float
    let projectionXYCoefficient: Float
    let projectionXZCoefficient: Float
    let projectionYZCoefficient: Float
    let projectionEffectiveCoefficient: Float
    let voxelSizeM: Float
    let partitionSizeM: Float
    let partitionCount: Int
    let pointCount: Int
    let preprocessedPointCount: Int
    let groundFilteredPointCount: Int
    let trunkFilteredPointCount: Int
    let neighborFilteredPointCount: Int
    let canopyClusterCount: Int
    let robustPointCount: Int
}

enum CanopyGeometryEstimator {
    private static let minimumPointCount = 30
    private static let lowerFraction: Float = 0.05
    private static let upperFraction: Float = 0.95
    private static let minimumVoxelSize: Float = 0.03
    private static let maximumVoxelSize: Float = 0.25
    private static let maximumNearestNeighborSamples = 1_500
    private static let maximumProjectionCells = 120_000
    private static let partitionVoxelMultiplier: Float = 5
    private static let maximumPartitionCount = 512
    private static let groundBandHeightFraction: Float = 0.05
    private static let minimumGroundBandHeight: Float = 0.05
    private static let maximumGroundBandHeight: Float = 0.18
    private static let minimumGroundPointRatio: Float = 0.12
    private static let minimumGroundFootprintRatio: Float = 0.55
    private static let trunkRadiusFraction: Float = 0.08
    private static let minimumTrunkRadius: Float = 0.06
    private static let maximumTrunkRadius: Float = 0.25
    private static let trunkHeightFraction: Float = 0.55
    private static let minimumTrunkPointRatio: Float = 0.03
    private static let minimumTrunkVerticalSpanFraction: Float = 0.30
    private static let segmentationVoxelMultiplier: Float = 3
    private static let minimumSegmentationVoxelSize: Float = 0.20
    private static let maximumSegmentationVoxelSize: Float = 0.60
    private static let minimumDominantCanopyClusterRatio: Float = 0.55
    private static let minimumNeighborFilteredPointCount = 30

    static func estimate(points: [ColoredPoint]) -> CanopyGeometryEstimate? {
        estimate(positions: points.map(\.pos))
    }

    static func estimate(positions: [SIMD3<Float>]) -> CanopyGeometryEstimate? {
        let usable = positions.filter { point in
            point.x.isFinite &&
                point.y.isFinite &&
                point.z.isFinite &&
                abs(point.x) <= 20 &&
                abs(point.y) <= 20 &&
                abs(point.z) <= 20
        }
        guard usable.count >= minimumPointCount else { return nil }

        let preprocessing = preprocessCanopyPoints(usable)
        let canopyPoints = preprocessing.points
        guard canopyPoints.count >= minimumPointCount else { return nil }

        let xRange = robustRange(canopyPoints.map(\.x))
        let yRange = robustRange(canopyPoints.map(\.y))
        let zRange = robustRange(canopyPoints.map(\.z))
        guard let xRange, let yRange, let zRange else { return nil }

        let crownWidth = max(0, xRange.upper - xRange.lower)
        let treeHeight = max(0, yRange.upper - yRange.lower)
        let crownDepth = max(0, zRange.upper - zRange.lower)
        guard crownWidth > 0, treeHeight > 0, crownDepth > 0 else { return nil }

        let robustPoints = canopyPoints.filter { point in
            point.x >= xRange.lower &&
                point.x <= xRange.upper &&
                point.y >= yRange.lower &&
                point.y <= yRange.upper &&
                point.z >= zRange.lower &&
                point.z <= zRange.upper
        }
        let robustPointCount = robustPoints.count
        guard robustPointCount >= minimumPointCount / 2 else { return nil }

        let outerVolume = ellipsoidVolume(width: crownWidth, height: treeHeight, depth: crownDepth)
        let voxelSize = estimateVoxelSize(
            points: robustPoints,
            width: crownWidth,
            height: treeHeight,
            depth: crownDepth
        )
        let partitionedVolume = estimatePartitionedEffectiveVolume(
            points: robustPoints,
            xRange: xRange,
            yRange: yRange,
            zRange: zRange,
            voxelSize: voxelSize,
            outerVolume: outerVolume
        )

        return CanopyGeometryEstimate(
            treeHeightM: treeHeight,
            crownWidthM: crownWidth,
            crownDepthM: crownDepth,
            outerCrownVolumeM3: outerVolume,
            crownVolumeM3: partitionedVolume.volumeM3,
            effectiveVolumeCoefficient: partitionedVolume.coefficient,
            projectionXYCoefficient: partitionedVolume.projectionXYCoefficient,
            projectionXZCoefficient: partitionedVolume.projectionXZCoefficient,
            projectionYZCoefficient: partitionedVolume.projectionYZCoefficient,
            projectionEffectiveCoefficient: partitionedVolume.projectionEffectiveCoefficient,
            voxelSizeM: voxelSize,
            partitionSizeM: partitionedVolume.partitionSizeM,
            partitionCount: partitionedVolume.partitionCount,
            pointCount: usable.count,
            preprocessedPointCount: canopyPoints.count,
            groundFilteredPointCount: preprocessing.groundFilteredCount,
            trunkFilteredPointCount: preprocessing.trunkFilteredCount,
            neighborFilteredPointCount: preprocessing.neighborFilteredCount,
            canopyClusterCount: preprocessing.clusterCount,
            robustPointCount: robustPointCount
        )
    }

    private static func preprocessCanopyPoints(_ points: [SIMD3<Float>]) -> CanopyPreprocessingResult {
        let groundFiltered = removeGroundPoints(points)
        let trunkFiltered = removeTrunkPoints(groundFiltered.points)
        let segmented = selectTargetCanopyCluster(trunkFiltered.points)
        return CanopyPreprocessingResult(
            points: segmented.points,
            groundFilteredCount: groundFiltered.removedCount,
            trunkFilteredCount: trunkFiltered.removedCount,
            neighborFilteredCount: segmented.removedCount,
            clusterCount: segmented.clusterCount
        )
    }

    private static func removeGroundPoints(_ points: [SIMD3<Float>]) -> (points: [SIMD3<Float>], removedCount: Int) {
        guard points.count >= minimumPointCount else { return (points, 0) }

        let sortedY = points.map(\.y).filter(\.isFinite).sorted()
        guard let minY = sortedY.first, let maxY = sortedY.last, maxY > minY else {
            return (points, 0)
        }

        let verticalSpan = maxY - minY
        let groundBandHeight = min(
            max(verticalSpan * groundBandHeightFraction, minimumGroundBandHeight),
            maximumGroundBandHeight
        )
        let groundCutoff = minY + groundBandHeight
        let groundCandidates = points.filter { $0.y <= groundCutoff }
        let groundRatio = Float(groundCandidates.count) / Float(points.count)
        guard groundCandidates.count >= minimumPointCount, groundRatio >= minimumGroundPointRatio else {
            return (points, 0)
        }

        guard
            let fullXRange = robustRange(points.map(\.x)),
            let fullZRange = robustRange(points.map(\.z)),
            let groundXRange = robustRange(groundCandidates.map(\.x)),
            let groundZRange = robustRange(groundCandidates.map(\.z))
        else {
            return (points, 0)
        }

        let fullWidth = max(fullXRange.upper - fullXRange.lower, 0.000_001)
        let fullDepth = max(fullZRange.upper - fullZRange.lower, 0.000_001)
        let groundWidthRatio = max(groundXRange.upper - groundXRange.lower, 0) / fullWidth
        let groundDepthRatio = max(groundZRange.upper - groundZRange.lower, 0) / fullDepth
        guard max(groundWidthRatio, groundDepthRatio) >= minimumGroundFootprintRatio else {
            return (points, 0)
        }

        let filtered = points.filter { $0.y > groundCutoff }
        guard filtered.count >= minimumPointCount else { return (points, 0) }
        return (filtered, points.count - filtered.count)
    }

    private static func removeTrunkPoints(_ points: [SIMD3<Float>]) -> (points: [SIMD3<Float>], removedCount: Int) {
        guard points.count >= minimumPointCount else { return (points, 0) }
        guard
            let xRange = robustRange(points.map(\.x)),
            let yRange = robustRange(points.map(\.y)),
            let zRange = robustRange(points.map(\.z))
        else {
            return (points, 0)
        }

        let crownWidth = max(xRange.upper - xRange.lower, 0)
        let crownDepth = max(zRange.upper - zRange.lower, 0)
        let treeHeight = max(yRange.upper - yRange.lower, 0)
        guard crownWidth > 0, crownDepth > 0, treeHeight > 0 else {
            return (points, 0)
        }

        let centerX = percentile(sortedValues: points.map(\.x).filter(\.isFinite).sorted(), fraction: 0.5)
        let centerZ = percentile(sortedValues: points.map(\.z).filter(\.isFinite).sorted(), fraction: 0.5)
        let trunkRadius = min(
            max(max(crownWidth, crownDepth) * trunkRadiusFraction, minimumTrunkRadius),
            maximumTrunkRadius
        )
        let trunkHeightLimit = yRange.lower + treeHeight * trunkHeightFraction
        let trunkCandidates = points.filter { point in
            let horizontalOffset = SIMD2<Float>(point.x - centerX, point.z - centerZ)
            return simd_length(horizontalOffset) <= trunkRadius && point.y <= trunkHeightLimit
        }

        let trunkRatio = Float(trunkCandidates.count) / Float(points.count)
        guard trunkCandidates.count >= minimumPointCount / 2, trunkRatio >= minimumTrunkPointRatio else {
            return (points, 0)
        }

        let sortedCandidateY = trunkCandidates.map(\.y).filter(\.isFinite).sorted()
        guard
            let candidateMinY = sortedCandidateY.first,
            let candidateMaxY = sortedCandidateY.last,
            candidateMaxY - candidateMinY >= treeHeight * minimumTrunkVerticalSpanFraction
        else {
            return (points, 0)
        }

        let filtered = points.filter { point in
            let horizontalOffset = SIMD2<Float>(point.x - centerX, point.z - centerZ)
            return !(simd_length(horizontalOffset) <= trunkRadius && point.y <= trunkHeightLimit)
        }
        guard filtered.count >= minimumPointCount else { return (points, 0) }
        return (filtered, points.count - filtered.count)
    }

    private static func selectTargetCanopyCluster(
        _ points: [SIMD3<Float>]
    ) -> (points: [SIMD3<Float>], removedCount: Int, clusterCount: Int) {
        guard points.count >= minimumPointCount else { return (points, 0, 0) }
        guard
            let xRange = robustRange(points.map(\.x)),
            let yRange = robustRange(points.map(\.y)),
            let zRange = robustRange(points.map(\.z))
        else {
            return (points, 0, 1)
        }

        let width = max(xRange.upper - xRange.lower, 0)
        let height = max(yRange.upper - yRange.lower, 0)
        let depth = max(zRange.upper - zRange.lower, 0)
        guard width > 0, height > 0, depth > 0 else {
            return (points, 0, 1)
        }

        let roughSpacing = fallbackPointSpacing(
            pointCount: points.count,
            width: width,
            height: height,
            depth: depth
        )
        let cellSize = min(
            max(roughSpacing * segmentationVoxelMultiplier, minimumSegmentationVoxelSize),
            maximumSegmentationVoxelSize
        )

        var pointKeys: [VoxelKey] = []
        pointKeys.reserveCapacity(points.count)
        var cellPointCounts: [VoxelKey: Int] = [:]
        for point in points {
            let key = voxelKey(point, cellSize: cellSize)
            pointKeys.append(key)
            cellPointCounts[key, default: 0] += 1
        }
        guard cellPointCounts.count > 1 else { return (points, 0, 1) }

        let components = connectedVoxelComponents(cellPointCounts: cellPointCounts)
        let significantComponents = components.filter { $0.pointCount >= minimumPointCount / 2 }
        let candidateComponents = significantComponents.isEmpty ? components : significantComponents
        let clusterCount = max(candidateComponents.count, 1)
        guard
            clusterCount > 1,
            let selectedComponent = candidateComponents.max(by: { $0.pointCount < $1.pointCount })
        else {
            return (points, 0, clusterCount)
        }

        let selectedRatio = Float(selectedComponent.pointCount) / Float(points.count)
        let removedCount = points.count - selectedComponent.pointCount
        guard
            selectedRatio >= minimumDominantCanopyClusterRatio,
            removedCount >= minimumNeighborFilteredPointCount
        else {
            return (points, 0, clusterCount)
        }

        let selectedKeys = selectedComponent.keys
        var filtered: [SIMD3<Float>] = []
        filtered.reserveCapacity(selectedComponent.pointCount)
        for (point, key) in zip(points, pointKeys) where selectedKeys.contains(key) {
            filtered.append(point)
        }
        guard filtered.count >= minimumPointCount else { return (points, 0, clusterCount) }
        return (filtered, points.count - filtered.count, clusterCount)
    }

    private static func connectedVoxelComponents(
        cellPointCounts: [VoxelKey: Int]
    ) -> [(keys: Set<VoxelKey>, pointCount: Int)] {
        var visited = Set<VoxelKey>()
        visited.reserveCapacity(cellPointCounts.count)
        var components: [(keys: Set<VoxelKey>, pointCount: Int)] = []

        for startKey in cellPointCounts.keys where !visited.contains(startKey) {
            var stack = [startKey]
            visited.insert(startKey)
            var componentKeys = Set<VoxelKey>()
            componentKeys.reserveCapacity(32)
            var pointCount = 0

            while let key = stack.popLast() {
                componentKeys.insert(key)
                pointCount += cellPointCounts[key] ?? 0

                for dx in -1...1 {
                    for dy in -1...1 {
                        for dz in -1...1 {
                            guard dx != 0 || dy != 0 || dz != 0 else { continue }
                            let neighbor = VoxelKey(x: key.x + dx, y: key.y + dy, z: key.z + dz)
                            guard cellPointCounts[neighbor] != nil, !visited.contains(neighbor) else {
                                continue
                            }
                            visited.insert(neighbor)
                            stack.append(neighbor)
                        }
                    }
                }
            }

            components.append((componentKeys, pointCount))
        }

        return components
    }

    private static func robustRange(_ values: [Float]) -> (lower: Float, upper: Float)? {
        let sorted = values.filter(\.isFinite).sorted()
        guard sorted.count >= minimumPointCount else { return nil }
        let lower = percentile(sortedValues: sorted, fraction: lowerFraction)
        let upper = percentile(sortedValues: sorted, fraction: upperFraction)
        guard lower.isFinite, upper.isFinite, upper > lower else { return nil }
        return (lower, upper)
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

    private static func ellipsoidVolume(width: Float, height: Float, depth: Float) -> Float {
        Float.pi / 6 * width * height * depth
    }

    private static func estimateVoxelSize(
        points: [SIMD3<Float>],
        width: Float,
        height: Float,
        depth: Float
    ) -> Float {
        let fallback = fallbackPointSpacing(
            pointCount: points.count,
            width: width,
            height: height,
            depth: depth
        )
        let samples = evenlySampled(points, limit: maximumNearestNeighborSamples)
        guard samples.count >= 2 else { return fallback }

        let hashCellSize = max(fallback, minimumVoxelSize)
        let cells = Dictionary(grouping: samples.indices) { index in
            voxelKey(samples[index], cellSize: hashCellSize)
        }

        var distances: [Float] = []
        distances.reserveCapacity(samples.count)
        for index in samples.indices {
            let point = samples[index]
            let key = voxelKey(point, cellSize: hashCellSize)
            var bestDistanceSquared = Float.greatestFiniteMagnitude

            for searchRadius in 0...3 {
                for dx in -searchRadius...searchRadius {
                    for dy in -searchRadius...searchRadius {
                        for dz in -searchRadius...searchRadius {
                            guard abs(dx) == searchRadius ||
                                    abs(dy) == searchRadius ||
                                    abs(dz) == searchRadius ||
                                    searchRadius == 0 else {
                                continue
                            }
                            let neighborKey = VoxelKey(
                                x: key.x + dx,
                                y: key.y + dy,
                                z: key.z + dz
                            )
                            guard let neighborIndices = cells[neighborKey] else { continue }
                            for neighborIndex in neighborIndices where neighborIndex != index {
                                let distanceSquared = simd_length_squared(point - samples[neighborIndex])
                                if distanceSquared > 0, distanceSquared < bestDistanceSquared {
                                    bestDistanceSquared = distanceSquared
                                }
                            }
                        }
                    }
                }
                if bestDistanceSquared < Float.greatestFiniteMagnitude {
                    break
                }
            }

            if bestDistanceSquared < Float.greatestFiniteMagnitude {
                distances.append(sqrt(bestDistanceSquared))
            }
        }

        guard !distances.isEmpty else { return fallback }
        let averageNearestNeighbor = distances.reduce(0, +) / Float(distances.count)
        return clampedVoxelSize(averageNearestNeighbor)
    }

    private static func fallbackPointSpacing(
        pointCount: Int,
        width: Float,
        height: Float,
        depth: Float
    ) -> Float {
        guard pointCount > 0 else { return minimumVoxelSize }
        let boundingVolume = max(width * height * depth, 0.000_001)
        let spacing = pow(boundingVolume / Float(pointCount), 1.0 / 3.0)
        return clampedVoxelSize(spacing)
    }

    private static func clampedVoxelSize(_ value: Float) -> Float {
        guard value.isFinite, value > 0 else { return minimumVoxelSize }
        return min(max(value, minimumVoxelSize), maximumVoxelSize)
    }

    private static func estimatePartitionedEffectiveVolume(
        points: [SIMD3<Float>],
        xRange: (lower: Float, upper: Float),
        yRange: (lower: Float, upper: Float),
        zRange: (lower: Float, upper: Float),
        voxelSize: Float,
        outerVolume: Float
    ) -> (
        volumeM3: Float,
        coefficient: Float,
        partitionSizeM: Float,
        partitionCount: Int,
        projectionXYCoefficient: Float,
        projectionXZCoefficient: Float,
        projectionYZCoefficient: Float,
        projectionEffectiveCoefficient: Float
    ) {
        let height = yRange.upper - yRange.lower
        guard height > 0, outerVolume > 0 else {
            return (0, 0, max(voxelSize * partitionVoxelMultiplier, minimumVoxelSize), 0, 0, 0, 0, 0)
        }

        let partitionSize = min(max(voxelSize * partitionVoxelMultiplier, minimumVoxelSize), height)
        let rawPartitionCount = partitionCount(height: height, partitionSize: partitionSize)
        let partitionCount = min(rawPartitionCount, maximumPartitionCount)
        let effectivePartitionSize = height / Float(partitionCount)

        var volume: Float = 0
        for index in 0..<partitionCount {
            let lower = yRange.lower + Float(index) * effectivePartitionSize
            let upper = index == partitionCount - 1
                ? yRange.upper
                : min(yRange.upper, lower + effectivePartitionSize)
            guard upper > lower else { continue }

            let slicePoints = points.filter { point in
                if index == partitionCount - 1 {
                    return point.y >= lower && point.y <= upper
                }
                return point.y >= lower && point.y < upper
            }
            guard !slicePoints.isEmpty else { continue }

            let fillRatio = projectionFillRatio(
                points: slicePoints,
                firstRange: xRange,
                secondRange: zRange,
                first: { $0.x },
                second: { $0.z },
                voxelSize: voxelSize
            )
            let sliceOuterVolume = ellipsoidSliceVolume(
                width: xRange.upper - xRange.lower,
                depth: zRange.upper - zRange.lower,
                yLower: lower,
                yUpper: upper,
                yRange: yRange
            )
            volume += sliceOuterVolume * fillRatio
        }

        let boundedSliceVolume = min(max(volume, 0), outerVolume)
        let sliceCoefficient = min(max(boundedSliceVolume / outerVolume, 0), 1)
        let projectionCoefficients = estimateOrthogonalProjectionCoefficients(
            points: points,
            xRange: xRange,
            yRange: yRange,
            zRange: zRange,
            voxelSize: voxelSize
        )
        let coefficient = min(sliceCoefficient, projectionCoefficients.effective)
        return (
            outerVolume * coefficient,
            coefficient,
            effectivePartitionSize,
            partitionCount,
            projectionCoefficients.xy,
            projectionCoefficients.xz,
            projectionCoefficients.yz,
            projectionCoefficients.effective
        )
    }

    private static func estimateOrthogonalProjectionCoefficients(
        points: [SIMD3<Float>],
        xRange: (lower: Float, upper: Float),
        yRange: (lower: Float, upper: Float),
        zRange: (lower: Float, upper: Float),
        voxelSize: Float
    ) -> (xy: Float, xz: Float, yz: Float, effective: Float) {
        let xy = projectionFillRatio(
            points: points,
            firstRange: xRange,
            secondRange: yRange,
            first: { $0.x },
            second: { $0.y },
            voxelSize: voxelSize
        )
        let xz = projectionFillRatio(
            points: points,
            firstRange: xRange,
            secondRange: zRange,
            first: { $0.x },
            second: { $0.z },
            voxelSize: voxelSize
        )
        let yz = projectionFillRatio(
            points: points,
            firstRange: yRange,
            secondRange: zRange,
            first: { $0.y },
            second: { $0.z },
            voxelSize: voxelSize
        )
        let effective = pow(max(xy * xz * yz, 0), 1.0 / 3.0)
        return (xy, xz, yz, min(max(effective, 0), 1))
    }

    private static func partitionCount(height: Float, partitionSize: Float) -> Int {
        guard height > 0, partitionSize > 0 else { return 1 }
        let idealCount = height / partitionSize
        let roundedCount = max(Int(round(idealCount)), 1)
        if abs(idealCount - Float(roundedCount)) < 0.02 {
            return roundedCount
        }
        return max(Int(ceil(idealCount)), 1)
    }

    private static func ellipsoidSliceVolume(
        width: Float,
        depth: Float,
        yLower: Float,
        yUpper: Float,
        yRange: (lower: Float, upper: Float)
    ) -> Float {
        let height = yRange.upper - yRange.lower
        guard width > 0, depth > 0, height > 0, yUpper > yLower else { return 0 }

        let radiusY = height / 2
        let centerY = (yRange.lower + yRange.upper) / 2
        func primitive(_ y: Float) -> Float {
            let offset = y - centerY
            return offset - (offset * offset * offset) / (3 * radiusY * radiusY)
        }
        let integratedHeight = max(primitive(yUpper) - primitive(yLower), 0)
        return Float.pi / 4 * width * depth * integratedHeight
    }

    private static func projectionFillRatio(
        points: [SIMD3<Float>],
        firstRange: (lower: Float, upper: Float),
        secondRange: (lower: Float, upper: Float),
        first: (SIMD3<Float>) -> Float,
        second: (SIMD3<Float>) -> Float,
        voxelSize: Float
    ) -> Float {
        let firstSpan = max(firstRange.upper - firstRange.lower, 0)
        let secondSpan = max(secondRange.upper - secondRange.lower, 0)
        guard firstSpan > 0, secondSpan > 0 else { return 0 }

        let area = max(firstSpan * secondSpan, 0.000_001)
        let cellSize = max(voxelSize, sqrt(area / Float(maximumProjectionCells)))
        let columns = max(Int(ceil(firstSpan / cellSize)), 1)
        let rows = max(Int(ceil(secondSpan / cellSize)), 1)
        let totalCellCount = max(columns * rows, 1)

        var occupied = Set<Int64>()
        occupied.reserveCapacity(min(points.count, totalCellCount))
        for point in points {
            let column = projectionIndex(
                value: first(point),
                lower: firstRange.lower,
                cellSize: cellSize,
                upperBound: columns
            )
            let row = projectionIndex(
                value: second(point),
                lower: secondRange.lower,
                cellSize: cellSize,
                upperBound: rows
            )
            occupied.insert(Int64(row * columns + column))
        }

        return min(Float(occupied.count) / Float(totalCellCount), 1)
    }

    private static func projectionIndex(
        value: Float,
        lower: Float,
        cellSize: Float,
        upperBound: Int
    ) -> Int {
        min(max(Int(floor((value - lower) / cellSize)), 0), upperBound - 1)
    }

    private static func evenlySampled(
        _ points: [SIMD3<Float>],
        limit: Int
    ) -> [SIMD3<Float>] {
        guard points.count > limit, limit > 0 else { return points }
        return (0..<limit).map { index in
            let sourceIndex = index * (points.count - 1) / (limit - 1)
            return points[sourceIndex]
        }
    }

    private static func voxelKey(_ point: SIMD3<Float>, cellSize: Float) -> VoxelKey {
        VoxelKey(
            x: Int(floor(point.x / cellSize)),
            y: Int(floor(point.y / cellSize)),
            z: Int(floor(point.z / cellSize))
        )
    }

    private struct CanopyPreprocessingResult {
        let points: [SIMD3<Float>]
        let groundFilteredCount: Int
        let trunkFilteredCount: Int
        let neighborFilteredCount: Int
        let clusterCount: Int
    }

    private struct VoxelKey: Hashable {
        let x: Int
        let y: Int
        let z: Int
    }
}
