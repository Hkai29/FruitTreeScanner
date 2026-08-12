import SwiftUI

extension ScanView {
    func handleAppear() {
        isViewActive = true
        refreshScanReadiness()
        coordinator.hudState = hudState
        coordinator.onCoveragePercentChange = handleCoveragePercentChange
        coordinator.onFruitCategoryMismatch = { mismatch in
            guard isViewActive else { return }
            categoryMismatch = mismatch
        }
        coordinator.onCalibrationWarning = { warning in
            guard isViewActive else { return }
            switch warning {
            case .recordsUnavailable:
                showTemporaryNotice(L10n.Scan.calibrationUnavailable)
            }
        }
        coordinator.onLifecycleStateChange = { snapshot in
            guard isViewActive else { return }
            lifecycleSnapshot = snapshot
            switch snapshot.state {
            case .systemInterrupted:
                isRecording = false
                isEstimating = false
                pauseCoverageCompletion()
                clearMeasurementState()
                showLifecycleRecovery = true
            case .failed(let reason):
                isRecording = false
                isEstimating = false
                pauseCoverageCompletion()
                clearMeasurementState()
                if reason.requiresCameraReadinessRecovery {
                    showLifecycleRecovery = false
                    refreshScanReadiness(showLifecycleRecoveryWhenReady: true)
                } else {
                    showLifecycleRecovery = true
                }
            case .recovering:
                isRecording = false
                isEstimating = false
                pauseCoverageCompletion()
                clearMeasurementState()
                refreshScanReadiness()
                showLifecycleRecovery = true
            default:
                break
            }
        }
        #if DEBUG
        coordinator.onDetectionDebugStateChange = { state in
            detectionDebugState = state
        }
        #endif
        coordinator.onMeasurementReady = { renderer in
            measurementController.renderer = renderer
        }
    }

    func handleDisappear() {
        isViewActive = false
        isEstimating = false
        invalidateTemporaryNotice()
        invalidateCoverageCompletion()
        clearMeasurementState()
        measurementController.renderer = nil
        coordinator.teardown()
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        switch phase {
        case .inactive:
            coordinator.handleSystemInterruption(.appInactive)
        case .background:
            coordinator.handleSystemInterruption(.appBackgrounded)
        case .active:
            coordinator.handleSessionInterruptionEnded()
        @unknown default:
            break
        }
        refreshScanReadinessWhenActive(phase)
    }

    func refreshScanReadiness(showLifecycleRecoveryWhenReady: Bool = false) {
        if showLifecycleRecoveryWhenReady {
            pendingLifecycleRecoveryAfterReadiness = true
        }
        guard !isCheckingScanReadiness else { return }
        isCheckingScanReadiness = true
        scanReadiness = .checking
        Task {
            let next = await ScanReadiness.determine()
            await MainActor.run {
                isCheckingScanReadiness = false
                guard isViewActive else {
                    pendingLifecycleRecoveryAfterReadiness = false
                    return
                }
                scanReadiness = next
                let shouldRecoverLifecycle = pendingLifecycleRecoveryAfterReadiness
                pendingLifecycleRecoveryAfterReadiness = false
                if next == .ready, shouldRecoverLifecycle {
                    showLifecycleRecovery = true
                }
                if next != .ready {
                    if shouldRecoverLifecycle {
                        showLifecycleRecovery = false
                    }
                    isRecording = false
                    pauseCoverageCompletion()
                    clearMeasurementState()
                    measurementController.renderer = nil
                    coordinator.teardown()
                }
            }
        }
    }

    func refreshScanReadinessWhenActive(_ phase: ScenePhase) {
        guard phase == .active else { return }
        guard !isEstimating && !showResult else { return }
        guard scanReadiness.blocksScanning || !isRecording else { return }
        refreshScanReadiness()
    }

    var lifecycleAlertTitle: String {
        if case .failed = lifecycleSnapshot.state {
            return L10n.Scan.sessionFailureTitle
        }
        return L10n.Scan.interruptionTitle
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
