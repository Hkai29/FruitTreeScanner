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
        lifecycleRecoveryPresentation.bind(
            acceptsRecovery: { acceptsLifecycleRecovery(scanIdentity: $0) },
            onRestart: { restartAfterInterruption(scanIdentity: $0) },
            onDiscard: { discardAfterInterruption(scanIdentity: $0) }
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
            guard isViewActive, snapshot == coordinator.lifecycleSnapshot() else { return }
            sessionModel.apply(snapshot)
            switch snapshot.state {
            case .systemInterrupted:
                finalizationWorkflow.cancel()
                pauseCoverageCompletion()
                clearMeasurementState()
                presentLifecycleRecovery()
            case .failed(let reason):
                finalizationWorkflow.cancel()
                pauseCoverageCompletion()
                clearMeasurementState()
                if reason.requiresCameraReadinessRecovery {
                    lifecycleRecoveryPresentation.dismiss()
                    refreshScanReadiness(showLifecycleRecoveryWhenReady: true)
                } else {
                    presentLifecycleRecovery()
                }
            case .recovering:
                finalizationWorkflow.cancel()
                pauseCoverageCompletion()
                clearMeasurementState()
                refreshScanReadiness()
                presentLifecycleRecovery()
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
        lifecycleRecoveryPresentation.invalidate()
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
                presentLifecycleRecovery()
            }
            if next != .ready {
                if shouldRecoverLifecycle {
                    lifecycleRecoveryPresentation.dismiss()
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
        let state = lifecycleRecoveryPresentation.presentation?.snapshot.state ?? lifecycleSnapshot.state
        if state == .failed(.invalidPointCloudCapture) {
            return L10n.Scan.pointCloudCaptureFailedTitle
        }
        if case .failed = state {
            return L10n.Scan.sessionFailureTitle
        }
        return L10n.Scan.interruptionTitle
    }

    var lifecycleAlertMessage: String {
        let state = lifecycleRecoveryPresentation.presentation?.snapshot.state ?? lifecycleSnapshot.state
        if state == .failed(.invalidPointCloudCapture) {
            return L10n.Scan.pointCloudCaptureFailedMessage
        }
        return L10n.Scan.interruptionMessage
    }

    func presentLifecycleRecovery() {
        let current = coordinator.lifecycleSnapshot()
        switch current.state {
        case .systemInterrupted, .recovering, .failed:
            lifecycleRecoveryPresentation.present(current)
        default:
            break
        }
    }

    func acceptsLifecycleRecovery(scanIdentity: UUID?) -> Bool {
        guard let scanIdentity, coordinator.lifecycleSnapshot().scanIdentity == scanIdentity else { return false }
        switch coordinator.lifecycleSnapshot().state {
        case .systemInterrupted, .recovering, .failed: return true
        default: return false
        }
    }

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
