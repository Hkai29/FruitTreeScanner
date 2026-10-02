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
            let operations = operations
            importTask = Task.detached(priority: .utility) {
                do {
                    let importedName = try operations.importPointCloud(fileURL)
                    guard !Task.isCancelled else { return }
                    await MainActor.run {
                        guard isViewActive else { return }
                        importStatus = .success(importedName)
                        operations.refreshHistory()
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
