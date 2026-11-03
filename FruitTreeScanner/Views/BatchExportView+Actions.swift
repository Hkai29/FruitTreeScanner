import Foundation

enum BatchExportShareCompletionPolicy {
    static func shouldPresentFailure(
        for result: ShareActivityResult,
        sharedURL: URL,
        currentExportURL: URL?
    ) -> Bool {
        guard ScanShareFailurePolicy.isFailure(result), let currentExportURL else { return false }
        return sharedURL.standardizedFileURL == currentExportURL.standardizedFileURL
    }
}

extension BatchExportView {
    func handleAppear() {
        store.loadRecords()
        selectAllIfNeeded()
    }

    func handleRecordsChanged(_ files: [ScanFileRecord]) {
        handleExportSourceChanged()
        pruneSelection(to: files)
        selectAllIfNeeded()
    }

    func handleExportSourceChanged() {
        if isExporting {
            cancelExport()
        }
        clearExportedFile()
    }

    func handleDisappear() {
        cancelExport()
        clearExportedFile()
    }

    func handlePrimaryExportAction() {
        if isExporting {
            cancelExport()
        } else {
            performExport()
        }
    }

    func showExportShareSheet() {
        guard let exportedURL else { return }
        presentedSheet = .share(exportedURL)
    }

    func handleShareCompletion(_ result: ShareActivityResult, for sharedURL: URL) {
        guard BatchExportShareCompletionPolicy.shouldPresentFailure(
            for: result,
            sharedURL: sharedURL,
            currentExportURL: exportedURL
        ) else { return }

        Log.export.error(
            "Batch export sharing failed: \(result.errorDescription ?? "Unknown activity error")"
        )
        showShareError = true
    }

    func toggleSelection(_ id: String) {
        guard !isExporting, exportableRecordIDs.contains(id) else { return }
        clearExportedFile()
        if selectedRecords.contains(id) {
            selectedRecords.remove(id)
        } else {
            selectedRecords.insert(id)
        }
    }

    func toggleSelectAll() {
        guard !isExporting else { return }
        clearExportedFile()
        if selectedRecords == exportableRecordIDs {
            selectedRecords.removeAll()
        } else {
            selectedRecords = exportableRecordIDs
        }
    }

    func performExport() {
        workflow.start(makeExportRequestSnapshot(), currentRequest: exportRequestReader())
    }

    func makeExportRequestSnapshot() -> BatchExportRequestSnapshot {
        Self.makeExportRequestSnapshot(
            records: store.scanFiles,
            selectedRecordIDs: selectedRecords,
            format: exportFormat,
            options: exportOptions,
            plotNames: plotNameByTreeID()
        )
    }

    static func makeExportRequestSnapshot(
        records: [ScanFileRecord],
        selectedRecordIDs: Set<String>,
        format: BatchExportService.ExportFormat,
        options: BatchExportService.ExportOptions,
        plotNames: [String: String]
    ) -> BatchExportRequestSnapshot {
        var options = options
        options.plotNameByTreeID = plotNames
        return BatchExportRequestSnapshot(
            records: records,
            selectedRecordIDs: selectedRecordIDs,
            format: format,
            options: options
        )
    }

    func cancelExport() {
        workflow.cancel()
    }

    func clearExportedFile() {
        guard exportedURL != nil else { return }
        workflow.clearExportedFile()
        presentedSheet = nil
    }

    func pruneSelection(to files: [ScanFileRecord]) {
        let normalizedSelection = BatchExportSelectionPolicy.normalizedSelection(
            selectedRecords,
            for: files
        )
        if normalizedSelection != selectedRecords {
            clearExportedFile()
            selectedRecords = normalizedSelection
        }
    }

    func selectAllIfNeeded() {
        guard selectedRecords.isEmpty, !exportableRecordIDs.isEmpty else { return }
        selectedRecords = exportableRecordIDs
    }

    func plotNameByTreeID() -> [String: String] {
        Self.plotNameByTreeID(tagStore: tagStore)
    }

    static func plotNameByTreeID(tagStore: TagStore) -> [String: String] {
        let plotNameByID = Dictionary(uniqueKeysWithValues: tagStore.plots.map { ($0.id, $0.name) })
        return Dictionary(uniqueKeysWithValues: tagStore.assignments.compactMap { assignment in
            guard let plotId = assignment.plotId,
                  let plotName = plotNameByID[plotId]
            else { return nil }
            return (assignment.treeId, plotName)
        })
    }
}
