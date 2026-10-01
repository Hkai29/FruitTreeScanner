import Combine
import Foundation

/// MainActor snapshot projection for SwiftUI. It cannot mutate scan lifecycle;
/// the ScanSession remains the authority and stale queued snapshots are ignored.
@MainActor
final class ScanFeatureModel: ObservableObject {
    @Published private(set) var lifecycleSnapshot: ScanLifecycleSnapshot

    init(initialSnapshot: ScanLifecycleSnapshot = ScanLifecycleSnapshot(
        state: .idle,
        scanIdentity: UUID(),
        generation: 0,
        interruptionCount: 0,
        lastInterruptionTimestamp: nil
    )) {
        lifecycleSnapshot = initialSnapshot
    }

    func apply(_ nextSnapshot: ScanLifecycleSnapshot) {
        guard nextSnapshot.generation >= lifecycleSnapshot.generation else { return }
        lifecycleSnapshot = nextSnapshot
    }

    var isRecording: Bool {
        lifecycleSnapshot.state == .recording
    }
}
