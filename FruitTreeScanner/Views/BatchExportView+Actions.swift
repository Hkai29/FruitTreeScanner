import Foundation

extension BatchExportView {
    func handleAppear() {
        store.loadRecords()
        selectAllIfNeeded()
    }

    func handleRecordsChanged(_ files: [ScanFileRecord]) {
        pruneSelection(to: files)
        selectAllIfNeeded()
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
        guard !isExporting else { return }
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
        if selectedRecords.count == store.scanFiles.count {
            selectedRecords.removeAll()
        } else {
            selectedRecords = Set(store.scanFiles.map { $0.id })
        }
    }

    func performExport() {
        let selectedFiles = store.scanFiles.filter { selectedRecords.contains($0.id) }

        guard !selectedFiles.isEmpty else { return }

        exportTask?.cancel()
        exportGeneration += 1
        let generation = exportGeneration
        isExporting = true
        clearExportedFile()
        let selectionSnapshot = selectedRecords
        let format = exportFormat
        let optionSnapshot = exportOptions
        var options = optionSnapshot
        options.plotNameByTreeID = plotNameByTreeID()

        exportTask = Task {
            defer {
                if exportGeneration == generation {
                    isExporting = false
                    exportTask = nil
                }
            }

            do {
                let exportResult = try await BatchExportService.shared.export(
                    records: selectedFiles,
                    format: format,
                    options: options
                )
                guard !Task.isCancelled,
                      exportGeneration == generation
                else {
                    try? FileManager.default.removeItem(at: exportResult.url)
                    return
                }
                guard selectedRecords == selectionSnapshot,
                      exportFormat == format,
                      exportOptions == optionSnapshot
                else {
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
                errorMessage = error.localizedDescription
                showError = true
            }
        }
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
        let availableIDs = Set(files.map(\.id))
        if !selectedRecords.isSubset(of: availableIDs) {
            clearExportedFile()
            selectedRecords.formIntersection(availableIDs)
        }
    }

    func selectAllIfNeeded() {
        guard selectedRecords.isEmpty, !store.scanFiles.isEmpty else { return }
        selectedRecords = Set(store.scanFiles.map { $0.id })
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
