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
            if layout.isPad {
                HStack(spacing: 8) {
                    wholeTreeBadge
                    treeIdentifierLabel
                    Spacer(minLength: 8)
                    recordingIndicator
                }
            } else {
                VStack(spacing: 6) {
                    HStack(spacing: 8) {
                        wholeTreeBadge
                        Spacer(minLength: 8)
                        recordingIndicator
                    }
                    treeIdentifierLabel
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
            }

            HStack(spacing: layout.isPad ? 10 : 8) {
                ScanPrimaryStatusMetric(
                    label: L10n.ScanHUD.coverage,
                    value: "\(hudState.coveragePercent)%",
                    accentColor: presentation.coverageColor,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: L10n.ScanHUD.fruitCount,
                    value: "\(hudState.detectedFruitCount)",
                    accentColor: hudState.detectedFruitCount > 0 ? Design.Colors.harvest : Design.Colors.warning,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: L10n.ScanHUD.quality,
                    value: qualityMonitor.getQualityStatus(),
                    accentColor: presentation.qualityColor,
                    valueFontSize: layout.metricFontSize,
                    labelFontSize: layout.metricLabelSize
                )
                ScanPrimaryStatusMetric(
                    label: L10n.ScanHUD.depth,
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

    private var wholeTreeBadge: some View {
        Label(L10n.ScanHUD.wholeTree, systemImage: "viewfinder")
            .font(.system(size: layout.isPad ? 14 : 12, weight: .semibold))
            .foregroundColor(Design.Colors.harvest)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .padding(.horizontal, 10)
            .padding(.vertical, 7)
            .background(Design.Colors.harvest.opacity(0.14))
            .clipShape(Capsule())
    }

    private var treeIdentifierLabel: some View {
        Text(L10n.ScanHUD.treeIdentifier(treeID))
            .font(.system(size: layout.isPad ? 13 : 11, weight: .semibold, design: .monospaced))
            .foregroundColor(Design.Colors.Dark.textPrimary)
            .lineLimit(1)
            .minimumScaleFactor(0.75)
    }

    private var recordingIndicator: some View {
        StatusIndicator(
            status: .recording,
            iconSize: layout.statusIconSize,
            labelSize: layout.statusLabelSize
        )
        .fixedSize(horizontal: true, vertical: false)
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
            if layout.isPad {
                HStack(spacing: 10) {
                    treeMetric
                    coverageMetric
                    fruitMetric
                    qualityMetric
                    statusIndicator
                }
            } else {
                VStack(spacing: 8) {
                    HStack(spacing: 8) {
                        treeMetric
                        statusIndicator.fixedSize(horizontal: true, vertical: false)
                    }
                    HStack(spacing: 8) {
                        coverageMetric
                        fruitMetric
                        qualityMetric
                    }
                }
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: layout.isPad ? 10 : 8) {
                    HUDPill(label: L10n.ScanHUD.points, value: ScanHUDValueFormatter.pointCount(hudState.pointCount), accentColor: Design.Colors.harvest, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: L10n.ScanHUD.vision, value: presentation.visionStatusText, accentColor: presentation.visionStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: L10n.ScanHUD.model, value: presentation.visionDetailText, accentColor: presentation.visionStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: L10n.ScanHUD.depth, value: presentation.depthStatusText, accentColor: presentation.depthStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: L10n.ScanHUD.pointCloud, value: presentation.pointCloudStatusText, accentColor: presentation.pointCloudStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: L10n.ScanHUD.frames, value: presentation.processedFrameText, accentColor: presentation.processedFrameColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: L10n.ScanHUD.fusion, value: presentation.fusionStatusText, accentColor: presentation.fusionStatusColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: L10n.ScanHUD.density, value: ScanHUDValueFormatter.pointDensity(qualityMonitor.pointDensity), accentColor: presentation.pointDensityColor, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                    HUDPill(label: L10n.ScanHUD.lighting, value: qualityMonitor.lightLevel.description, accentColor: qualityMonitor.lightLevel.color, labelSize: layout.pillLabelSize, valueSize: layout.pillValueSize)
                }
            }
        }
    }

    private var treeMetric: some View {
        ScanPrimaryStatusMetric(
            label: L10n.ScanHUD.treeID,
            value: treeID,
            accentColor: Design.Colors.harvest,
            valueFontSize: layout.metricFontSize,
            labelFontSize: layout.metricLabelSize
        )
    }

    private var coverageMetric: some View {
        ScanPrimaryStatusMetric(
            label: L10n.ScanHUD.coverage,
            value: "\(hudState.coveragePercent)%",
            accentColor: presentation.coverageColor,
            valueFontSize: layout.metricFontSize,
            labelFontSize: layout.metricLabelSize
        )
    }

    private var fruitMetric: some View {
        ScanPrimaryStatusMetric(
            label: L10n.ScanHUD.fruitCount,
            value: "\(hudState.detectedFruitCount)",
            accentColor: hudState.detectedFruitCount > 0 ? Design.Colors.harvest : Design.Colors.warning,
            valueFontSize: layout.metricFontSize,
            labelFontSize: layout.metricLabelSize
        )
    }

    private var qualityMetric: some View {
        ScanPrimaryStatusMetric(
            label: L10n.ScanHUD.quality,
            value: qualityMonitor.getQualityStatus(),
            accentColor: presentation.qualityColor,
            valueFontSize: layout.metricFontSize,
            labelFontSize: layout.metricLabelSize
        )
    }

    private var statusIndicator: some View {
        StatusIndicator(
            status: isRecording ? .recording : .ready,
            iconSize: layout.statusIconSize,
            labelSize: layout.statusLabelSize
        )
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
