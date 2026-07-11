import Foundation

struct ScanDiagnosticsBuilder {
    static func makeDiagnostics(
        pointCloudPointCount: Int,
        depthAvailable: Bool,
        imageDiagnostics: ImageDetectionDiagnostics
    ) -> ScanYieldDiagnostics {
        var diagnostics = ScanYieldDiagnostics()
        diagnostics.pointCloudPointCount = pointCloudPointCount
        diagnostics.depthAvailable = depthAvailable
        diagnostics.imageFramesProcessed = imageDiagnostics.processedFrameCount
        diagnostics.imageObservationCount = imageDiagnostics.observationCount
        diagnostics.imageConfidenceFilteredCount = imageDiagnostics.confidenceFilteredCount
        diagnostics.imageMappedFruitCount = imageDiagnostics.mappedFruitCount
        diagnostics.imageModelStatus = imageDiagnostics.modelStatus
        diagnostics.imageModelName = imageDiagnostics.modelName
        diagnostics.imageFailureReason = imageDiagnostics.effectiveFailureReason
        diagnostics.imageRuntimeModelLabels = imageDiagnostics.runtimeModelLabels
        diagnostics.imageRuntimeModelLabelsAvailable = imageDiagnostics.runtimeModelLabelsAvailable
        diagnostics.imageModelLabelCompatibilityStatus = imageDiagnostics.modelLabelCompatibilityStatus
        diagnostics.imageModelLabelCompatibilityWarnings = imageDiagnostics.modelLabelCompatibilityWarnings
        diagnostics.imageRawDetectedLabels = imageDiagnostics.rawDetectedLabels
        diagnostics.imageMappedCategories = imageDiagnostics.mappedCategories
        diagnostics.imageUnmappedLabels = imageDiagnostics.unmappedLabels
        return diagnostics
    }

    static func zeroYieldReasons(
        diagnostics: ScanYieldDiagnostics,
        pointCloudMinimum: Int
    ) -> [String] {
        var reasons: [String] = []

        if diagnostics.imageModelStatus != "CoreML" {
            reasons.append(L10n.Diagnostics.modelNotLoaded)
        }
        if !diagnostics.depthAvailable {
            reasons.append(L10n.Diagnostics.depthUnavailable)
        }
        if !diagnostics.depthConfidenceFailureReason.isEmpty {
            reasons.append(diagnostics.depthConfidenceFailureReason)
        }
        if diagnostics.pointCloudPointCount < pointCloudMinimum {
            reasons.append(L10n.Diagnostics.insufficientPoints)
        }
        if diagnostics.imageFramesProcessed == 0 {
            reasons.append(L10n.Diagnostics.noImageFrames)
        }
        if diagnostics.imageObservationCount == 0 {
            reasons.append(L10n.Diagnostics.noDetections)
        }
        if diagnostics.imageObservationCount > 0,
           diagnostics.imageMappedFruitCount == 0,
           diagnostics.imageConfidenceFilteredCount > 0 {
            reasons.append(L10n.Diagnostics.confidenceFiltered)
        }
        if diagnostics.imageObservationCount > 0,
           diagnostics.imageMappedFruitCount == 0,
           diagnostics.imageConfidenceFilteredCount < diagnostics.imageObservationCount {
            reasons.append(L10n.Diagnostics.unmappedLabels)
        }
        if diagnostics.pointCloudCandidateCount == 0 {
            reasons.append(L10n.Diagnostics.noCandidates)
        }
        if diagnostics.imageDetectionCount > 0,
           diagnostics.pointCloudCandidateCount > 0,
           diagnostics.fusedFruitCount == 0 {
            reasons.append(L10n.Diagnostics.fusionFailed)
        }
        if diagnostics.cloudOnlyConservativeMode,
           diagnostics.fusedFruitCount == 0,
           !reasons.contains(L10n.Diagnostics.noDetections) {
            reasons.append(L10n.Diagnostics.cloudOnlyRejected)
        }

        return reasons
    }

    static func zeroYieldNote(
        reasons: [String],
        fallback: String = "⚠️ RGB+LiDAR 未检测到果实（图像检测未确认）"
    ) -> String {
        reasons.isEmpty ? fallback : "⚠️ " + reasons.joined(separator: "；")
    }
}
