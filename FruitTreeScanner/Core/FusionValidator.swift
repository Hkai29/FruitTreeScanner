// FusionValidator.swift
// 图像检测 ↔ 点云聚类融合验证

import CoreGraphics
import Foundation
@preconcurrency import CoreVideo
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
            let availableCandidates = candidates.filter { !usedCandidateIDs.contains($0.id) }
            let matchedCandidate = findNearestCandidate(
                position: projectedPosition,
                candidates: availableCandidates,
                detection: detection,
                cameraIntrinsics: context.cameraIntrinsics,
                cameraTransform: context.cameraTransform,
                imageSize: context.imageSize
            )

            if let candidate = matchedCandidate {
                usedCandidateIDs.insert(candidate.id)

                // Fused: both image and point cloud validated
                let validatedFruit = ValidatedFruit(
                    category: detection.category,
                    position: candidate.position,
                    confidence: fusedConfidence(detection: detection, candidate: candidate),
                    source: .fused
                )
                validatedFruits.append(validatedFruit)
            } else {
                if hasRejectedDetectionDepthCandidate(
                    near: projectedPosition,
                    candidates: availableCandidates,
                    detection: detection,
                    cameraIntrinsics: context.cameraIntrinsics,
                    cameraTransform: context.cameraTransform,
                    imageSize: context.imageSize
                ) {
                    continue
                }
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

    private func hasRejectedDetectionDepthCandidate(
        near projectedPosition: SIMD3<Float>,
        candidates: [FruitCandidate],
        detection: DetectedFruit,
        cameraIntrinsics: matrix_float3x3,
        cameraTransform: simd_float4x4,
        imageSize: CGSize
    ) -> Bool {
        let expandedBox = detection.boundingBox.insetBy(
            dx: -detection.boundingBox.width * 0.12,
            dy: -detection.boundingBox.height * 0.12
        )

        return candidates.contains { candidate in
            guard candidate.sourceCategory == detection.category,
                  candidate.depthSupportRatio != nil else {
                return false
            }

            let distance = simd_distance(projectedPosition, candidate.position)
            let distanceThreshold = max(0.08, min(candidate.diameter * 3.0, 0.24))
            if distance <= distanceThreshold {
                return true
            }

            guard let projectedCandidate = Self.projectWorldPointToNormalizedImage(
                candidate.position,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            ) else {
                return false
            }
            return expandedBox.contains(projectedCandidate)
        }
    }

    private func fusedConfidence(detection: DetectedFruit, candidate: FruitCandidate) -> Float {
        let depthSupportQuality: Float
        if let depthSupportRatio = candidate.depthSupportRatio {
            let clampedRatio = min(max(depthSupportRatio, 0), 1)
            depthSupportQuality = 0.55 + clampedRatio * 0.45
        } else {
            depthSupportQuality = 1
        }
        return min(max(detection.confidence * candidate.sphericity * depthSupportQuality, 0), 1)
    }

}
