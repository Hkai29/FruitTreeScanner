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
            onRetryResultPersistence: retryResultPersistence,
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
            onRetryResultPersistence: retryResultPersistence,
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
        if coordinator.lifecycleSnapshot().state != .completed {
            coordinator.discardInterruptedScan()
            discardCurrentScanArtifacts()
        }
        finalizationWorkflow.resetForNewScan()
        yieldResult = nil
        showResult = false
        clearMeasurementState()
        createDirectory(folder: "scans")
        beginCoverageCompletionForNewScan()
        let plan = appDependencies.scanPlanFactory.makePlan(
            treeID: treeID,
            season: season,
            selectedCategory: selectedFruitCategory,
            renderer: coordinator.renderer
        )
        coordinator.startRecording(plan: plan)
        sessionModel.apply(coordinator.lifecycleSnapshot())
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
        sessionModel.apply(coordinator.lifecycleSnapshot())
        showGuide = false
    }

    func stopRecording() {
        coordinator.stopRecording()
        sessionModel.apply(coordinator.lifecycleSnapshot())
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
        if isRecording {
            stopRecording()
        }
        clearMeasurementState()
        coordinator.discardInterruptedScan()
        discardCurrentScanArtifacts()
        coordinator.teardown()
        dismiss()
    }

    func restartAfterInterruption() {
        guard scanReadiness == .ready else {
            showTemporaryNotice(scanReadiness.title)
            return
        }
        discardCurrentScanArtifacts()
        clearMeasurementState()
        finalizationWorkflow.resetForNewScan()
        let plan = appDependencies.scanPlanFactory.makePlan(
            treeID: treeID,
            season: season,
            selectedCategory: selectedFruitCategory,
            renderer: coordinator.renderer
        )
        let restarted = coordinator.restartInterruptedScan(plan: plan)
        sessionModel.apply(coordinator.lifecycleSnapshot())
        guard restarted else {
            showLifecycleRecovery = true
            showTemporaryNotice(L10n.Scan.sessionFailureTitle)
            return
        }
        beginCoverageCompletionForNewScan()
        showGuide = false
        showLifecycleRecovery = false
    }

    func discardAfterInterruption() {
        showLifecycleRecovery = false
        coordinator.discardInterruptedScan()
        discardCurrentScanArtifacts()
        coordinator.teardown()
        dismiss()
    }

}
