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

    /// 导入成功后的收尾。
    /// 文件已经落到磁盘上了，**历史一定要刷新** —— 即使这个视图已经被关掉、
    /// 这次导入的任务也刚被取消。否则档案列表还停在旧数据上，
    /// 用户会以为导入没成功，回头再导一次就多出一条重复记录。
    /// 提示只给还在看这个视图的人。
    func finishSuccessfulImport(importedName: String, wasCancelled: Bool) {
        if isViewActive && !wasCancelled {
            importStatus = .success(importedName)
        }
        operations.refreshHistory()
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
                    let wasCancelled = Task.isCancelled
                    await MainActor.run {
                        finishSuccessfulImport(importedName: importedName, wasCancelled: wasCancelled)
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
