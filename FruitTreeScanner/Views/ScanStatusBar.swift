// ScanStatusBar.swift
// 采集读数面板：深色仪器面板，浮在相机画面之上。

import SwiftUI

struct ScanStatusBar: View {
    let treeID: String
    let isRecording: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass
    @ScaledMetric(relativeTo: .body) private var metricFontSize: CGFloat = 16
    @ScaledMetric(relativeTo: .caption) private var metricLabelSize: CGFloat = 11

    private var isPad: Bool { horizontalSizeClass == .regular }

    private var layout: ScanStatusBarLayout {
        ScanStatusBarLayout(
            isPad: isPad,
            metricFontSize: metricFontSize,
            metricLabelSize: metricLabelSize,
            pillLabelSize: metricLabelSize,
            pillValueSize: metricFontSize,
            statusIconSize: isPad ? 12 : 10,
            statusLabelSize: isPad ? 13 : 12
        )
    }

    private var presentation: ScanStatusBarPresentation {
        ScanStatusBarPresentation(
            hudState: hudState,
            qualityMonitor: qualityMonitor
        )
    }

    var body: some View {
        Group {
            if isRecording {
                ScanRecordingStatusContent(
                    treeID: treeID,
                    hudState: hudState,
                    qualityMonitor: qualityMonitor,
                    presentation: presentation,
                    layout: layout
                )
            } else {
                ScanDetailedStatusContent(
                    treeID: treeID,
                    isRecording: isRecording,
                    hudState: hudState,
                    qualityMonitor: qualityMonitor,
                    presentation: presentation,
                    layout: layout
                )
            }
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 12)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .fill(Design.Colors.Dark.bgSurface.opacity(0.94))
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.medium, style: .continuous)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .frame(maxWidth: 760)
        .padding(.horizontal, 16)
        .padding(.top, 10)
    }
}
