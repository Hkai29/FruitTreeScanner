// ImageDetectorYOLOParser.swift
// YOLO MultiArray parsing for ImageDetector.

import Foundation
import CoreGraphics
import CoreML

extension ImageDetector {
    struct YOLOParsingResult {
        let fruits: [DetectedFruit]
        let modelCandidateCount: Int
        let confidenceFilteredCount: Int
        let thresholdPassedCount: Int
        let unmappedObservationCount: Int
        let mappedCategories: [String]
        let unmappedLabels: [String]
        let rawPredictions: [DetectionPredictionDebug]
        let filteredPredictions: [DetectionPredictionDebug]
        let labelMappingFailureReason: String?
    }

    static func parseYOLOMultiArray(
        _ multiArray: MLMultiArray,
        timestamp: TimeInterval,
        config: FruitScanConfig,
        labelDiagnostics: ModelLabelCompatibilityDiagnostics,
        lowConfidenceFloor: Float = 0.05,
        nmsThreshold: Float = 0.45
    ) -> YOLOParsingResult {
        let dimensions = multiArray.shape.map { $0.intValue }
        guard dimensions.count == 3 else {
            return YOLOParserSupport.emptyResult()
        }

        let channelAxis: Int
        if dimensions[1] >= 5 {
            channelAxis = 1
        } else if dimensions[2] >= 5 {
            channelAxis = 2
        } else {
            return YOLOParserSupport.emptyResult()
        }

        let anchorAxis = channelAxis == 1 ? 2 : 1
        let channelCount = dimensions[channelAxis]
        let anchorCount = dimensions[anchorAxis]
        let classCount = channelCount - 4
        guard classCount > 0, anchorCount > 0 else {
            return YOLOParserSupport.emptyResult()
        }

        let runtimeLabels = labelDiagnostics.runtimeModelLabels
        let usesLegacyFixedOrder = labelDiagnostics.legacyFixedOrderContractConfirmed
        if labelDiagnostics.runtimeModelLabelsAvailable {
            guard runtimeLabels.count == classCount else {
                return YOLOParserSupport.emptyResult(
                    labelMappingFailureReason: "YOLO label contract rejected: runtime label count \(runtimeLabels.count) does not match output class count \(classCount)."
                )
            }
        } else {
            guard usesLegacyFixedOrder, classCount == FruitCategory.customModelLabelOrder.count else {
                return YOLOParserSupport.emptyResult(
                    labelMappingFailureReason: "YOLO label contract rejected: runtime labels are unavailable and no confirmed legacy 26-class contract exists."
                )
            }
        }

        var predictions: [YOLOPrediction] = []
        var rawDebugPredictions: [DetectionPredictionDebug] = []
        var filteredDebugPredictions: [DetectionPredictionDebug] = []
        var mappedCategories: [String] = []
        var unmappedLabels: [String] = []
        predictions.reserveCapacity(64)
        var modelCandidateCount = 0
        var confidenceFilteredCount = 0
        var thresholdPassedCount = 0
        var unmappedObservationCount = 0

        for anchorIndex in 0..<anchorCount {
            let (classIndex, confidence) = YOLOParserSupport.bestClassScore(
                in: multiArray,
                classCount: classCount,
                anchorIndex: anchorIndex,
                channelAxis: channelAxis
            )

            guard confidence >= lowConfidenceFloor else { continue }
            modelCandidateCount += 1

            let centerX = YOLOParserSupport.value(in: multiArray, channel: 0, anchor: anchorIndex, channelAxis: channelAxis)
            let centerY = YOLOParserSupport.value(in: multiArray, channel: 1, anchor: anchorIndex, channelAxis: channelAxis)
            let width = YOLOParserSupport.value(in: multiArray, channel: 2, anchor: anchorIndex, channelAxis: channelAxis)
            let height = YOLOParserSupport.value(in: multiArray, channel: 3, anchor: anchorIndex, channelAxis: channelAxis)

            let boundingBox = YOLOParserSupport.makeVisionBoundingBox(
                centerX: centerX,
                centerY: centerY,
                width: width,
                height: height
            )

            if let boundingBox {
                rawDebugPredictions.append(DetectionPredictionDebug(
                    label: YOLOParserSupport.debugLabel(
                        forClassIndex: classIndex,
                        runtimeLabels: runtimeLabels,
                        usesLegacyFixedOrder: usesLegacyFixedOrder
                    ),
                    confidence: confidence,
                    boundingBox: boundingBox
                ))
            }

            guard confidence >= config.minConfidence else {
                confidenceFilteredCount += 1
                continue
            }
            thresholdPassedCount += 1

            guard let boundingBox else {
                unmappedObservationCount += 1
                continue
            }

            let debugPrediction = DetectionPredictionDebug(
                label: YOLOParserSupport.debugLabel(
                    forClassIndex: classIndex,
                    runtimeLabels: runtimeLabels,
                    usesLegacyFixedOrder: usesLegacyFixedOrder
                ),
                confidence: confidence,
                boundingBox: boundingBox
            )
            filteredDebugPredictions.append(debugPrediction)

            let category: FruitCategory?
            if labelDiagnostics.usesRuntimeLabelMapping {
                category = labelDiagnostics.runtimeLabel(forClassIndex: classIndex)
                    .flatMap { FruitCategoryMapper.standard.category(forRuntimeModelLabel: $0) }
            } else {
                category = FruitCategory.fromCustomModel(classIndex)
            }

            guard let category else {
                unmappedObservationCount += 1
                unmappedLabels.append(debugPrediction.label)
                continue
            }

            mappedCategories.append(category.rawValue)
            predictions.append(YOLOPrediction(
                category: category,
                boundingBox: boundingBox,
                confidence: confidence
            ))
        }

        let fruits = YOLOParserSupport.nonMaximumSuppression(
            predictions,
            threshold: nmsThreshold
        ).map {
            DetectedFruit(
                category: $0.category,
                boundingBox: $0.boundingBox,
                confidence: $0.confidence,
                timestamp: timestamp
            )
        }

        return YOLOParsingResult(
            fruits: fruits,
            modelCandidateCount: modelCandidateCount,
            confidenceFilteredCount: confidenceFilteredCount,
            thresholdPassedCount: thresholdPassedCount,
            unmappedObservationCount: unmappedObservationCount,
            mappedCategories: mappedCategories,
            unmappedLabels: unmappedLabels,
            rawPredictions: rawDebugPredictions,
            filteredPredictions: filteredDebugPredictions,
            labelMappingFailureReason: nil
        )
    }
}
