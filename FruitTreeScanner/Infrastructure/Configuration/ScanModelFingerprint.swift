import CryptoKit
import Foundation

/// File-backed model identity. The bundled value is initialized once, including
/// unavailable results, matching the established calibration cache semantics.
enum ScanModelFingerprint {
    static let bundledIdentity: ScanModelIdentity = {
        guard let resource = ImageDetectorModelLoader.modelURL(named: "FruitsDetector") else {
            return .modelMissing
        }
        return identity(at: resource.url)
    }()

    static func identity(
        at root: URL,
        directoryEntries: (URL) throws -> [URL] = {
            try FileManager.default.contentsOfDirectory(at: $0,
                includingPropertiesForKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
        },
        openFile: (URL) throws -> FileHandle = { try FileHandle(forReadingFrom: $0) }
    ) -> ScanModelIdentity {
        var isDirectory: ObjCBool = false
        guard FileManager.default.fileExists(atPath: root.path, isDirectory: &isDirectory) else {
            return .fingerprintUnavailable
        }
        do {
            var files: [URL] = []
            if isDirectory.boolValue {
                // A throwing walk cannot silently accept the readable subset of
                // an inaccessible package. Do not follow directory symlinks.
                var pending = [root]
                while let directory = pending.popLast() {
                    for file in try directoryEntries(directory) {
                        let properties = try file.resourceValues(forKeys: [.isRegularFileKey, .isDirectoryKey, .isSymbolicLinkKey])
                        guard let regular = properties.isRegularFile else { return .fingerprintUnavailable }
                        if regular {
                            files.append(file)
                        } else if properties.isDirectory == true && properties.isSymbolicLink != true {
                            pending.append(file)
                        }
                    }
                }
                files.sort { $0.path < $1.path }
            } else {
                files = [root]
            }
            guard !files.isEmpty else { return .fingerprintUnavailable }
            var hash = SHA256()
            for file in files {
                // Preserve the legacy path bytes exactly; changing delimiters or
                // normalization would invalidate previously saved calibrations.
                hash.update(data: Data(file.path.replacingOccurrences(of: root.path, with: "").utf8))
                let handle = try openFile(file)
                defer { try? handle.close() }
                while let data = try handle.read(upToCount: 1_048_576), !data.isEmpty {
                    hash.update(data: data)
                }
            }
            return .verified(hash.finalize().map { String(format: "%02x", $0) }.joined())
        } catch {
            return .fingerprintUnavailable
        }
    }
}
