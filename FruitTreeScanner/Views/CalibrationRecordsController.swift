import Combine
import Foundation

enum CalibrationRecordMutation: Equatable, Sendable {
    case add
    case delete
}

enum CalibrationRecordsState: Equatable, Sendable {
    case loading
    case ready
    case saving(CalibrationRecordMutation)
    case loadFailed
    case saveFailed(CalibrationRecordMutation)

    var canModify: Bool {
        switch self {
        case .ready, .saveFailed:
            return true
        case .loading, .saving, .loadFailed:
            return false
        }
    }

    var isSaving: Bool {
        if case .saving = self {
            return true
        }
        return false
    }

    var showsDerivedStatistics: Bool {
        switch self {
        case .ready, .saving, .saveFailed:
            return true
        case .loading, .loadFailed:
            return false
        }
    }

    var accessibilityAnnouncement: String? {
        switch self {
        case .loading:
            return L10n.Calibration.loadingRecords
        case .saving(.add):
            return L10n.Calibration.savingAddedRecord
        case .saving(.delete):
            return L10n.Calibration.savingDeletedRecord
        case .loadFailed:
            return "\(L10n.Calibration.loadFailedTitle). \(L10n.Calibration.loadFailedMessage)"
        case .saveFailed(.add):
            return "\(L10n.Calibration.saveFailedTitle). \(L10n.Calibration.addSaveFailedMessage)"
        case .saveFailed(.delete):
            return "\(L10n.Calibration.saveFailedTitle). \(L10n.Calibration.deleteSaveFailedMessage)"
        case .ready:
            return nil
        }
    }
}

enum CalibrationRecordsLoadResult: Sendable {
    case success([CalibrationRecord])
    case failure(String)
}

@MainActor
final class CalibrationRecordsController: ObservableObject {
    typealias Loader = @Sendable () async -> CalibrationRecordsLoadResult
    typealias Saver = @Sendable ([CalibrationRecord], Int) async -> CalibrationRecordSaveResult
    typealias RevisionProvider = @MainActor () -> Int

    @Published private(set) var records: [CalibrationRecord]
    @Published private(set) var state: CalibrationRecordsState

    private let loader: Loader
    private let saver: Saver
    private let revisionProvider: RevisionProvider
    private var loadTask: Task<Void, Never>?
    private var saveTask: Task<Void, Never>?
    private var latestSaveRevision: Int?

    init(
        records: [CalibrationRecord] = [],
        state: CalibrationRecordsState = .loading,
        loader: @escaping Loader = {
            await CalibrationRecordsController.liveLoader()
        },
        saver: @escaping Saver = { records, revision in
            await CalibrationRecordsController.liveSaver(records, revision)
        },
        revisionProvider: @escaping RevisionProvider = {
            CalibrationSaveRevisionSource.shared.nextRevision()
        }
    ) {
        self.records = records
        self.state = state
        self.loader = loader
        self.saver = saver
        self.revisionProvider = revisionProvider
    }

    func load() {
        guard !state.isSaving else { return }
        loadTask?.cancel()
        state = .loading
        let loader = loader
        loadTask = Task { [weak self] in
            let result = await loader()
            guard !Task.isCancelled else { return }
            self?.applyLoadResult(result)
        }
    }

    func cancelLoading() {
        loadTask?.cancel()
        loadTask = nil
    }

    func waitForLoading() async {
        await loadTask?.value
    }

    func waitForSaving() async {
        await saveTask?.value
    }

    func add(_ record: CalibrationRecord) {
        persist(
            [record] + records,
            previousRecords: records,
            mutation: .add
        )
    }

    func delete(_ record: CalibrationRecord) {
        let updatedRecords = records.filter { $0.id != record.id }
        guard updatedRecords.count != records.count else { return }
        persist(
            updatedRecords,
            previousRecords: records,
            mutation: .delete
        )
    }

    func dismissSaveFailure() {
        if case .saveFailed = state {
            state = .ready
        }
    }

    private func applyLoadResult(_ result: CalibrationRecordsLoadResult) {
        loadTask = nil
        switch result {
        case .success(let loadedRecords):
            records = loadedRecords
            state = .ready
        case .failure(let description):
            Log.general.error("Calibration load failed: \(description)")
            state = .loadFailed
        }
    }

    private func persist(
        _ updatedRecords: [CalibrationRecord],
        previousRecords: [CalibrationRecord],
        mutation: CalibrationRecordMutation
    ) {
        guard state.canModify else { return }
        let revision = revisionProvider()
        latestSaveRevision = revision
        records = updatedRecords
        state = .saving(mutation)
        let saver = saver

        saveTask = Task { [weak self] in
            let result = await saver(updatedRecords, revision)
            self?.finishSave(
                result,
                revision: revision,
                previousRecords: previousRecords,
                mutation: mutation
            )
        }
    }

    private func finishSave(
        _ result: CalibrationRecordSaveResult,
        revision: Int,
        previousRecords: [CalibrationRecord],
        mutation: CalibrationRecordMutation
    ) {
        guard latestSaveRevision == revision else { return }
        saveTask = nil

        switch result {
        case .saved:
            state = .ready
        case .superseded:
            state = .ready
            load()
        case .failed(let description):
            Log.general.error("Calibration save failed: \(description)")
            records = previousRecords
            state = .saveFailed(mutation)
        }
    }

    nonisolated private static func liveLoader() async -> CalibrationRecordsLoadResult {
        await Task.detached(priority: .utility) {
            do {
                return .success(try CalibrationRecordPersistence.load())
            } catch {
                return .failure(error.localizedDescription)
            }
        }.value
    }

    nonisolated private static func liveSaver(
        _ records: [CalibrationRecord],
        _ revision: Int
    ) async -> CalibrationRecordSaveResult {
        await CalibrationRecordPersistenceController.shared.saveResult(
            records,
            generation: revision
        )
    }
}
