import Foundation

// Coordinates finish, retry, persistence and cancellation for one scan.
import Combine

/// Unique retry/attempt identity; changing it never changes the ScanID.
struct ScanWorkID: Equatable, Sendable {
    let rawValue: UUID

    init(rawValue: UUID = UUID()) {
        self.rawValue = rawValue
    }
}

@MainActor
struct ScanFinalizationOperations {
    let lifecycleSnapshot: () -> ScanLifecycleSnapshot
    let beginFinishing: () -> Bool
    let freezePointCloud: (ScanPlan) async throws -> FrozenPointCloudExport
    let stagePointCloud: (PointCloudStageInput) async throws -> StagedPointCloud
    let captureSnapshot: (Season, StagedPointCloud) async throws -> ScanYieldEstimationController.Snapshot
    let bindSnapshot: (ScanYieldEstimationController.Snapshot, StagedPointCloud, ScanPlan) async throws -> ScanEvidenceSnapshot
    let estimateYield: (ScanEvidenceSnapshot) async throws -> ScanEstimate
    let persistResult: (ScanPlan, ScanEvidenceReceipt, ScanEstimate, Double, Double) async throws -> Void
    let markCompleted: () -> Void
    let refreshHistory: @MainActor () -> Void
    let discardArtifacts: (DraftScan) async -> DraftSettlement

    static func production(
        coordinator: ScanCoordinator,
        repository: ScanRepository = .shared,
        refreshHistory: @escaping @MainActor () -> Void = { ScanHistoryStore.shared.notifyRecordsUpdated() }
    ) -> ScanFinalizationOperations {
        ScanFinalizationOperations(
            lifecycleSnapshot: { coordinator.lifecycleSnapshot() },
            beginFinishing: { coordinator.beginFinishingScan() },
            freezePointCloud: { plan in
                try await coordinator.freezePointCloud(plan: plan)
            },
            stagePointCloud: { input in
                try await PointCloudStaging.stage(input, repository: repository)
            },
            captureSnapshot: { season, staged in
                try await coordinator.prepareYieldEstimationSnapshot(season: season, finalPointCloud: staged.pointCloud)
            },
            bindSnapshot: { input, staged, plan in
                return try await ScanEvidenceSnapshot.freeze(snapshot: input, draft: staged.draft, repository: repository, plan: plan)
            },
            estimateYield: { snapshot in
                let identity = coordinator.lifecycleSnapshot().scanIdentity
                let estimate = try await ScanYieldEstimationController.estimate(snapshot)
                try Task.checkCancellation()
                guard coordinator.lifecycleSnapshot().scanIdentity == identity,
                      coordinator.lifecycleSnapshot().state == .finishing else { throw CancellationError() }
                let result = estimate.result
                coordinator.hudState?.update(
                    detectedFruitCount: result.diagnostics.fusedFruitCount,
                    fusionStatus: result.diagnostics.fusedFruitCount > 0 ? "OK" : "0kg"
                )
                return estimate
            },
            persistResult: { plan, receipt, estimate, latitude, longitude in
                try await ScanFinalizationPersistence.persist(
                    plan: plan,
                    receipt: receipt,
                    estimate: estimate,
                    repository: repository,
                    fallbackLatitude: latitude,
                    fallbackLongitude: longitude
                )
            },
            markCompleted: { coordinator.markScanCompleted() },
            refreshHistory: refreshHistory,
            discardArtifacts: { draft in
                await Task.detached(priority: .utility) {
                    repository.settleCancelledDraft(draft)
                }.value
            }
        )
    }
}

@MainActor
final class ScanFinalizationWorkflow: ObservableObject {
    enum Failure: Equatable {
        case lifecycleRejected
        case pointCloudExport
        case pointCloudCaptureInvalid
        case yieldEstimation(String)
        case resultPersistence(String)
    }

    enum Phase: Equatable {
        case idle
        case exportingPointCloud
        case estimating
        case persisting
        case failed(Failure)
        case completed
        case cancelled
    }

    enum RetryAction: Equatable {
        case unavailable
        case exportPointCloud
        case estimateYield
        case persistResult
    }

