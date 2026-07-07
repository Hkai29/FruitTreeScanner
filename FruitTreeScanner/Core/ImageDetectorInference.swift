// ImageDetectorInference.swift
// Vision/CoreML execution for ImageDetector.

import Foundation
import CoreGraphics
import CoreML
import os
import Vision
@preconcurrency import CoreVideo

extension ImageDetector {
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

}
