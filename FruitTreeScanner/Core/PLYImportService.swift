import Darwin
import Foundation

enum PLYImportService {
    private static let maximumDestinationCommitAttempts = 64

    nonisolated static func importFile(
        _ fileURL: URL,
        scansDirectory: URL? = nil,
        stagingCopy: (URL, URL) throws -> Void = { sourceURL, destinationURL in
            try PLYStagingFileCopier.copyFile(from: sourceURL, to: destinationURL)
        },
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

        let stagingURL = scansDir.appendingPathComponent(".import-\(UUID().uuidString).ply-partial")
        defer {
            if fileManager.fileExists(atPath: stagingURL.path) {
                try? fileManager.removeItem(at: stagingURL)
            }
        }

        try stagingCopy(fileURL, stagingURL)
        try cancellationCheckpoint()
        try validatePLYHeader(at: stagingURL)
        guard try PLYParserHelper.parsePointCloudDataCancellable(at: stagingURL) != nil else {
            throw ImportError.invalidPointCloud
        }
        try cancellationCheckpoint()
        let destURL = try commitStagedFile(
            at: stagingURL,
            for: fileURL,
            in: scansDir
        )
        do {
            try cancellationCheckpoint()
        } catch {
            try? fileManager.removeItem(at: destURL)
            throw error
        }

        return destURL.lastPathComponent
    }

    nonisolated static func commitStagedFile(
        at stagingURL: URL,
        for sourceURL: URL,
        in directory: URL,
        timestamp: String = importTimestamp(),
        uniqueSuffix: () -> String = { String(UUID().uuidString.prefix(6)) },
        exclusiveMove: (URL, URL) throws -> Void = { sourceURL, destinationURL in
            try moveItemExclusively(from: sourceURL, to: destinationURL)
        }
    ) throws -> URL {
        let baseName = sourceURL.deletingPathExtension().lastPathComponent
        let safeBaseName = TreeIdentifierPolicy.safeFileComponent(from: baseName)
        var lastCollision: Error?

        for attempt in 0..<maximumDestinationCommitAttempts {
            let filename: String
            switch attempt {
            case 0:
                filename = "\(safeBaseName).ply"
            case 1:
                filename = "\(safeBaseName)_import_\(timestamp).ply"
            default:
                filename = "\(safeBaseName)_import_\(timestamp)_\(uniqueSuffix()).ply"
            }
            let candidate = directory.appendingPathComponent(filename)

            do {
                try exclusiveMove(stagingURL, candidate)
                return candidate
            } catch {
                guard isDestinationExistsError(error) else {
                    throw error
                }
                lastCollision = error
            }
        }

        throw lastCollision ?? CocoaError(.fileWriteUnknown)
    }

    nonisolated static func moveItemExclusively(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {
        // A preflight check plus FileManager.moveItem can still replace a concurrently created file.
        try sourceURL.withUnsafeFileSystemRepresentation { sourcePath in
            guard let sourcePath else {
                throw CocoaError(.fileWriteInvalidFileName)
            }

            try destinationURL.withUnsafeFileSystemRepresentation { destinationPath in
                guard let destinationPath else {
                    throw CocoaError(.fileWriteInvalidFileName)
                }

                guard renamex_np(
                    sourcePath,
                    destinationPath,
                    UInt32(RENAME_EXCL)
                ) == 0 else {
                    let errorCode = errno
                    throw NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(errorCode),
                        userInfo: [NSFilePathErrorKey: destinationURL.path]
                    )
                }
            }
        }
    }

    nonisolated static func isDestinationExistsError(_ error: Error) -> Bool {
        let nsError = error as NSError
        if nsError.domain == NSPOSIXErrorDomain, nsError.code == Int(EEXIST) {
            return true
        }
        if nsError.domain == NSCocoaErrorDomain,
           nsError.code == CocoaError.fileWriteFileExists.rawValue {
            return true
        }
        if let underlyingError = nsError.userInfo[NSUnderlyingErrorKey] as? Error {
            return isDestinationExistsError(underlyingError)
        }
        return false
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

enum PLYStagingFileCopier {
    static let chunkByteCount = 1_048_576

    nonisolated static func copyFile(
        from sourceURL: URL,
        to destinationURL: URL,
        cancellationCheckpoint: () throws -> Void = { try Task.checkCancellation() }
    ) throws {
        try cancellationCheckpoint()

        let sourceHandle = try FileHandle(forReadingFrom: sourceURL)
        defer {
            try? sourceHandle.close()
        }

        try Data().write(to: destinationURL, options: .withoutOverwriting)
        var didComplete = false
        defer {
            if !didComplete {
                try? FileManager.default.removeItem(at: destinationURL)
            }
        }

        let destinationHandle = try FileHandle(forWritingTo: destinationURL)
        var destinationIsOpen = true
        defer {
            if destinationIsOpen {
                try? destinationHandle.close()
            }
        }

        while true {
            try cancellationCheckpoint()
            let chunk = try sourceHandle.read(upToCount: chunkByteCount) ?? Data()
            guard !chunk.isEmpty else {
                break
            }

            try cancellationCheckpoint()
            try destinationHandle.write(contentsOf: chunk)
        }

        try destinationHandle.close()
        destinationIsOpen = false
        try cancellationCheckpoint()
        didComplete = true
    }
}
