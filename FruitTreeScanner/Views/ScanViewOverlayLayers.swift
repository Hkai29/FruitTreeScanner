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
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    let isRecording: Bool
    let isEstimating: Bool
    let canExportScan: Bool
    let shouldShowPostCapturePanel: Bool
    @ObservedObject var hudState: ScanHUDState
    @ObservedObject var measurementController: MetalMeasurementController
    let actions: ScanScannerInterfaceActions
    var treeID: String? = nil
    var qualityMonitor: ScanQualityMonitor? = nil
    var showCoverageComplete = false
    var notice: String? = nil

    var body: some View {
        if !measurementController.isActive {
            GeometryReader { geometry in
                VStack(spacing: 12) {
                    ScrollViewReader { proxy in
                        ScrollView {
                            scanInformation(in: geometry)
                        }
                        .task {
                            if notice != nil {
                                proxy.scrollTo("scan.notice", anchor: .bottom)
                            } else if showCoverageComplete {
                                proxy.scrollTo("scan.coverage", anchor: .bottom)
                            }
                        }
                        .onChange(of: notice) { value in
                            guard value != nil else { return }
                            if reduceMotion {
                                proxy.scrollTo("scan.notice", anchor: .bottom)
                            } else {
                                withAnimation { proxy.scrollTo("scan.notice", anchor: .bottom) }
                            }
                        }
                        .onChange(of: hudState.guidanceHint) { hint in
                            guard isRecording, hint != .none, hint != .goodPace else { return }
                            if reduceMotion {
                                proxy.scrollTo("scan.guidance", anchor: .top)
                            } else {
                                withAnimation { proxy.scrollTo("scan.guidance", anchor: .top) }
                            }
                        }
                        .onChange(of: showCoverageComplete) { shown in
                            guard shown else { return }
                            if reduceMotion {
                                proxy.scrollTo("scan.coverage", anchor: .bottom)
                            } else {
                                withAnimation { proxy.scrollTo("scan.coverage", anchor: .bottom) }
                            }
                        }
                    }
                    .clipped()
                    .accessibilityIdentifier(shouldShowPostCapturePanel ? "scan.paused.summary" : "scan.live.summary")
                    bottomControls.fixedSize(horizontal: false, vertical: true)
                }
                .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .bottom)
                .animation(reduceMotion ? nil : .easeInOut(duration: 0.3), value: showCoverageComplete)
            }
        }
    }

    private func scanInformation(in geometry: GeometryProxy) -> some View {
        VStack(spacing: 12) {
            if guidanceComesFirst(in: geometry) {
                guidance
            }
            if let treeID, let qualityMonitor {
                ScanStatusBar(treeID: treeID, isRecording: isRecording,
                              hudState: hudState, qualityMonitor: qualityMonitor)
            }
            if !guidanceComesFirst(in: geometry) {
                guidance
            }
            if let notice {
                // 末尾留出空隙：自动滚动后提示仍然完全落在可视区内，而不是贴着下边缘。
                VStack(spacing: 0) {
                    ScanNoticeToast(message: notice)
                    Color.clear.frame(height: 24)
                }
                .id("scan.notice")
            }
            if showCoverageComplete {
                VStack(spacing: 0) {
                    ScanCoverageCompleteToast()
                    Color.clear.frame(height: 24)
                }
                .id("scan.coverage")
            }
            if shouldShowPostCapturePanel {
                if !dynamicTypeSize.isAccessibilitySize && geometry.size.height > geometry.size.width {
                    Color.clear.frame(height: geometry.size.height * 0.18)
                        .accessibilityHidden(true)
                }
                ScanPostCapturePanel(
                    pointCount: hudState.pointCount,
                    coveragePercent: hudState.coveragePercent,
                    completion: hudState.scanCompletion,
                    canFinish: canExportScan,
                    onResume: actions.onResumeRecording,
                    onFinish: actions.onFinishScan,
                    showsActions: false
                )
            }
        }
        .padding(.bottom, 12)
    }

    private var guidance: some View {
        ScanGuidanceOverlay(hudState: hudState, isRecording: isRecording)
            .id("scan.guidance")
    }

    private func guidanceComesFirst(in geometry: GeometryProxy) -> Bool {
        dynamicTypeSize.isAccessibilitySize || geometry.size.width > geometry.size.height
    }

    private var bottomControls: some View {
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
                    onResume: shouldShowPostCapturePanel ? actions.onResumeRecording : nil,
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
                    onFinish: actions.onFinishScan,
                    onResume: shouldShowPostCapturePanel ? actions.onResumeRecording : nil
                )
            #endif
    }
}

struct ScanResultLayer: View {
    let treeID: String
    let showResult: Bool
    let yieldResult: YieldResult?
    let resultPersistenceState: ScanResultPersistenceState
    let onRetryResultPersistence: () -> Void
    let onDismissResult: () -> Void
    let onDismissResultToHome: () -> Void
    @ObservedObject var tagStore = TagStore.shared

    var body: some View {
        if showResult, let result = yieldResult {
            ResultView(
                treeID: treeID,
                result: result,
                persistenceState: resultPersistenceState,
                onRetryPersistence: onRetryResultPersistence,
                onDismiss: onDismissResult,
                onDismissToHome: onDismissResultToHome,
                tagStore: tagStore
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
