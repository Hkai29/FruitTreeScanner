// ImageDetectorDebugging.swift
// Debug state access and failure sample export for ImageDetector.

import Foundation
import CoreGraphics

extension ImageDetector {
    func detectionDebugSnapshot() -> DetectionDebugState {
        lock.lock()
        defer { lock.unlock() }
        return detectionDebugState
    }

    func detectionFailureSamplesSnapshot() -> [DetectionFailureSample] {
        lock.lock()
        defer { lock.unlock() }
        return detectionFailureSamples
    }

    func recordDebugInferenceStarted(
        frameSize: CGSize,
        pixelBufferSize: CGSize,
        threshold: Float
    ) {
        lock.lock()
        detectionDebugState.markInferenceStarted(
            frameSize: frameSize,
            pixelBufferSize: pixelBufferSize,
            threshold: threshold
        )
        lock.unlock()
    }

    func recordDebugInferenceCompleted(
        elapsedMs: Double,
        rawObservationCount: Int,
        filteredObservationCount: Int,
        rawPredictions: [DetectionPredictionDebug],
        filteredPredictions: [DetectionPredictionDebug],
        threshold: Float,
        errorMessage: String? = nil
    ) {
        lock.lock()
        detectionDebugState.markInferenceCompleted(
            elapsedMs: elapsedMs,
            rawObservationCount: rawObservationCount,
            filteredObservationCount: filteredObservationCount,
            rawPredictions: rawPredictions,
            filteredPredictions: filteredPredictions,
            threshold: threshold,
            errorMessage: errorMessage
        )
        lock.unlock()
    }

    func captureDetectionFailureSample(
        note: String? = nil,
        fruitCategoryExpected: String? = nil
    ) {
        lock.lock()
        let sample = DetectionFailureSample(
            timestamp: Date(),
            modelName: detectionDebugState.modelName,
            threshold: detectionDebugState.currentThreshold,
            topPredictions: detectionDebugState.topPredictions,
            rawObservationCount: detectionDebugState.rawObservationCount,
            filteredObservationCount: detectionDebugState.filteredObservationCount,
            note: note,
            fruitCategoryExpected: fruitCategoryExpected
        )
        detectionFailureSamples.append(sample)
        if detectionFailureSamples.count > maxDetectionFailureSamples {
            detectionFailureSamples.removeFirst(detectionFailureSamples.count - maxDetectionFailureSamples)
        }
        lock.unlock()

        Log.detection.info("Detection failure sample captured: model=\(sample.modelName), raw=\(sample.rawObservationCount), filtered=\(sample.filteredObservationCount), threshold=\(sample.threshold)")
    }
}

#if DEBUG

struct DetectionFailureExportPayload: Codable {
    let exportTimestamp: Date
    let appVersion: String
    let sampleCount: Int
    let samples: [DetectionFailureSample]
    let debugState: DetectionDebugStateSnapshot
}

struct DetectionDebugStateSnapshot: Codable {
    let modelLoaded: Bool
    let modelName: String
    let currentThreshold: Float
    let lastInferenceTimeMs: Double
    let lastErrorMessage: String?
    let rawObservationCount: Int
    let filteredObservationCount: Int

    init(from state: DetectionDebugState) {
        modelLoaded = state.modelLoaded
        modelName = state.modelName
        currentThreshold = state.currentThreshold
        lastInferenceTimeMs = state.lastInferenceTimeMs
        lastErrorMessage = state.lastErrorMessage
        rawObservationCount = state.rawObservationCount
        filteredObservationCount = state.filteredObservationCount
    }
}

enum DetectionFailureExportService {

    static func appVersion() -> String {
        Bundle.main.infoDictionary?["CFBundleShortVersionString"] as? String
            ?? Bundle.main.infoDictionary?["CFBundleVersion"] as? String
            ?? "unknown"
    }

    static func exportFile(
        from samples: [DetectionFailureSample],
        debugState: DetectionDebugState,
        directory: URL = FileManager.default.temporaryDirectory
    ) throws -> URL {
        let payload = makePayload(from: samples, debugState: debugState)
        let data = try encode(payload: payload, formatting: [.prettyPrinted, .sortedKeys])
        let filename = [
            "detection-failure-samples",
            filenameTimestamp(from: payload.exportTimestamp),
            UUID().uuidString.lowercased()
        ].joined(separator: "-") + ".json"
        let fileURL = directory.appendingPathComponent(filename, isDirectory: false)
        try data.write(to: fileURL, options: .atomic)
        return fileURL
    }

    static func exportJSON(
        from samples: [DetectionFailureSample],
        debugState: DetectionDebugState
    ) -> String? {
        do {
            let data = try encode(
                payload: makePayload(from: samples, debugState: debugState),
                formatting: [.prettyPrinted, .sortedKeys]
            )
            return String(data: data, encoding: .utf8)
        } catch {
            Log.detection.error("Failed to export detection failure samples: \(error.localizedDescription)")
            return nil
        }
    }

    static func exportData(
        from samples: [DetectionFailureSample],
        debugState: DetectionDebugState
    ) -> Data? {
        do {
            return try encode(
                payload: makePayload(from: samples, debugState: debugState),
                formatting: [.prettyPrinted, .sortedKeys]
            )
        } catch {
            Log.detection.error("Failed to export detection failure samples: \(error.localizedDescription)")
            return nil
        }
    }

    private static func makePayload(
        from samples: [DetectionFailureSample],
        debugState: DetectionDebugState
    ) -> DetectionFailureExportPayload {
        let payload = DetectionFailureExportPayload(
            exportTimestamp: Date(),
            appVersion: appVersion(),
            sampleCount: samples.count,
            samples: samples,
            debugState: DetectionDebugStateSnapshot(from: debugState)
        )
        return payload
    }

    private static func encode(
        payload: DetectionFailureExportPayload,
        formatting: JSONEncoder.OutputFormatting
    ) throws -> Data {
        let encoder = JSONEncoder()
        encoder.outputFormatting = formatting
        encoder.dateEncodingStrategy = .iso8601
        return try encoder.encode(payload)
    }

    private static func filenameTimestamp(from date: Date) -> String {
        let formatter = ISO8601DateFormatter()
        formatter.formatOptions = [.withInternetDateTime, .withDashSeparatorInDate, .withColonSeparatorInTime]
        return formatter.string(from: date)
            .replacingOccurrences(of: ":", with: "-")
    }
}

extension ImageDetector {
    func exportFailureSamplesJSON() -> String? {
        let (samples, state) = (detectionFailureSamplesSnapshot(), detectionDebugSnapshot())
        return DetectionFailureExportService.exportJSON(from: samples, debugState: state)
    }

    func exportFailureSamplesData() -> Data? {
        let (samples, state) = (detectionFailureSamplesSnapshot(), detectionDebugSnapshot())
        return DetectionFailureExportService.exportData(from: samples, debugState: state)
    }

    func exportFailureSamplesFile() throws -> URL {
        let (samples, state) = (detectionFailureSamplesSnapshot(), detectionDebugSnapshot())
        return try DetectionFailureExportService.exportFile(from: samples, debugState: state)
    }
}

#endif
