import Foundation

enum ScanSourceFileError: LocalizedError {
    case invalidOrChanged

    var errorDescription: String? {
        "点云文件缺失、损坏或保存后发生变化，不能将当前结果标记为完整。"
    }
}

struct DraftScan: Equatable, Sendable {
    let sourceURL: URL
    let sourceSHA256: String
    let fileIdentity: ScanSourceFileIdentity
    let ownershipID: UUID
    let captureIdentity: ScanCaptureIdentity?
    var sourceFilename: String { sourceURL.lastPathComponent }

    init(sourceURL: URL, sourceSHA256: String, fileIdentity: ScanSourceFileIdentity,
         ownershipID: UUID, captureIdentity: ScanCaptureIdentity? = nil) {
        self.sourceURL = sourceURL
        self.sourceSHA256 = sourceSHA256
        self.fileIdentity = fileIdentity
        self.ownershipID = ownershipID
        self.captureIdentity = captureIdentity
    }
}

struct ScanSourceFileIdentity: Equatable, Sendable {
    let device: UInt64
    let inode: UInt64

    static func read(at url: URL) throws -> Self {
        let attributes = try FileManager.default.attributesOfItem(atPath: url.path)
        guard let device = attributes[.systemNumber] as? NSNumber,
              let inode = attributes[.systemFileNumber] as? NSNumber else {
            throw ScanSourceFileError.invalidOrChanged
        }
        return Self(device: device.uint64Value, inode: inode.uint64Value)
    }
}

enum DraftSettlement: Equatable, Sendable {
    case discarded
    case preservedCommitted
    case requiresRecovery(String)
}

/// Only the source ownership registry can issue a bound receipt. It is small
/// enough to retain for persistence retries after releasing the full input.
struct ScanEvidenceReceipt: Sendable {
    let draft: DraftScan
    let identity: ScanEvidenceIdentity

    fileprivate init(draft: DraftScan, identity: ScanEvidenceIdentity) {
        self.draft = draft
        self.identity = identity
    }
}

/// Shared by the repository and compatibility exporter. Neither layer calls
/// back into the other to acquire a lock or inspect draft ownership.
final class ScanArchiveAccess: @unchecked Sendable {
    static let shared = ScanArchiveAccess()

    private struct Entry {
        let semaphore: DispatchSemaphore
        var users: Int
    }

    private struct DraftOwner {
        let id: UUID
        let captureIdentity: ScanCaptureIdentity?
        var evidence: ScanEvidenceIdentity?
    }

    private let registryLock = NSLock()
    private var entries: [String: Entry] = [:]
    private var draftOwners: [String: DraftOwner] = [:]

    private init() {}

    /// Lock order: exporter queue (when used), source semaphore, registry lock.
    /// Callers must not invoke an exporter or reenter the same source inside
    /// this closure. The registry lock is never held while waiting for a source.
    func withTransaction<T>(at sourceURL: URL, operation: () throws -> T) throws -> T {
        let key = transactionKey(sourceURL)
        let semaphore = retainSemaphore(for: key)
        var acquired = false
        defer {
            if acquired { semaphore.signal() }
            releaseSemaphore(for: key)
        }

        while semaphore.wait(timeout: .now() + .milliseconds(50)) == .timedOut {
            try Task.checkCancellation()
        }
        acquired = true
        try Task.checkCancellation()
        return try operation()
    }

    /// Ownership methods are called while holding this source's transaction.
    func registerDraft(_ draft: DraftScan) {
        let key = transactionKey(draft.sourceURL)
        registryLock.lock()
        defer { registryLock.unlock() }
        draftOwners[key] = DraftOwner(id: draft.ownershipID, captureIdentity: draft.captureIdentity)
    }

    func ownsDraft(_ draft: DraftScan) -> Bool {
        let key = transactionKey(draft.sourceURL)
        registryLock.lock()
        defer { registryLock.unlock() }
        return draftOwners[key]?.id == draft.ownershipID
    }

    func requiresEvidenceReceipt(at sourceURL: URL) -> Bool {
        let key = transactionKey(sourceURL)
        registryLock.lock()
        defer { registryLock.unlock() }
        return draftOwners[key]?.captureIdentity != nil
    }

    func releaseDraft(_ draft: DraftScan) {
        let key = transactionKey(draft.sourceURL)
        registryLock.lock()
        defer { registryLock.unlock() }
        if draftOwners[key]?.id == draft.ownershipID { draftOwners.removeValue(forKey: key) }
    }

    func bindEvidence(_ identity: ScanEvidenceIdentity, to draft: DraftScan) throws -> ScanEvidenceReceipt {
        let key = transactionKey(draft.sourceURL)
        registryLock.lock()
        defer { registryLock.unlock() }
        guard identity.capture == draft.captureIdentity,
              identity.sourceOwnershipID == draft.ownershipID,
              identity.sourceSHA256 == draft.sourceSHA256,
              var owner = draftOwners[key], owner.id == draft.ownershipID,
              owner.evidence == nil || owner.evidence == identity else {
            throw ScanEvidenceError.mismatchedInput
        }
        owner.evidence = identity
        draftOwners[key] = owner
        return ScanEvidenceReceipt(draft: draft, identity: identity)
    }

    private func transactionKey(_ url: URL) -> String {
        url.standardizedFileURL.resolvingSymlinksInPath().path
    }

    private func retainSemaphore(for key: String) -> DispatchSemaphore {
        registryLock.lock()
        defer { registryLock.unlock() }
        if var entry = entries[key] {
            entry.users += 1
            entries[key] = entry
            return entry.semaphore
        }
        let semaphore = DispatchSemaphore(value: 1)
        entries[key] = Entry(semaphore: semaphore, users: 1)
        return semaphore
    }

    private func releaseSemaphore(for key: String) {
        registryLock.lock()
        defer { registryLock.unlock() }
        guard var entry = entries[key] else { return }
        if entry.users == 1 {
            entries.removeValue(forKey: key)
        } else {
            entry.users -= 1
            entries[key] = entry
        }
    }
}
