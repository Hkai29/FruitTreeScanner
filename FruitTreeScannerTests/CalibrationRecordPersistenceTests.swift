import XCTest
@testable import FruitTreeScanner

final class CalibrationRecordPersistenceTests: XCTestCase {
    func testMissingCalibrationRecordFileLoadsAsEmpty() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("missing")
            .appendingPathExtension("json")

        XCTAssertEqual(try CalibrationRecordPersistence.load(from: url).count, 0)
    }

    func testCalibrationRecordRoundTripKeepsValues() throws {
        let url = temporaryDirectory()
            .appendingPathComponent("records")
            .appendingPathExtension("json")
        let record = CalibrationRecord(
            id: UUID(uuidString: "A3A3A3A3-A3A3-4A3A-8A3A-A3A3A3A3A3A3")!,
            treeID: "T-01",
            scanDate: Date(timeIntervalSince1970: 1_780_000_000),
            estimatedFruitCount: 42,
            manualFruitCount: 40,
            estimatedYieldKg: 8.5,
            actualYieldKg: 8.0,
            fruitType: "apple"
        )

        try CalibrationRecordPersistence.save([record], to: url)

        let loaded = try CalibrationRecordPersistence.load(from: url)
        XCTAssertEqual(loaded.count, 1)
        XCTAssertEqual(loaded[0].id, record.id)
        XCTAssertEqual(loaded[0].treeID, "T-01")
        XCTAssertEqual(loaded[0].estimatedFruitCount, 42)
        XCTAssertEqual(loaded[0].manualFruitCount, 40)
        XCTAssertEqual(loaded[0].estimatedYieldKg, 8.5, accuracy: 0.000_1)
        let actualYieldKg = try XCTUnwrap(loaded[0].actualYieldKg)
        XCTAssertEqual(actualYieldKg, 8.0, accuracy: 0.000_1)
        XCTAssertEqual(loaded[0].fruitType, "apple")
    }

    func testStaleCalibrationGenerationCannotOverwriteNewerRecords() async throws {
        let url = temporaryDirectory().appendingPathComponent("records.json")
        let old = makeRecord(fruitType: "apple", estimatedCount: 1, manualCount: 1, estimatedYield: 1, actualYield: 1)
        let newer = makeRecord(fruitType: "pear", estimatedCount: 2, manualCount: 2, estimatedYield: 2, actualYield: 2)
        let controller = CalibrationRecordPersistenceController(url: url)

        let newerSaved = await controller.save([newer], generation: 2)
        let staleSaved = await controller.save([old], generation: 1)
        XCTAssertTrue(newerSaved)
        XCTAssertFalse(staleSaved)
        XCTAssertEqual(try CalibrationRecordPersistence.load(from: url).map(\.id), [newer.id])
    }

    @MainActor
    func testSaveRevisionRemainsMonotonicWhenCalibrationViewIsRecreated() async throws {
        let url = temporaryDirectory().appendingPathComponent("records.json")
        let firstViewRecord = makeRecord(
            fruitType: "apple",
            estimatedCount: 1,
            manualCount: 1,
            estimatedYield: 1,
            actualYield: 1
        )
        let reopenedViewRecord = makeRecord(
            fruitType: "pear",
            estimatedCount: 2,
            manualCount: 2,
            estimatedYield: 2,
            actualYield: 2
        )
        let revisions = CalibrationSaveRevisionSource()
        let controller = CalibrationRecordPersistenceController(url: url)

        let firstViewRevisions = (0..<3).map { _ in revisions.nextRevision() }
        let firstViewSaved = await controller.save(
            [firstViewRecord],
            generation: try XCTUnwrap(firstViewRevisions.last)
        )

        let reopenedViewFirstRevision = revisions.nextRevision()
        let reopenedViewSaved = await controller.save(
            [reopenedViewRecord],
            generation: reopenedViewFirstRevision
        )

        XCTAssertTrue(firstViewSaved)
        XCTAssertGreaterThan(reopenedViewFirstRevision, try XCTUnwrap(firstViewRevisions.last))
        XCTAssertTrue(reopenedViewSaved)
        XCTAssertEqual(
            try CalibrationRecordPersistence.load(from: url).map(\.id),
            [reopenedViewRecord.id]
        )
    }

    func testRapidCalibrationAddAddDeletePersistsLatestSnapshot() async throws {
        let url = temporaryDirectory().appendingPathComponent("records.json")
        let a = makeRecord(fruitType: "apple", estimatedCount: 1, manualCount: 1, estimatedYield: 1, actualYield: 1)
        let b = makeRecord(fruitType: "pear", estimatedCount: 2, manualCount: 2, estimatedYield: 2, actualYield: 2)
        let controller = CalibrationRecordPersistenceController(url: url)

        _ = await controller.save([a], generation: 1)
        _ = await controller.save([a, b], generation: 2)
        _ = await controller.save([b], generation: 3)

        XCTAssertEqual(try CalibrationRecordPersistence.load(from: url).map(\.id), [b.id])
    }

    func testCalibrationWriteFailurePreservesExistingCompleteFileAndReportsError() async throws {
        let url = temporaryDirectory().appendingPathComponent("records.json")
        let existing = makeRecord(fruitType: "apple", estimatedCount: 1, manualCount: 1, estimatedYield: 1, actualYield: 1)
        let replacement = makeRecord(fruitType: "pear", estimatedCount: 2, manualCount: 2, estimatedYield: 2, actualYield: 2)
        try CalibrationRecordPersistence.save([existing], to: url)
        let controller = CalibrationRecordPersistenceController(url: url) { _, _ in
            throw CocoaError(.fileWriteNoPermission)
        }

        let saved = await controller.save([replacement], generation: 1)
        let error = await controller.lastErrorDescription
        XCTAssertFalse(saved)
        XCTAssertNotNil(error)
        XCTAssertEqual(try CalibrationRecordPersistence.load(from: url).map(\.id), [existing.id])
    }

    @MainActor
    func testCalibrationLoadFailurePreservesSnapshotAndBlocksMutationUntilRetry() async {
        let initial = makeRecord(
            fruitType: "apple",
            estimatedCount: 10,
            manualCount: 9,
            estimatedYield: 4,
            actualYield: 3.8
        )
        let repaired = makeRecord(
            fruitType: "pear",
            estimatedCount: 12,
            manualCount: 11,
            estimatedYield: 5,
            actualYield: 4.7
        )
        let rejected = makeRecord(
            fruitType: "orange",
            estimatedCount: 20,
            manualCount: 18,
            estimatedYield: 8,
            actualYield: 7.5
        )
        let driver = CalibrationRecordLoadSequenceDriver(results: [
            .success([initial]),
            .failure(.unavailable),
            .success([repaired])
        ])
        let store = CalibrationRecordStore(recordsLoader: { await driver.next() })

        await store.reloadRecords()
        XCTAssertEqual(store.records.map(\.id), [initial.id])
        XCTAssertTrue(store.canMutate)

        await store.reloadRecords()
        XCTAssertEqual(
            store.records.map(\.id),
            [initial.id],
            "A failed refresh must retain the last verified calibration snapshot"
        )
        XCTAssertEqual(store.loadFailure, .unavailable)
        XCTAssertFalse(store.canMutate)
        XCTAssertNil(store.prepend(rejected))
        XCTAssertNil(store.remove(id: initial.id))
        XCTAssertEqual(store.records.map(\.id), [initial.id])

        await store.reloadRecords()
        XCTAssertEqual(store.records.map(\.id), [repaired.id])
        XCTAssertNil(store.loadFailure)
        XCTAssertTrue(store.canMutate)
    }

    @MainActor
    func testCalibrationSuccessfulEmptyLoadAllowsFirstMutation() async {
        let record = makeRecord(
            fruitType: "apple",
            estimatedCount: 10,
            manualCount: 9,
            estimatedYield: 4,
            actualYield: 3.8
        )
        let store = CalibrationRecordStore(recordsLoader: { .success([]) })

        await store.reloadRecords()

        XCTAssertTrue(store.hasLoaded)
        XCTAssertTrue(store.canMutate)
        XCTAssertEqual(store.prepend(record)?.map(\.id), [record.id])
        XCTAssertEqual(store.records.map(\.id), [record.id])
    }

    @MainActor
    func testSupersededCalibrationLoadCannotOverwriteNewerSnapshot() async {
        let older = makeRecord(
            fruitType: "apple",
            estimatedCount: 10,
            manualCount: 9,
            estimatedYield: 4,
            actualYield: 3.8
        )
        let newer = makeRecord(
            fruitType: "pear",
            estimatedCount: 12,
            manualCount: 11,
            estimatedYield: 5,
            actualYield: 4.7
        )
        let driver = CalibrationRecordControlledLoadDriver()
        let store = CalibrationRecordStore(recordsLoader: { await driver.load() })

        let olderTask = store.loadRecords()
        await driver.waitForPendingCount(1)
        let newerTask = store.loadRecords()
        await driver.waitForPendingCount(2)

        await driver.resume(request: 1, with: .success([newer]))
        await newerTask.value
        XCTAssertEqual(store.records.map(\.id), [newer.id])

        await driver.resume(request: 0, with: .success([older]))
        await olderTask.value
        XCTAssertEqual(store.records.map(\.id), [newer.id])
        XCTAssertFalse(store.isLoading)
    }

    @MainActor
    func testCancelledCalibrationLoadCannotApplyAfterViewTeardown() async {
        let late = makeRecord(
            fruitType: "apple",
            estimatedCount: 10,
            manualCount: 9,
            estimatedYield: 4,
            actualYield: 3.8
        )
        let driver = CalibrationRecordControlledLoadDriver()
        let store = CalibrationRecordStore(recordsLoader: { await driver.load() })

        let task = store.loadRecords()
        await driver.waitForPendingCount(1)
        store.invalidateLoad()
        await driver.resume(request: 0, with: .success([late]))
        await task.value

        XCTAssertTrue(store.records.isEmpty)
        XCTAssertFalse(store.hasLoaded)
        XCTAssertFalse(store.isLoading)
        XCTAssertFalse(store.canMutate)
    }

    func testCalibrationLoadPresentationNeverTreatsFailureAsEmptyRecords() {
        let presentation = CalibrationRecordLoadPresentation(
            records: [],
            isLoading: false,
            hasLoaded: false,
            loadFailure: .unavailable
        )

        XCTAssertEqual(presentation.primaryContent, .loadFailure)
        XCTAssertFalse(presentation.allowsMutation)
        XCTAssertFalse(presentation.showsStatistics)
    }

    @MainActor
    func testMalformedCalibrationRecordFileFailsClosedAndCannotBeOverwritten() async throws {
        let url = temporaryDirectory().appendingPathComponent("malformed.json")
        try Data("not-json".utf8).write(to: url)
        let replacement = makeRecord(
            fruitType: "apple",
            estimatedCount: 10,
            manualCount: 9,
            estimatedYield: 4,
            actualYield: 3.8
        )
        let store = CalibrationRecordStore(recordsLoader: {
            do {
                return .success(try CalibrationRecordPersistence.load(from: url))
            } catch {
                return .failure(.unavailable)
            }
        })

        await store.reloadRecords()

        XCTAssertThrowsError(try CalibrationRecordPersistence.load(from: url))
        XCTAssertEqual(store.loadFailure, .unavailable)
        XCTAssertNil(store.prepend(replacement))
        XCTAssertEqual(try Data(contentsOf: url), Data("not-json".utf8))
    }

    func testYieldCalibrationCorrectionUsesMatchingFruitTypeMedianRatios() {
        let records = [
            makeRecord(fruitType: "苹果", estimatedCount: 10, manualCount: 8, estimatedYield: 5, actualYield: 4),
            makeRecord(fruitType: "apple", estimatedCount: 20, manualCount: 18, estimatedYield: 9, actualYield: 8.1),
            makeRecord(fruitType: "橙子", estimatedCount: 10, manualCount: 30, estimatedYield: 1, actualYield: 3),
        ]

        let correction = YieldCalibrationCorrector.correction(
            from: records,
            fruitCategory: .apple,
            fruitType: "apple"
        )

        XCTAssertEqual(correction.countSampleCount, 2)
        XCTAssertEqual(correction.yieldSampleCount, 2)
        XCTAssertEqual(correction.countFactor, 0.85, accuracy: 0.001)
        XCTAssertEqual(correction.yieldFactor, 0.85, accuracy: 0.001)
    }

    func testYieldCalibrationCorrectionClampsExtremeRatios() {
        let records = [
            makeRecord(fruitType: "苹果", estimatedCount: 1, manualCount: 4, estimatedYield: 1, actualYield: 4),
        ]

        let correction = YieldCalibrationCorrector.correction(
            from: records,
            fruitCategory: .apple,
            fruitType: "苹果"
        )

        XCTAssertEqual(correction.countFactor, 1.5, accuracy: 0.001)
        XCTAssertEqual(correction.yieldFactor, 2.0, accuracy: 0.001)
    }

    func testYieldCalibrationCorrectionReturnsNeutralWithoutMatchingEvidence() {
        let records = [
            makeRecord(fruitType: "橙子", estimatedCount: 10, manualCount: 8, estimatedYield: 4, actualYield: 3.5),
            makeRecord(fruitType: "苹果", estimatedCount: 0, manualCount: 8, estimatedYield: 0, actualYield: 3.5),
        ]

        let correction = YieldCalibrationCorrector.correction(
            from: records,
            fruitCategory: .apple,
            fruitType: "apple"
        )

        XCTAssertEqual(correction, .neutral)
    }

    func testCalibrationValidationMetricsUsesAbsoluteErrorsWithoutCancellation() throws {
        let records = [
            makeRecord(fruitType: "apple", estimatedCount: 12, manualCount: 10, estimatedYield: 6, actualYield: 5),
            makeRecord(fruitType: "apple", estimatedCount: 8, manualCount: 10, estimatedYield: 4, actualYield: 5),
        ]

        let metrics = CalibrationValidationMetrics.make(from: records)

        XCTAssertEqual(metrics.recordCount, 2)
        XCTAssertEqual(metrics.countSampleCount, 2)
        XCTAssertEqual(metrics.yieldSampleCount, 2)
        XCTAssertEqual(try XCTUnwrap(metrics.countMAE), 2, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.countMAPE), 20, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.countRMSE), 2, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.yieldMAE), 1, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.yieldMAPE), 20, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.yieldRMSE), 1, accuracy: 0.000_1)
    }

    func testCalibrationValidationMetricsSkipsInvalidGroundTruthSamples() throws {
        let records = [
            makeRecord(fruitType: "apple", estimatedCount: 12, manualCount: nil, estimatedYield: 6, actualYield: nil),
            makeRecord(fruitType: "apple", estimatedCount: 12, manualCount: 0, estimatedYield: 6, actualYield: 0),
            makeRecord(fruitType: "apple", estimatedCount: 10, manualCount: 8, estimatedYield: .nan, actualYield: 5),
            makeRecord(fruitType: "apple", estimatedCount: 9, manualCount: 9, estimatedYield: 4, actualYield: 5),
        ]

        let metrics = CalibrationValidationMetrics.make(from: records)

        XCTAssertTrue(metrics.hasEvidence)
        XCTAssertEqual(metrics.recordCount, 2)
        XCTAssertEqual(metrics.countSampleCount, 2)
        XCTAssertEqual(metrics.yieldSampleCount, 1)
        XCTAssertEqual(try XCTUnwrap(metrics.countMAE), 1, accuracy: 0.000_1)
        XCTAssertEqual(try XCTUnwrap(metrics.yieldMAE), 1, accuracy: 0.000_1)
    }

    private func temporaryDirectory() -> URL {
        let url = FileManager.default.temporaryDirectory
            .appendingPathComponent(UUID().uuidString, isDirectory: true)
        try? FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    private func makeRecord(
        fruitType: String,
        estimatedCount: Int,
        manualCount: Int?,
        estimatedYield: Double,
        actualYield: Double?
    ) -> CalibrationRecord {
        CalibrationRecord(
            id: UUID(),
            treeID: "T-\(UUID().uuidString)",
            scanDate: Date(timeIntervalSince1970: 1_780_000_000),
            estimatedFruitCount: estimatedCount,
            manualFruitCount: manualCount,
            estimatedYieldKg: estimatedYield,
            actualYieldKg: actualYield,
            fruitType: fruitType
        )
    }
}

private actor CalibrationRecordLoadSequenceDriver {
    private var results: [CalibrationRecordLoadResult]

    init(results: [CalibrationRecordLoadResult]) {
        self.results = results
    }

    func next() -> CalibrationRecordLoadResult {
        precondition(!results.isEmpty, "Test requested more calibration loads than configured")
        return results.removeFirst()
    }
}

private actor CalibrationRecordControlledLoadDriver {
    private var continuations: [Int: CheckedContinuation<CalibrationRecordLoadResult, Never>] = [:]
    private var nextRequest = 0

    func load() async -> CalibrationRecordLoadResult {
        let request = nextRequest
        nextRequest += 1
        return await withCheckedContinuation { continuation in
            continuations[request] = continuation
        }
    }

    func waitForPendingCount(_ expectedCount: Int) async {
        while continuations.count < expectedCount {
            await Task.yield()
        }
    }

    func resume(request: Int, with result: CalibrationRecordLoadResult) {
        guard let continuation = continuations.removeValue(forKey: request) else {
            preconditionFailure("No pending calibration load for request \(request)")
        }
        continuation.resume(returning: result)
    }
}
