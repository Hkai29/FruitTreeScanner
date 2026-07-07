import SwiftUI

struct ResultDiagnosticsSection: View {
    let result: YieldResult

    private var diagnostics: ScanYieldDiagnostics {
        result.diagnostics
    }

    private var recommendations: [String] {
        DiagnosticRecommendation.recommendations(for: diagnostics.zeroYieldReasons)
    }

    private var imageModelStatusText: String {
        switch diagnostics.imageModelStatus {
        case "CoreML": return "本机模型"
        case "Fallback": return "备用模式"
        case "--": return "未知"
        default: return diagnostics.imageModelStatus
        }
    }

    private var canopyPreprocessingText: String {
        let retained = diagnostics.canopyPreprocessedPointCount
        let ground = diagnostics.canopyGroundFilteredPointCount
        let trunk = diagnostics.canopyTrunkFilteredPointCount
        let neighbor = diagnostics.canopyNeighborFilteredPointCount
        let clusters = max(diagnostics.canopyClusterCount, 0)
        return "保留 \(retained)，去地面 \(ground) / 树干 \(trunk) / 邻树 \(neighbor)，簇 \(clusters)"
    }

    private var canopyProjectionText: String {
        let xy = percent(diagnostics.canopyProjectionXYCoefficient)
        let xz = percent(diagnostics.canopyProjectionXZCoefficient)
        let yz = percent(diagnostics.canopyProjectionYZCoefficient)
        return "XY \(xy) / XZ \(xz) / YZ \(yz)"
    }

    private func percent(_ value: Float) -> String {
        guard value.isFinite else { return "0%" }
        return String(format: "%.0f%%", min(max(value, 0), 1) * 100)
    }

    private func meters(_ value: Float) -> String {
        String(format: "%.2f m", max(value.isFinite ? value : 0, 0))
    }

    private func cubicMeters(_ value: Float) -> String {
        String(format: "%.2f m³", max(value.isFinite ? value : 0, 0))
    }

    var body: some View {
        ResultSectionCard(
            title: "0kg / 低置信度诊断",
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

                    ForEach(recommendations, id: \.self) { rec in
                        DiagnosticRecommendationRow(recommendation: rec)
                    }
                }
            }

            Divider().background(Design.Colors.Dark.glassBorder)

            ResultInfoRow(label: "图像识别", value: imageModelStatusText)
            ResultInfoRow(label: "识别模型", value: diagnostics.imageModelName == "--" ? "未知" : diagnostics.imageModelName)
            if !diagnostics.imageFailureReason.isEmpty {
                ResultInfoRow(label: "图像检测失败", value: diagnostics.imageFailureReason)
            }
            ResultInfoRow(label: "点云点数", value: "\(diagnostics.pointCloudPointCount)")
            ResultInfoRow(label: "果色过滤后点数", value: "\(diagnostics.pointCloudColorFilteredCount)")
            ResultInfoRow(label: "统计去噪后点数", value: "\(diagnostics.pointCloudDenoisedPointCount)")
            ResultInfoRow(label: "统计离群点", value: "\(diagnostics.pointCloudOutlierPointCount) / \(percent(diagnostics.pointCloudOutlierRatio))")
            if diagnostics.canopyVolumeM3 > 0 {
                ResultInfoRow(label: "冠层有效体积", value: cubicMeters(diagnostics.canopyVolumeM3))
                ResultInfoRow(label: "冠层外形体积", value: cubicMeters(diagnostics.canopyOuterVolumeM3))
                ResultInfoRow(label: "有效体积系数", value: percent(diagnostics.canopyEffectiveVolumeCoefficient))
                ResultInfoRow(label: "三投影系数", value: canopyProjectionText)
                ResultInfoRow(label: "冠层体素大小", value: meters(diagnostics.canopyVoxelSizeM))
                ResultInfoRow(label: "冠层分层", value: "\(diagnostics.canopyPartitionCount) × \(meters(diagnostics.canopyPartitionSizeM))")
                ResultInfoRow(label: "冠层预处理", value: canopyPreprocessingText)
                ResultInfoRow(label: "冠层树高", value: meters(diagnostics.canopyHeightM))
                ResultInfoRow(
                    label: "冠幅/深度",
                    value: "\(meters(diagnostics.canopyWidthM)) × \(meters(diagnostics.canopyDepthM))"
                )
            }
            ResultInfoRow(label: "LiDAR 深度", value: diagnostics.depthAvailable ? "可用" : "不可用")
            ResultInfoRow(label: "图像处理帧", value: "\(diagnostics.imageFramesProcessed)")
            ResultInfoRow(label: "Observation 候选", value: "\(diagnostics.imageObservationCount)")
            ResultInfoRow(label: "置信度过滤", value: "\(diagnostics.imageConfidenceFilteredCount)")
            ResultInfoRow(label: "图像检测果实", value: "\(diagnostics.imageDetectionCount)")
            ResultInfoRow(label: "2D 去重后", value: "\(diagnostics.deduplicatedImageDetectionCount)")
            ResultInfoRow(label: "融合候选总数", value: "\(diagnostics.pointCloudCandidateCount)")
            ResultInfoRow(label: "点云聚类候选", value: "\(diagnostics.pointCloudClusterCandidateCount)")
            ResultInfoRow(label: "ROI 深度候选", value: "\(diagnostics.detectionDepthCandidateCount)")
            ResultInfoRow(label: "ROI 深度支持", value: percent(diagnostics.detectionDepthSupportRatio))
            ResultInfoRow(label: "有效果实总数", value: "\(diagnostics.validatedFruitCount)")
            ResultInfoRow(label: "RGB+LiDAR 融合", value: "\(diagnostics.fusedValidationCount)")
            ResultInfoRow(label: "多帧视觉轨迹", value: "\(diagnostics.trackedImageFruitCount)")
            ResultInfoRow(label: "单帧视觉估计", value: "\(diagnostics.imageOnlyFruitCount)")
            ResultInfoRow(label: "点云保守估计", value: "\(diagnostics.cloudOnlyFruitCount)")
            ResultInfoRow(label: "来源可靠性", value: percent(diagnostics.validationSourceReliability))
            ResultInfoRow(
                label: "本地计数校准",
                value: String(format: "×%.2f (%d)", diagnostics.localCalibrationCountFactor, diagnostics.localCalibrationCountSampleCount)
            )
            ResultInfoRow(
                label: "本地产量校准",
                value: String(format: "×%.2f (%d)", diagnostics.localCalibrationYieldFactor, diagnostics.localCalibrationYieldSampleCount)
            )
            ResultInfoRow(label: "点云角覆盖", value: percent(diagnostics.pointCloudAngleCoverage))
            ResultInfoRow(label: "相机角覆盖", value: percent(diagnostics.cameraAngleCoverage))
            ResultInfoRow(label: "遮挡采用覆盖", value: percent(diagnostics.scanAngleCoverage))
            ResultInfoRow(label: "cloudOnly 保守模式", value: diagnostics.cloudOnlyConservativeMode ? "已进入" : "未进入")
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
