import Foundation

enum ScanInterruptionReason: String, Equatable, Sendable {
    case appInactive, appBackgrounded, arSessionInterrupted, trackingFailure, cameraUnavailable
}

enum ScanFailureReason: Equatable, Sendable {
    case cameraUnavailable(String)
    case sessionFailed(String)

    var requiresCameraReadinessRecovery: Bool {
        if case .cameraUnavailable = self { return true }
        return false
    }
}

enum ScanLifecycleState: Equatable, Sendable {
    case idle, recording, userPaused, systemInterrupted(ScanInterruptionReason)
    case recovering, finishing, completed, failed(ScanFailureReason), cancelled
}

/// Logical scan identity. A fresh scan/restart receives a new value.
typealias ScanID = UUID

/// Admission epoch invalidated by bind, interruption, teardown, or cancellation.
/// A normal pause closes the gate without changing this epoch so accepted work can drain.
typealias EvidenceEpoch = UInt64

struct ScanLifecycleSnapshot: Equatable, Sendable {
    let state: ScanLifecycleState
    let scanIdentity: ScanID
    let generation: Int
    let interruptionCount: Int
    let lastInterruptionTimestamp: Date?
    var acceptsReliableEvidence: Bool { state == .recording }
}

/// Identity of one ARSession/Renderer/MTKView binding.
struct ScanBindingID: Equatable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) { self.rawValue = rawValue }
}

struct ScanCapturedEvidenceToken: Equatable, Sendable {
    let scanIdentity: ScanID
    let bindingID: ScanBindingID
    let invalidationEpoch: EvidenceEpoch
}

/// The single owner of scan identity, lifecycle transitions, and the plan
/// attached to the current scan. Mutations stay synchronous because ARKit
/// callbacks and evidence admission must observe the same identity boundary.
final class ScanSession {
    struct Snapshot: Sendable {
        let lifecycle: ScanLifecycleSnapshot
        let bindingID: ScanBindingID
    }

    private let lock = NSLock()
    private var state: ScanLifecycleState = .idle
    private var scanIdentity = UUID()
    private var generation = 0
    private var interruptionCount = 0
    private var lastInterruptionTimestamp: Date?
    private var bindingID = ScanBindingID()
    private var storedPlan: ScanPlan?
    private var storedCompatibilityConfiguration: ScanFruitConfiguration?

    func snapshot() -> ScanLifecycleSnapshot {
        withLock { makeSnapshot() }
    }

    func sessionSnapshot() -> Snapshot {
        withLock { Snapshot(lifecycle: makeSnapshot(), bindingID: bindingID) }
    }

    func beginBinding() -> ScanBindingID {
        withLock {
            bindingID = ScanBindingID()
            return bindingID
        }
    }

    var activePlan: ScanPlan? {
        withLock { storedPlan }
    }

    var activeFruitConfiguration: ScanFruitConfiguration? {
        withLock { storedPlan?.fruitConfiguration ?? storedCompatibilityConfiguration }
    }

    func startNewScan(
        plan: ScanPlan? = nil,
        compatibilityConfiguration: ScanFruitConfiguration? = nil
    ) -> ScanLifecycleSnapshot {
        withLock {
            generation &+= 1
            scanIdentity = UUID()
            state = .recording
            interruptionCount = 0
            lastInterruptionTimestamp = nil
            storedPlan = plan
            storedCompatibilityConfiguration = compatibilityConfiguration
            return makeSnapshot()
        }
    }

    func clearConfiguration() {
        withLock {
            storedPlan = nil
            storedCompatibilityConfiguration = nil
        }
    }

    func userPaused() -> ScanLifecycleSnapshot {
        withLock {
            if state == .recording {
                generation &+= 1
                state = .userPaused
            }
            return makeSnapshot()
        }
    }

    func resumeUserPaused() -> ScanLifecycleSnapshot {
        withLock {
            if state == .userPaused {
                generation &+= 1
                state = .recording
            }
            return makeSnapshot()
        }
    }

