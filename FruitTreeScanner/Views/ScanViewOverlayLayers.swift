import SwiftUI

struct ScanStatusLayer: View {
    let treeID: String
    let isRecording: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor

    var body: some View {
        VStack {
            ScanStatusBar(
                treeID: treeID,
                isRecording: isRecording,
                hudState: hudState,
                qualityMonitor: qualityMonitor
            )
            Spacer()
        }
    }
}

struct ScanMeasurementLayer: View {
    @ObservedObject var measurementController: MetalMeasurementController
    @Binding var measuredDistance: Float?
    let onClearMeasurement: () -> Void

    var body: some View {
        if measurementController.isActive {
            MetalMeasurementOverlay(
                controller: measurementController,
                measuredDistance: $measuredDistance,
                onClose: onClearMeasurement
            )
        }
    }
}

struct ScanControlLayer: View {
    let isRecording: Bool
    let isEstimating: Bool
    let canExportScan: Bool
    let shouldShowPostCapturePanel: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var measurementController: MetalMeasurementController
    let actions: ScanScannerInterfaceActions

    var body: some View {
        VStack {
            Spacer()

            if isRecording {
                ScanCoverageHintBar(hudState: hudState)
                    .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            if shouldShowPostCapturePanel {
                ScanPostCapturePanel(
                    pointCount: hudState.pointCount,
                    coveragePercent: hudState.coveragePercent,
                    completion: hudState.scanCompletion,
                    canFinish: canExportScan,
                    onResume: actions.onResumeRecording,
                    onFinish: actions.onFinishScan
                )
                .transition(.move(edge: .bottom).combined(with: .opacity))
            }

            #if DEBUG
                ScanBottomControlBar(
                    isRecording: isRecording,
                    isEstimating: isEstimating,
                    canFinish: canExportScan,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: actions.onToggleGuide,
                    onToggleRecording: actions.onToggleRecording,
                    onToggleMeasurement: actions.onToggleMeasurement,
                    onCancel: actions.onRequestCancelScan,
                    onFinish: actions.onFinishScan,
                    onDebug: actions.onDebug ?? {}
                )
            #else
                ScanBottomControlBar(
                    isRecording: isRecording,
                    isEstimating: isEstimating,
                    canFinish: canExportScan,
                    hudState: hudState,
                    measurementController: measurementController,
                    onToggleGuide: actions.onToggleGuide,
                    onToggleRecording: actions.onToggleRecording,
                    onToggleMeasurement: actions.onToggleMeasurement,
                    onCancel: actions.onRequestCancelScan,
                    onFinish: actions.onFinishScan
                )
            #endif
        }
    }
}

struct ScanResultLayer: View {
    let treeID: String
    let showResult: Bool
    let yieldResult: YieldResult?
    let onDismissResult: () -> Void
    let onDismissResultToHome: () -> Void

    var body: some View {
        if showResult, let result = yieldResult {
            ResultView(
                treeID: treeID,
                result: result,
                onDismiss: onDismissResult,
                onDismissToHome: onDismissResultToHome
            )
            .transition(.move(edge: .bottom).combined(with: .opacity))
        }
    }
}

struct ScanEstimatingOverlay: View {
    var body: some View {
        Color.black.opacity(0.5)
            .transition(.opacity)

        VStack(spacing: 16) {
            ProgressView()
                .scaleEffect(1.5)
                .tint(Design.Colors.harvest)

            Text(L10n.Scan.estimating)
                .font(.system(size: 15, weight: .medium))
                .foregroundColor(.white)
        }
        .transition(.scale(scale: 0.9).combined(with: .opacity))
    }
}