    enum Event {
        case phaseChanged(Phase)
        case pointCloudExported(scanIdentity: UUID, filename: String)
        case estimateProduced(scanIdentity: UUID, result: YieldResult)
        case completed(scanIdentity: UUID, filename: String, result: YieldResult)
        case failed(scanIdentity: UUID?, failure: Failure)
        case cancelled(scanIdentity: UUID?)
    }

    var onEvent: ((Event) -> Void)?

    @Published private(set) var phase: Phase = .idle
    private(set) var scanIdentity: UUID?
    var filename: String? { draft?.sourceFilename }
    var result: YieldResult? { estimateResult?.result }
    private var estimateResult: ScanEstimate?
    private var evidenceReceipt: ScanEvidenceReceipt?
    @Published private(set) var cancellationSettlement: DraftSettlement?
    private var draft: DraftScan?
    private(set) var frozenPointCloud: FrozenPointCloudExport?
    private(set) var stagedPointCloud: StagedPointCloud?
    private(set) var estimationSnapshot: ScanEvidenceSnapshot?
    /// Capture consumes coordinator evidence. Keep that exact input before
    /// fallible archive IO so a retry cannot recapture an empty observation set.
    private(set) var capturedSnapshot: ScanYieldEstimationController.Snapshot?
    private var exportTask: Task<Void, Never>?
    private var estimationTask: Task<Void, Never>?

    private var workIdentity: ScanWorkID?
    private var plan: ScanPlan?
    private var fallbackLatitude: Double = 0
    private var fallbackLongitude: Double = 0
    private var operations: ScanFinalizationOperations?
    private var persistenceInFlight = false

    var retryAction: RetryAction {
        switch phase {
        case .failed(.pointCloudExport): return .exportPointCloud
        case .failed(.yieldEstimation): return .estimateYield
        case .failed(.resultPersistence): return .persistResult
        case .idle, .exportingPointCloud, .estimating, .persisting, .completed, .cancelled,
             .failed(.lifecycleRejected), .failed(.pointCloudCaptureInvalid): return .unavailable
        }
    }

    var isWorking: Bool {
        switch phase {
        case .exportingPointCloud, .estimating, .persisting: return true
        case .idle, .failed, .completed, .cancelled: return false
        }
    }

    func finish(
        plan: ScanPlan,
        latitude: Double,
        longitude: Double,
        operations: ScanFinalizationOperations
    ) {
        guard !isWorking else { return }
        switch phase {
        case .completed, .cancelled, .failed(.pointCloudCaptureInvalid):
            return
        case .failed(.pointCloudExport):
            self.operations = operations
            retryPointCloudExport()
            return
        case .failed(.resultPersistence):
            self.operations = operations
            retryPersistence()
            return
        case .failed(.yieldEstimation):
            self.operations = operations
            retryEstimation()
            return
        case .idle, .failed(.lifecycleRejected):
            break
        case .exportingPointCloud, .estimating, .persisting:
            return
        }

        let before = operations.lifecycleSnapshot()
        if before.state != .finishing, !operations.beginFinishing() {
            fail(.lifecycleRejected, scanIdentity: before.scanIdentity)
            return
        }
        let finishing = operations.lifecycleSnapshot()
        guard finishing.state == .finishing else {
            fail(.lifecycleRejected, scanIdentity: finishing.scanIdentity)
            return
        }

        self.operations = operations
        self.plan = plan
        self.scanIdentity = finishing.scanIdentity
        self.fallbackLatitude = latitude
        self.fallbackLongitude = longitude
        self.stagedPointCloud = nil
        self.frozenPointCloud = nil
        self.draft = nil
        self.estimationSnapshot = nil
        self.capturedSnapshot = nil
        self.cancellationSettlement = nil
        self.estimateResult = nil
        self.evidenceReceipt = nil
        retryPointCloudExport()
    }

    func retry() {
        guard !isWorking else { return }
        switch retryAction {
        case .exportPointCloud:
            retryPointCloudExport()
        case .estimateYield:
            retryEstimation()
        case .persistResult:
            retryPersistence()
        case .unavailable:
            return
        }
    }

