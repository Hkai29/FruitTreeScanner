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
        let thresholdPassedCount: Int
        let unmappedObservationCount: Int
        let rawPredictions: [DetectionPredictionDebug]
        let filteredPredictions: [DetectionPredictionDebug]
        let yoloDiagnostics: YOLOOutputDiagnostics
    }

    private struct YOLOPrediction {
        let category: FruitCategory
        let boundingBox: CGRect
        let confidence: Float
    }

    func performDetection(pixelBuffer: CVPixelBuffer, timestamp: TimeInterval, imageSize: CGSize) async -> [DetectedFruit] {
        let sendablePixelBuffer = SendablePixelBuffer(value: pixelBuffer)
        let config = configSnapshot()

        return await withCheckedContinuation { continuation in
            detectionQueue.async { [weak self, sendablePixelBuffer, config] in
                guard let self else {
                    continuation.resume(returning: [])
                    return
                }

                let pixelBuffer = sendablePixelBuffer.value
                let pixelBufferSize = Self.pixelBufferSize(pixelBuffer)
                let inferenceStart = Date()
                self.recordDebugInferenceStarted(
                    frameSize: imageSize,
                    pixelBufferSize: pixelBufferSize,
                    threshold: config.minConfidence
                )

                if let model = self.coreMLModel {
                    self.performCoreMLDetection(
                        pixelBuffer: pixelBuffer,
                        timestamp: timestamp,
                        imageSize: imageSize,
                        inferenceStart: inferenceStart,
                        model: model,
                        config: config,
                        completion: { fruits in
                            continuation.resume(returning: fruits)
                        }
                    )
                } else {
                    self.performVisionClassification(
                        pixelBuffer: pixelBuffer,
                        timestamp: timestamp,
                        imageSize: imageSize,
                        inferenceStart: inferenceStart,
                        config: config,
                        completion: { fruits in
                        continuation.resume(returning: fruits)
                    })
                }
            }
        }
    }

    func performCoreMLDetection(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        imageSize: CGSize,
        inferenceStart: Date,
        model: VNCoreMLModel,
        config: FruitScanConfig,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        let request = VNCoreMLRequest(model: model) { [weak self] request, error in
            guard let self else {
                completion([])
                return
            }

            if let error {
                let reason = error.localizedDescription
                Log.detection.error("CoreML detection failed: \(reason)")
                self.recordDetectionFailure(reason)
                self.recordDebugDetectionResult(
                    startedAt: inferenceStart,
                    rawObservationCount: 0,
                    filteredObservationCount: 0,
                    rawPredictions: [],
                    filteredPredictions: [],
                    threshold: config.minConfidence,
                    errorMessage: reason
                )
                self.captureDetectionFailureSample(note: reason)
                completion([])
                return
            }

            let observations = request.results ?? []
            let objectObservations = observations.compactMap { $0 as? VNRecognizedObjectObservation }
            if !objectObservations.isEmpty {
                let confidenceFilteredCount = objectObservations.filter { $0.confidence < config.minConfidence }.count
                let filteredObservationCount = objectObservations.count - confidenceFilteredCount
                let rawPredictions = objectObservations.compactMap(Self.debugPrediction)
                let filteredPredictions = objectObservations
                    .filter { $0.confidence >= config.minConfidence }
                    .compactMap(Self.debugPrediction)
                let detectedFruits = self.mapObjectObservationsToFruits(
                    observations: objectObservations,
                    timestamp: timestamp,
                    config: config
                )
                self.recordCoreMLDetection(
                    observationCount: objectObservations.count,
                    confidenceFilteredCount: confidenceFilteredCount,
                    unmappedObservationCount: max(objectObservations.count - detectedFruits.count - confidenceFilteredCount, 0),
                    mappedFruitCount: detectedFruits.count
                )
                self.recordDebugDetectionResult(
                    startedAt: inferenceStart,
                    rawObservationCount: objectObservations.count,
                    filteredObservationCount: filteredObservationCount,
                    rawPredictions: rawPredictions,
                    filteredPredictions: filteredPredictions,
                    threshold: config.minConfidence
                )
                completion(detectedFruits)
                return
            }

            let featureObservations = observations.compactMap { $0 as? VNCoreMLFeatureValueObservation }
            guard let multiArray = featureObservations.compactMap({ $0.featureValue.multiArrayValue }).first else {
                let reason = "CoreML 输出格式不支持：未返回目标框或 YOLO MultiArray"
                Log.detection.error("\(reason)")
                self.recordDetectionFailure(reason)
                self.recordDebugDetectionResult(
                    startedAt: inferenceStart,
                    rawObservationCount: 0,
                    filteredObservationCount: 0,
                    rawPredictions: [],
                    filteredPredictions: [],
                    threshold: config.minConfidence,
                    errorMessage: reason
                )
                self.captureDetectionFailureSample(note: reason)
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
            self.recordDebugDetectionResult(
                startedAt: inferenceStart,
                rawObservationCount: parsed.modelCandidateCount,
                filteredObservationCount: parsed.thresholdPassedCount,
                rawPredictions: parsed.rawPredictions,
                filteredPredictions: parsed.filteredPredictions,
                threshold: config.minConfidence,
                yoloOutputDiagnostics: parsed.yoloDiagnostics
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
            recordDebugDetectionResult(
                startedAt: inferenceStart,
                rawObservationCount: 0,
                filteredObservationCount: 0,
                rawPredictions: [],
                filteredPredictions: [],
                threshold: config.minConfidence,
                errorMessage: error.localizedDescription
            )
            captureDetectionFailureSample(note: error.localizedDescription)
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

            if let mapping = categoryMapper.categoryMapping(
                for: topLabel.identifier,
                selectedFruitType: config.selectedFruitType
            ) {
                if mapping.usedGenericFallback, let debugWarning = mapping.debugWarning {
                    recordDebugWarning(debugWarning)
                }
                detectedFruits.append(DetectedFruit(
                    category: mapping.category,
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
        imageSize: CGSize,
        inferenceStart: Date,
        config: FruitScanConfig,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        let reason = "CoreML model not loaded; fallback has no 2D bounding boxes"
        recordFallbackFrame(reason: modelStatus.hudDetail)
        recordDebugDetectionResult(
            startedAt: inferenceStart,
            rawObservationCount: 0,
            filteredObservationCount: 0,
            rawPredictions: [],
            filteredPredictions: [],
            threshold: config.minConfidence,
            errorMessage: reason
        )
        captureDetectionFailureSample(note: reason)
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
        var diagnostics = YOLOOutputDiagnostics(
            outputShape: dimensions,
            lowConfidenceFloor: lowConfidenceFloor,
            coordinateScaleGuess: 1
        )
        guard dimensions.count == 3 else {
            return emptyYOLOParsingResult(diagnostics: diagnostics)
        }

        let channelAxis: Int
        if dimensions[1] >= 5 {
            channelAxis = 1
        } else if dimensions[2] >= 5 {
            channelAxis = 2
        } else {
            return emptyYOLOParsingResult(diagnostics: diagnostics)
        }

        let anchorAxis = channelAxis == 1 ? 2 : 1
        let channelCount = dimensions[channelAxis]
        let anchorCount = dimensions[anchorAxis]
        let classCount = channelCount - 4
        diagnostics.channelAxis = channelAxis
        diagnostics.anchorAxis = anchorAxis
        diagnostics.classCount = max(classCount, 0)
        diagnostics.anchorCount = anchorCount
        guard classCount > 0, anchorCount > 0 else {
            return emptyYOLOParsingResult(diagnostics: diagnostics)
        }

        var predictions: [YOLOPrediction] = []
        var rawDebugPredictions: [DetectionPredictionDebug] = []
        var filteredDebugPredictions: [DetectionPredictionDebug] = []
        predictions.reserveCapacity(64)
        var modelCandidateCount = 0
        var confidenceFilteredCount = 0
        var thresholdPassedCount = 0
        var unmappedObservationCount = 0
        var invalidBoundingBoxCount = 0

        for anchorIndex in 0..<anchorCount {
            let (classIndex, confidence) = bestClassScore(
                in: multiArray,
                classCount: classCount,
                anchorIndex: anchorIndex,
                channelAxis: channelAxis
            )

            guard confidence >= lowConfidenceFloor else { continue }
            modelCandidateCount += 1

            let centerX = value(in: multiArray, channel: 0, anchor: anchorIndex, channelAxis: channelAxis)
            let centerY = value(in: multiArray, channel: 1, anchor: anchorIndex, channelAxis: channelAxis)
            let width = value(in: multiArray, channel: 2, anchor: anchorIndex, channelAxis: channelAxis)
            let height = value(in: multiArray, channel: 3, anchor: anchorIndex, channelAxis: channelAxis)

            if diagnostics.sampleRawBoxes.count < 5 {
                diagnostics.sampleRawBoxes.append(rawBoxSample(
                    centerX: centerX,
                    centerY: centerY,
                    width: width,
                    height: height,
                    confidence: confidence
                ))
            }
            diagnostics.coordinateScaleGuess = max(
                diagnostics.coordinateScaleGuess,
                coordinateScaleGuess(
                    centerX: centerX,
                    centerY: centerY,
                    width: width,
                    height: height
                )
            )

            let boundingBox = makeVisionBoundingBox(
                centerX: centerX,
                centerY: centerY,
                width: width,
                height: height
            )

            if let boundingBox {
                rawDebugPredictions.append(DetectionPredictionDebug(
                    label: debugLabel(forClassIndex: classIndex),
                    confidence: confidence,
                    boundingBox: boundingBox
                ))
            } else {
                invalidBoundingBoxCount += 1
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
                label: debugLabel(forClassIndex: classIndex),
                confidence: confidence,
                boundingBox: boundingBox
            )
            filteredDebugPredictions.append(debugPrediction)

            guard let category = FruitCategory.fromCustomModel(classIndex) else {
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

        diagnostics.modelCandidateCount = modelCandidateCount
        diagnostics.invalidBoundingBoxCount = invalidBoundingBoxCount
        return YOLOParsingResult(
            fruits: fruits,
            modelCandidateCount: modelCandidateCount,
            confidenceFilteredCount: confidenceFilteredCount,
            thresholdPassedCount: thresholdPassedCount,
            unmappedObservationCount: unmappedObservationCount,
            rawPredictions: rawDebugPredictions,
            filteredPredictions: filteredDebugPredictions,
            yoloDiagnostics: diagnostics
        )
    }

    private func recordDebugDetectionResult(
        startedAt: Date,
        rawObservationCount: Int,
        filteredObservationCount: Int,
        rawPredictions: [DetectionPredictionDebug],
        filteredPredictions: [DetectionPredictionDebug],
        threshold: Float,
        errorMessage: String? = nil,
        yoloOutputDiagnostics: YOLOOutputDiagnostics? = nil
    ) {
        recordDebugInferenceCompleted(
            elapsedMs: Date().timeIntervalSince(startedAt) * 1000,
            rawObservationCount: rawObservationCount,
            filteredObservationCount: filteredObservationCount,
            rawPredictions: rawPredictions,
            filteredPredictions: filteredPredictions,
            threshold: threshold,
            errorMessage: errorMessage,
            yoloOutputDiagnostics: yoloOutputDiagnostics
        )

        if errorMessage == nil, rawObservationCount == 0 {
            captureDetectionFailureSample(note: "No raw detections")
        } else if errorMessage == nil, rawObservationCount > 0, filteredObservationCount == 0 {
            captureDetectionFailureSample(note: "Raw detections filtered by confidence threshold")
        }
    }

    private static func pixelBufferSize(_ pixelBuffer: CVPixelBuffer) -> CGSize {
        CGSize(
            width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        )
    }

    private static func debugPrediction(
        from observation: VNRecognizedObjectObservation
    ) -> DetectionPredictionDebug? {
        guard let topLabel = observation.labels.first else { return nil }
        return DetectionPredictionDebug(
            label: topLabel.identifier,
            confidence: topLabel.confidence,
            boundingBox: observation.boundingBox
        )
    }

    private static func debugLabel(forClassIndex classIndex: Int) -> String {
        FruitCategory.fromCustomModel(classIndex)?.displayName ?? "class \(classIndex)"
    }

    private static func emptyYOLOParsingResult(diagnostics: YOLOOutputDiagnostics) -> YOLOParsingResult {
        YOLOParsingResult(
            fruits: [],
            modelCandidateCount: 0,
            confidenceFilteredCount: 0,
            thresholdPassedCount: 0,
            unmappedObservationCount: 0,
            rawPredictions: [],
            filteredPredictions: [],
            yoloDiagnostics: diagnostics
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

        let coordinateScale = coordinateScaleGuess(
            centerX: centerX,
            centerY: centerY,
            width: width,
            height: height
        )
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

    private static func coordinateScaleGuess(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float
    ) -> Float {
        max(abs(centerX), abs(centerY), abs(width), abs(height)) > 2 ? 320 : 1
    }

    private static func rawBoxSample(
        centerX: Float,
        centerY: Float,
        width: Float,
        height: Float,
        confidence: Float
    ) -> String {
        String(
            format: "cx=%.3f cy=%.3f w=%.3f h=%.3f conf=%.3f",
            centerX,
            centerY,
            width,
            height,
            confidence
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
