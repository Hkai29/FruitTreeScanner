import CoreGraphics
import Foundation
import simd

enum ObservationProjection {
    /// 从检测框内的深度样本中选择靠近相机且具有足够支持的表面。
    /// 返回中位数以降低单个噪声像素对三维位置的影响。
    static func robustDepth(from rawDepths: [Float]) -> Float? {
        // 优先选择近端且有足够支持的深度簇，降低叶片后方背景的干扰。
        let depths = rawDepths
            .filter { $0.isFinite && $0 > 0.1 && $0 < 10.0 }
            .sorted()
        guard !depths.isEmpty else { return nil }

        let globalMedian = median(depths)
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

        let minimumForegroundSupport = max(3, Int(ceil(Float(depths.count) * 0.10)))
        let foregroundCluster = clusters.first { $0.count >= minimumForegroundSupport }
            ?? clusters.max { lhs, rhs in
                if lhs.count == rhs.count {
                    return median(lhs) > median(rhs)
                }
                return lhs.count < rhs.count
            }

        guard let foregroundCluster, !foregroundCluster.isEmpty else {
            return globalMedian
        }
        return median(foregroundCluster)
    }

    /// 将世界坐标点投影到 Vision 使用的左下原点归一化图像坐标。
    static func projectWorldPointToNormalizedImage(
        _ worldPoint: SIMD3<Float>,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> CGPoint? {
        // 先转回相机坐标，再使用内参投影到 Vision 的归一化坐标系。
        guard imageSize.width > 0, imageSize.height > 0 else { return nil }

        let cameraPoint4 = cameraTransform.inverse * SIMD4<Float>(
            worldPoint.x,
            worldPoint.y,
            worldPoint.z,
            1.0
        )
        let cameraPoint = SIMD3<Float>(cameraPoint4.x, cameraPoint4.y, cameraPoint4.z)
        guard cameraPoint.z < -0.05,
              cameraPoint.x.isFinite,
              cameraPoint.y.isFinite,
              cameraPoint.z.isFinite else {
            return nil
        }

        let fx = cameraIntrinsics[0][0]
        let fy = cameraIntrinsics[1][1]
        let cx = cameraIntrinsics[2][0]
        let cy = cameraIntrinsics[2][1]
        guard fx.isFinite, fy.isFinite, cx.isFinite, cy.isFinite,
              abs(fx) > 1e-6, abs(fy) > 1e-6 else {
            return nil
        }

        let imageX = (fx * cameraPoint.x / -cameraPoint.z) + cx
        let imageY = (fy * -cameraPoint.y / -cameraPoint.z) + cy
        let normalizedX = CGFloat(imageX) / imageSize.width
        let normalizedY = 1.0 - CGFloat(imageY) / imageSize.height

        guard normalizedX.isFinite, normalizedY.isFinite else { return nil }
        return CGPoint(x: normalizedX, y: normalizedY)
    }

    /// 把 Vision 归一化坐标换算到可能具有不同分辨率的深度图像素坐标。
    static func depthSamplePoint(
        normalizedPoint: CGPoint,
        imageSize: CGSize,
        depthSize: CGSize
    ) -> CGPoint {
        guard imageSize.width > 0, imageSize.height > 0,
              depthSize.width > 0, depthSize.height > 0 else {
            return .zero
        }

        let imagePoint = CGPoint(
            x: normalizedPoint.x * imageSize.width,
            y: (1 - normalizedPoint.y) * imageSize.height
        )

        return CGPoint(
            x: imagePoint.x * depthSize.width / imageSize.width,
            y: imagePoint.y * depthSize.height / imageSize.height
        )
    }

    /// 利用相机内参和实测深度，把图像像素反投影到相机坐标系。
    static func cameraPointFromImagePoint(
        _ imagePoint: SIMD3<Float>,
        depth: Float,
        cameraIntrinsics: matrix_float3x3
    ) -> SIMD3<Float>? {
        guard depth.isFinite, depth > 0.1 else { return nil }
        return ImageCameraCoordinateSpace.cameraPoint(
            imagePoint: imagePoint,
            depth: depth,
            inverseIntrinsics: cameraIntrinsics.inverse
        )
    }

    /// Buffer-free fusion path used after FramePacket has produced an Observation.
    static func projectObservationTo3D(
        detection: Observation,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize,
        fallbackDepth: Float?
    ) -> SIMD3<Float>? {
        let box = detection.boundingBox

        let depth: Float
        if let robustDepth = Self.robustDepth(from: detection.projectionDepthSamples) {
            depth = robustDepth
        } else if let fallbackDepth {
            depth = fallbackDepth
        } else {
            return nil
        }

        let normCenterX = box.origin.x + box.size.width / 2
        let normCenterY = box.origin.y + box.size.height / 2
        let centerX = normCenterX * imageSize.width
        let centerY = (1 - normCenterY) * imageSize.height

        let imagePoint = SIMD3<Float>(Float(centerX), Float(centerY), 1.0)
        guard let cameraPoint = Self.cameraPointFromImagePoint(
            imagePoint,
            depth: depth,
            cameraIntrinsics: cameraIntrinsics
        ) else { return nil }

        let worldPoint = cameraTransform * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1.0)
        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    private static func median(_ sortedValues: [Float]) -> Float {
        guard !sortedValues.isEmpty else { return 0 }
        let mid = sortedValues.count / 2
        if sortedValues.count % 2 == 0 {
            return (sortedValues[mid - 1] + sortedValues[mid]) / 2
        }
        return sortedValues[mid]
    }
}
