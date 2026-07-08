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
