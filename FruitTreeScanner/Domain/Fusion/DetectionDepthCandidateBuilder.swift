import CoreGraphics
import Foundation
import simd

enum DetectionDepthCandidateBuilder {
    // 固定网格限制每个检测框的深度读取量，避免随图像分辨率增长。
    private static let roiSampleGrid = 9

    // 同时保留网格位置和世界坐标，用于连通性及形状检查。
    private struct DepthWorldSample {
        let row: Int
        let col: Int
        let worldPoint: SIMD3<Float>
    }

    static func makeCandidates(
        from observations: [Observation],
        clusterConfig: ClusterConfig
    ) -> [FruitCandidate] {
        observations.compactMap { makeCandidate(from: $0, clusterConfig: clusterConfig) }
    }

    private static func makeCandidate(
        from detection: Observation,
        clusterConfig: ClusterConfig
    ) -> FruitCandidate? {
        // 没有同帧对齐深度采样时不构造 depth-backed candidate。
        guard detection.hasAlignedDepthContext,
              !detection.roiDepthSamples.isEmpty,
              let cameraIntrinsics = detection.cameraIntrinsics,
              let cameraTransform = detection.cameraTransform,
              let imageSize = detection.imageSize,
              imageSize.width > 0,
              imageSize.height > 0 else {
            return nil
        }

        // 在框内均匀取样，避免只读取中心像素时被枝叶或孔洞误导。
        let samples = detection.roiDepthSamples.map {
            (
                point: CGPoint(x: CGFloat($0.normalizedImageX), y: CGFloat($0.normalizedImageY)),
                depth: $0.depthMeters,
                row: $0.row,
                col: $0.column
            )
        }

        // 从 ROI 中分离近端深度簇，避免把树后背景当作果实表面。
        guard let foregroundDepth = roiForegroundDepth(from: samples.map { $0.depth }) else {
            return nil
        }

        // 阈值随距离增长，并保留近距离场景所需的最小容差。
        let foregroundThreshold = max(0.08, foregroundDepth * 0.05)
        let foregroundSamples = samples.filter { abs($0.depth - foregroundDepth) <= foregroundThreshold }
        guard foregroundSamples.count >= max(3, min(clusterConfig.minPoints, 8)) else {
            return nil
        }

        // 初始直径只用于确定空间连通半径，最终直径会结合三维点集重算。
        let preliminaryDiameter = estimatedDiameter(
            detection: detection,
            depth: foregroundDepth,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize,
            clusterConfig: clusterConfig
        )

        // 每个前景深度样本使用同帧位姿转换到世界坐标。
        var worldSamples: [DepthWorldSample] = []
        worldSamples.reserveCapacity(foregroundSamples.count)
        for sample in foregroundSamples {
            if let worldPoint = projectNormalizedImagePointToWorld(
                sample.point,
                depth: sample.depth,
                imageSize: imageSize,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform
            ) {
                worldSamples.append(DepthWorldSample(row: sample.row, col: sample.col, worldPoint: worldPoint))
            }
        }
        let referencePoint = projectNormalizedImagePointToWorld(
            CGPoint(x: detection.boundingBox.midX, y: detection.boundingBox.midY),
            depth: foregroundDepth,
            imageSize: imageSize,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform
        )
        // 仅保留空间连通且靠近检测框中心射线的主簇。
        let selectedCluster = selectDominantCluster(
            from: worldSamples,
            referencePoint: referencePoint,
            distanceThreshold: roiClusterDistance(
                diameter: preliminaryDiameter,
                category: detection.category
            )
        )
        let worldPoints = selectedCluster.map(\.worldPoint)
        guard worldPoints.count >= max(3, min(clusterConfig.minPoints, 8)) else {
            return nil
        }
        // 过细或过于稀疏的网格簇更可能来自枝条，不生成候选。
        let shapeQuality = roiClusterShapeQuality(selectedCluster)
        guard shapeQuality >= roiClusterShapeQualityThreshold(for: detection.category) else {
            return nil
        }

        // 支持率记录有效三维样本占整个检测框采样网格的比例。
        let center = centroid(of: worldPoints)
        let depthSupportRatio = Float(worldPoints.count) / Float(roiSampleGrid * roiSampleGrid)
        // 直径综合图像投影与三维点集，并限制在品类物理范围内。
        let diameter = estimatedDiameter(
            detection: detection,
            depth: foregroundDepth,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize,
            clusterConfig: clusterConfig,
            worldPoints: worldPoints,
            shapeQuality: shapeQuality,
            depthSupportRatio: depthSupportRatio
        )
        guard diameter >= clusterConfig.minDiameter, diameter <= clusterConfig.maxDiameter else {
            return nil
        }

        return FruitCandidate(
            position: center,
            diameter: diameter,
            sphericity: roiCandidateSphericity(shapeQuality: shapeQuality, category: detection.category),
            pointCount: worldPoints.count,
            averageColor: representativeColor(for: detection.category),
            points: worldPoints,
            sourceCategory: detection.category,
            depthSupportRatio: depthSupportRatio
        )
    }

