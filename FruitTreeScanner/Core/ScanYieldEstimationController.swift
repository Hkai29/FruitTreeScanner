import Foundation
import os

struct YieldEstimationRequestGate: Sendable {
    private(set) var currentGeneration: UInt64 = 0

    mutating func beginRequest() -> UInt64 {
        currentGeneration &+= 1
        return currentGeneration
    }

    mutating func invalidate() {
        currentGeneration &+= 1
    }

    func accepts(_ generation: UInt64) -> Bool {
        generation == currentGeneration
    }
}

final class ScanYieldEstimationController {
    struct Snapshot: Sendable {
        let id = UUID()
        let context: ScanContext?
        let input: ScanFusionYieldBuilder.Input

        init(context: ScanContext? = nil, input: ScanFusionYieldBuilder.Input) {
            self.context = context
            self.input = input
        }
    }

    enum PreparationError: Error {
        case snapshotUnavailable
    }

    /// The finalization workflow retains this immutable input for retries.
    /// Cancellation propagates to computation and always has a terminal result.
    static func estimate(_ evidence: ScanEvidenceSnapshot) async throws -> ScanEstimate {
        try Task.checkCancellation()
        let worker = Task.detached(priority: .userInitiated) {
            try Task.checkCancellation()
            let (result, _) = await ScanFusionYieldBuilder.build(from: evidence.snapshot.input)
            try Task.checkCancellation()
            return ScanEstimate(evidenceIdentity: evidence.identity, result: result)
        }
        return try await withTaskCancellationHandler(
            operation: { try await worker.value },
            onCancel: { worker.cancel() }
        )
    }

    private var requestGate = YieldEstimationRequestGate()
    private var estimationTask: Task<Void, Never>?

    @MainActor
    func start(
        season: Season,
        flushPendingDetections: @escaping () async -> Void,
        makeSnapshot: @escaping (Season) -> Snapshot?,
        completion: @escaping (YieldResult, FruitCountResult) -> Void
    ) {
        let generation = beginRequest()

        estimationTask = Task { @MainActor [weak self] in
            guard let self else { return }

            await flushPendingDetections()
            guard !Task.isCancelled,
                  self.requestGate.accepts(generation),
                  let snapshot = makeSnapshot(season) else {
                return
            }

            let builderTask = Task.detached(priority: .userInitiated) { [weak self, snapshot] in
                let input = snapshot.input
                guard !Task.isCancelled else { return }

                Log.fusion.info("Starting yield estimation: \(input.points.count) points, \(input.observations.count) detections")
                let (result, countResult) = await ScanFusionYieldBuilder.build(from: input)
                guard !Task.isCancelled else { return }

                Log.fusion.info("Yield estimate complete: \(result.yieldFinalKg, format: .fixed(precision: 2))kg, confidence=\(result.confidence), method=\(result.methodUsed)")
                await self?.deliver(
                    result,
                    countResult: countResult,
                    generation: generation,
                    completion: completion
                )
            }

            guard self.requestGate.accepts(generation) else {
                builderTask.cancel()
                return
            }
            self.estimationTask = builderTask
        }
    }

    @MainActor
    func cancel() {
        requestGate.invalidate()
        estimationTask?.cancel()
        estimationTask = nil
    }

    @MainActor
    private func beginRequest() -> UInt64 {
        estimationTask?.cancel()
        estimationTask = nil
        return requestGate.beginRequest()
    }

    @MainActor
    private func deliver(
        _ result: YieldResult,
        countResult: FruitCountResult,
        generation: UInt64,
        completion: @escaping (YieldResult, FruitCountResult) -> Void
    ) {
        guard requestGate.accepts(generation) else { return }

        estimationTask = nil
        completion(result, countResult)
    }
}
