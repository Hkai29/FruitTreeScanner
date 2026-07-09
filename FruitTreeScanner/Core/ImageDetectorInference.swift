// ImageDetectorInference.swift
// Vision/CoreML execution for ImageDetector.

import Foundation
import CoreGraphics
import CoreML
import os
@preconcurrency import Vision
@preconcurrency import CoreVideo

struct ImageDetectorInference: Sendable {
    func performDetection(
        detector: ImageDetector,
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        imageSize: CGSize,
        queue: DispatchQueue
    ) async -> [DetectedFruit] {
        let sendablePixelBuffer = ImageDetector.SendablePixelBuffer(value: pixelBuffer)
        let config = detector.configSnapshot()
        let model = detector.coreMLModel

        return await withCheckedContinuation { continuation in
            queue.async { [sendablePixelBuffer, config, weak detector] in
                guard let detector else {
                    continuation.resume(returning: [])
                    return
                }

                let pixelBuffer = sendablePixelBuffer.value
                let pixelBufferSize = ImageDetector.pixelBufferSize(pixelBuffer)
                let inferenceStart = Date()
                detector.recordDebugInferenceStarted(
                    frameSize: imageSize,
                    pixelBufferSize: pixelBufferSize,
                    threshold: config.minConfidence
                )

                if let model {
                    self.performCoreMLDetection(
                        detector: detector,
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
                        detector: detector,
                        inferenceStart: inferenceStart,
                        config: config,
                        completion: { fruits in
                            continuation.resume(returning: fruits)
                        }
                    )
                }
            }
        }
    }

    private func performCoreMLDetection(
        detector: ImageDetector,
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        imageSize: CGSize,
        inferenceStart: Date,
        model: VNCoreMLModel,
        config: FruitScanConfig,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        let request = VNCoreMLRequest(model: model) { [weak detector] request, error in
            guard let detector else {
                completion([])
                return
            }

            if let error {
                let reason = error.localizedDescription
                Log.detection.error("CoreML detection failed: \(reason)")
                detector.recordDetectionFailure(reason)
                detector.recordDebugDetectionResult(
                    startedAt: inferenceStart,
                    rawObservationCount: 0,
                    filteredObservationCount: 0,
                    rawPredictions: [],
                    filteredPredictions: [],
                    threshold: config.minConfidence,
                    errorMessage: reason
                )
                detector.captureDetectionFailureSample(note: reason)
                completion([])
                return
            }

            let observations = request.results ?? []
            let objectObservations = observations.compactMap { $0 as? VNRecognizedObjectObservation }
            if !objectObservations.isEmpty {
                let confidenceFilteredCount = objectObservations.filter { $0.confidence < config.minConfidence }.count
                let filteredObservationCount = objectObservations.count - confidenceFilteredCount
                let rawPredictions = objectObservations.compactMap(ImageDetector.debugPrediction)
                let filteredPredictions = objectObservations
                    .filter { $0.confidence >= config.minConfidence }
                    .compactMap(ImageDetector.debugPrediction)
                let detectedFruits = mapObjectObservationsToFruits(
                    observations: objectObservations,
                    timestamp: timestamp,
                    config: config,
                    categoryMapper: detector.categoryMapper
                )
                let highConfidenceLabels = objectObservations
                    .filter { $0.confidence >= config.minConfidence }
                    .compactMap { $0.labels.first?.identifier }
                let unmappedLabels = highConfidenceLabels.filter {
                    detector.categoryMapper.category(for: $0) == nil
                }
                detector.recordCoreMLDetection(
                    observationCount: objectObservations.count,
                    confidenceFilteredCount: confidenceFilteredCount,
                    unmappedObservationCount: max(objectObservations.count - detectedFruits.count - confidenceFilteredCount, 0),
                    mappedFruitCount: detectedFruits.count,
                    rawDetectedLabels: rawPredictions.map(\.label),
                    mappedCategories: detectedFruits.map(\.category.rawValue),
                    unmappedLabels: unmappedLabels
                )
                detector.recordDebugDetectionResult(
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
                detector.recordDetectionFailure(reason)
                detector.recordDebugDetectionResult(
                    startedAt: inferenceStart,
                    rawObservationCount: 0,
                    filteredObservationCount: 0,
                    rawPredictions: [],
                    filteredPredictions: [],
                    threshold: config.minConfidence,
                    errorMessage: reason
                )
                detector.captureDetectionFailureSample(note: reason)
                completion([])
                return
            }

            let parsed = ImageDetector.parseYOLOMultiArray(
                multiArray,
                timestamp: timestamp,
                config: config
            )
            detector.recordCoreMLDetection(
                observationCount: parsed.modelCandidateCount,
                confidenceFilteredCount: parsed.confidenceFilteredCount,
                unmappedObservationCount: parsed.unmappedObservationCount,
                mappedFruitCount: parsed.fruits.count,
                rawDetectedLabels: parsed.rawPredictions.map(\.label),
                mappedCategories: parsed.mappedCategories,
                unmappedLabels: parsed.unmappedLabels
            )
            detector.recordDebugDetectionResult(
                startedAt: inferenceStart,
                rawObservationCount: parsed.modelCandidateCount,
                filteredObservationCount: parsed.thresholdPassedCount,
                rawPredictions: parsed.rawPredictions,
                filteredPredictions: parsed.filteredPredictions,
                threshold: config.minConfidence
            )
            completion(parsed.fruits)
        }

        request.imageCropAndScaleOption = .scaleFill

        let handler = VNImageRequestHandler(cvPixelBuffer: pixelBuffer, options: [:])

        do {
            try handler.perform([request])
        } catch {
            Log.detection.error("VNImageRequestHandler failed: \(error.localizedDescription)")
            detector.recordDetectionFailure(error.localizedDescription)
            detector.recordDebugDetectionResult(
                startedAt: inferenceStart,
                rawObservationCount: 0,
                filteredObservationCount: 0,
                rawPredictions: [],
                filteredPredictions: [],
                threshold: config.minConfidence,
                errorMessage: error.localizedDescription
            )
            detector.captureDetectionFailureSample(note: error.localizedDescription)
            completion([])
        }
    }

    private func mapObjectObservationsToFruits(
        observations: [VNRecognizedObjectObservation],
        timestamp: TimeInterval,
        config: FruitScanConfig,
        categoryMapper: FruitCategoryMapper
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

    private func performVisionClassification(
        detector: ImageDetector,
        inferenceStart: Date,
        config: FruitScanConfig,
        completion: @escaping ([DetectedFruit]) -> Void
    ) {
        let reason = "CoreML model not loaded; fallback has no 2D bounding boxes"
        detector.recordFallbackFrame(reason: detector.modelStatus.hudDetail)
        detector.recordDebugDetectionResult(
            startedAt: inferenceStart,
            rawObservationCount: 0,
            filteredObservationCount: 0,
            rawPredictions: [],
            filteredPredictions: [],
            threshold: config.minConfidence,
            errorMessage: reason
        )
        detector.captureDetectionFailureSample(note: reason)
        completion([])
    }
}

extension ImageDetector {
    func performDetection(
        pixelBuffer: CVPixelBuffer,
        timestamp: TimeInterval,
        imageSize: CGSize
    ) async -> [DetectedFruit] {
        await ImageDetectorInference().performDetection(
            detector: self,
            pixelBuffer: pixelBuffer,
            timestamp: timestamp,
            imageSize: imageSize,
            queue: detectionQueue
        )
    }
}
