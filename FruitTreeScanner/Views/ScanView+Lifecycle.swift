import SwiftUI

extension ScanView {
    func handleAppear() {
        isViewActive = true
        sessionModel.apply(coordinator.lifecycleSnapshot())
        finalizationWorkflow.onEvent = { [weak workflow = finalizationWorkflow] event in
            guard workflow != nil else { return }
            self.handleFinalizationEvent(event)
        }
        refreshScanReadiness()
        coordinator.hudState = hudState
        coordinator.onCoveragePercentChange = handleCoveragePercentChange
        categoryMismatchPresentation.bind(
            settings: appDependencies.settings,
            currentScanIdentity: { [weak coordinator = coordinator] in coordinator?.lifecycleSnapshot().scanIdentity },
            onStop: cancelScan
        )
        coordinator.onFruitCategoryMismatch = { mismatch in
            guard isViewActive else { return }
            categoryMismatchPresentation.present(mismatch, scanIdentity: coordinator.lifecycleSnapshot().scanIdentity)
        }
        coordinator.onCalibrationWarning = { warning in
            guard isViewActive else { return }
            switch warning {
            case .recordsUnavailable:
                showTemporaryNotice(L10n.Scan.calibrationUnavailable)
            case .modelMissing:
                showTemporaryNotice(L10n.Scan.modelMissing)
            case .modelIdentityUnavailable:
                showTemporaryNotice(L10n.Scan.modelIdentityUnavailable)
            }
        }
        coordinator.onLifecycleStateChange = { snapshot in
            guard isViewActive else { return }
            sessionModel.apply(snapshot)
            switch snapshot.state {
            case .systemInterrupted:
                finalizationWorkflow.cancel()
                pauseCoverageCompletion()
                clearMeasurementState()
                showLifecycleRecovery = true
            case .failed(let reason):
                finalizationWorkflow.cancel()
                pauseCoverageCompletion()
                clearMeasurementState()
                if reason.requiresCameraReadinessRecovery {
                    showLifecycleRecovery = false
                    refreshScanReadiness(showLifecycleRecoveryWhenReady: true)
                } else {
                    showLifecycleRecovery = true
                }
            case .recovering:
                finalizationWorkflow.cancel()
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
        categoryMismatchPresentation.invalidate()
        finalizationWorkflow.onEvent = nil
        cancelScanReadinessRequest(clearRecoveryRequest: true)
        invalidateTemporaryNotice()
        invalidateCoverageCompletion()
        if coordinator.lifecycleSnapshot().state != .completed {
            coordinator.discardInterruptedScan()
            discardCurrentScanArtifacts()
        }
        clearMeasurementState()
        measurementController.renderer = nil
        coordinator.teardown()
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        if phase != .active {
            cancelScanReadinessRequest(clearRecoveryRequest: false)
        }
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
        guard !readinessRequestController.isRunning else { return }
        scanReadiness = .checking
        readinessRequestController.start { next in
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
                let scanWasActive = lifecycleSnapshot.state == .recording
                    || lifecycleSnapshot.state == .userPaused
                    || lifecycleSnapshot.state == .finishing
                if scanWasActive {
                    pendingLifecycleRecoveryAfterReadiness = true
                }
                finalizationWorkflow.cancel()
                pauseCoverageCompletion()
                clearMeasurementState()
                measurementController.renderer = nil
                coordinator.teardownForReadinessBlock()
                sessionModel.apply(coordinator.lifecycleSnapshot())
            }
        }
    }

    private func cancelScanReadinessRequest(clearRecoveryRequest: Bool) {
        readinessRequestController.cancel()
        if clearRecoveryRequest {
            pendingLifecycleRecoveryAfterReadiness = false
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
