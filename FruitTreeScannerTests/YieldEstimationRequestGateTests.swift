import XCTest
@testable import FruitTreeScanner

@MainActor
final class YieldEstimationRequestGateTests: XCTestCase {
    func testNewRequestRejectsOlderGeneration() {
        var gate = YieldEstimationRequestGate()
        let firstGeneration = gate.beginRequest()
        let secondGeneration = gate.beginRequest()

        XCTAssertFalse(gate.accepts(firstGeneration))
        XCTAssertTrue(gate.accepts(secondGeneration))
    }

    func testInvalidationRejectsCurrentGeneration() {
        var gate = YieldEstimationRequestGate()
        let generation = gate.beginRequest()

        gate.invalidate()

        XCTAssertFalse(gate.accepts(generation))
    }

    func testOnlyLatestRequestCanCommitAfterRepeatedRequests() {
        var gate = YieldEstimationRequestGate()
        let firstGeneration = gate.beginRequest()
        let secondGeneration = gate.beginRequest()
        let thirdGeneration = gate.beginRequest()

        XCTAssertFalse(gate.accepts(firstGeneration))
        XCTAssertFalse(gate.accepts(secondGeneration))
        XCTAssertTrue(gate.accepts(thirdGeneration))
    }

    func testControllerRejectsStaleRequestBeforeSnapshotPreparation() async {
        let controller = ScanYieldEstimationController()
        var preparedRequests: [String] = []
        var deliveredCount = 0

        controller.start(
            season: .mature,
            flushPendingDetections: {
                try? await Task.sleep(nanoseconds: 80_000_000)
            },
            makeSnapshot: { _ in
                preparedRequests.append("first")
                return self.makeSnapshot()
            },
            completion: { _, _ in
                deliveredCount += 1
            }
        )
        controller.start(
            season: .mature,
            flushPendingDetections: {},
            makeSnapshot: { _ in
                preparedRequests.append("second")
                return self.makeSnapshot()
            },
            completion: { _, _ in
                deliveredCount += 1
            }
        )

        try? await Task.sleep(nanoseconds: 200_000_000)

        XCTAssertEqual(preparedRequests, ["second"])
        XCTAssertEqual(deliveredCount, 1)
    }

    func testControllerCancellationPreventsSnapshotAndResultDelivery() async {
        let controller = ScanYieldEstimationController()
        var snapshotPrepared = false
        var resultDelivered = false

        controller.start(
            season: .mature,
            flushPendingDetections: {
                try? await Task.sleep(nanoseconds: 80_000_000)
            },
            makeSnapshot: { _ in
                snapshotPrepared = true
                return self.makeSnapshot()
            },
            completion: { _, _ in
                resultDelivered = true
            }
        )
        controller.cancel()

        try? await Task.sleep(nanoseconds: 120_000_000)

        XCTAssertFalse(snapshotPrepared)
        XCTAssertFalse(resultDelivered)
    }

    private func makeSnapshot() -> ScanYieldEstimationController.Snapshot {
        let params = FruitVarietyParams(category: .apple)
        return ScanYieldEstimationController.Snapshot(
            input: .init(
                points: [],
                savedDetections: [],
                imageDiagnostics: ImageDetectionDiagnostics(),
                fruitType: FruitCategory.apple.rawValue,
                fruitCategory: .apple,
                paramsSnapshot: [FruitCategory.apple.rawValue: params],
                defaultParams: params,
                clusterConfig: .default,
                fusionConfig: .default,
                colorFilter: nil
            )
        )
    }
}
