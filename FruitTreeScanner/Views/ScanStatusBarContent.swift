// ScanStatusBarContent.swift
// 采集读数面板：把覆盖度、检测数、质量与深度状态做成仪器读数。
// 覆盖度是本次采集最关键的进度，因此用分段电平表表达，而不是只给一个数字。

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
        VStack(alignment: .leading, spacing: 14) {
            ScanStatusIdentity(treeID: treeID, isRecording: true,
                               duration: hudState.scanCompletion.formattedDuration)
            ScanStatusReadings(hudState: hudState, qualityMonitor: qualityMonitor,
                               presentation: presentation)
            Label(presentation.recordingRouteHint, systemImage: "arrow.triangle.2.circlepath")
                .font(.footnote)
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
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
    @State private var showsDiagnostics = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            ScanStatusIdentity(treeID: treeID, isRecording: isRecording,
                               duration: hudState.scanCompletion.formattedDuration)
            ScanStatusReadings(hudState: hudState, qualityMonitor: qualityMonitor,
                               presentation: presentation)
            DisclosureGroup(isExpanded: $showsDiagnostics) {
                VStack(spacing: 0) {
                    diagnostic(L10n.ScanHUD.points, ScanHUDValueFormatter.pointCount(hudState.pointCount))
                    diagnostic(L10n.ScanHUD.vision, presentation.visionStatusText)
                    diagnostic(L10n.ScanHUD.model, presentation.visionDetailText)
                    diagnostic(L10n.ScanHUD.depth, presentation.depthStatusText)
                    diagnostic(L10n.ScanHUD.pointCloud, presentation.pointCloudStatusText)
                    diagnostic(L10n.ScanHUD.frames, presentation.processedFrameText)
                    diagnostic(L10n.ScanHUD.fusion, presentation.fusionStatusText)
                    diagnostic(L10n.ScanHUD.density, ScanHUDValueFormatter.pointDensity(qualityMonitor.pointDensity))
                    diagnostic(L10n.ScanHUD.lighting, qualityMonitor.lightLevel.description)
                }
                .padding(.top, 6)
            } label: {
                Text(L10n.ScanHUD.diagnosticsTitle)
                    .font(.system(.caption2, design: .default).weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundColor(Design.Colors.Dark.textSecondary)
                    .frame(minHeight: 44, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .tint(Design.Colors.Dark.textSecondary)
            .accessibilityIdentifier("scan.diagnostics")
        }
    }

    private func diagnostic(_ label: String, _ value: String) -> some View {
        HStack(alignment: .firstTextBaseline, spacing: 16) {
            Text(label)
                .font(.system(.caption, design: .default))
                .foregroundColor(Design.Colors.Dark.textSecondary)
            Spacer(minLength: 8)
            Text(value)
                .font(.system(.caption, design: .monospaced))
                .monospacedDigit()
                .frame(maxWidth: .infinity, alignment: .trailing)
                .fixedSize(horizontal: false, vertical: true)
                .foregroundColor(Design.Colors.Dark.textPrimary)
        }
        .padding(.vertical, 5)
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.Dark.glassBorder).frame(height: 0.5)
        }
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(value)
    }
}

private struct ScanStatusIdentity: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    let treeID: String
    let isRecording: Bool
    let duration: String

    var body: some View {
        HStack(alignment: .top, spacing: 12) {
            VStack(alignment: .leading, spacing: 3) {
                Text(treeID)
                    .font(.system(.headline, design: .monospaced).weight(.semibold))
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .lineLimit(dynamicTypeSize.isAccessibilitySize ? nil : 1)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                    .accessibilityLabel(L10n.ScanHUD.treeIdentifier(treeID))
                Text(L10n.ScanHUD.wholeTree)
                    .font(.system(.caption2, design: .default).weight(.semibold))
                    .tracking(0.6)
                    .textCase(.uppercase)
                    .foregroundColor(Design.Colors.Dark.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            VStack(alignment: .trailing, spacing: 4) {
                HStack(spacing: 6) {
                    Circle().fill(isRecording ? Design.Colors.Dark.error : Design.Colors.Dark.glow)
                        .frame(width: 6, height: 6)
                        .accessibilityHidden(true)
                    Text(isRecording ? L10n.ScanHUD.recording : L10n.ScanHUD.ready)
                        .font(.system(.caption, design: .default).weight(.medium))
                }
                .foregroundColor(Design.Colors.Dark.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                if isRecording {
                    Text(duration)
                        .font(.system(.caption, design: .monospaced))
                        .monospacedDigit()
                        .foregroundColor(Design.Colors.Dark.textPrimary)
                }
            }
        }
        .overlay(alignment: .bottom) {
            Rectangle().fill(Design.Colors.Dark.glassBorder).frame(height: 0.5)
        }
        .padding(.bottom, 10)
    }
}

private struct ScanStatusReadings: View {
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor
    let presentation: ScanStatusBarPresentation

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            if dynamicTypeSize.isAccessibilitySize {
                LazyVGrid(columns: [GridItem(.flexible(), alignment: .leading),
                                    GridItem(.flexible(), alignment: .leading)],
                          alignment: .leading, spacing: 12) {
                    metrics
                }
            } else {
                HStack(alignment: .top, spacing: 0) { metrics }
            }
        }
    }

    @ViewBuilder
    private var metrics: some View {
        ScanPrimaryStatusMetric(
            label: L10n.ScanHUD.coverage,
            value: "\(hudState.coveragePercent)%",
            meter: Double(hudState.coveragePercent) / 100.0,
            meterTint: presentation.coverageColor
        )
        ScanPrimaryStatusMetric(label: L10n.ScanHUD.fruitCount, value: "\(hudState.detectedFruitCount)")
        ScanPrimaryStatusMetric(label: L10n.ScanHUD.quality, value: qualityMonitor.getQualityStatus(),
                                signal: presentation.qualityColor)
        ScanPrimaryStatusMetric(label: L10n.ScanHUD.depth, value: presentation.depthStatusText,
                                signal: presentation.depthStatusColor)
    }
}

private struct ScanPrimaryStatusMetric: View {
    let label: String
    let value: String
    var signal: Color? = nil
    var meter: Double? = nil
    var meterTint: Color = Design.Colors.Dark.glow

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(label)
                .font(.system(.caption2, design: .default).weight(.semibold))
                .tracking(0.6)
                .textCase(.uppercase)
                .foregroundColor(Design.Colors.Dark.textMuted)
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 5) {
                if let signal {
                    Circle().fill(signal).frame(width: 5, height: 5).accessibilityHidden(true)
                }
                Text(value)
                    .font(.system(.title3, design: .default).weight(.semibold))
                    .monospacedDigit()
                    .foregroundColor(Design.Colors.Dark.textPrimary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            if let meter {
                // 覆盖度电平表：与读数同列，宽度即该列宽度。
                InstrumentMeter(
                    value: meter,
                    segments: 10,
                    tint: meterTint,
                    trackColor: Design.Colors.Dark.glassBorder,
                    height: 4,
                    cornerRadius: 1
                )
                .padding(.top, 3)
                .padding(.trailing, 4)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .accessibilityElement(children: .combine)
    }
}
