// FusionValidator.swift
// 图像检测 ↔ 点云聚类融合验证

import Foundation
@preconcurrency import CoreVideo
import VideoToolbox
import simd

// MARK: - Fusion Validator

final class FusionValidator: Sendable {

    private struct ProjectionContext {
        let depthMap: CVPixelBuffer?
        let cameraIntrinsics: matrix_float3x3
        let cameraTransform: simd_float4x4
        let imageSize: CGSize
    }

    // MARK: - Properties

    let config: FruitScanConfig

    // MARK: - Initialization

    init(config: FruitScanConfig = .default) {
        self.config = config
    }

    // MARK: - Validation

    func validate(
        detections: [DetectedFruit],
        candidates: [FruitCandidate],
        depthMap: CVPixelBuffer?,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> [ValidatedFruit] {
        validate(detections: detections, candidates: candidates) { detection in
            ProjectionContext(
                depthMap: depthMap,
                cameraIntrinsics: detection.cameraIntrinsics ?? cameraIntrinsics,
                cameraTransform: detection.cameraTransform ?? cameraTransform,
                imageSize: detection.imageSize ?? imageSize
            )
        }
    }

    /// Validates live scan detections only when each one carries the depth map
    /// captured with its RGB frame. This avoids projecting old detections
    /// through a later ARFrame's depth map after the operator has moved.
    func validate(
        detections: [DetectedFruit],
        candidates: [FruitCandidate]
    ) -> [ValidatedFruit] {
        validate(detections: detections, candidates: candidates) { detection in
            guard let depthMap = detection.depthMap,
                  let cameraIntrinsics = detection.cameraIntrinsics,
                  let cameraTransform = detection.cameraTransform,
                  let imageSize = detection.imageSize
            else {
                return nil
            }
            return ProjectionContext(
                depthMap: depthMap,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            )
        }
    }

    private func validate(
        detections: [DetectedFruit],
        candidates: [FruitCandidate],
        projectionContext: (DetectedFruit) -> ProjectionContext?
    ) -> [ValidatedFruit] {
        var validatedFruits: [ValidatedFruit] = []
        var usedCandidateIDs = Set<UUID>()

        for detection in detections {
            guard let context = projectionContext(detection) else { continue }

            let projectedPosition = projectDetectionTo3D(
                detection: detection,
                depthMap: context.depthMap,
                cameraIntrinsics: context.cameraIntrinsics,
                cameraTransform: context.cameraTransform,
                imageSize: context.imageSize
            )

            // Find nearest candidate within tolerance
            let matchedCandidate = findNearestCandidate(
                position: projectedPosition,
                candidates: candidates.filter { !usedCandidateIDs.contains($0.id) },
                detection: detection
            )

            if let candidate = matchedCandidate {
                usedCandidateIDs.insert(candidate.id)

                // Fused: both image and point cloud validated
                let validatedFruit = ValidatedFruit(
                    category: detection.category,
                    position: candidate.position,
                    confidence: detection.confidence * candidate.sphericity,
                    source: .fused
                )
                validatedFruits.append(validatedFruit)
            } else {
                // Image only: no matching candidate found
                let validatedFruit = ValidatedFruit(
                    category: detection.category,
                    position: projectedPosition,
                    confidence: detection.confidence,
                    source: .imageOnly
                )
                validatedFruits.append(validatedFruit)
            }
        }

        return validatedFruits
    }

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

    // MARK: - 2D → 3D Back Projection

    private func projectDetectionTo3D(
        detection: DetectedFruit,
        depthMap: CVPixelBuffer?,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> SIMD3<Float> {
        let box = detection.boundingBox

        // 3×3 网格多点采样深度，比中心单点更抗噪声
        var validDepths: [Float] = []
        if let depthMap = depthMap, let depthSampler = DepthSampler(depthMap: depthMap) {
            for row in 0..<3 {
                for col in 0..<3 {
                    // Vision boundingBox 是左下角原点；depthSamplePoint 会转换到图像像素坐标。
                    let normalizedPoint = CGPoint(
                        x: box.origin.x + box.size.width * CGFloat(col * 2 + 1) / 6.0,
                        y: box.origin.y + box.size.height * CGFloat(row * 2 + 1) / 6.0
                    )
                    let depthPoint = Self.depthSamplePoint(
                        normalizedPoint: normalizedPoint,
                        imageSize: imageSize,
                        depthSize: CGSize(width: depthSampler.width, height: depthSampler.height)
                    )

                    if let d = depthSampler.depth(x: Int(depthPoint.x), y: Int(depthPoint.y)) {
                        validDepths.append(d)
                    }
                }
            }
        }

        // 用中值深度（抗噪声），fallback 到默认深度
        let depth: Float
        if !validDepths.isEmpty {
            let sorted = validDepths.sorted()
            depth = sorted[sorted.count / 2]
        } else {
            depth = 2.0
        }

        // 中心点用于射线方向（像素坐标）
        let normCenterX = box.origin.x + box.size.width / 2
        let normCenterY = box.origin.y + box.size.height / 2
        let centerX = normCenterX * imageSize.width
        let centerY = (1 - normCenterY) * imageSize.height

        let imagePoint = SIMD3<Float>(Float(centerX), Float(centerY), 1.0)
        let intrinsicsInverse = cameraIntrinsics.inverse
        var direction = intrinsicsInverse * imagePoint
        direction = simd_normalize(direction)
        let cameraPoint = direction * depth

        let worldPoint = cameraTransform * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1.0)
        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    // MARK: - Depth Sampling

    private final class DepthSampler {
        let width: Int
        let height: Int

        private let depthMap: CVPixelBuffer
        private let baseAddress: UnsafeMutableRawPointer
        private let pixelFormat: FourCharCode

        init?(depthMap: CVPixelBuffer) {
            CVPixelBufferLockBaseAddress(depthMap, .readOnly)
            guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
                CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
                return nil
            }

            self.depthMap = depthMap
            self.baseAddress = baseAddress
            self.width = CVPixelBufferGetWidth(depthMap)
            self.height = CVPixelBufferGetHeight(depthMap)
            self.pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)
        }

        deinit {
            CVPixelBufferUnlockBaseAddress(depthMap, .readOnly)
        }

        func depth(x: Int, y: Int) -> Float? {
            guard width > 0, height > 0 else { return nil }

            let clampedX = max(0, min(x, width - 1))
            let clampedY = max(0, min(y, height - 1))
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)

            let fp32: FourCharCode = 0x66703233  // 'fp32' = kCVPixelFormatType_32Float
            let up16: FourCharCode = 0x75703136  // 'up16' = kCVPixelFormatType_16U
            let depth: Float

            if pixelFormat == fp32 {
                let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
                let rowBytes = bytesPerRow / MemoryLayout<Float>.size
                depth = floatBuffer[clampedY * rowBytes + clampedX]
            } else if pixelFormat == up16 {
                let shortBuffer = baseAddress.assumingMemoryBound(to: UInt16.self)
                let rowShorts = bytesPerRow / MemoryLayout<UInt16>.size
                let rawDepth = shortBuffer[clampedY * rowShorts + clampedX]
                depth = Float(rawDepth) / 1000.0
            } else {
                return nil
            }

            guard depth > 0.1, depth < 10.0 else { return nil }
            return depth
        }
    }

    // MARK: - Candidate Matching

    private func findNearestCandidate(
        position: SIMD3<Float>,
        candidates: [FruitCandidate],
        detection: DetectedFruit
    ) -> FruitCandidate? {
        let positionTolerance: Float = 0.15
        let sizeTolerance = config.sizeTolerance

        var nearestCandidate: FruitCandidate?
        var nearestDistance: Float = .infinity

        for candidate in candidates {
            guard candidate.isValidFruit(expectedCategory: detection.category) else { continue }

            // Calculate 3D distance
            let distance = simd_distance(position, candidate.position)

            // Check position tolerance
            guard distance < positionTolerance else { continue }

            // Estimate expected size from category
            let expectedSize = detection.category.sizeRange
            let expectedDiameter = (expectedSize.lowerBound + expectedSize.upperBound) / 2

            // Check size tolerance
            let sizeDiff = abs(candidate.diameter - expectedDiameter) / expectedDiameter
            guard sizeDiff <= sizeTolerance else { continue }

            // Update nearest if this candidate is closer
            if distance < nearestDistance {
                nearestDistance = distance
                nearestCandidate = candidate
            }
        }

        return nearestCandidate
    }
}
