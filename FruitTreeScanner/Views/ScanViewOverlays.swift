import SwiftUI

struct ScanScannerInterfaceActions {
    let onCloseGuide: () -> Void
    let onStartRecording: () -> Void
    let onToggleGuide: () -> Void
    let onToggleRecording: () -> Void
    let onToggleMeasurement: () -> Void
    let onRequestCancelScan: () -> Void
    let onResumeRecording: () -> Void
    let onFinishScan: () -> Void
    let onClearMeasurement: () -> Void
    let onRetryResultPersistence: () -> Void
    let onDismissResult: () -> Void
    let onDismissResultToHome: () -> Void
    let onDebug: (() -> Void)?

    init(
        onCloseGuide: @escaping () -> Void,
        onStartRecording: @escaping () -> Void,
        onToggleGuide: @escaping () -> Void,
        onToggleRecording: @escaping () -> Void,
        onToggleMeasurement: @escaping () -> Void,
        onRequestCancelScan: @escaping () -> Void,
        onResumeRecording: @escaping () -> Void,
        onFinishScan: @escaping () -> Void,
        onClearMeasurement: @escaping () -> Void,
        onRetryResultPersistence: @escaping () -> Void,
        onDismissResult: @escaping () -> Void,
        onDismissResultToHome: @escaping () -> Void,
        onDebug: (() -> Void)? = nil
    ) {
        self.onCloseGuide = onCloseGuide
        self.onStartRecording = onStartRecording
        self.onToggleGuide = onToggleGuide
        self.onToggleRecording = onToggleRecording
        self.onToggleMeasurement = onToggleMeasurement
        self.onRequestCancelScan = onRequestCancelScan
        self.onResumeRecording = onResumeRecording
        self.onFinishScan = onFinishScan
        self.onClearMeasurement = onClearMeasurement
        self.onRetryResultPersistence = onRetryResultPersistence
        self.onDismissResult = onDismissResult
        self.onDismissResultToHome = onDismissResultToHome
        self.onDebug = onDebug
    }
}

struct ScanScannerInterfaceLayer: View {
    let treeID: String
    let scanReadiness: ScanReadiness
    let isRecording: Bool
    let isEstimating: Bool
    let canExportScan: Bool
    let shouldShowPostCapturePanel: Bool
    let showGuide: Bool
    let showResult: Bool
    let showCoverageComplete: Bool
    let yieldResult: YieldResult?
    let resultPersistenceState: ScanResultPersistenceState
    let detectionDebugState: DetectionDebugState?

    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var qualityMonitor: ScanQualityMonitor
    @ObservedObject var measurementController: MetalMeasurementController
    @Binding var measuredDistance: Float?

    let actions: ScanScannerInterfaceActions

    var body: some View {
        if !scanReadiness.blocksScanning {
            #if DEBUG
            if let detectionDebugState {
                DetectionDebugOverlayView(state: detectionDebugState)
                    .ignoresSafeArea()
                    .allowsHitTesting(false)
            }
            #endif

            ScanStatusLayer(
                treeID: treeID,
                isRecording: isRecording,
                hudState: hudState,
                qualityMonitor: qualityMonitor
            )

            ScanGuidanceOverlay(hudState: hudState, isRecording: isRecording)

            ScanMeasurementLayer(
                measurementController: measurementController,
                measuredDistance: $measuredDistance,
                onClearMeasurement: actions.onClearMeasurement
            )

            ScanControlLayer(
                isRecording: isRecording,
                isEstimating: isEstimating,
                canExportScan: canExportScan,
                shouldShowPostCapturePanel: shouldShowPostCapturePanel,
                hudState: hudState,
                measurementController: measurementController,
                actions: actions
            )

            if showGuide {
                ScanFieldGuideOverlay(
                    onClose: actions.onCloseGuide,
                    onStartScan: actions.onStartRecording
                )
            }

            ScanResultLayer(
                treeID: treeID,
                showResult: showResult,
                yieldResult: yieldResult,
                resultPersistenceState: resultPersistenceState,
                onRetryResultPersistence: actions.onRetryResultPersistence,
                onDismissResult: actions.onDismissResult,
                onDismissResultToHome: actions.onDismissResultToHome
            )

            if isEstimating {
                ScanEstimatingOverlay()
            }

            if showCoverageComplete {
                ScanCoverageCompleteToast()
                    .animation(.easeInOut(duration: 0.3), value: showCoverageComplete)
            }
        }
    }
}
