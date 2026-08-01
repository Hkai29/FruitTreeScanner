import Foundation

enum PLYImportService {
    nonisolated static func importFile(
        _ fileURL: URL,
        scansDirectory: URL? = nil,
        cancellationCheckpoint: () throws -> Void = { try Task.checkCancellation() }
    ) throws -> String {
        guard fileURL.pathExtension.lowercased() == "ply" else {
            throw ImportError.unsupportedFormat
        }

        let didAccess = fileURL.startAccessingSecurityScopedResource()
        defer {
            if didAccess {
                fileURL.stopAccessingSecurityScopedResource()
            }
        }
        try cancellationCheckpoint()

        let fileManager = FileManager.default
        let scansDir: URL
        if let scansDirectory {
            scansDir = scansDirectory
        } else {
            scansDir = try LocalFileStorage.directoryURL(folder: "scans", fileManager: fileManager)
        }

        try fileManager.createDirectory(at: scansDir, withIntermediateDirectories: true)

        let destURL = uniqueDestinationURL(for: fileURL, in: scansDir)
        let stagingURL = scansDir.appendingPathComponent(".import-\(UUID().uuidString).ply-partial")
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        try fileManager.copyItem(at: fileURL, to: stagingURL)
        try cancellationCheckpoint()
        try validatePLYHeader(at: stagingURL)
        guard try PLYParserHelper.parsePointCloudDataCancellable(at: stagingURL) != nil else {
            throw ImportError.invalidPointCloud
        }
        try cancellationCheckpoint()
        try fileManager.moveItem(at: stagingURL, to: destURL)
        do {
            try cancellationCheckpoint()
        } catch {
            try? fileManager.removeItem(at: destURL)
            throw error
        }

        return destURL.lastPathComponent
    }

    nonisolated static func uniqueDestinationURL(for sourceURL: URL, in directory: URL) -> URL {
        let fileManager = FileManager.default
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeBaseName = TreeIdentifierPolicy.safeFileComponent(from: baseName)
        var candidate = directory.appendingPathComponent("\(safeBaseName).ply")

        guard fileManager.fileExists(atPath: candidate.path) else {
            return candidate
        }

        let timestamp = importTimestamp()
        candidate = directory.appendingPathComponent("\(safeBaseName)_import_\(timestamp).ply")

        if !fileManager.fileExists(atPath: candidate.path) {
            return candidate
        }

        let shortID = UUID().uuidString.prefix(6)
        return directory.appendingPathComponent("\(safeBaseName)_import_\(timestamp)_\(shortID).ply")
    }

    nonisolated static func validatePLYHeader(at fileURL: URL) throws {
        let handle = try FileHandle(forReadingFrom: fileURL)
        defer {
            try? handle.close()
        }

        let prefix = try handle.read(upToCount: PLYParserHelper.maximumHeaderSize + 1) ?? Data()
        let terminator = PLYParserHelper.headerEndRange(in: prefix)
        guard let terminator,
              terminator.upperBound <= PLYParserHelper.maximumHeaderSize,
              let header = String(data: prefix[..<terminator.upperBound], encoding: .utf8)
        else {
            throw ImportError.invalidPLY
        }

        let lines = header
            .components(separatedBy: .newlines)
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
        guard lines.first == "ply",
              PLYParserHelper.parsePointCloudHeader(lines) != nil
        else {
            throw ImportError.invalidPLY
        }
    }

    nonisolated static func importTimestamp() -> String {
        StableDataFormatting.dateFormatter(dateFormat: "yyyyMMdd_HHmmss").string(from: Date())
    }

    enum ImportError: LocalizedError {
        case unsupportedFormat
        case invalidPLY
        case invalidPointCloud

        var errorDescription: String? {
            switch self {
            case .unsupportedFormat:
                return L10n.Import.unsupportedFormatError
            case .invalidPLY:
                return L10n.Import.invalidPLYError
            case .invalidPointCloud:
                return L10n.Import.invalidPointCloudError
            }
        }
    }
}
