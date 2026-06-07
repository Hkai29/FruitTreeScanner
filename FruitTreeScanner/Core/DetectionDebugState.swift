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

struct ModelResourceDiagnostics: Sendable, Equatable {
    var expectedModelName: String = "FruitsDetector"
    var foundModelURL: Bool = false
    var foundExtension: String?
    var bundlePath: String?
    var loadedSuccessfully: Bool = false
    var loadErrorMessage: String?
    var supportedClasses: [String] = []
    var labelsSource: String = "none"
}

struct YOLOOutputDiagnostics: Sendable, Equatable {
    var outputShape: [Int] = []
    var channelAxis: Int?
    var anchorAxis: Int?
    var classCount: Int = 0
    var anchorCount: Int = 0
    var lowConfidenceFloor: Float = 0
    var modelCandidateCount: Int = 0
    var invalidBoundingBoxCount: Int = 0
    var coordinateScaleGuess: Float = 0
    var sampleRawBoxes: [String] = []
}

enum DetectionDebugConfiguration {
    static let defaultThreshold: Float = 0.25
    #if DEBUG
    static var debugRunDetectionWhilePreviewing: Bool = true
    #endif

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
    var modelResourceDiagnostics = ModelResourceDiagnostics()
    var yoloOutputDiagnostics = YOLOOutputDiagnostics()
    var previewDetectionEnabled: Bool = false
    var lastWarningMessage: String?

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
        let diagnostics = ModelResourceDiagnostics(
            expectedModelName: modelName,
            foundModelURL: modelURLFound,
            foundExtension: nil,
            bundlePath: nil,
            loadedSuccessfully: true,
            loadErrorMessage: nil,
            supportedClasses: supportedClasses,
            labelsSource: supportedClasses.isEmpty ? "none" : "coremlMetadata"
        )
        markModelDiagnostics(diagnostics)
    }

    mutating func markModelLoadFailure(
        modelName: String,
        modelURLFound: Bool,
        errorMessage: String
    ) {
        let diagnostics = ModelResourceDiagnostics(
            expectedModelName: modelName,
            foundModelURL: modelURLFound,
            foundExtension: nil,
            bundlePath: nil,
            loadedSuccessfully: false,
            loadErrorMessage: errorMessage,
            supportedClasses: [],
            labelsSource: "none"
        )
        markModelDiagnostics(diagnostics)
    }

    mutating func markModelDiagnostics(_ diagnostics: ModelResourceDiagnostics) {
        modelResourceDiagnostics = diagnostics
        modelLoaded = diagnostics.loadedSuccessfully
        modelName = diagnostics.foundExtension.map { "\(diagnostics.expectedModelName).\($0)" } ?? diagnostics.expectedModelName
        modelURLFound = diagnostics.foundModelURL
        supportedClasses = diagnostics.supportedClasses
        lastErrorMessage = diagnostics.loadErrorMessage
        lastUpdatedAt = Date()
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
        errorMessage: String? = nil,
        yoloOutputDiagnostics: YOLOOutputDiagnostics? = nil
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
        self.yoloOutputDiagnostics = yoloOutputDiagnostics ?? YOLOOutputDiagnostics()
        lastUpdatedAt = Date()
    }

    mutating func markWarning(_ warning: String) {
        lastWarningMessage = warning
        lastUpdatedAt = Date()
    }
}