    /// 使用网格长宽比和填充率衡量候选在检测框内是否形成紧凑区域。
    private static func roiClusterShapeQuality(_ samples: [DepthWorldSample]) -> Float {
        guard samples.count >= 3 else { return 0 }
        let rows = samples.map(\.row)
        let cols = samples.map(\.col)
        guard let minRow = rows.min(), let maxRow = rows.max(),
              let minCol = cols.min(), let maxCol = cols.max() else {
            return 0
        }

        let rowSpan = maxRow - minRow + 1
        let colSpan = maxCol - minCol + 1
        guard rowSpan >= 2, colSpan >= 2 else { return 0 }

        let aspect = Float(min(rowSpan, colSpan)) / Float(max(rowSpan, colSpan))
        let boundingCells = max(rowSpan * colSpan, 1)
        let fillRatio = Float(samples.count) / Float(boundingCells)
        return min(max(aspect * sqrt(min(max(fillRatio, 0), 1)), 0), 1)
    }

    /// 按深度间隔分簇，并只接受具有最小支持数的最近表面。
    private static func roiForegroundDepth(from rawDepths: [Float]) -> Float? {
        let depths = rawDepths
            .filter { $0.isFinite && $0 > 0.1 && $0 < 10.0 }
            .sorted()
        guard !depths.isEmpty else { return nil }

        let globalMedian = median(of: depths)
        let maxClusterGap = max(0.12, globalMedian * 0.06)
        var clusters: [[Float]] = []
        var current: [Float] = []

        for depth in depths {
            if let last = current.last, depth - last > maxClusterGap {
                clusters.append(current)
                current = [depth]
            } else {
                current.append(depth)
            }
        }
        if !current.isEmpty {
            clusters.append(current)
        }

        guard let nearestCluster = clusters.first, !nearestCluster.isEmpty else {
            return nil
        }
        if clusters.count == 1 {
            return median(of: nearestCluster)
        }

        let minimumForegroundSupport = max(3, Int(ceil(Float(depths.count) * 0.10)))
        guard nearestCluster.count >= minimumForegroundSupport else {
            return nil
        }
        return median(of: nearestCluster)
    }

    private static func median(of sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        let mid = sortedValues.count / 2
        if sortedValues.count % 2 == 0 {
            return (sortedValues[mid - 1] + sortedValues[mid]) / 2
        }
        return sortedValues[mid]
    }

    // 细长或成串水果使用较低形状阈值，圆形水果保持更严格要求。
    private static func roiClusterShapeQualityThreshold(for category: FruitCategory) -> Float {
        switch category {
        case .mango, .papaya, .pear, .fig:
            return 0.22
        case .grape, .blueberry, .mulberry:
            return 0.28
        default:
            return 0.30
        }
    }

    // 将二维网格形状质量映射为候选球形度，但不低于品类先验下限。
    private static func roiCandidateSphericity(shapeQuality: Float, category: FruitCategory) -> Float {
        let base = max(category.sphericityThreshold + 0.05, 0.55)
        let qualityBoost = min(max(shapeQuality, 0), 1) * 0.35
        return min(max(base + qualityBoost, base), 0.95)
    }

    /// 在三维样本中搜索连通分量，并选择点数与中心位置综合得分最高的一簇。
    private static func selectDominantCluster(
        from samples: [DepthWorldSample],
        referencePoint: SIMD3<Float>?,
        distanceThreshold: Float
    ) -> [DepthWorldSample] {
        guard !samples.isEmpty else { return [] }
        var visited = Array(repeating: false, count: samples.count)
        var bestCluster: [DepthWorldSample] = []
        var bestScore = -Float.infinity

        for startIndex in samples.indices where !visited[startIndex] {
            var cluster: [DepthWorldSample] = []
            var stack = [startIndex]
            visited[startIndex] = true

            // 深度优先遍历把空间距离小于阈值的样本归入同一分量。
            while let index = stack.popLast() {
                let sample = samples[index]
                cluster.append(sample)

                for nextIndex in samples.indices where !visited[nextIndex] {
                    let distance = simd_distance(sample.worldPoint, samples[nextIndex].worldPoint)
                    if distance <= distanceThreshold {
                        visited[nextIndex] = true
                        stack.append(nextIndex)
                    }
                }
            }

            let score = clusterScore(
                cluster,
                referencePoint: referencePoint,
                distanceScale: max(distanceThreshold, 0.025)
            )
            if score > bestScore {
                bestScore = score
                bestCluster = cluster
            }
        }

        return bestCluster
    }

