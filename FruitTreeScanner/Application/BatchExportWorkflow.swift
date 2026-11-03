import Combine
import Foundation

/// The service owns and cleans partial files; a successful return hands its URL to the workflow.
struct BatchExportOperations {
    let export: @MainActor (BatchExportRequestSnapshot) async throws -> BatchExportService.ExportResult
    let removeTemporaryExport: (URL) -> Void

    static var production: BatchExportOperations {
        BatchExportOperations(
            export: { request in
                try await BatchExportService.shared.export(
                    records: request.records, format: request.format, options: request.options
                )
            },
            removeTemporaryExport: { url in
                BatchExportService.removeTemporaryExport(at: url)
            }
        )
    }
}

/// Immutable resource ownership needs no actor hop when its last reference dies.
private final class BatchExportFile {
    let url: URL
    private let remove: (URL) -> Void

    init(url: URL, remove: @escaping (URL) -> Void) {
        self.url = url
        self.remove = remove
    }

    deinit { remove(url) }
}

/// Owns one page's export attempts and completed temporary file, independently of SwiftUI.
@MainActor
final class BatchExportWorkflow: ObservableObject {
    @Published private(set) var isExporting = false
    @Published private var completedFile: BatchExportFile?
    @Published private(set) var failure: Error?

    var exportedURL: URL? { completedFile?.url }

    private let operations: BatchExportOperations
    private var exportTask: Task<Void, Never>?
    private var generation = 0

    init(operations: BatchExportOperations = .production, exportedURL: URL? = nil) {
        self.operations = operations
        self.completedFile = exportedURL.map {
            BatchExportFile(url: $0, remove: operations.removeTemporaryExport)
        }
    }

    deinit {
        exportTask?.cancel()
    }

    @discardableResult
    func start(
        _ request: BatchExportRequestSnapshot,
        currentRequest: @escaping @MainActor () -> BatchExportRequestSnapshot
    ) -> Task<Void, Never>? {
        guard !request.records.isEmpty else { return nil }

        exportTask?.cancel()
        generation += 1
        let attempt = generation
        isExporting = true
        clearExportedFile()

        // Capture operations, not the owner, across await. Even a released page's
        // late successful URL must be cleaned after the service hands it over.
        let operations = operations
        let task = Task { [weak self] in
            defer { self?.finish(attempt: attempt) }

            do {
                let result = try await operations.export(request)
                guard !Task.isCancelled, let self, self.generation == attempt else {
                    operations.removeTemporaryExport(result.url)
                    return
                }
                guard currentRequest() == request else {
                    operations.removeTemporaryExport(result.url)
                    return
                }
                self.completedFile = BatchExportFile(url: result.url, remove: operations.removeTemporaryExport)
            } catch is CancellationError {
            } catch {
                // Preserve the old failure branch: it checks cancellation and
                // attempt identity, without adding success's request comparison.
                guard !Task.isCancelled, let self, self.generation == attempt else { return }
                Log.export.error("Batch export failed: \(error.localizedDescription)")
                self.failure = error
            }
        }
        exportTask = task
        return task
    }

    func cancel() {
        generation += 1
        exportTask?.cancel()
        exportTask = nil
        if isExporting { isExporting = false }
    }

    func clearExportedFile() {
        guard completedFile != nil else { return }
        completedFile = nil
    }

    func dismissFailure() {
        // SwiftUI also writes false while reconciling an already-dismissed
        // alert. An unchanged nil must not publish during that view update.
        guard failure != nil else { return }
        failure = nil
    }

    private func finish(attempt: Int) {
        guard generation == attempt else { return }
        isExporting = false
        exportTask = nil
    }
}
