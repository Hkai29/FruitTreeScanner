import SwiftUI

extension ScanView {
    var scannerInterfaceActions: ScanScannerInterfaceActions {
        #if DEBUG
        return ScanScannerInterfaceActions(
            onCloseGuide: closeGuide,
            onStartRecording: startRecording,
            onToggleGuide: toggleGuide,
            onToggleRecording: toggleRecording,
            onToggleMeasurement: toggleMeasurement,
            onRequestCancelScan: requestCancelScan,
            onResumeRecording: resumeRecording,
            onFinishScan: finishScan,
            onClearMeasurement: clearMeasurementState,
            onDismissResult: dismissResult,
            onDismissResultToHome: dismissResultToHome,
            onDebug: showDebugSnapshot
        )
        #else
        return ScanScannerInterfaceActions(
            onCloseGuide: closeGuide,
            onStartRecording: startRecording,
            onToggleGuide: toggleGuide,
            onToggleRecording: toggleRecording,
            onToggleMeasurement: toggleMeasurement,
            onRequestCancelScan: requestCancelScan,
            onResumeRecording: resumeRecording,
            onFinishScan: finishScan,
            onClearMeasurement: clearMeasurementState,
            onDismissResult: dismissResult,
            onDismissResultToHome: dismissResultToHome
        )
        #endif
    }

    func closeGuide() {
        showGuide = false
    }

    func toggleGuide() {
        showGuide.toggle()
    }

    func dismissResult() {
        onScanNextTree()
    }

    func dismissResultToHome() {
        showResult = false
        dismiss()
    }

    func handleCoveragePercentChange(_ newValue: Int) {
        guard newValue >= 85, isRecording else { return }
        presentCoverageCompletionIfNeeded()
    }

    func toggleMeasurement() {
        guard !isEstimating else { return }
        if hudState.pointCount == 0 && !measurementController.isActive {
            showTemporaryNotice(L10n.Scan.noPointCloud)
            return
        }
        if measurementController.isActive {
            clearMeasurementState()
        } else {
            measurementController.activate()
        }
    }

    func clearMeasurementState() {
        measurementController.deactivate()
        measuredDistance = nil
    }

    #if DEBUG
    func showDebugSnapshot() {
        detectionDebugState = coordinator.detectionDebugSnapshot()
        showDebugView = true
    }
    #endif

    func toggleRecording() {
        guard !isEstimating else { return }
        if isRecording {
            stopRecording()
        } else {
            startRecording()
        }
    }

    func startRecording() {
        guard !isEstimating else { return }
        guard scanReadiness == .ready else {
            showTemporaryNotice(scanReadiness.title)
            return
        }
        clearMeasurementState()
        createDirectory(folder: "scans")
        beginCoverageCompletionForNewScan()
        coordinator.startRecording(selectedCategory: selectedFruitCategory)
        lifecycleSnapshot = coordinator.lifecycleSnapshot()
        isRecording = true
        showGuide = false
    }

    func resumeRecording() {
        guard !isEstimating else { return }
        guard scanReadiness == .ready else {
            showTemporaryNotice(scanReadiness.title)
            return
        }
        guard lifecycleSnapshot.state == .userPaused else {
            showTemporaryNotice(L10n.Scan.interruptionTitle)
            return
        }
        guard coordinator.pointCount > 0 || hudState.pointCount > 0 else {
            startRecording()
            return
        }
        clearMeasurementState()
        createDirectory(folder: "scans")
        coordinator.resumeRecordingPreservingCapture()
        lifecycleSnapshot = coordinator.lifecycleSnapshot()
        isRecording = true
        showGuide = false
    }

    func stopRecording() {
        coordinator.stopRecording()
        lifecycleSnapshot = coordinator.lifecycleSnapshot()
        isRecording = false
        pauseCoverageCompletion()
    }

    func requestCancelScan() {
        guard !isEstimating else { return }
        if isRecording || coordinator.pointCount > 0 || hudState.pointCount > 0 {
            showCancelConfirmation = true
        } else {
            cancelScan()
        }
    }

    func cancelScan() {
        isEstimating = false
        if isRecording {
            stopRecording()
        }
        clearMeasurementState()
        coordinator.discardInterruptedScan()
        coordinator.teardown()
        dismiss()
    }

    func restartAfterInterruption() {
        guard scanReadiness == .ready else {
            showTemporaryNotice(scanReadiness.title)
            return
        }
        clearMeasurementState()
        let restarted = coordinator.restartInterruptedScan(
            selectedCategory: selectedFruitCategory
        )
        lifecycleSnapshot = coordinator.lifecycleSnapshot()
        guard restarted else {
            isRecording = false
            showLifecycleRecovery = true
            showTemporaryNotice(L10n.Scan.sessionFailureTitle)
            return
        }
        beginCoverageCompletionForNewScan()
        isRecording = true
        showGuide = false
        showLifecycleRecovery = false
    }

    func discardAfterInterruption() {
        showLifecycleRecovery = false
        isEstimating = false
        coordinator.discardInterruptedScan()
        coordinator.teardown()
        dismiss()
    }

    func showTemporaryNotice(_ message: String) {
        withAnimation(.easeInOut(duration: 0.2)) {
            scanNotice = message
        }
        DispatchQueue.main.asyncAfter(deadline: .now() + 2.2) {
            guard isViewActive else { return }
            guard scanNotice == message else { return }
            withAnimation(.easeInOut(duration: 0.2)) {
                scanNotice = nil
            }
        }
    }
}
