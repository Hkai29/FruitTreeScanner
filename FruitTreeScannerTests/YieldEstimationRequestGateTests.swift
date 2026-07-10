import XCTest
@testable import FruitTreeScanner

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
}
