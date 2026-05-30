// FusionValidator.swift
// 图像检测 ↔ 点云聚类融合验证

import Foundation
import CoreVideo
import VideoToolbox
import simd

// MARK: - Delegate Protocol

protocol FusionValidatorDelegate: AnyObject {
    func fusionValidator(_ validator: FusionValidator, didValidate fruits: [ValidatedFruit])
}

// MARK: - Fusion Validator

class FusionValidator {

    // MARK: - Properties

    weak var delegate: FusionValidatorDelegate?
    var config: FruitScanConfig

    // MARK: - Initialization

    init(config: FruitScanConfig = .default) {
        self.config = config
    }

    func updateConfig(_ newConfig: FruitScanConfig) {
        self.config = newConfig
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
        var validatedFruits: [ValidatedFruit] = []

        #if DEBUG
        print("🔍 [FusionValidator] 开始融合: \(detections.count) 个检测, \(candidates.count) 个候选")
        #endif

        // Match detections to candidates
        for detection in detections {
            let projectedPosition = projectDetectionTo3D(
                detection: detection,
                depthMap: depthMap,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            )

            #if DEBUG
            print("       检测: \(detection.category.displayName), 投影位置: \(projectedPosition)")
            #endif

            // Find nearest candidate within tolerance
            let matchedCandidate = findNearestCandidate(
                position: projectedPosition,
                candidates: candidates,
                detection: detection
            )

            if let candidate = matchedCandidate {
                // Fused: both image and point cloud validated
                #if DEBUG
                print("       → 匹配到候选: 位置\(candidate.position), 球形度\(candidate.sphericity)")
                #endif
                let validatedFruit = ValidatedFruit(
                    category: detection.category,
                    position: candidate.position,
                    confidence: detection.confidence * candidate.sphericity,
                    source: .fused
                )
                validatedFruits.append(validatedFruit)
            } else {
                // Image only: no matching candidate found
                #if DEBUG
                print("       → 无匹配候选 (imageOnly)")
                #endif
                let validatedFruit = ValidatedFruit(
                    category: detection.category,
                    position: projectedPosition,
                    confidence: detection.confidence,
                    source: .imageOnly
                )
                validatedFruits.append(validatedFruit)
            }
        }

        #if DEBUG
        print("🔍 [FusionValidator] 融合结果: \(validatedFruits.count) 个 (fused + imageOnly)")
        #endif

        // Notify delegate
        delegate?.fusionValidator(self, didValidate: validatedFruits)

        return validatedFruits
    }

    // MARK: - 2D → 3D Back Projection

    private func projectDetectionTo3D(
        detection: DetectedFruit,
        depthMap: CVPixelBuffer?,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> SIMD3<Float> {
        // Get bounding box center in pixel coordinates
        let box = detection.boundingBox
        let centerX = (box.origin.x + box.size.width / 2) * imageSize.width
        let centerY = (box.origin.y + box.size.height / 2) * imageSize.height

        // Get depth at center point (scale from image coords to depth map coords)
        var depth: Float = 2.0 // Default depth if no depth map
        if let depthMap = depthMap {
            let depthW = CVPixelBufferGetWidth(depthMap)
            let depthH = CVPixelBufferGetHeight(depthMap)
            let depthX = Int(centerX * CGFloat(depthW) / imageSize.width)
            let depthY = Int(centerY * CGFloat(depthH) / imageSize.height)
            depth = sampleDepth(depthMap: depthMap, x: depthX, y: depthY, imageSize: imageSize)
        }

        // Create image point in camera coordinates (pixel)
        let imagePoint = SIMD3<Float>(Float(centerX), Float(centerY), 1.0)

        // Back-project to camera space
        // K_inv * [u, v, 1]^T gives ray direction, scale by depth to get camera point
        let intrinsicsInverse = cameraIntrinsics.inverse
        var direction = intrinsicsInverse * imagePoint
        direction = simd_normalize(direction)  // Normalize to unit ray before scaling by depth
        let cameraPoint = direction * depth

        // Transform to world space
        let worldPoint = cameraTransform * SIMD4<Float>(cameraPoint.x, cameraPoint.y, cameraPoint.z, 1.0)

        return SIMD3<Float>(worldPoint.x, worldPoint.y, worldPoint.z)
    }

    // MARK: - Depth Sampling

    private func sampleDepth(depthMap: CVPixelBuffer, x: Int, y: Int, imageSize: CGSize) -> Float {
        CVPixelBufferLockBaseAddress(depthMap, .readOnly)
        defer { CVPixelBufferUnlockBaseAddress(depthMap, .readOnly) }

        guard let baseAddress = CVPixelBufferGetBaseAddress(depthMap) else {
            return 2.0
        }

        let width = CVPixelBufferGetWidth(depthMap)
        let height = CVPixelBufferGetHeight(depthMap)

        // Clamp coordinates to valid range
        let clampedX = max(0, min(x, width - 1))
        let clampedY = max(0, min(y, height - 1))

        // Determine pixel format
        let pixelFormat = CVPixelBufferGetPixelFormatType(depthMap)

        // Determine pixel format using raw fourCC codes
        let fp32: FourCharCode = 0x66703233  // 'fp32' = kCVPixelFormatType_32Float
        let up16: FourCharCode = 0x75703136  // 'up16' = kCVPixelFormatType_16U
        var depth: Float = 2.0

        if pixelFormat == fp32 {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let floatBuffer = baseAddress.assumingMemoryBound(to: Float.self)
            let rowBytes = bytesPerRow / MemoryLayout<Float>.size
            depth = floatBuffer[clampedY * rowBytes + clampedX]
        } else if pixelFormat == up16 {
            let bytesPerRow = CVPixelBufferGetBytesPerRow(depthMap)
            let shortBuffer = baseAddress.assumingMemoryBound(to: UInt16.self)
            let rowShorts = bytesPerRow / MemoryLayout<UInt16>.size
            let rawDepth = shortBuffer[clampedY * rowShorts + clampedX]
            // Convert mm to meters (typical depth sensor output)
            depth = Float(rawDepth) / 1000.0
        }

        // Validate depth range (0.1m to 10m)
        if depth < 0.1 || depth > 10.0 {
            depth = 2.0
        }

        return depth
    }

    // MARK: - Candidate Matching

    private func findNearestCandidate(
        position: SIMD3<Float>,
        candidates: [FruitCandidate],
        detection: DetectedFruit
    ) -> FruitCandidate? {
        let positionTolerance: Float = 0.1 // 0.1m tolerance
        let sizeTolerance = config.sizeTolerance // ±20% from config

        var nearestCandidate: FruitCandidate?
        var nearestDistance: Float = .infinity

        for candidate in candidates {
            // Skip invalid candidates
            guard candidate.isValidFruit() else { continue }

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