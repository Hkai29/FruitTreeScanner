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
        let depthText = diagnostics.depthAvailable ? "深度可用" : "深度不可用"
        return "\(diagnostics.pointCloudPointCount) 点 · \(depthText)"
    }

    private var imageFrameText: String {
        diagnostics.imageFramesProcessed > 0
            ? "\(diagnostics.imageFramesProcessed) 帧"
            : "未处理"
    }

    private var fusionEvidenceText: String {
        if diagnostics.fusedValidationCount > 0 {
            return "\(diagnostics.fusedValidationCount) 个 RGB+LiDAR"
        }
        if diagnostics.trackedImageFruitCount > 0 {
            return "\(diagnostics.trackedImageFruitCount) 个多帧视觉"
        }
        if diagnostics.detectionDepthCandidateCount > 0 {
            return "\(diagnostics.detectionDepthCandidateCount) 个深度候选"
        }
        if diagnostics.pointCloudClusterCandidateCount > 0 {
            return "\(diagnostics.pointCloudClusterCandidateCount) 个点云候选"
        }
        return "不足"
    }

    private var scanCoverageText: String {
        let coverage = max(diagnostics.pointCloudAngleCoverage, diagnostics.cameraAngleCoverage)
        return coverage > 0 ? percent(coverage) : "不足"
    }

    private func percent(_ value: Float) -> String {
        guard value.isFinite else { return "0%" }
        return String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }

    var body: some View {
        ResultSectionCard(
            title: "结果复核",
            icon: "stethoscope",
            color: Design.Colors.warning
        ) {
            if !diagnostics.zeroYieldReasons.isEmpty {
                ForEach(diagnostics.zeroYieldReasons, id: \.self) { reason in
                    DiagnosticReasonRow(reason: reason)
                }
            } else if !result.note.isEmpty {
                DiagnosticReasonRow(reason: result.note)
            } else {
                DiagnosticReasonRow(reason: "有效果实数量不足，建议检查模型、深度和点云质量")
            }

            if !recommendations.isEmpty {
                VStack(alignment: .leading, spacing: 4) {
                    Divider().background(Design.Colors.Dark.glassBorder)

                    Text("操作建议")
                        .font(.system(size: 12, weight: .semibold))
                        .foregroundColor(Design.Colors.harvest)
                        .padding(.bottom, 4)

                    ForEach(Array(recommendations.prefix(2)), id: \.self) { rec in
                        DiagnosticRecommendationRow(recommendation: rec)
                    }
                }
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            Text("关键质量")
                .font(.system(size: 12, weight: .semibold))
                .foregroundColor(Design.Colors.harvest)
                .padding(.bottom, 4)

            ResultInfoRow(label: "果数确认", value: "\(diagnostics.validatedFruitCount)", highlight: diagnostics.validatedFruitCount > 0)
            ResultInfoRow(label: "点云 / 深度", value: pointDepthText)
            ResultInfoRow(label: "图像帧", value: imageFrameText)
            ResultInfoRow(label: "融合证据", value: fusionEvidenceText)
            ResultInfoRow(label: "扫描覆盖", value: scanCoverageText)
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