    /// 点数是主得分，偏离检测框中心或中心射线的簇会被扣分。
    private static func clusterScore(
        _ cluster: [DepthWorldSample],
        referencePoint: SIMD3<Float>?,
        distanceScale: Float
    ) -> Float {
        var score = Float(cluster.count)
        score -= roiCenterDistancePenalty(for: cluster)
        if let referencePoint {
            let center = centroid(of: cluster.map(\.worldPoint))
            let normalizedDistance = simd_distance(center, referencePoint) / max(distanceScale, 1e-6)
            score -= min(normalizedDistance, 3.0) * 0.5
        }
        return score
    }

    /// 抑制贴近检测框边缘的簇，降低邻近果实或枝叶进入候选的概率。
    private static func roiCenterDistancePenalty(for cluster: [DepthWorldSample]) -> Float {
        guard !cluster.isEmpty else { return 0 }
        let averageRow = cluster.reduce(Float(0)) { $0 + Float($1.row) } / Float(cluster.count)
        let averageCol = cluster.reduce(Float(0)) { $0 + Float($1.col) } / Float(cluster.count)
        let centerIndex = Float(roiSampleGrid - 1) * 0.5
        let maxGridDistance = sqrt(centerIndex * centerIndex * 2)
        let gridDistance = hypot(averageRow - centerIndex, averageCol - centerIndex)
        let normalizedDistance = min(max(gridDistance / max(maxGridDistance, 1), 0), 1)
        return normalizedDistance * Float(cluster.count) * 0.65
    }

    // 连通半径由估计直径和品类尺寸共同约束，避免跨果实合并。
    private static func roiClusterDistance(
        diameter: Float,
        category: FruitCategory
    ) -> Float {
        let categoryDiameter = (category.sizeRange.lowerBound + category.sizeRange.upperBound) * 0.5
        let referenceDiameter = max(
            min(diameter, category.sizeRange.upperBound * 1.2),
            categoryDiameter * 0.6
        )
        return max(0.025, min(referenceDiameter * 1.10, 0.14))
    }

