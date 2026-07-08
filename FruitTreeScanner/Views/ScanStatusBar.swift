import SwiftUI

struct ScanStatusBar: View {
    let treeID: String
    let isRecording: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    private var isPad: Bool { horizontalSizeClass == .regular }

    private var layout: ScanStatusBarLayout {
        ScanStatusBarLayout(
            isPad: isPad,
            metricFontSize: isPad ? 14 : 12,
            metricLabelSize: isPad ? 11 : 9,
            pillLabelSize: isPad ? 12 : 10,
            pillValueSize: isPad ? 16 : 14,
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
        .padding(.horizontal, isPad ? 14 : 10)
        .padding(.vertical, isPad ? 14 : 10)
        .background(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .fill(Design.Colors.Dark.hudBackground)
        )
        .overlay(
            RoundedRectangle(cornerRadius: Design.Radius.Glass.medium)
                .stroke(Design.Colors.Dark.glassBorder, lineWidth: 1)
        )
        .padding(.horizontal, Design.Space.md)
        .padding(.top, Design.Space.md)
    }
}
