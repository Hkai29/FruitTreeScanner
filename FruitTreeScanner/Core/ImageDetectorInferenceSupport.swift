// ImageDetectorInferenceSupport.swift
// Small helpers used by Vision/CoreML inference.

import Foundation
import CoreGraphics
import Vision
@preconcurrency import CoreVideo

extension ImageDetector {
    func recordDebugDetectionResult(
        startedAt: Date,
        rawObservationCount: Int,
        filteredObservationCount: Int,
        rawPredictions: [DetectionPredictionDebug],
        filteredPredictions: [DetectionPredictionDebug],
        threshold: Float,
        errorMessage: String? = nil
    ) {
        recordDebugInferenceCompleted(
            elapsedMs: Date().timeIntervalSince(startedAt) * 1000,
            rawObservationCount: rawObservationCount,
            filteredObservationCount: filteredObservationCount,
            rawPredictions: rawPredictions,
            filteredPredictions: filteredPredictions,
            threshold: threshold,
            errorMessage: errorMessage
        )

        if errorMessage == nil, rawObservationCount == 0 {
            captureDetectionFailureSample(note: "No raw detections")
        } else if errorMessage == nil, rawObservationCount > 0, filteredObservationCount == 0 {
            captureDetectionFailureSample(note: "Raw detections filtered by confidence threshold")
        }
    }

    static func pixelBufferSize(_ pixelBuffer: CVPixelBuffer) -> CGSize {
        CGSize(
            width: CGFloat(CVPixelBufferGetWidth(pixelBuffer)),
            height: CGFloat(CVPixelBufferGetHeight(pixelBuffer))
        )
    }

    static func debugPrediction(
        from observation: VNRecognizedObjectObservation
    ) -> DetectionPredictionDebug? {
        guard let topLabel = observation.labels.first else { return nil }
        return DetectionPredictionDebug(
            label: topLabel.identifier,
            confidence: topLabel.confidence,
            boundingBox: observation.boundingBox
        )
    }
}
