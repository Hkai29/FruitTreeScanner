import Foundation

extension ImportFileView {
    var isProcessing: Bool {
        importStatus.isProcessing
    }

    func beginImportSelection() {
        isImporting = true
        importStatus = .selecting
    }

    func handleAppear() {
        isViewActive = true
    }

    func handleDisappear() {
        isViewActive = false
        importTask?.cancel()
        importTask = nil
    }

    func handleFileImport(_ result: Result<[URL], Error>) {
        do {
            let urls = try result.get()
            guard let fileURL = urls.first else {
                importStatus = .error(L10n.Import.noFileError)
                return
            }

            let fileName = fileURL.lastPathComponent
            importStatus = .processing(fileName)
            importTask?.cancel()
            importTask = Task.detached(priority: .utility) {
                do {
                    let importedName = try PLYImportService.importFile(fileURL)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard isViewActive else { return }
                        importStatus = .success(importedName)
                        ScanHistoryStore.shared.notifyRecordsUpdated()
                    }
                } catch {
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard isViewActive else { return }
                        importStatus = .error(error.localizedDescription)
                    }
                }
            }

        } catch {
            if ImportFileErrorClassifier.isUserCancellation(error) {
                importStatus = .idle
                return
            }
            importStatus = .error(error.localizedDescription)
        }
    }
}
