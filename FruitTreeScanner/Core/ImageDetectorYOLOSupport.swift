// ImageDetectorYOLOSupport.swift
// Support types and post-processing for YOLO MultiArray parsing.

import Foundation
import CoreGraphics
import CoreML

struct YOLOPrediction {
    let category: FruitCategory
    let boundingBox: CGRect
    let confidence: Float
}

enum YOLOParserSupport {
    static func emptyResult(labelMappingFailureReason: String? = nil) -> ImageDetector.YOLOParsingResult {
        ImageDetector.YOLOParsingResult(
            fruits: [],
            modelCandidateCount: 0,
            confidenceFilteredCount: 0,
            thresholdPassedCount: 0,
            unmappedObservationCount: 0,
            mappedCategories: [],
            unmappedLabels: [],
            rawPredictions: [],
            filteredPredictions: [],
            labelMappingFailureReason: labelMappingFailureReason
        )
    }

    static func debugLabel(
        forClassIndex classIndex: Int,
        runtimeLabels: [String] = [],
        usesLegacyFixedOrder: Bool = false
    ) -> String {
        if runtimeLabels.indices.contains(classIndex) {
            return runtimeLabels[classIndex]
        }
        if !runtimeLabels.isEmpty {
            return "class \(classIndex)"
        }
        guard usesLegacyFixedOrder else { return "class \(classIndex)" }
        return FruitCategory.fromCustomModel(classIndex)?.displayName ?? "class \(classIndex)"
    }

    static func bestClassScore(
        in multiArray: MLMultiArray,
        classCount: Int,
        anchorIndex: Int,
        channelAxis: Int
    ) -> (classIndex: Int, confidence: Float) {
        var bestIndex = 0
        var bestScore: Float = -.infinity
        for classIndex in 0..<classCount {
            let rawScore = value(
                in: multiArray,
                channel: classIndex + 4,
                anchor: anchorIndex,
                channelAxis: channelAxis
            )
            let score = normalizedConfidence(rawScore)
            if score > bestScore {
                bestScore = score
                bestIndex = classIndex
            }
        }
        return (bestIndex, bestScore.isFinite ? bestScore : 0)
    }

    static func value(
        in multiArray: MLMultiArray,
        channel: Int,
        anchor: Int,
        channelAxis: Int
    ) -> Float {
        let indices: [NSNumber]
        if channelAxis == 1 {
            indices = [NSNumber(value: 0), NSNumber(value: channel), NSNumber(value: anchor)]
        } else {
            indices = [NSNumber(value: 0), NSNumber(value: anchor), NSNumber(value: channel)]
        }
        return multiArray[indices].floatValue
    }

    static func makeVisionBoundingBox(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float
    ) -> CGRect? {
        guard centerX.isFinite, centerY.isFinite, width.isFinite, height.isFinite,
              width > 0, height > 0 else { return nil }

        let coordinateScale: Float = max(abs(centerX), abs(centerY), abs(width), abs(height)) > 2 ? 320 : 1
        let normalizedCenterX = centerX / coordinateScale
        let normalizedCenterY = centerY / coordinateScale
        let normalizedWidth = width / coordinateScale
        let normalizedHeight = height / coordinateScale

        let minX = max(0, min(1, normalizedCenterX - normalizedWidth / 2))
        let maxX = max(0, min(1, normalizedCenterX + normalizedWidth / 2))
        let minYTopOrigin = max(0, min(1, normalizedCenterY - normalizedHeight / 2))
        let maxYTopOrigin = max(0, min(1, normalizedCenterY + normalizedHeight / 2))

        let clampedWidth = maxX - minX
        let clampedHeight = maxYTopOrigin - minYTopOrigin
        guard clampedWidth > 0.001, clampedHeight > 0.001 else { return nil }

        return CGRect(
            x: CGFloat(minX),
            y: CGFloat(1 - maxYTopOrigin),
            width: CGFloat(clampedWidth),
            height: CGFloat(clampedHeight)
        )
    }

    static func nonMaximumSuppression(
        _ predictions: [YOLOPrediction],
        threshold: Float
    ) -> [YOLOPrediction] {
        let sorted = predictions.sorted { $0.confidence > $1.confidence }
        var kept: [YOLOPrediction] = []
        kept.reserveCapacity(min(sorted.count, 64))

        for prediction in sorted {
            let overlapsExisting = kept.contains { keptPrediction in
                keptPrediction.category == prediction.category &&
                DetectionDeduplicator.computeIoU(keptPrediction.boundingBox, prediction.boundingBox) >= threshold
            }
            if !overlapsExisting {
                kept.append(prediction)
            }
        }

        return kept
    }

    private static func normalizedConfidence(_ rawScore: Float) -> Float {
        guard rawScore.isFinite else { return 0 }
        if rawScore >= 0, rawScore <= 1 {
            return rawScore
        }
        return 1 / (1 + exp(-rawScore))
    }
}
