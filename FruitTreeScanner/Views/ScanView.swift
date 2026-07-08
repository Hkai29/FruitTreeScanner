// ScanView.swift
// 扫描主界面 + 产量估算（扫描停止后自动触发）

import SwiftUI

struct ScanView: View {
    let treeID: String
    @ObservedObject var gps: GPSRecorder
    let season: Season

    @State var coordinator = ScanCoordinator()
    @StateObject var hudState = ScanHUDState()
    @StateObject var qualityMonitor = ScanQualityMonitor()
    @StateObject var measurementController = MetalMeasurementController()
    @Environment(\.dismiss) var dismiss
    @Environment(\.scenePhase) private var scenePhase

    @State var isRecording = false
    @State var showGuide = true
    @State var savedFilename = ""
    @State var yieldResult: YieldResult? = nil
    @State var showResult = false
    @State var isEstimating = false
    @State var showCoverageComplete = false
    @State var hasShownCoverageComplete = false
    #if DEBUG
    @State var showDebugView = false
    @State var detectionDebugState = DetectionDebugState(
        currentThreshold: DetectionDebugConfiguration.defaultThreshold
    )
    #endif
    @State var measuredDistance: Float?
    @State var scanNotice: String?
    @State var isViewActive = false
    @State var scanReadiness: ScanReadiness = .checking
    @State var isCheckingScanReadiness = false
    @State var showCancelConfirmation = false

    var body: some View {
        ZStack {
            ScanRenderLayer(
                scanReadiness: scanReadiness,
                coordinator: coordinator,
                qualityMonitor: qualityMonitor
            )

            ScanScannerInterfaceLayer(
                treeID: treeID,
                scanReadiness: scanReadiness,
                isRecording: isRecording,
                isEstimating: isEstimating,
                canExportScan: canExportScan,
                shouldShowPostCapturePanel: shouldShowPostCapturePanel,
                showGuide: showGuide,
                showResult: showResult,
                showCoverageComplete: showCoverageComplete,
                yieldResult: yieldResult,
                detectionDebugState: currentDetectionDebugState,
                hudState: hudState,
                qualityMonitor: qualityMonitor,
                measurementController: measurementController,
                measuredDistance: $measuredDistance,
                actions: scannerInterfaceActions
            )

            ScanReadinessOverlay(
                scanReadiness: scanReadiness,
                onOpenSettings: openAppSettings,
                onDismiss: requestCancelScan
            )

            if let scanNotice {
                ScanNoticeToast(message: scanNotice)
            }
        }
        .onAppear(perform: handleAppear)
        .onDisappear(perform: handleDisappear)
        .onChange(of: scenePhase) { phase in
            handleScenePhaseChange(phase)
        }
        #if DEBUG
            .sheet(isPresented: $showDebugView) {
                DetectionDebugView(
                    state: detectionDebugState,
                    onExport: { try coordinator.imageDetector.exportFailureSamplesFile() }
                )
            }
        #endif
            .alert("取消本次扫描？", isPresented: $showCancelConfirmation) {
                Button("继续扫描", role: .cancel) {}
                Button("放弃", role: .destructive) {
                    cancelScan()
                }
            } message: {
                Text("已采集的点云不会保存。若要保留本次采集，请点击完成。")
            }
    }

}
