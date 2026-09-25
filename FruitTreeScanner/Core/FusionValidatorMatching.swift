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
        var nearestCandidate: FruitCandidate?
        var bestScore: Float = .infinity

        for candidate in candidates {
            guard let score = matchScore(
                position: position,
                candidate: candidate,
                detection: detection,
                cameraIntrinsics: cameraIntrinsics,
                cameraTransform: cameraTransform,
                imageSize: imageSize
            ) else { continue }

            if score < bestScore {
                bestScore = score
                nearestCandidate = candidate
            }
        }

        return nearestCandidate
    }

    func matchScore(
        position: SIMD3<Float>,
        candidate: FruitCandidate,
        detection: DetectedFruit,
        cameraIntrinsics: matrix_float3x3?,
        cameraTransform: simd_float4x4?,
        imageSize: CGSize?
    ) -> Float? {
        // Keep the same gates used by the single-detection matcher.
        guard candidate.isValidFruit(expectedCategory: detection.category) else { return nil }
        let experimentConfig = FruitScanExperimentConfig.default.fusion
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
        detection: DetectedFruit,
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
            by: CGFloat(FruitScanExperimentConfig.default.fusion.projectedBoxExpansionFraction)
        )
        let centerInside = Self.projectWorldPointToNormalizedImage(
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

/// Maximum-cardinality bipartite matching, then minimum total match score.
/// Only edges that passed the existing depth, size and geometric gates enter
/// this graph. Residual shortest paths can reassign an earlier detection.
enum FusionAssignment {
    struct Option {
        let detectionIndex: Int
        let candidateIndex: Int
        let score: Float
    }

    private struct Edge {
        let destination: Int
        let reverseIndex: Int
        var capacity: Int
        let cost: Int64
    }

    static func match(detectionCount: Int, candidateCount: Int, options: [Option]) -> [Int: Int] {
        guard detectionCount > 0, candidateCount > 0, !options.isEmpty else { return [:] }
        let validOptions = options.filter {
            $0.score.isFinite && (0..<detectionCount).contains($0.detectionIndex)
                && (0..<candidateCount).contains($0.candidateIndex)
        }
        guard !validOptions.isEmpty else { return [:] }
        let activeDetections = Set(validOptions.map(\.detectionIndex)).sorted()
        let activeCandidates = Set(validOptions.map(\.candidateIndex)).sorted()
        let detectionNodes = Dictionary(uniqueKeysWithValues: activeDetections.enumerated().map { ($0.element, $0.offset) })
        let candidateNodes = Dictionary(uniqueKeysWithValues: activeCandidates.enumerated().map { ($0.element, $0.offset) })
        let source = 0
        let firstDetection = 1
        let firstCandidate = firstDetection + activeDetections.count
        let sink = firstCandidate + activeCandidates.count
        let nodeCount = sink + 1
        var graph = [[Edge]](repeating: [], count: nodeCount)

        func addEdge(_ from: Int, _ to: Int, _ cost: Int64) {
            let forwardIndex = graph[from].count
            let reverseIndex = graph[to].count
            graph[from].append(Edge(destination: to, reverseIndex: reverseIndex, capacity: 1, cost: cost))
            graph[to].append(Edge(destination: from, reverseIndex: forwardIndex, capacity: 0, cost: -cost))
        }

        for index in activeDetections.indices { addEdge(source, firstDetection + index, 0) }
        for option in validOptions {
            guard let detectionNode = detectionNodes[option.detectionIndex],
                  let candidateNode = candidateNodes[option.candidateIndex] else { continue }
            // The geometric score is at least -0.08. A common shift keeps
            // forward costs nonnegative without changing same-size optima.
            let shifted = max(0, Double(option.score) + 0.1)
            let cost = Int64((shifted * 1_000_000).rounded())
            addEdge(firstDetection + detectionNode, firstCandidate + candidateNode, cost)
        }
        for index in activeCandidates.indices { addEdge(firstCandidate + index, sink, 0) }

        let infinity = Int64.max / 4
        var potential = [Int64](repeating: 0, count: nodeCount)
        while true {
            if Task.isCancelled { return [:] }
            var distance = [Int64](repeating: infinity, count: nodeCount)
            var previousNode = [Int](repeating: -1, count: nodeCount)
            var previousEdge = [Int](repeating: -1, count: nodeCount)
            var settled = [Bool](repeating: false, count: nodeCount)
            distance[source] = 0

            // The graph is sparse after geometric filtering. A simple node
            // scan avoids a heap and keeps the residual path logic explicit.
            for _ in 0..<nodeCount {
                var current = -1
                for node in 0..<nodeCount where !settled[node] && distance[node] < infinity {
                    if current == -1 || distance[node] < distance[current] { current = node }
                }
                guard current >= 0 else { break }
                settled[current] = true
                for (edgeIndex, edge) in graph[current].enumerated() where edge.capacity > 0 {
                    let reduced = edge.cost + potential[current] - potential[edge.destination]
                    let proposed = distance[current] + reduced
                    if proposed < distance[edge.destination] {
                        distance[edge.destination] = proposed
                        previousNode[edge.destination] = current
                        previousEdge[edge.destination] = edgeIndex
                    }
                }
            }
            guard previousNode[sink] >= 0 else { break }
            for node in 0..<nodeCount where distance[node] < infinity {
                potential[node] += distance[node]
            }
            var node = sink
            while node != source {
                let previous = previousNode[node]
                let edgeIndex = previousEdge[node]
                let reverseIndex = graph[previous][edgeIndex].reverseIndex
                graph[previous][edgeIndex].capacity -= 1
                graph[node][reverseIndex].capacity += 1
                node = previous
            }
        }

        var assignments: [Int: Int] = [:]
        for (denseIndex, detectionIndex) in activeDetections.enumerated() {
            let node = firstDetection + denseIndex
            if let matched = graph[node].first(where: {
                $0.destination >= firstCandidate && $0.destination < sink && $0.capacity == 0
            }) {
                assignments[detectionIndex] = activeCandidates[matched.destination - firstCandidate]
            }
        }
        return assignments
    }
}
