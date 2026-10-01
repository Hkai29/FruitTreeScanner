import SwiftUI

enum ScanResultPersistenceState: Equatable {
    case idle
    case saved
    case failed
    case retrying

    static func resolved(didPersist: Bool) -> Self {
        didPersist ? .saved : .failed
    }

    var showsRecovery: Bool {
        self == .failed || self == .retrying
    }

    var isRetrying: Bool {
        self == .retrying
    }

    var blocksResultDismissal: Bool {
        isRetrying
    }
}

extension ScanView {
    func finishScan() {
        guard !isEstimating else { return }
        switch exportRetryAction {
        case .exportPointCloud, .estimateYield, .persistResult:
            finalizationWorkflow.retry()
            return
        case .unavailable:
            break
        }
        guard canExportScan else {
            showTemporaryNotice(exportBlockedReason)
            return
        }
        guard let plan = coordinator.activeScanPlan else {
            showTemporaryNotice(L10n.Scan.interruptionTitle)
            return
        }
        clearMeasurementState()
        resultPersistenceState = .idle
        yieldResult = nil
        let gpsSnapshot = gps.reliableLocationSnapshot()
        pauseCoverageCompletion()
        finalizationWorkflow.finish(
            plan: plan,
            latitude: gpsSnapshot?.latitude ?? 0,
            longitude: gpsSnapshot?.longitude ?? 0,
            operations: .production(coordinator: coordinator, repository: appDependencies.scanRepository)
        )
        sessionModel.apply(coordinator.lifecycleSnapshot())
    }

    func retryResultPersistence() {
        finalizationWorkflow.retry()
    }

    func handleFinalizationEvent(_ event: ScanFinalizationWorkflow.Event) {
        switch event {
        case .phaseChanged(let phase):
            if case .exportingPointCloud = phase {
                pauseCoverageCompletion()
            }
            if case .persisting = phase, resultPersistenceState == .failed {
                resultPersistenceState = .retrying
            }
        case .pointCloudExported(_, _):
            resultPersistenceState = .idle
        case .estimateProduced(_, let result):
            yieldResult = result
        case .completed(_, _, let result):
            sessionModel.apply(coordinator.lifecycleSnapshot())
            yieldResult = result
            resultPersistenceState = .saved
            withAnimation(.easeInOut(duration: 0.3)) { showResult = true }
        case .failed(_, let failure):
            switch failure {
            case .lifecycleRejected:
                showTemporaryNotice(L10n.Scan.interruptionTitle)
            case .pointCloudExport:
                showTemporaryNotice(L10n.Scan.exportFailed)
            case .yieldEstimation:
                showTemporaryNotice(L10n.Scan.estimateFailed)
            case .resultPersistence:
                yieldResult = finalizationWorkflow.result
                resultPersistenceState = .failed
                withAnimation(.easeInOut(duration: 0.3)) { showResult = true }
            }
        case .cancelled:
            break
        }
    }

    func discardCurrentScanArtifacts() {
        guard coordinator.lifecycleSnapshot().state != .completed else { return }
        finalizationWorkflow.cancel()
    }
}