    /// 依次完成归一化坐标到像素、相机坐标和世界坐标的转换。
    private static func projectNormalizedImagePointToWorld(
        _ normalizedPoint: CGPoint,
        depth: Float,
        imageSize: CGSize,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4
    ) -> SIMD3<Float>? {
        guard depth.isFinite, depth > 0.1, imageSize.width > 0, imageSize.height > 0 else {
            return nil
        }

        let imageX = Float(normalizedPoint.x * imageSize.width)
        let imageY = Float((1 - normalizedPoint.y) * imageSize.height)
        let imagePoint = SIMD3<Float>(imageX, imageY, 1.0)
        guard let cameraPoint = ObservationProjection.cameraPointFromImagePoint(
            imagePoint,
            depth: depth,
            cameraIntrinsics: cameraIntrinsics
        ) else {
            return nil
        }
        let worldPoint = cameraTransform * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1.0)
        let result = SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
        guard result.x.isFinite, result.y.isFinite, result.z.isFinite else { return nil }
        return result
    }

    /// 融合图像投影直径、点集空间范围和品类先验，输出受物理范围约束的直径。
    private static func estimatedDiameter(
        detection: Observation,
        depth: Float,
        cameraIntrinsics: matrix_float3x3,
        imageSize: CGSize,
        clusterConfig: ClusterConfig,
        worldPoints: [SIMD3<Float>] = [],
        shapeQuality: Float = 0.5,
        depthSupportRatio: Float = 0
    ) -> Float {
        let categoryRange = detection.category.sizeRange
        let expectedDiameter = (categoryRange.lowerBound + categoryRange.upperBound) / 2
        let imageDiameter = projectedImageDiameter(
            detection: detection,
            depth: depth,
            cameraIntrinsics: cameraIntrinsics,
            imageSize: imageSize
        )
        let clusterDiameter = spatialExtentDiameter(of: worldPoints)
        let plausibleMeasuredDiameter = measuredDiameter(
            imageDiameter: imageDiameter,
            clusterDiameter: clusterDiameter,
            categoryRange: categoryRange
        )
        // 点簇越紧凑、深度支持越充分，实测尺寸在融合结果中的权重越高。
        var measurementReliability = min(
            max(0.20 + min(max(shapeQuality, 0), 1) * 0.35 + min(max(depthSupportRatio, 0), 1) * 0.30, 0.20),
            0.75
        )
        if imageDiameter < categoryRange.lowerBound * 0.60 ||
            imageDiameter > categoryRange.upperBound * 1.50 {
            measurementReliability *= 0.5
        }

        let blended = plausibleMeasuredDiameter * measurementReliability
            + expectedDiameter * (1 - measurementReliability)
        let minDiameter = max(clusterConfig.minDiameter, categoryRange.lowerBound * 0.75)
        let maxDiameter = min(clusterConfig.maxDiameter, categoryRange.upperBound * 1.05)
        return min(max(blended, minDiameter), maxDiameter)
    }

    // 根据焦距、框尺寸和深度近似目标在真实空间中的直径。
    private static func projectedImageDiameter(
        detection: Observation,
        depth: Float,
        cameraIntrinsics: matrix_float3x3,
        imageSize: CGSize
    ) -> Float {
        let fx = max(abs(cameraIntrinsics[0][0]), 1)
        let fy = max(abs(cameraIntrinsics[1][1]), 1)
        let widthM = Float(detection.boundingBox.width * imageSize.width) / fx * depth
        let heightM = Float(detection.boundingBox.height * imageSize.height) / fy * depth
        let diameter = max((widthM + heightM) / 2, 0)
        return diameter.isFinite ? diameter : 0
    }

    // 使用三维包围盒对角线描述点簇的最大空间跨度。
    private static func spatialExtentDiameter(of points: [SIMD3<Float>]) -> Float {
        guard points.count >= 2 else { return 0 }
        var minPoint = points[0]
        var maxPoint = points[0]
        for point in points.dropFirst() {
            minPoint = SIMD3<Float>(
                Swift.min(minPoint.x, point.x),
                Swift.min(minPoint.y, point.y),
                Swift.min(minPoint.z, point.z)
            )
            maxPoint = SIMD3<Float>(
                Swift.max(maxPoint.x, point.x),
                Swift.max(maxPoint.y, point.y),
                Swift.max(maxPoint.z, point.z)
            )
        }
        let extent = maxPoint - minPoint
        let diameter = simd_length(extent)
        return diameter.isFinite ? diameter : 0
    }

    /// 图像直径为主体，点簇跨度只作为防止明显低估的下限证据。
    private static func measuredDiameter(
        imageDiameter: Float,
        clusterDiameter: Float,
        categoryRange: ClosedRange<Float>
    ) -> Float {
        guard imageDiameter.isFinite && imageDiameter > 0 else {
            return categoryRange.lowerBound <= categoryRange.upperBound
                ? (categoryRange.lowerBound + categoryRange.upperBound) / 2
                : 0
        }
        let cappedImageDiameter = min(max(imageDiameter, categoryRange.lowerBound * 0.40), categoryRange.upperBound * 1.50)
        let clusterLowerBound = clusterDiameter.isFinite && clusterDiameter > 0
            ? clusterDiameter * 1.25
            : 0
        return max(cappedImageDiameter, clusterLowerBound)
    }

    private static func centroid(of points: [SIMD3<Float>]) -> SIMD3<Float> {
        guard !points.isEmpty else { return .zero }
        var sum = SIMD3<Float>.zero
        for point in points {
            sum += point
        }
        return sum / Float(points.count)
    }

    // 深度候选没有可靠 RGB 均值时，使用品类代表色供点云显示。
    private static func representativeColor(for category: FruitCategory) -> SIMD3<Float> {
        switch category {
        case .apple, .cherry, .persimmon, .pomegranate, .hawthorn, .bayberry:
            return SIMD3<Float>(0.75, 0.18, 0.12)
        case .orange, .mandarin, .pomelo, .peach, .loquat, .mango, .papaya:
            return SIMD3<Float>(0.95, 0.48, 0.10)
        case .pear, .kiwi, .grape, .fig, .coconut:
            return SIMD3<Float>(0.45, 0.58, 0.20)
        case .plum, .mulberry, .blueberry:
            return SIMD3<Float>(0.22, 0.14, 0.45)
        case .lychee, .longan, .jujube, .chestnut, .strawberry:
            return SIMD3<Float>(0.70, 0.28, 0.18)
        }
    }
}
