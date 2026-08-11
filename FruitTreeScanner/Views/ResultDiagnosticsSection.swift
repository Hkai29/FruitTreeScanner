import SwiftUI

struct ResultDiagnosticsSection: View {
    let result: YieldResult

    private var diagnostics: ScanYieldDiagnostics {
        result.diagnostics
    }

    private var recommendations: [String] {
        DiagnosticRecommendation.recommendations(for: diagnostics.zeroYieldReasons)
    }

    private var pointDepthText: String {
        let depthText = L10n.Result.detail(
            diagnostics.depthAvailable ? .diagnosticsDepthAvailable : .diagnosticsDepthUnavailable
        )
        return L10n.Result.detailFormat(
            .diagnosticsPointDepthFormat,
            arguments: [Int64(diagnostics.pointCloudPointCount), depthText]
        )
    }

    private var imageFrameText: String {
        diagnostics.imageFramesProcessed > 0
            ? L10n.Result.detailFormat(
                .diagnosticsFramesFormat,
                arguments: [Int64(diagnostics.imageFramesProcessed)]
            )
            : L10n.Result.detail(.diagnosticsFramesUnprocessed)
    }

    private var fusionEvidenceText: String {
        if diagnostics.fusedValidationCount > 0 {
            return L10n.Result.detailFormat(
                .diagnosticsFusedFormat,
                arguments: [Int64(diagnostics.fusedValidationCount)]
            )
        }
        if diagnostics.trackedImageFruitCount > 0 {
            return L10n.Result.detailFormat(
                .diagnosticsTrackedFormat,
                arguments: [Int64(diagnostics.trackedImageFruitCount)]
            )
        }
        if diagnostics.detectionDepthCandidateCount > 0 {
            return L10n.Result.detailFormat(
                .diagnosticsDepthCandidateFormat,
                arguments: [Int64(diagnostics.detectionDepthCandidateCount)]
            )
        }
        if diagnostics.pointCloudClusterCandidateCount > 0 {
            return L10n.Result.detailFormat(
                .diagnosticsCloudCandidateFormat,
                arguments: [Int64(diagnostics.pointCloudClusterCandidateCount)]
            )
        }
        return L10n.Result.detail(.diagnosticsInsufficient)
    }

    private var scanCoverageText: String {
        let coverage = max(diagnostics.pointCloudAngleCoverage, diagnostics.cameraAngleCoverage)
        return coverage > 0 ? percent(coverage) : L10n.Result.detail(.diagnosticsInsufficient)
    }

    private func percent(_ value: Float) -> String {
        guard value.isFinite else { return "0%" }
        return String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }

    var body: some View {
        ResultSectionCard(
            title: L10n.Result.detail(.diagnosticsTitle),
            icon: "stethoscope",
            color: Design.Colors.warning
        ) {
            if !diagnostics.zeroYieldReasons.isEmpty {
                ForEach(diagnostics.zeroYieldReasons, id: \.self) { reason in
                    DiagnosticReasonRow(reason: DiagnosticRecommendation.localizedReason(reason))
                }
            } else if !result.note.isEmpty {
                DiagnosticReasonRow(reason: DiagnosticRecommendation.localizedReason(result.note))
            } else {
                DiagnosticReasonRow(reason: L10n.Result.detail(.diagnosticsFallbackReason))
            }

            if !recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(Design.Colors.Dark.glassBorder)

                    Text(L10n.Result.detail(.diagnosticsRecommendations))
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.harvest)
                        .padding(.bottom, 4)

                    ForEach(Array(recommendations.prefix(2)), id: \.self) { rec in
                        DiagnosticRecommendationRow(recommendation: rec)
                    }
                }
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            Text(L10n.Result.detail(.diagnosticsKeyQuality))
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .padding(.bottom, 4)

            ResultInfoRow(label: L10n.Result.detail(.diagnosticsValidatedFruit), value: "\(diagnostics.validatedFruitCount)", highlight: diagnostics.validatedFruitCount > 0)
            ResultInfoRow(label: L10n.Result.detail(.diagnosticsPointDepth), value: pointDepthText)
            ResultInfoRow(label: L10n.Result.detail(.diagnosticsImageFrames), value: imageFrameText)
            ResultInfoRow(label: L10n.Result.detail(.diagnosticsFusionEvidence), value: fusionEvidenceText)
            ResultInfoRow(label: L10n.Result.detail(.diagnosticsScanCoverage), value: scanCoverageText)
        }
    }
}

private struct DiagnosticReasonRow: View {
    let reason: String

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Image(systemName: "exclamationmark.triangle.fill")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.warning)
                .padding(.top, 2)
            Text(reason)
                .font(.system(size: 13, weight: .medium))
                .foregroundColor(Design.Colors.Dark.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
            Spacer(minLength: 0)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.vertical, 4)
    }
}
