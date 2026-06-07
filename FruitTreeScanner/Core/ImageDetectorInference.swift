// ImageDetectorInference.swift
// Vision/CoreML execution for ImageDetector.

import Foundation
import CoreGraphics
import CoreML
import os
import Vision
@preconcurrency import CoreVideo

extension ImageDetector {
    struct YOLOParsingResult {
        let fruits: [DetectedFruit]
        let modelCandidateCount: Int
        let confidenceFilteredCount: Int
        let unmappedObservationCount: Int
    }

    private struct YOLOPrediction {
        let category: FruitCategory
        let boundingBox: CGRect
        let confidence: Float
    }

    func performDetection(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval) async -> [DetectedFruit] {
        let sendablePixelBuffer = SendablePixelBuffer(value: pixelBuffer)
        let config = configSnapshot()

        return await withCheckedContinuation { continuation in
            detectionQueue.async { [weak self, sendablePixelBuffer, config] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }

                let pixelBuffer = sendablePixelBuffer.value
                if let model = self.coreMLModel {
                    self.performCoreMLDetection(
                        pixelBuffer: pixelBuffer,
                        timestamp: timestamp,
                        model: model,
                        config: config,
                        completion: { fruits in
                            continuation.resume(returning: fruits)
                        }
                    )
                } else {
                    self.performVisionClassification(pixelBuffer: pixelBuffer, timestamp: timestamp, completion: { fruits in
                        continuation.resume(returning: fruits)
                    })
                }
            }
        }
    }

    func performCoreMLDetection(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        model: VNCoreMLModel,
        config: FruitScanConfig,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self, error == nil else {
                let reason = error?.localizedDescription ?? "CoreML 没有返回 observation"
                Log.detection.error("CoreML detection failed: \(reason)")
                self?.recordDetectionFailure(reason)
                completion([])
                return
            }

            let observations = request.results ?? []
            let objectObservations = observations.compactMap { $0 as? VNRecognizedObjectObservation }
            if !objectObservations.isEmpty {
                let detectedFruits = self.mapObjectObservationsToFruits(
                    observations: objectObservations,
                    timestamp: timestamp,
                    config: config
                )
                let confidenceFilteredCount = objectObservations.filter { $0.confidence < config.minConfidence }.count
                self.recordCoreMLDetection(
                    observationCount: objectObservations.count,
                    confidenceFilteredCount: confidenceFilteredCount,
                    unmappedObservationCount: max(objectObservations.count - detectedFruits.count - confidenceFilteredCount, 0),
                    mappedFruitCount: detectedFruits.count
                )
                completion(detectedFruits)
                return
            }

            let featureObservations = observations.compactMap { $0 as? VNCoreMLFeatureValueObservation }
            guard let multiArray = featureObservations.compactMap({ $0.featureValue.multiArrayValue }).first else {
                let reason = "CoreML 输出格式不支持：未返回目标框或 YOLO MultiArray"
                Log.detection.error("\(reason)")
                self.recordDetectionFailure(reason)
                completion([])
                return
            }

            let parsed = Self.parseYOLOMultiArray(
                multiArray,
                timestamp: timestamp,
                config: config
            )
            self.recordCoreMLDetection(
                observationCount: parsed.modelCandidateCount,
                confidenceFilteredCount: parsed.confidenceFilteredCount,
                unmappedObservationCount: parsed.unmappedObservationCount,
                mappedFruitCount: parsed.fruits.count
            )
            completion(parsed.fruits)
        }

        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            Log.detection.error("VNImageRequestHandler failed: \(error.localizedDescription)")
            recordDetectionFailure(error.localizedDescription)
            completion([])
        }
    }

    func mapObjectObservationsToFruits(
        observations: [VNRecognizedObjectObservation],
        timestamp: TimeInterval,
        config: FruitScanConfig
    ) -> [DetectedFruit] {
        var detectedFruits: [DetectedFruit] = []

        for observation in observations {
            guard observation.confidence >= config.minConfidence else {
                continue
            }

            guard let topLabel = observation.labels.first else {
                continue
            }

            if let fruitCategory = categoryMapper.category(for: topLabel.identifier) {
                detectedFruits.append(DetectedFruit(
                    category: fruitCategory,
                    boundingBox: observation.boundingBox,
                    confidence: topLabel.confidence,
                    timestamp: timestamp
                ))
            }
        }

        return detectedFruits
    }

    func performVisionClassification(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        recordFallbackFrame(reason: modelStatus.hudDetail)
        completion([])
    }

    static func parseYOLOMultiArray(
        _ multiArray: MLMultiArray,
        timestamp: TimeInterval,
        config: FruitScanConfig,
        lowConfidenceFloor: Float = 0.05,
        nmsThreshold: Float = 0.45
    ) -> YOLOParsingResult {
        let dimensions = multiArray.shape.map { $0.intValue }
        guard dimensions.count == 3 else {
            return YOLOParsingResult(
                fruits: [],
                modelCandidateCount: 0,
                confidenceFilteredCount: 0,
                unmappedObservationCount: 0
            )
        }

        let channelAxis: Int
        if dimensions[1] >= 5 {
            channelAxis = 1
        } else if dimensions[2] >= 5 {
            channelAxis = 2
        } else {
            return YOLOParsingResult(
                fruits: [],
                modelCandidateCount: 0,
                confidenceFilteredCount: 0,
                unmappedObservationCount: 0
            )
        }

        let anchorAxis = channelAxis == 1 ? 2 : 1
        let channelCount = dimensions[channelAxis]
        let anchorCount = dimensions[anchorAxis]
        let classCount = channelCount - 4
        guard classCount > 0, anchorCount > 0 else {
            return YOLOParsingResult(
                fruits: [],
                modelCandidateCount: 0,
                confidenceFilteredCount: 0,
                unmappedObservationCount: 0
            )
        }

        var predictions: [YOLOPrediction] = []
        predictions.reserveCapacity(64)
        var modelCandidateCount = 0
        var confidenceFilteredCount = 0
        var unmappedObservationCount = 0

        for anchorIndex in 0..<anchorCount {
            let (classIndex, confidence) = bestClassScore(
                in: multiArray,
                classCount: classCount,
                anchorIndex: anchorIndex,
                channelAxis: channelAxis
            )

            guard confidence >= lowConfidenceFloor else { continue }
            modelCandidateCount += 1

            guard confidence >= config.minConfidence else {
                confidenceFilteredCount += 1
                continue
            }

            guard let category = FruitCategory.fromCustomModel(classIndex) else {
                unmappedObservationCount += 1
                continue
            }

            let centerX = value(in: multiArray, channel: 0, anchor: anchorIndex, channelAxis: channelAxis)
            let centerY = value(in: multiArray, channel: 1, anchor: anchorIndex, channelAxis: channelAxis)
            let width = value(in: multiArray, channel: 2, anchor: anchorIndex, channelAxis: channelAxis)
            let height = value(in: multiArray, channel: 3, anchor: anchorIndex, channelAxis: channelAxis)

            guard let boundingBox = makeVisionBoundingBox(
                centerX: centerX,
                centerY: centerY,
                width: width,
                height: height
            ) else {
                unmappedObservationCount += 1
                continue
            }

            predictions.append(YOLOPrediction(
                category: category,
                boundingBox: boundingBox,
                confidence: confidence
            ))
        }

        let fruits = nonMaximumSuppression(
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
            unmappedObservationCount: unmappedObservationCount
        )
    }

    private static func bestClassScore(
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

    private static func value(
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

    private static func normalizedConfidence(_ rawScore: Float) -> Float {
        guard rawScore.isFinite else { return 0 }
        if rawScore >= 0, rawScore <= 1 {
            return rawScore
        }
        return 1 / (1 + exp(-rawScore))
    }

    private static func makeVisionBoundingBox(
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

    private static func nonMaximumSuppression(
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
}
