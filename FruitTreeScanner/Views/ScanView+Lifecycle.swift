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
        clearMeasurementState()
        measurementController.renderer = nil
        coordinator.teardown()
    }

    func handleScenePhaseChange(_ phase: ScenePhase) {
        refreshScanReadinessWhenActive(phase)
    }

    func refreshScanReadiness() {
        guard !isCheckingScanReadiness else { return }
        isCheckingScanReadiness = true
        scanReadiness = .checking
        Task {
            let next = await ScanReadiness.determine()
            await MainActor.run {
                isCheckingScanReadiness = false
                guard isViewActive else { return }
                scanReadiness = next
                if next != .ready {
                    isRecording = false
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

    func openAppSettings() {
        guard let url = URL(string: UIApplication.openSettingsURLString) else { return }
        UIApplication.shared.open(url)
    }
}
