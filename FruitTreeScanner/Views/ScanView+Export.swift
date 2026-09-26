import SwiftUI

extension ScanView {
    func finishScan() {
        guard !isEstimating else { return }
        if lifecycleSnapshot.state == .finishing,
           let result = yieldResult,
           let identity = resultScanIdentity,
           identity == coordinator.lifecycleSnapshot().scanIdentity,
           !savedFilename.isEmpty {
            isEstimating = true
            let filename = savedFilename
            Task { @MainActor in
                await saveEstimatedResult(result, filename: filename, scanIdentity: identity)
            }
            return
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
        let scanIdentity = coordinator.lifecycleSnapshot().scanIdentity
        withAnimation(.easeInOut(duration: 0.2)) { isEstimating = true }
        coordinator.exportPLY(treeID: treeID, lat: gps.latitude, lon: gps.longitude) { filename in
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
                    await self.saveEstimatedResult(result, filename: filename, scanIdentity: scanIdentity)
                }
            }
        }
    }

    @MainActor
    func saveEstimatedResult(_ result: YieldResult, filename: String, scanIdentity: UUID) async {
        guard isViewActive,
              coordinator.lifecycleSnapshot().scanIdentity == scanIdentity,
              coordinator.lifecycleSnapshot().state == .finishing else { return }
        yieldResult = result
        resultScanIdentity = scanIdentity
        savedFilename = filename
        let didPersist = await persistScanResult(result: result, filename: filename)
        guard isViewActive,
              coordinator.lifecycleSnapshot().scanIdentity == scanIdentity,
              coordinator.lifecycleSnapshot().state == .finishing else { return }
        isEstimating = false
        if didPersist {
            ScanHistoryStore.shared.notifyRecordsUpdated()
            if let existing = TagStore.shared.getAssignment(treeId: treeID) {
                TagStore.shared.createOrUpdateAssignment(
                    treeId: treeID, plotId: existing.plotId, tagIds: existing.tagIds, status: .scanned
                )
            } else {
                TagStore.shared.createOrUpdateAssignment(
                    treeId: treeID, plotId: nil, tagIds: [], status: .scanned
                )
            }
            coordinator.markScanCompleted()
            lifecycleSnapshot = coordinator.lifecycleSnapshot()
            withAnimation(.easeInOut(duration: 0.3)) { showResult = true }
        } else {
            showResult = false
            showTemporaryNotice("结果保存失败，点击完成可重试保存，无需重新扫描")
        }
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
            return (Date(), gps.latitude, gps.longitude)
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
