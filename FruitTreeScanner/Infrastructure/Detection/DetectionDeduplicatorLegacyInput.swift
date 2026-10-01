import CoreGraphics
import Foundation

/// Legacy callers retain their original facades, including private pixel buffers.
/// All selection rules live in the buffer-free Observation implementation.
extension DetectionDeduplicator {
    static func stableDetections(
        _ detections: [DetectedFruit],
        minimumObservations: Int = 2,
        minimumConfidence: Float = 0.85,
        timeWindow: TimeInterval = 3.5,
        centerDistanceThreshold: CGFloat = 0.16,
        minimumDuration: TimeInterval = 0.35
    ) -> [DetectedFruit] {
        selectingOriginalDetections(detections) { observations in
            stableDetections(
                observations: observations,
                minimumObservations: minimumObservations,
                minimumConfidence: minimumConfidence,
                timeWindow: timeWindow,
                centerDistanceThreshold: centerDistanceThreshold,
                minimumDuration: minimumDuration
            )
        }
    }

    static func stableEvidenceDetections(
        _ detections: [DetectedFruit],
        minimumObservations: Int = 2,
        minimumConfidence: Float = 0.85,
        timeWindow: TimeInterval = 3.5,
        centerDistanceThreshold: CGFloat = 0.16,
        minimumDuration: TimeInterval = 0.35,
        recentOnly: Bool = false
    ) -> [DetectedFruit] {
        selectingOriginalDetections(detections) { observations in
            stableEvidenceDetections(
                observations: observations,
                minimumObservations: minimumObservations,
                minimumConfidence: minimumConfidence,
                timeWindow: timeWindow,
                centerDistanceThreshold: centerDistanceThreshold,
                minimumDuration: minimumDuration,
                recentOnly: recentOnly
            )
        }
    }

    static func compactStableEvidenceDetections(
        _ detections: [DetectedFruit],
        minimumObservations: Int = 2,
        minimumConfidence: Float = 0.85,
        timeWindow: TimeInterval = 3.5,
        centerDistanceThreshold: CGFloat = 0.16,
        minimumDuration: TimeInterval = 0.35,
        maxObservationsPerTrack: Int? = nil
    ) -> [DetectedFruit] {
        selectingOriginalDetections(detections) { observations in
            compactStableEvidenceDetections(
                observations: observations,
                minimumObservations: minimumObservations,
                minimumConfidence: minimumConfidence,
                timeWindow: timeWindow,
                centerDistanceThreshold: centerDistanceThreshold,
                minimumDuration: minimumDuration,
                maxObservationsPerTrack: maxObservationsPerTrack
            )
        }
    }

    static func stableTrackCount(
        _ detections: [DetectedFruit],
        minimumObservations: Int = 2,
        minimumConfidence: Float = 0.85,
        timeWindow: TimeInterval = 3.5
    ) -> Int {
        stableTrackCount(
            observations: detections.map { $0.resolvedObservation() },
            minimumObservations: minimumObservations,
            minimumConfidence: minimumConfidence,
            timeWindow: timeWindow
        )
    }

    static func deduplicate2D(
        _ detections: [DetectedFruit],
        iouThreshold: Float = 0.5,
        centerDistanceThreshold: CGFloat = 0.16,
        timeWindow: TimeInterval = 2.0
    ) -> [DetectedFruit] {
        selectingOriginalDetections(detections) { observations in
            deduplicate2D(
                observations: observations,
                iouThreshold: iouThreshold,
                centerDistanceThreshold: centerDistanceThreshold,
                timeWindow: timeWindow
            )
        }
    }

    private static func selectingOriginalDetections(
        _ detections: [DetectedFruit],
        select: ([Observation]) -> [Observation]
    ) -> [DetectedFruit] {
        // Identical detections may occur more than once. Do not collapse the
        // selected sequence or trap while indexing repeated identities.
        var originalsByID: [UUID: DetectedFruit] = [:]
        for detection in detections where originalsByID[detection.id] == nil {
            originalsByID[detection.id] = detection
        }
        return select(detections.map { $0.resolvedObservation() }).map { observation in
            // The core selects input values only, so every returned ID is present.
            originalsByID[observation.id]!
        }
    }
}

// MARK: - Detection retention

extension DetectionRetentionPolicy {
    static func trimmedByFrameLimit(
        _ detections: [DetectedFruit],
        maxFrameCount: Int = defaultMaxFrameCount
    ) -> [DetectedFruit] {
        trimmedByFrameLimit(detections, timestamp: \.timestamp, maxFrameCount: maxFrameCount)
    }
}
