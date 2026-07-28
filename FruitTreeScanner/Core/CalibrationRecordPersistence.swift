import Foundation

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
