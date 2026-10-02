import Foundation

/// Import and completion refresh must belong to the same root dependencies.
/// The caller runs blocking import work in its cancellable background task.
struct ScanImportOperations: Sendable {
    let importPointCloud: @Sendable (URL) throws -> String
    let refreshHistory: @MainActor @Sendable () -> Void

    @MainActor
    static func production(
        repository: ScanRepository,
        historyStore: ScanHistoryStore
    ) -> ScanImportOperations {
        ScanImportOperations(
            importPointCloud: { source in try repository.importPointCloud(source) },
            refreshHistory: { historyStore.notifyRecordsUpdated() }
        )
    }
}
