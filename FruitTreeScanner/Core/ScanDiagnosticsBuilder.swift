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
        zeroYieldReasonDescriptions(ZeroYieldReasonPolicy.reasons(
            diagnostics: diagnostics, pointCloudMinimum: pointCloudMinimum
        ))
    }

    /// Preserve the existing ordered string schema and its text-dependent
    /// cloudOnly suppression. Equal dynamic and formal reasons stay repeated.
    static func zeroYieldReasonDescriptions(_ reasons: [ZeroYieldReason]) -> [String] {
        var descriptions: [String] = []
        for reason in reasons {
            switch reason {
            case .modelNotLoaded:
                descriptions.append(L10n.Diagnostics.modelNotLoaded)
            case .depthUnavailable:
                descriptions.append(L10n.Diagnostics.depthUnavailable)
            case .depthConfidenceFailure(let message):
                descriptions.append(message)
            case .insufficientPoints:
                descriptions.append(L10n.Diagnostics.insufficientPoints)
            case .noImageFrames:
                descriptions.append(L10n.Diagnostics.noImageFrames)
            case .noDetections:
                descriptions.append(L10n.Diagnostics.noDetections)
            case .confidenceFiltered:
                descriptions.append(L10n.Diagnostics.confidenceFiltered)
            case .unmappedLabels:
                descriptions.append(L10n.Diagnostics.unmappedLabels)
            case .noCandidates:
                descriptions.append(L10n.Diagnostics.noCandidates)
            case .fusionFailed:
                descriptions.append(L10n.Diagnostics.fusionFailed)
            case .cloudOnlyRejected:
                if !descriptions.contains(L10n.Diagnostics.noDetections) {
                    descriptions.append(L10n.Diagnostics.cloudOnlyRejected)
                }
            case .uncalibratedSeason:
                descriptions.append("非成熟期冠层回归模型尚未标定，本次未生成产量估算")
            }
        }
        return descriptions
    }

    static func zeroYieldNote(
        reasons: [String],
        fallback: String = "⚠️ RGB+LiDAR 未检测到果实（图像检测未确认）"
    ) -> String {
        reasons.isEmpty ? fallback : "⚠️ " + reasons.joined(separator: "；")
    }
}
