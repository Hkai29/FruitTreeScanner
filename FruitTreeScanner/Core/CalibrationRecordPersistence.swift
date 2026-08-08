import Foundation
import Combine

enum CalibrationRecordLoadFailure: Equatable, Sendable {
    case unavailable
}

enum CalibrationRecordLoadResult: Sendable {
    case success([CalibrationRecord])
    case failure(CalibrationRecordLoadFailure)
}

typealias CalibrationRecordsLoader = @Sendable () async -> CalibrationRecordLoadResult

enum CalibrationRecordPersistence {
    static let fileName = "calibration_records.json"

    static func defaultURL() -> URL {
        getDocumentsDirectory().appendingPathComponent(fileName)
    }

    static func load() throws -> [CalibrationRecord] {
        try load(from: defaultURL())
    }

    static func load(from url: URL) throws -> [CalibrationRecord] {
        do {
            let data = try Data(contentsOf: url)
            return try JSONDecoder().decode([CalibrationRecord].self, from: data)
        } catch CocoaError.fileReadNoSuchFile {
            return []
        }
    }

    static func save(_ records: [CalibrationRecord]) throws {
        try save(records, to: defaultURL())
    }

    static func save(_ records: [CalibrationRecord], to url: URL) throws {
        let data = try JSONEncoder().encode(records)
        try data.write(to: url, options: .atomic)
    }
}

/// Owns the last verified calibration snapshot and rejects mutations until the
/// initial file read succeeds. A read failure must never masquerade as an empty
/// file because saving from that false-empty state could replace user records.
@MainActor
final class CalibrationRecordStore: ObservableObject {
    @Published private(set) var records: [CalibrationRecord] = []
    @Published private(set) var loadFailure: CalibrationRecordLoadFailure?
    @Published private(set) var isLoading = false
    @Published private(set) var hasLoaded = false

    private let recordsLoader: CalibrationRecordsLoader
    private var loadTask: Task<Void, Never>?
    private var loadGeneration = 0

    convenience init() {
        self.init(recordsLoader: Self.liveLoader)
    }

    init(recordsLoader: @escaping CalibrationRecordsLoader) {
        self.recordsLoader = recordsLoader
    }

    var canMutate: Bool {
        hasLoaded && !isLoading && loadFailure == nil
    }

    @discardableResult
    func loadRecords() -> Task<Void, Never> {
        loadGeneration += 1
        let generation = loadGeneration
        loadTask?.cancel()
        isLoading = true
        let recordsLoader = recordsLoader
        let task = Task { [weak self, generation] in
            let result = await recordsLoader()
            guard !Task.isCancelled else { return }
            self?.apply(result, generation: generation)
        }
        loadTask = task
        return task
    }

    func reloadRecords() async {
        let task = loadRecords()
        await task.value
    }

    func invalidateLoad() {
        loadGeneration += 1
        loadTask?.cancel()
        loadTask = nil
        isLoading = false
    }

    @discardableResult
    func prepend(_ record: CalibrationRecord) -> [CalibrationRecord]? {
        guard canMutate else { return nil }
        records.insert(record, at: 0)
        return records
    }

    @discardableResult
    func remove(id: UUID) -> [CalibrationRecord]? {
        guard canMutate else { return nil }
        records.removeAll { $0.id == id }
        return records
    }

    private func apply(_ result: CalibrationRecordLoadResult, generation: Int) {
        guard generation == loadGeneration else { return }
        loadTask = nil
        isLoading = false

        switch result {
        case .success(let records):
            self.records = records
            loadFailure = nil
            hasLoaded = true
        case .failure(let failure):
            loadFailure = failure
        }
    }

    nonisolated private static let liveLoader: CalibrationRecordsLoader = {
        await Task.detached(priority: .utility) {
            do {
                return .success(try CalibrationRecordPersistence.load())
            } catch {
                Log.general.error("Failed to load calibration records: \(error.localizedDescription)")
                return .failure(.unavailable)
            }
        }.value
    }
}

/// Assigns save revisions at the main-actor event source before unstructured
/// tasks cross to the persistence actor. The shared lifetime prevents a newly
/// created calibration view from restarting at an older revision.
@MainActor
final class CalibrationSaveRevisionSource {
    static let shared = CalibrationSaveRevisionSource()

    private var latestRevision = 0

    func nextRevision() -> Int {
        latestRevision += 1
        return latestRevision
    }
}

/// Serializes immutable calibration snapshots so an older detached save cannot
/// replace a newer user edit after it finishes.
actor CalibrationRecordPersistenceController {
    typealias Writer = @Sendable ([CalibrationRecord], URL) throws -> Void

    static let shared = CalibrationRecordPersistenceController()

    private let url: URL
    private let writer: Writer
    private var latestGeneration = 0
    private(set) var lastErrorDescription: String?

    init(
        url: URL = CalibrationRecordPersistence.defaultURL(),
        writer: @escaping Writer = { records, url in
            try CalibrationRecordPersistence.save(records, to: url)
        }
    ) {
        self.url = url
        self.writer = writer
    }

    /// Returns false for a superseded snapshot or a failed write. The in-memory
    /// view state remains authoritative; an existing complete file is only
    /// replaced by the atomic writer after encoding succeeds.
    @discardableResult
    func save(_ records: [CalibrationRecord], generation: Int) -> Bool {
        guard generation >= latestGeneration else { return false }
        latestGeneration = generation

        do {
            try writer(records, url)
            guard generation == latestGeneration else { return false }
            lastErrorDescription = nil
            return true
        } catch {
            if generation == latestGeneration {
                lastErrorDescription = error.localizedDescription
            }
            return false
        }
    }
}
