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
        case .exportPointCloud:
            exportAndEstimate()
            return
        case .persistResult:
            retryResultPersistence()
            return
        case .unavailable:
            break
        }
        guard canExportScan else {
            showTemporaryNotice(exportBlockedReason)
            return
        }
        if isRecording {
            stopRecording()
        }
        guard coordinator.beginFinishingScan() else {
            showTemporaryNotice(L10n.Scan.interruptionTitle)
            return
        }
        lifecycleSnapshot = coordinator.lifecycleSnapshot()
        exportAndEstimate()
    }

    func exportAndEstimate() {
        guard !isEstimating else { return }
        guard lifecycleSnapshot.state == .finishing else {
            showTemporaryNotice(L10n.Scan.interruptionTitle)
            return
        }

        clearMeasurementState()
        resultPersistenceState = .idle
        let scanIdentity = coordinator.lifecycleSnapshot().scanIdentity
        withAnimation(.easeInOut(duration: 0.2)) { isEstimating = true }
        let gpsSnapshot = gps.reliableLocationSnapshot()
        coordinator.exportPLY(
            treeID: treeID,
            lat: gpsSnapshot?.latitude ?? 0,
            lon: gpsSnapshot?.longitude ?? 0
        ) { filename in
            guard self.isViewActive,
                  self.coordinator.lifecycleSnapshot().scanIdentity == scanIdentity,
                  self.coordinator.lifecycleSnapshot().state == .finishing else {
                if let filename { self.discardScanArtifacts(filename: filename) }
                return
            }
            guard let filename else {
                self.isEstimating = false
                self.showTemporaryNotice(L10n.Scan.exportFailed)
                return
            }
            self.savedFilename = filename

            self.coordinator.runMultiModalYieldEstimate(season: season) { result, _ in
                Task { @MainActor in
                    guard self.isViewActive,
                          self.coordinator.lifecycleSnapshot().scanIdentity == scanIdentity,
                          self.coordinator.lifecycleSnapshot().state == .finishing else { return }
                    self.resultScanIdentity = scanIdentity
                    let didPersist = await self.persistScanResult(result: result, filename: filename)
                    guard self.isViewActive,
                          self.coordinator.lifecycleSnapshot().scanIdentity == scanIdentity,
                          self.coordinator.lifecycleSnapshot().state == .finishing else { return }

                    if !didPersist {
                        ScanHistoryStore.shared.notifyRecordsUpdated()
                    }

                    self.isEstimating = false
                    self.yieldResult = result
                    self.resultPersistenceState = .resolved(didPersist: didPersist)
                    if didPersist {
                        self.markResultPersistenceComplete()
                    }
                    withAnimation(.easeInOut(duration: 0.3)) { self.showResult = true }
                }
            }
        }
    }

    func retryResultPersistence() {
        guard resultPersistenceState == .failed,
              let result = yieldResult,
              !savedFilename.isEmpty,
              resultScanIdentity == coordinator.lifecycleSnapshot().scanIdentity,
              coordinator.lifecycleSnapshot().state == .finishing
        else { return }

        resultPersistenceState = .retrying
        let filename = savedFilename
        let scanIdentity = coordinator.lifecycleSnapshot().scanIdentity
        Task { @MainActor in
            let didPersist = await persistScanResult(result: result, filename: filename)
            guard isViewActive,
                  coordinator.lifecycleSnapshot().scanIdentity == scanIdentity,
                  resultScanIdentity == scanIdentity,
                  coordinator.lifecycleSnapshot().state == .finishing else { return }

            resultPersistenceState = .resolved(didPersist: didPersist)
            if didPersist {
                markResultPersistenceComplete()
                showTemporaryNotice(L10n.ScanResultPersistence.text(.successNotice))
            } else {
                ScanHistoryStore.shared.notifyRecordsUpdated()
                showTemporaryNotice(L10n.ScanResultPersistence.text(.failureNotice))
            }
        }
    }

    private func markResultPersistenceComplete() {
        coordinator.markScanCompleted()
        lifecycleSnapshot = coordinator.lifecycleSnapshot()
    }

    @MainActor
    func persistScanResult(result: YieldResult, filename: String) async -> Bool {
        let includeCSV = SettingsStore.shared.autoExportCSV
        let scanMetadata = savedScanMetadata(for: filename)
        let request = ScanResultExportService.ExportRequest(
            treeID: treeID,
            fruitType: selectedFruitCategory.rawValue,
            scanDate: scanMetadata.scanDate,
            gpsLat: scanMetadata.gpsLat,
            gpsLon: scanMetadata.gpsLon,
            sourceFilename: filename,
            result: result,
            includeCSV: includeCSV
        )

        do {
            _ = try await Task.detached(priority: .utility) {
                try ScanResultExportService.shared.exportIfNeeded(request)
            }.value
            return true
        } catch {
            Log.export.error("Failed to persist scan result: \(error.localizedDescription)")
            return false
        }
    }

    func savedScanMetadata(for filename: String) -> (scanDate: Date, gpsLat: Double, gpsLon: Double) {
        let fileURL = getDocumentsDirectory()
            .appendingPathComponent("scans", isDirectory: true)
            .appendingPathComponent(filename)
        guard let parsed = PLYParserHelper.parsePLYFile(at: fileURL) else {
            let gpsSnapshot = gps.reliableLocationSnapshot()
            return (
                Date(),
                gpsSnapshot?.latitude ?? 0,
                gpsSnapshot?.longitude ?? 0
            )
        }
        return (parsed.scanDate, parsed.gpsLat, parsed.gpsLon)
    }

    func discardCurrentScanArtifacts() {
        guard coordinator.lifecycleSnapshot().state != .completed,
              !savedFilename.isEmpty else { return }
        discardScanArtifacts(filename: savedFilename)
        savedFilename = ""
        resultScanIdentity = nil
    }

    func discardScanArtifacts(filename: String) {
        Task.detached(priority: .utility) {
            do {
                try ScanResultExportService.shared.discardScanArtifacts(sourceFilename: filename)
                await ScanHistoryStore.shared.notifyRecordsUpdated()
            } catch {
                Log.export.error("Failed to discard scan artifacts for \(filename): \(error.localizedDescription)")
            }
        }
    }
}
