import SwiftUI

struct ScanStatusBarLayout {
    let isPad: Bool
    let metricFontSize: CGFloat
    let metricLabelSize: CGFloat
    let pillLabelSize: CGFloat
    let pillValueSize: CGFloat
    let statusIconSize: CGFloat
    let statusLabelSize: CGFloat
}

struct ScanRecordingStatusContent: View {
    let treeID: String
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor
    let presentation: ScanStatusBarPresentation
    let layout: ScanStatusBarLayout

    var body: some View {
        VStack(spacing: layout.isPad ? 10 : 8) {
            HStack(spacing: 8) {
                Label("果树全株", systemImage: "viewfinder")
                    .font(.system(size: layout.isPad ? 14 : 12, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                    .lineLimit(1)
                    .padding(.horizontal, 10)
                    .padding(.vertical, 7)
                    .background(Design.Colors.harvest.opacity(0.14))
                    .clipShape(Capsule())

                Text("树号 \(treeID)")
                    .font(.system(size: layout.isPad ? 13 : 11, weight: .semibold, design: .monospaced))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.75)

                Spacer(minLength: 8)

                StatusIndicator(
                    status: .recording,
                    iconSize: layout.statusIconSize,
                    labelSize: layout.statusLabelSize
                )
            }

            HStack(spacing: layout.isPad ? 10 : 8) {
                ScanPrimaryStatusMetric(
                    label: "覆盖",
                    value: "\(hudState.coveragePercent)%",
                    accentColor: presentation.coverageColor,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "果数",
                    value: "\(hudState.detectedFruitCount)",
                    accentColor: hudState.detectedFruitCount > 0 ? Design.Colors.harvest : Design.Colors.warning,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "质量",
                    value: qualityMonitor.getQualityStatus(),
                    accentColor: presentation.qualityColor,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "深度",
                    value: presentation.depthStatusText,
                    accentColor: presentation.depthStatusColor,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
            }

            HStack(spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath")
                    .font(.system(size: 11, weight: .semibold))
                    .foregroundColor(Design.Colors.harvest)
                Text(presentation.recordingRouteHint)
                    .font(.system(size: layout.isPad ? 12 : 10, weight: .medium))
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .lineLimit(1)
                    .minimumScaleFactor(0.78)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Design.Colors.Dark.bgElevated.opacity(0.64))
            .clipShape(RoundedRectangle(cornerRadius: 8))
        }
    }
}

struct ScanDetailedStatusContent: View {
    let treeID: String
    let isRecording: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor
    let presentation: ScanStatusBarPresentation
    let layout: ScanStatusBarLayout

    var body: some View {
        VStack(spacing: layout.isPad ? 10 : 8) {
            HStack(spacing: layout.isPad ? 10 : 8) {
                ScanPrimaryStatusMetric(
                    label: "树号",
                    value: treeID,
                    accentColor: Design.Colors.harvest,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "覆盖",
                    value: "\(hudState.coveragePercent)%",
                    accentColor: presentation.coverageColor,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "果数",
                    value: "\(hudState.detectedFruitCount)",
                    accentColor: hudState.detectedFruitCount > 0 ? Design.Colors.harvest : Design.Colors.warning,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: "质量",
                    value: qualityMonitor.getQualityStatus(),
                    accentColor: presentation.qualityColor,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                StatusIndicator(
                    status: isRecording ? .recording : .ready,
                    iconSize: layout.statusIconSize,
                    labelSize: layout.statusLabelSize
                )
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.isPad ? 10 : 8) {
                    HUDPill(label: "点数", value: ScanHUDValueFormatter.pointCount(hudState.pointCount), accentColor: Design.Colors.harvest, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: "图像", value: presentation.visionStatusText, accentColor: presentation.visionStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: "模型", value: presentation.visionDetailText, accentColor: presentation.visionStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: "深度", value: presentation.depthStatusText, accentColor: presentation.depthStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: "点云", value: presentation.pointCloudStatusText, accentColor: presentation.pointCloudStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: "帧数", value: presentation.processedFrameText, accentColor: presentation.processedFrameColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: "融合", value: presentation.fusionStatusText, accentColor: presentation.fusionStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: "密度", value: ScanHUDValueFormatter.pointDensity(qualityMonitor.pointDensity), accentColor: presentation.pointDensityColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: "光照", value: qualityMonitor.lightLevel.description, accentColor: qualityMonitor.lightLevel.color, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                }
            }
        }
    }
}

private struct ScanPrimaryStatusMetric: View {
    let label: String
    let value: String
    let accentColor: Color
    var valueFontSize: CGFloat = 12
    var labelFontSize: CGFloat = 9

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(label)
                .font(.system(size: labelFontSize, weight: .semibold))
                .foregroundColor(Design.Colors.Dark.textMuted)
                .lineLimit(1)

            Text(value)
                .font(.system(size: valueFontSize, weight: .semibold, design: .monospaced))
                .foregroundColor(accentColor)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.horizontal, 8)
        .padding(.vertical, 7)
        .background(Design.Colors.Dark.bgElevated.opacity(0.82))
        .clipShape(RoundedRectangle(cornerRadius: 8))
    }
}
