import CoreGraphics
import Foundation
import simd

/// Value-only geometric gates for assignment and rejected ROI evidence.
struct CandidateMatcher: Sendable {
    let config: FruitScanConfig
    let experimentConfiguration: FusionExperimentConfig

    init(config: FruitScanConfig = .default, experimentConfiguration: FusionExperimentConfig = .default) {
        self.config = config
        self.experimentConfiguration = experimentConfiguration
    }

    func matchScore(
        position: SIMD3<Float>,
        candidate: FruitCandidate,
        detection: Observation,
        cameraIntrinsics: matrix_float3x3?,
        cameraTransform: simd_float4x4?,
        imageSize: CGSize?
    ) -> Float? {
        // Keep the established geometric gates for each assignment edge.
        guard candidate.isValidFruit(expectedCategory: detection.category) else { return nil }
        let experimentConfig = experimentConfiguration
        let positionTolerance = experimentConfig.nearestCandidateDistance
        let distance = simd_distance(position, candidate.position)
        let expectedSize = detection.category.sizeRange
        let expectedDiameter = (expectedSize.lowerBound + expectedSize.upperBound) / 2
        let sizeDiff = abs(candidate.diameter - expectedDiameter) / expectedDiameter
        guard distance.isFinite, sizeDiff <= config.sizeTolerance else { return nil }

        let frustumEvidence = makeFrustumEvidence(
            candidate: candidate,
            detection: detection,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize
        )
        let relaxedTolerance = max(
            positionTolerance,
            min(candidate.diameter * experimentConfig.relaxedDistanceMultiplier,
                experimentConfig.relaxedDistanceCap)
        )
        let centerMatch = distance < positionTolerance
        let frustumMatch = frustumEvidence.ratio >= experimentConfig.frustumSupportRatio && distance < relaxedTolerance
        let projectedCenterMatch = frustumEvidence.centerInside && distance < relaxedTolerance
        guard centerMatch || frustumMatch || projectedCenterMatch else { return nil }

        return distance
            - min(frustumEvidence.ratio, 1.0) * 0.06
            - (frustumEvidence.centerInside ? 0.02 : 0)
    }

    private func makeFrustumEvidence(
        candidate: FruitCandidate,
        detection: Observation,
        cameraIntrinsics: matrix_float3x3?,
        cameraTransform: simd_float4x4?,
        imageSize: CGSize?
    ) -> (ratio: Float, centerInside: Bool) {
        // 缺少投影上下文时不推断视锥支持，保持保守匹配。
        guard let cameraIntrinsics,
              let cameraTransform,
              let imageSize else {
            return (0, false)
        }

        let box = expandedDetectionBox(
            detection.boundingBox,
            by: CGFloat(experimentConfiguration.projectedBoxExpansionFraction)
        )
        let centerInside = ObservationProjection.projectWorldPointToNormalizedImage(
            candidate.position,
            cameraIntrinsics: cameraIntrinsics,
            cameraTransform: cameraTransform,
            imageSize: imageSize
        ).map { box.contains($0) } ?? false

        // 无点集候选只能使用中心投影，不能伪造点级支持比例。
        guard !candidate.points.isEmpty else {
            return (centerInside ? 1 : 0, centerInside)
        }

        var projectedCount = 0
        var insideCount = 0
        for point in candidate.points {
            guard let projected = ObservationProjection.projectWorldPointToNormalizedImage(
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

    func hasRejectedDetectionDepthCandidate(
        near projectedPosition: SIMD3<Float>,
        candidates: [FruitCandidate],
        detection: Observation,
        context: FusionProjectionContext
    ) -> Bool {
        let experimentConfig = experimentConfiguration
        let expandedBox = detection.boundingBox.insetBy(
            dx: -detection.boundingBox.width * CGFloat(experimentConfig.projectedBoxExpansionFraction),
            dy: -detection.boundingBox.height * CGFloat(experimentConfig.projectedBoxExpansionFraction)
        )

        return candidates.contains { candidate in
            guard candidate.sourceCategory == detection.category,
                  candidate.depthSupportRatio != nil else {
                return false
            }

            let distance = simd_distance(projectedPosition, candidate.position)
            let distanceThreshold = max(
                experimentConfig.rejectedDepthCandidateMinimumDistance,
                min(
                    candidate.diameter * experimentConfig.relaxedDistanceMultiplier,
                    experimentConfig.rejectedDepthCandidateMaximumDistance
                )
            )
            if distance <= distanceThreshold {
                return true
            }

            guard let projectedCandidate = ObservationProjection.projectWorldPointToNormalizedImage(
                candidate.position,
                cameraIntrinsics: context.cameraIntrinsics,
                cameraTransform: context.cameraTransform,
                imageSize: context.imageSize
            ) else {
                return false
            }
            return expandedBox.contains(projectedCandidate)
        }
    }
}
