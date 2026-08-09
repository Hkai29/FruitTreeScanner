import Foundation

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
        let requestSnapshot = makeExportRequestSnapshot()
        guard !requestSnapshot.records.isEmpty else { return }

        exportTask?.cancel()
        exportGeneration += 1
        let generation = exportGeneration
        isExporting = true
        clearExportedFile()

        exportTask = Task {
            defer {
                if exportGeneration == generation {
                    isExporting = false
                    exportTask = nil
                }
            }

            do {
                let exportResult = try await BatchExportService.shared.export(
                    records: requestSnapshot.records,
                    format: requestSnapshot.format,
                    options: requestSnapshot.options
                )
                guard !Task.isCancelled,
                      exportGeneration == generation
                else {
                    try? FileManager.default.removeItem(at: exportResult.url)
                    return
                }
                guard makeExportRequestSnapshot() == requestSnapshot else {
                    try? FileManager.default.removeItem(at: exportResult.url)
                    return
                }
                exportedURL = exportResult.url
                presentedSheet = .share(exportResult.url)
            } catch is CancellationError {
            } catch {
                guard !Task.isCancelled,
                      exportGeneration == generation
                else { return }
                Log.export.error("Batch export failed: \(error.localizedDescription)")
                exportFailure = BatchExportFailurePresentation(error: error)
            }
        }
    }

    func makeExportRequestSnapshot() -> BatchExportRequestSnapshot {
        var options = exportOptions
        options.plotNameByTreeID = plotNameByTreeID()
        return BatchExportRequestSnapshot(
            records: store.scanFiles,
            selectedRecordIDs: selectedRecords,
            format: exportFormat,
            options: options
        )
    }

    func cancelExport() {
        exportGeneration += 1
        exportTask?.cancel()
        exportTask = nil
        if isExporting {
            isExporting = false
        }
    }

    func clearExportedFile() {
        guard let url = exportedURL else { return }
        exportedURL = nil
        presentedSheet = nil

        let tempDirectory = FileManager.default.temporaryDirectory.standardizedFileURL
        guard url.deletingLastPathComponent().standardizedFileURL == tempDirectory else { return }
        try? FileManager.default.removeItem(at: url)
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
        let plotNameByID = Dictionary(uniqueKeysWithValues: tagStore.plots.map { ($0.id, $0.name) })
        return Dictionary(uniqueKeysWithValues: tagStore.assignments.compactMap { assignment in
            guard let plotId = assignment.plotId,
                  let plotName = plotNameByID[plotId]
            else { return nil }
            return (assignment.treeId, plotName)
        })
    }
}
