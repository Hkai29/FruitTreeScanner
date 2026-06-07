import XCTest
@testable import FruitTreeScanner

final class DashboardSummaryTests: XCTestCase {

    func testSummaryCountsOnlyTodaysRecordsAndUniqueTrees() {
        let calendar = Calendar(identifier: .gregorian)
        let now = Date()
        let yesterday = calendar.date(byAdding: .day, value: -1, to: now)!

        let records = [
            makeRecord(id: "scan-1", treeID: "T-001", scanDate: now, yieldKg: 4.25),
            makeRecord(id: "scan-2", treeID: "T-001", scanDate: now, yieldKg: 2.75),
            makeRecord(id: "scan-3", treeID: "T-002", scanDate: now, yieldKg: 3.0),
            makeRecord(id: "scan-4", treeID: "T-999", scanDate: yesterday, yieldKg: 99.0)
        ]

        let summary = DashboardDailySummary(records: records, calendar: calendar)

        XCTAssertEqual(summary.scanCount, 3)
        XCTAssertEqual(summary.treeCount, 2)
        XCTAssertEqual(summary.yieldKg, 10.0, accuracy: 0.001)
    }

    func testSummaryIsZeroForEmptyRecords() {
        let summary = DashboardDailySummary(records: [])

        XCTAssertEqual(summary.scanCount, 0)
        XCTAssertEqual(summary.treeCount, 0)
        XCTAssertEqual(summary.yieldKg, 0, accuracy: 0.001)
    }

    private func makeRecord(
        id: String,
        treeID: String,
        scanDate: Date,
        yieldKg: Float
    ) -> ScanFileRecord {
        ScanFileRecord(
            id: id,
            treeID: treeID,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).ply"),
            scanDate: scanDate,
            yieldKg: yieldKg
        )
    }
}