    func resetForNewScan() {
        guard !isWorking else { return }
        workIdentity = nil
        persistenceInFlight = false
        scanIdentity = nil
        stagedPointCloud = nil
        frozenPointCloud = nil
        draft = nil
        estimationSnapshot = nil
        capturedSnapshot = nil
        exportTask?.cancel()
        exportTask = nil
        estimationTask?.cancel()
        estimationTask = nil
        cancellationSettlement = nil
        estimateResult = nil
        evidenceReceipt = nil
        plan = nil
        operations = nil
        fallbackLatitude = 0
        fallbackLongitude = 0
        setPhase(.idle)
    }

    func cancel() {
        guard phase != .completed, phase != .cancelled else { return }
        let oldScanIdentity = scanIdentity
        workIdentity = nil
        exportTask?.cancel()
        exportTask = nil
        estimationTask?.cancel()
        estimationTask = nil

        if !persistenceInFlight, let draft, let operations {
            settle(draft, scanIdentity: oldScanIdentity, operations: operations)
        }
        stagedPointCloud = nil
        frozenPointCloud = nil
        estimationSnapshot = nil
        capturedSnapshot = nil

        setPhase(.cancelled)
        onEvent?(.cancelled(scanIdentity: oldScanIdentity))
    }

    private func retryPointCloudExport() {
        guard let operations, let plan, let scanIdentity else {
            fail(.lifecycleRejected, scanIdentity: scanIdentity)
            return
        }
        guard isFinishing(operations, scanIdentity: scanIdentity) else {
            fail(.lifecycleRejected, scanIdentity: scanIdentity)
            return
        }

        let workIdentity = ScanWorkID()
        self.workIdentity = workIdentity
        let retainedFrozen = frozenPointCloud
        setPhase(.exportingPointCloud)
        let latitude = fallbackLatitude
        let longitude = fallbackLongitude
        exportTask = Task { @MainActor [weak self] in
            do {
                guard self?.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) == true else { return }
                let frozen: FrozenPointCloudExport
                if let retainedFrozen {
                    frozen = retainedFrozen
                } else {
                    frozen = try await operations.freezePointCloud(plan)
                    // Synchronous handoff ends before the stage await. Never
                    // retain a strong workflow while the writer is suspended.
                    guard try self?.acceptFrozenPointCloud(frozen, workIdentity: workIdentity,
                        scanIdentity: scanIdentity, plan: plan, operations: operations) == true else { return }
                }
                guard self?.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) == true else { return }
                let staged = try await operations.stagePointCloud(PointCloudStageInput(
                    frozen: frozen, treeID: plan.treeID, latitude: latitude, longitude: longitude
                ))
                guard let self,
                      self.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) else {
                    let settlement = await operations.discardArtifacts(staged.draft)
                    operations.refreshHistory()
                    self?.recordSettlement(settlement, scanIdentity: scanIdentity)
                    return
                }
                self.exportTask = nil
                self.frozenPointCloud = nil
                self.stagedPointCloud = staged
                self.draft = staged.draft
                self.onEvent?(.pointCloudExported(scanIdentity: scanIdentity, filename: staged.draft.sourceFilename))
                // Retain the exact cloud that was written, independent of renderer caches.
                self.estimate(workIdentity: workIdentity, scanIdentity: scanIdentity, operations: operations)
            } catch {
                guard let self, self.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) else { return }
                self.exportTask = nil
                Log.export.error("PLY export failed: \(error.localizedDescription)")
                let failure: Failure
                switch error {
                case PointCloudExportError.gpuWriteFailed, PointCloudExportError.captureChanged:
                    self.frozenPointCloud = nil
                    failure = .pointCloudCaptureInvalid
                default:
                    failure = .pointCloudExport
                }
                self.fail(failure, scanIdentity: scanIdentity)
            }
        }
    }

    private func acceptFrozenPointCloud(
        _ frozen: FrozenPointCloudExport,
        workIdentity: ScanWorkID,
        scanIdentity: UUID,
        plan: ScanPlan,
        operations: ScanFinalizationOperations
    ) throws -> Bool {
        guard accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) else { return false }
        guard let capture = frozen.captureIdentity,
              capture.context == ScanContext(scanID: scanIdentity, planID: plan.id),
              capture.pointCloud == frozen.pointCloud.identity else {
            throw PointCloudExportError.captureChanged
        }
        frozenPointCloud = frozen
        return true
    }

    private func estimate(
        workIdentity: ScanWorkID,
        scanIdentity: UUID,
        operations: ScanFinalizationOperations
    ) {
        guard accepts(workIdentity, scanIdentity: scanIdentity, operations: operations),
              let plan, let stagedPointCloud else { return }
        setPhase(.estimating)
        estimationTask = Task { @MainActor [weak self] in
            do {
                let snapshot: ScanEvidenceSnapshot
                if let existing = self?.estimationSnapshot {
                    snapshot = existing
                } else {
                    let input: ScanYieldEstimationController.Snapshot
                    if let captured = self?.capturedSnapshot {
                        input = captured
                    } else {
                        input = try await operations.captureSnapshot(plan.season, stagedPointCloud)
                        try Task.checkCancellation()
                        guard self?.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) == true else { return }
                        guard input.context == ScanContext(scanID: scanIdentity, planID: plan.id),
                              input.input.finalPointCloudIdentity == stagedPointCloud.pointCloud.identity else {
                            throw ScanEvidenceError.mismatchedInput
                        }
                        self?.capturedSnapshot = input
                    }
                    snapshot = try await operations.bindSnapshot(input, stagedPointCloud, plan)
                    guard snapshot.snapshot.id == input.id, snapshot.identity.snapshotID == input.id else {
                        throw ScanEvidenceError.mismatchedInput
                    }
                }
                try Task.checkCancellation()
                guard self?.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) == true else { return }
                guard snapshot.identity.capture.context == ScanContext(scanID: scanIdentity, planID: plan.id),
                      snapshot.identity.capture.pointCloud == stagedPointCloud.pointCloud.identity,
                      snapshot.receipt.draft == stagedPointCloud.draft else {
                    throw ScanEvidenceError.mismatchedInput
                }
                self?.estimationSnapshot = snapshot
                self?.capturedSnapshot = nil
                self?.evidenceReceipt = snapshot.receipt
                let estimate = try await operations.estimateYield(snapshot)
                try Task.checkCancellation()
                guard let self, self.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) else { return }
                guard estimate.evidenceIdentity == snapshot.identity else { throw ScanEvidenceError.mismatchedInput }
                self.estimationTask = nil
                self.stagedPointCloud = nil
                self.estimationSnapshot = nil
                self.estimateResult = estimate
                self.onEvent?(.estimateProduced(scanIdentity: scanIdentity, result: estimate.result))
                self.persist(
                    estimate: estimate,
                    workIdentity: workIdentity,
                    scanIdentity: scanIdentity,
                    operations: operations
                )
            } catch {
                guard let self, self.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) else { return }
                self.estimationTask = nil
                self.fail(.yieldEstimation(error.localizedDescription), scanIdentity: scanIdentity)
            }
        }
    }

    private func retryEstimation() {
        guard let operations, let scanIdentity,
              isFinishing(operations, scanIdentity: scanIdentity) else {
            fail(.lifecycleRejected, scanIdentity: scanIdentity)
            return
        }
        let identity = ScanWorkID()
        workIdentity = identity
        estimate(workIdentity: identity, scanIdentity: scanIdentity, operations: operations)
    }

    private func retryPersistence() {
        guard let operations, let estimateResult, filename != nil, let scanIdentity,
              isFinishing(operations, scanIdentity: scanIdentity) else {
            fail(.lifecycleRejected, scanIdentity: scanIdentity)
            return
        }
        let workIdentity = ScanWorkID()
        self.workIdentity = workIdentity
        persist(estimate: estimateResult, workIdentity: workIdentity, scanIdentity: scanIdentity, operations: operations)
    }

    private func persist(
        estimate: ScanEstimate,
        workIdentity: ScanWorkID,
        scanIdentity: UUID,
        operations: ScanFinalizationOperations
    ) {
        guard let plan, let draft, let evidenceReceipt,
              accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) else { return }
        let filename = draft.sourceFilename
        persistenceInFlight = true
        setPhase(.persisting)
        let latitude = fallbackLatitude
        let longitude = fallbackLongitude
        Task { @MainActor [weak self] in
            do {
                try await operations.persistResult(plan, evidenceReceipt, estimate, latitude, longitude)
                // Repository completion belongs to the operation even if its UI
                // has disappeared or a newer scan has replaced the projection.
                operations.refreshHistory()
                guard let self,
                      self.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) else {
                    self?.recordSettlement(.preservedCommitted, scanIdentity: scanIdentity)
                    return
                }
                self.persistenceInFlight = false
                self.workIdentity = nil
                operations.markCompleted()
                self.setPhase(.completed)
                self.onEvent?(.completed(scanIdentity: scanIdentity, filename: filename, result: estimate.result))
            } catch {
                guard let self,
                      self.accepts(workIdentity, scanIdentity: scanIdentity, operations: operations) else {
                    let settlement = await operations.discardArtifacts(draft)
                    operations.refreshHistory()
                    self?.recordSettlement(settlement, scanIdentity: scanIdentity)
                    return
                }
                self.persistenceInFlight = false
                self.workIdentity = nil
                self.fail(.resultPersistence(error.localizedDescription), scanIdentity: scanIdentity)
            }
        }
    }

    private func settle(_ draft: DraftScan, scanIdentity: UUID?, operations: ScanFinalizationOperations) {
        Task { @MainActor [weak self] in
            let settlement = await operations.discardArtifacts(draft)
            operations.refreshHistory()
            self?.recordSettlement(settlement, scanIdentity: scanIdentity)
        }
    }

    private func recordSettlement(_ settlement: DraftSettlement, scanIdentity: UUID?) {
        if case .requiresRecovery(let reason) = settlement {
            Log.export.error("Cancelled scan requires recovery: \(reason)")
        }
        guard self.scanIdentity == scanIdentity, phase == .cancelled else { return }
        cancellationSettlement = settlement
        persistenceInFlight = false
    }

    private func isFinishing(_ operations: ScanFinalizationOperations, scanIdentity: UUID) -> Bool {
        let snapshot = operations.lifecycleSnapshot()
        return snapshot.scanIdentity == scanIdentity && snapshot.state == .finishing
    }

    private func accepts(
        _ workIdentity: ScanWorkID,
        scanIdentity: UUID,
        operations: ScanFinalizationOperations
    ) -> Bool {
        self.workIdentity == workIdentity && isFinishing(operations, scanIdentity: scanIdentity)
    }

    private func fail(_ failure: Failure, scanIdentity: UUID?) {
        workIdentity = nil
        let owner = self.scanIdentity
        setPhase(.failed(failure))
        // A phase observer may synchronously cancel/reset and start a new scan.
        // Keep the pre-initialization lifecycleRejected event, whose owner is nil.
        guard phase == .failed(failure), self.scanIdentity == owner else { return }
        onEvent?(.failed(scanIdentity: scanIdentity, failure: failure))
    }

    private func setPhase(_ phase: Phase) {
        self.phase = phase
        onEvent?(.phaseChanged(phase))
    }
}

private enum ScanFinalizationPersistence {
    static func persist(
        plan: ScanPlan,
        receipt: ScanEvidenceReceipt,
        estimate: ScanEstimate,
        repository: ScanRepository,
        fallbackLatitude: Double,
        fallbackLongitude: Double
    ) async throws {
        let fileURL = receipt.draft.sourceURL
        try await Task.detached(priority: .utility) {
            guard receipt.identity.capture.context.planID == plan.id else {
                throw ScanEvidenceError.mismatchedInput
            }
            let metadata = try repository.readRecord(at: fileURL)
            let assessment = ScanAssessment(
                receipt: receipt,
                estimate: estimate,
                treeID: plan.treeID,
                fruitType: plan.fruitConfiguration.selectedCategory.rawValue,
                scanDate: metadata?.scanDate ?? Date(),
                gpsLat: metadata?.gpsLat ?? fallbackLatitude,
                gpsLon: metadata?.gpsLon ?? fallbackLongitude,
                includeCSV: plan.autoExportCSV,
                classification: plan.classification
            )
            _ = try repository.commit(assessment)
        }.value
    }
}
