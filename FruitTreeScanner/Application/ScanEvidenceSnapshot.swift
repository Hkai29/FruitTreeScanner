import Foundation

/// The immutable observations and point cloud consumed by one estimate.
/// Snapshot.id is created with the input and remains stable across retries.
struct ScanEvidenceSnapshot: Sendable {
    let snapshot: ScanYieldEstimationController.Snapshot
    let receipt: ScanEvidenceReceipt
    var identity: ScanEvidenceIdentity { receipt.identity }

    private init(snapshot: ScanYieldEstimationController.Snapshot, receipt: ScanEvidenceReceipt) {
        self.snapshot = snapshot
        self.receipt = receipt
    }

    static func freeze(snapshot: ScanYieldEstimationController.Snapshot, draft: DraftScan,
                       repository: ScanRepository = .shared) async throws -> Self {
        guard let capture = draft.captureIdentity,
              snapshot.context == capture.context,
              snapshot.input.finalPointCloudIdentity == capture.pointCloud else {
            throw ScanEvidenceError.mismatchedInput
        }
        let identity = ScanEvidenceIdentity(
            capture: capture,
            snapshotID: snapshot.id,
            sourceOwnershipID: draft.ownershipID,
            sourceSHA256: draft.sourceSHA256
        )
        let worker = Task.detached(priority: .utility) {
            try repository.bindEvidence(identity, to: draft)
        }
        let receipt = try await withTaskCancellationHandler {
            try await worker.value
        } onCancel: {
            worker.cancel()
        }
        try Task.checkCancellation()
        return Self(snapshot: snapshot, receipt: receipt)
    }
}