    func interrupt(_ reason: ScanInterruptionReason) -> ScanLifecycleSnapshot {
        withLock {
            switch state {
            case .recording, .userPaused, .finishing:
                generation &+= 1
                interruptionCount += 1
                lastInterruptionTimestamp = Date()
                state = .systemInterrupted(reason)
            default:
                break
            }
            return makeSnapshot()
        }
    }

    func interruptionEnded() -> ScanLifecycleSnapshot {
        withLock {
            if case .systemInterrupted = state {
                generation &+= 1
                state = .recovering
            }
            return makeSnapshot()
        }
    }

    func beginFinishing() -> ScanLifecycleSnapshot {
        withLock {
            if state == .recording || state == .userPaused {
                generation &+= 1
                state = .finishing
            }
            return makeSnapshot()
        }
    }

    func complete() -> ScanLifecycleSnapshot {
        withLock {
            if state == .finishing {
                generation &+= 1
                state = .completed
            }
            return makeSnapshot()
        }
    }

    func fail(_ reason: ScanFailureReason) -> ScanLifecycleSnapshot {
        withLock {
            if state != .completed && state != .cancelled {
                generation &+= 1
                state = .failed(reason)
            }
            return makeSnapshot()
        }
    }

    func cancel() -> ScanLifecycleSnapshot {
        withLock {
            if state != .completed {
                generation &+= 1
                state = .cancelled
            }
            return makeSnapshot()
        }
    }

    private func withLock<T>(_ body: () -> T) -> T {
        lock.lock()
        defer { lock.unlock() }
        return body()
    }

    private func makeSnapshot() -> ScanLifecycleSnapshot {
        ScanLifecycleSnapshot(
            state: state,
            scanIdentity: scanIdentity,
            generation: generation,
            interruptionCount: interruptionCount,
            lastInterruptionTimestamp: lastInterruptionTimestamp
        )
    }
}

/// Source compatibility for the lifecycle-focused tests and adapters.
typealias ScanLifecycleController = ScanSession

/// A minimal synchronous gate used by ARKit callbacks to admit or reject new
/// evidence before work crosses into asynchronous detection and fusion paths.
final class CaptureAdmissionGate {
    struct Snapshot: Sendable {
        let isOpen: Bool
        let generation: Int
        let invalidationEpoch: EvidenceEpoch
        let bindingID: ScanBindingID
    }

    private let lock = NSLock()
    private var generation = 0
    private var isOpen = false
    private var invalidationEpoch: EvidenceEpoch = 0
    private var bindingID: ScanBindingID

    init(bindingID: ScanBindingID = ScanBindingID()) {
        self.bindingID = bindingID
    }

    func snapshot() -> Snapshot {
        lock.lock()
        defer { lock.unlock() }
        return Snapshot(
            isOpen: isOpen,
            generation: generation,
            invalidationEpoch: invalidationEpoch,
            bindingID: bindingID
        )
    }

    func bind(to bindingID: ScanBindingID) {
        lock.lock()
        generation &+= 1
        isOpen = false
        invalidationEpoch &+= 1
        self.bindingID = bindingID
        lock.unlock()
    }

    func setOpen(_ open: Bool) -> Int {
        lock.lock()
        generation &+= 1
        isOpen = open
        let nextGeneration = generation
        lock.unlock()
        return nextGeneration
    }

    func makeToken(scanIdentity: ScanID, bindingID: ScanBindingID) -> ScanCapturedEvidenceToken? {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen, self.bindingID == bindingID else { return nil }
        return ScanCapturedEvidenceToken(
            scanIdentity: scanIdentity,
            bindingID: bindingID,
            invalidationEpoch: invalidationEpoch
        )
    }

    func invalidate() {
        lock.lock()
        generation &+= 1
        isOpen = false
        invalidationEpoch &+= 1
        lock.unlock()
    }

    func accepts(generation expectedGeneration: Int?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        guard isOpen else { return false }
        return expectedGeneration.map { $0 == generation } ?? true
    }
}
