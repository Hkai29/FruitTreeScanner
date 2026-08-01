// LocalFileStorage.swift
// Documents-directory storage helpers with leaf filename validation.

import Darwin
import Foundation

enum LocalFileStorage {
    static func isSafeLeafFilename(_ filename: String) -> Bool {
        guard !filename.isEmpty, filename != ".", filename != ".." else { return false }
        guard filename == (filename as NSString).lastPathComponent else { return false }
        let forbidden = CharacterSet(charactersIn: "/\\:")
        return !filename.unicodeScalars.contains { scalar in
            forbidden.contains(scalar) || CharacterSet.controlCharacters.contains(scalar)
        }
    }

    static func documentsDirectory(fileManager: FileManager = .default) -> URL {
        fileManager.urls(for: .documentDirectory, in: .userDomainMask).first
            ?? fileManager.temporaryDirectory
    }

    static func directoryURL(folder: String, fileManager: FileManager = .default) throws -> URL {
        guard isSafeLeafFilename(folder) else {
            throw LocalFileStorageError.invalidFolder
        }
        let url = documentsDirectory(fileManager: fileManager).appendingPathComponent(folder, isDirectory: true)
        try fileManager.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    nonisolated static func writeFileExclusively(
        data: Data,
        to destinationURL: URL,
        fileManager: FileManager = .default,
        stagingWrite: (Data, URL) throws -> Void = { data, url in
            try data.write(to: url, options: [.atomic])
        },
        exclusiveMove: (URL, URL) throws -> Void = { sourceURL, destinationURL in
            try moveItemExclusively(from: sourceURL, to: destinationURL)
        }
    ) throws {
        // Stage in the destination directory, then publish without replacing an existing file.
        let stagingURL = destinationURL
            .deletingLastPathComponent()
            .appendingPathComponent(".save-\(UUID().uuidString).partial")
        defer {
            try? fileManager.removeItem(at: stagingURL)
        }

        try stagingWrite(data, stagingURL)
        try exclusiveMove(stagingURL, destinationURL)
    }

    nonisolated static func moveItemExclusively(
        from sourceURL: URL,
        to destinationURL: URL
    ) throws {
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
                    if errorCode == EEXIST {
                        throw CocoaError(
                            .fileWriteFileExists,
                            userInfo: [NSFilePathErrorKey: destinationURL.path]
                        )
                    }
                    throw NSError(
                        domain: NSPOSIXErrorDomain,
                        code: Int(errorCode),
                        userInfo: [NSFilePathErrorKey: destinationURL.path]
                    )
                }
            }
        }
    }
}

enum LocalFileStorageError: LocalizedError {
    case invalidFilename
    case invalidFolder

    var errorDescription: String? {
        switch self {
        case .invalidFilename:
            return "文件名包含不安全的路径字符"
        case .invalidFolder:
            return "文件夹名包含不安全的路径字符"
        }
    }
}

/// 保存二进制数据到 Documents 目录
func saveFile(data: Data, filename: String, folder: String) async throws {
    guard LocalFileStorage.isSafeLeafFilename(filename) else {
        throw LocalFileStorageError.invalidFilename
    }
    let directory = try LocalFileStorage.directoryURL(folder: folder)
    let url = directory.appendingPathComponent(filename)
    try LocalFileStorage.writeFileExclusively(data: data, to: url)
}

/// Documents 目录
func getDocumentsDirectory() -> URL {
    LocalFileStorage.documentsDirectory()
}

/// 创建目录
func createDirectory(folder: String) {
    do {
        _ = try LocalFileStorage.directoryURL(folder: folder)
    } catch {
        Log.general.error("Failed to create local storage folder \(folder): \(error.localizedDescription)")
    }
}
