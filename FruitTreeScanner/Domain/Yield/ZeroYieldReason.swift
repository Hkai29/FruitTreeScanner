/// Ordered diagnostic facts. Dynamic legacy depth explanations remain opaque;
/// classification does not interpret localized text.
enum ZeroYieldReason: Equatable, Sendable {
    case modelNotLoaded
    case depthUnavailable
    case depthConfidenceFailure(String)
    case insufficientPoints
    case noImageFrames
    case noDetections
    case confidenceFiltered
    case unmappedLabels
    case noCandidates
    case fusionFailed
    case cloudOnlyRejected
    case uncalibratedSeason
}

enum ZeroYieldReasonPolicy {
    static func reasons(
        diagnostics: ScanYieldDiagnostics,
        pointCloudMinimum: Int
    ) -> [ZeroYieldReason] {
        var reasons: [ZeroYieldReason] = []

        if diagnostics.imageModelStatus != "CoreML" {
            reasons.append(.modelNotLoaded)
        }
        if !diagnostics.depthAvailable {
            reasons.append(.depthUnavailable)
        }
        if !diagnostics.depthConfidenceFailureReason.isEmpty {
            reasons.append(.depthConfidenceFailure(diagnostics.depthConfidenceFailureReason))
        }
        if diagnostics.pointCloudPointCount < pointCloudMinimum {
            reasons.append(.insufficientPoints)
        }
        if diagnostics.imageFramesProcessed == 0 {
            reasons.append(.noImageFrames)
        }
        if diagnostics.imageObservationCount == 0 {
            reasons.append(.noDetections)
        }
        if diagnostics.imageObservationCount > 0,
           diagnostics.imageMappedFruitCount == 0,
           diagnostics.imageConfidenceFilteredCount > 0 {
            reasons.append(.confidenceFiltered)
        }
        if diagnostics.imageObservationCount > 0,
           diagnostics.imageMappedFruitCount == 0,
           diagnostics.imageConfidenceFilteredCount < diagnostics.imageObservationCount {
            reasons.append(.unmappedLabels)
        }
        if diagnostics.pointCloudCandidateCount == 0 {
            reasons.append(.noCandidates)
        }
        if diagnostics.imageDetectionCount > 0,
           diagnostics.pointCloudCandidateCount > 0,
           diagnostics.fusedFruitCount == 0 {
            reasons.append(.fusionFailed)
        }
        if diagnostics.cloudOnlyConservativeMode,
           diagnostics.fusedFruitCount == 0 {
            // The legacy text adapter may suppress this candidate when an
            // earlier rendered array element equals its no-detections message.
            reasons.append(.cloudOnlyRejected)
        }

        return reasons
    }
}
