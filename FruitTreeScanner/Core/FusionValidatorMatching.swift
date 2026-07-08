// FusionValidatorMatching.swift
// Point-cloud candidate matching rules for fusion validation.

import CoreGraphics
import Foundation
import simd

extension FusionValidator {
    func findNearestCandidate(
        position: SIMD3<Float>,
        candidates: [FruitCandidate],
        detection: DetectedFruit,
        cameraIntrinsics: matrix_float3x3? = nil,
        cameraTransform: simd_float4x4? = nil,
        imageSize: CGSize? = nil
    ) -> FruitCandidate? {
        let positionTolerance: Float = 0.15
        let sizeTolerance = config.sizeTolerance

        var nearestCandidate: FruitCandidate?
        var bestScore: Float = .infinity

        for candidate in candidates {
            guard candidate.isValidFruit(expectedCategory: detection.category) else { continue }

            let distance = simd_distance(position, candidate.position)
            let expectedSize = detection.category.sizeRange
            let expectedDiameter = (expectedSize.lowerBound + expectedSize.upperBound) / 2
            let sizeDiff = abs(candidate.diameter - expectedDiameter) / expectedDiameter
            guard sizeDiff <= sizeTolerance else { continue }

            let frustumEvidence = makeFrustumEvidence(
                candidate: candidate,
                detection: detection,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            )
            let relaxedTolerance = max(positionTolerance, min(candidate.diameter * 3.0, 0.30))
            let centerMatch = distance < positionTolerance
            let frustumMatch = frustumEvidence.ratio >= 0.25 && distance < relaxedTolerance
            let projectedCenterMatch = frustumEvidence.centerInside && distance < relaxedTolerance

            guard centerMatch || frustumMatch || projectedCenterMatch else { continue }

            let score = distance
                - min(frustumEvidence.ratio, 1.0) * 0.06
                - (frustumEvidence.centerInside ? 0.02 : 0)

            if score < bestScore {
                bestScore = score
                nearestCandidate = candidate
            }
        }

        return nearestCandidate
    }

    private func makeFrustumEvidence(
        candidate: FruitCandidate,
        detection: DetectedFruit,
        cameraIntrinsics: matrix_float3x3?,
        cameraTransform: simd_float4x4?,
        imageSize: CGSize?
    ) -> (ratio: Float, centerInside: Bool) {
        guard let cameraIntrinsics,
              let cameraTransform,
              let imageSize else {
            return (0, false)
        }

        let box = expandedDetectionBox(detection.boundingBox, by: 0.12)
        let centerInside = Self.projectWorldPointToNormalizedImage(
            candidate.position,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize
        ).map { box.contains($0) } ?? false

        guard !candidate.points.isEmpty else {
            return (centerInside ? 1 : 0, centerInside)
        }

        var projectedCount = 0
        var insideCount = 0
        for point in candidate.points {
            guard let projected = Self.projectWorldPointToNormalizedImage(
                point,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            ) else {
                continue
            }
            projectedCount += 1
            if box.contains(projected) {
                insideCount += 1
            }
        }

        guard projectedCount > 0 else {
            return (centerInside ? 1 : 0, centerInside)
        }
        return (Float(insideCount) / Float(projectedCount), centerInside)
    }

    private func expandedDetectionBox(_ box: CGRect, by fraction: CGFloat) -> CGRect {
        let dx = box.width * fraction
        let dy = box.height * fraction
        let expanded = box.insetBy(dx: -dx, dy: -dy)
        let minX = max(0, expanded.minX)
        let minY = max(0, expanded.minY)
        let maxX = min(1, expanded.maxX)
        let maxY = min(1, expanded.maxY)
        guard maxX > minX, maxY > minY else { return box }
        return CGRect(x: minX, y: minY, width: maxX - minX, height: maxY - minY)
    }
}
