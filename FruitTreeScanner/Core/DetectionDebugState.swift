// DetectionDebugState.swift
// Lightweight diagnostics for the Vision/CoreML fruit detection pipeline.

import CoreGraphics
import Foundation

struct DetectionPredictionDebug: Identifiable, Sendable, Equatable {
    let label: String
    let confidence: Float
    let boundingBox: CGRect

    var id: String {
        "\(label)-\(confidence)-\(boundingBox.minX)-\(boundingBox.minY)-\(boundingBox.width)-\(boundingBox.height)"
    }
}

struct DetectionFailureSample: Identifiable, Sendable, Equatable {
    let id = UUID()
    let timestamp: Date
    let modelName: String
    let threshold: Float
    let topPredictions: [DetectionPredictionDebug]
    let rawObservationCount: Int
    let filteredObservationCount: Int
    let note: String?
    let fruitCategoryExpected: String?
}

enum DetectionDebugConfiguration {
    static let defaultThreshold: Float = 0.25

    static func effectiveThreshold(for configuredThreshold: Float, debugEnabled: Bool = isBuildDebug) -> Float {
        let clampedThreshold = clamped(configuredThreshold)
        return debugEnabled ? min(clampedThreshold, defaultThreshold) : clampedThreshold
    }

    private static var isBuildDebug: Bool {
        #if DEBUG
        return true
        #else
        return false
        #endif
    }

    private static func clamped(_ threshold: Float) -> Float {
        guard threshold.isFinite else { return 0 }
        return min(max(threshold, 0), 1)
    }
}

struct DetectionDebugState: Sendable, Equatable {
    var modelLoaded: Bool = false
    var modelName: String = "--"
    var modelURLFound: Bool = false
    var supportedClasses: [String] = []
    var frameReceived: Bool = false
    var inferenceRequested: Bool = false
    var inferenceRunning: Bool = false
    var lastInferenceTimeMs: Double = 0
    var rawObservationCount: Int = 0
    var filteredObservationCount: Int = 0
    var topPredictions: [DetectionPredictionDebug] = []
    var currentThreshold: Float
    var lastFrameSize: CGSize = .zero
    var lastPixelBufferSize: CGSize = .zero
    var lastErrorMessage: String?
    var lastUpdatedAt: Date = Date()
    var rawPredictions: [DetectionPredictionDebug] = []
    var filteredPredictions: [DetectionPredictionDebug] = []

    init(currentThreshold: Float = 0.5) {
        self.currentThreshold = currentThreshold
    }

    var diagnosticHint: String? {
        if rawObservationCount == 0 {
            return "No raw detections. Check model loading, model class coverage, image orientation, preprocessing, or unsupported fruit type."
        }

        if filteredObservationCount == 0 {
            return "Raw detections exist but are filtered by confidence threshold. Try lowering threshold."
        }

        return "Detections exist. Check bounding box coordinate mapping or overlay rendering."
    }

    static func sortedTopPredictions(
        _ predictions: [DetectionPredictionDebug],
        limit: Int = 5
    ) -> [DetectionPredictionDebug] {
        Array(predictions.sorted { $0.confidence > $1.confidence }.prefix(limit))
    }

    mutating func markModelLoaded(
        modelName: String,
        modelURLFound: Bool,
        supportedClasses: [String]
    ) {
        self.modelLoaded = true
        self.modelName = modelName
        self.modelURLFound = modelURLFound
        self.supportedClasses = supportedClasses
        self.lastErrorMessage = nil
        self.lastUpdatedAt = Date()
    }

    mutating func markModelLoadFailure(
        modelName: String,
        modelURLFound: Bool,
        errorMessage: String
    ) {
        self.modelLoaded = false
        self.modelName = modelName
        self.modelURLFound = modelURLFound
        self.supportedClasses = []
        self.lastErrorMessage = errorMessage
        self.lastUpdatedAt = Date()
    }

    mutating func markFrameReceived(
        frameSize: CGSize,
        pixelBufferSize: CGSize,
        threshold: Float
    ) {
        frameReceived = true
        lastFrameSize = frameSize
        lastPixelBufferSize = pixelBufferSize
        currentThreshold = threshold
        lastUpdatedAt = Date()
    }

    mutating func markInferenceStarted(
        frameSize: CGSize,
        pixelBufferSize: CGSize,
        threshold: Float
    ) {
        frameReceived = true
        inferenceRequested = true
        inferenceRunning = true
        currentThreshold = threshold
        lastFrameSize = frameSize
        lastPixelBufferSize = pixelBufferSize
        lastUpdatedAt = Date()
    }

    mutating func markInferenceCompleted(
        elapsedMs: Double,
        rawObservationCount: Int,
        filteredObservationCount: Int,
        rawPredictions: [DetectionPredictionDebug],
        filteredPredictions: [DetectionPredictionDebug],
        threshold: Float,
        errorMessage: String? = nil
    ) {
        inferenceRunning = false
        inferenceRequested = true
        lastInferenceTimeMs = elapsedMs
        self.rawObservationCount = rawObservationCount
        self.filteredObservationCount = filteredObservationCount
        self.rawPredictions = rawPredictions
        self.filteredPredictions = filteredPredictions
        self.topPredictions = Self.sortedTopPredictions(rawPredictions)
        currentThreshold = threshold
        lastErrorMessage = errorMessage
        lastUpdatedAt = Date()
    }
}
