import XCTest
@testable import FruitTreeScanner

final class DashboardSummaryTests: XCTestCase {

    @MainActor
    func testNavigationRouterReceivesRequestPostedAfterInitialization() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let notificationCenter = NotificationCenter()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: notificationCenter
        )

        defaults.set(AppNavigation.history.rawValue, forKey: AppNavigation.defaultsKey)
        notificationCenter.post(
            name: AppNavigation.notificationName,
            object: AppNavigation.history.rawValue
        )

        XCTAssertEqual(router.pendingDestination?.rawValue, AppNavigation.history.rawValue)
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    @MainActor
    func testNavigationRouterConsumesPersistedColdStartRequest() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set(AppNavigation.map.rawValue, forKey: AppNavigation.defaultsKey)

        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertEqual(router.pendingDestination?.rawValue, AppNavigation.map.rawValue)
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    @MainActor
    func testNavigationRouterDropsInvalidPersistedColdStartRequest() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        defer { defaults.removePersistentDomain(forName: suiteName) }

        defaults.set("not-a-navigation-target", forKey: AppNavigation.defaultsKey)

        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: NotificationCenter()
        )

        XCTAssertNil(router.pendingDestination)
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

    @MainActor
    func testNavigationRouterIgnoresInvalidNotificationAndClearsMatchingPersistedRequest() {
        let suiteName = "NavigationRouterTests.\(UUID().uuidString)"
        let defaults = UserDefaults(suiteName: suiteName)!
        let notificationCenter = NotificationCenter()
        defer { defaults.removePersistentDomain(forName: suiteName) }

        let router = NavigationRouter(
            defaults: defaults,
            notificationCenter: notificationCenter
        )

        defaults.set("not-a-navigation-target", forKey: AppNavigation.defaultsKey)
        notificationCenter.post(
            name: AppNavigation.notificationName,
            object: "not-a-navigation-target"
        )

        XCTAssertNil(router.pendingDestination)
        XCTAssertNil(defaults.string(forKey: AppNavigation.defaultsKey))
    }

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

    func testOrchardMapDataIncludesOnlyCompleteLocatedRecords() throws {
        let records = [
            makeRecord(
                id: "complete",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 100),
                fruitCount: 21,
                yieldKg: 4.25,
                gpsLat: 31.2304,
                gpsLon: 121.4737,
                confidence: "high"
            ),
            makeRecord(
                id: "incomplete",
                treeID: "T-ERR-1",
                scanDate: Date(timeIntervalSince1970: 200),
                fruitCount: 0,
                yieldKg: 0,
                gpsLat: 31.2315,
                gpsLon: 121.4748,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "T-ERR-2",
                scanDate: Date(timeIntervalSince1970: 300),
                fruitCount: 0,
                yieldKg: 0,
                gpsLat: 31.2326,
                gpsLon: 121.4759,
                persistenceState: .invalid
            ),
            makeRecord(
                id: "unlocated",
                treeID: "T-002",
                scanDate: Date(timeIntervalSince1970: 400),
                yieldKg: 8
            )
        ]

        let mapData = OrchardMapData(records: records)
        let tree = try XCTUnwrap(mapData.trees.first)

        XCTAssertEqual(mapData.trees.map(\.id), ["complete"])
        XCTAssertEqual(tree.treeID, "T-001")
        XCTAssertEqual(tree.coordinate.latitude, 31.2304, accuracy: 0.000001)
        XCTAssertEqual(tree.coordinate.longitude, 121.4737, accuracy: 0.000001)
        XCTAssertEqual(tree.weight, 4.25, accuracy: 0.001)
        XCTAssertEqual(tree.fruitCount, 21)
        XCTAssertEqual(tree.confidence, "high")
    }

    func testOrchardMapDataIsEmptyWhenOnlyIncompleteLocatedRecordsExist() {
        let mapData = OrchardMapData(records: [
            makeRecord(
                id: "incomplete",
                treeID: "T-ERR",
                scanDate: Date(),
                yieldKg: 0,
                gpsLat: 31.2315,
                gpsLon: 121.4748,
                persistenceState: .incomplete
            )
        ])

        XCTAssertTrue(mapData.trees.isEmpty)
    }

    func testOrchardMapDataKeepsCompleteZeroYieldRecordsAsLowYield() throws {
        let mapData = OrchardMapData(records: [
            makeRecord(
                id: "complete-zero",
                treeID: "T-003",
                scanDate: Date(),
                fruitCount: 0,
                yieldKg: 0,
                gpsLat: 31.2337,
                gpsLon: 121.4770
            )
        ])

        let tree = try XCTUnwrap(mapData.trees.first)
        XCTAssertEqual(tree.yieldLevel, .low)
        XCTAssertEqual(tree.weight, 0, accuracy: 0.001)
    }

    private func makeRecord(
        id: String,
        treeID: String,
        scanDate: Date,
        fruitCount: Int = 0,
        yieldKg: Float,
        gpsLat: Double = 0,
        gpsLon: Double = 0,
        confidence: String = "",
        persistenceState: ScanPersistenceState = .complete
    ) -> ScanFileRecord {
        ScanFileRecord(
            id: id,
            treeID: treeID,
            fileURL: URL(fileURLWithPath: "/tmp/\(id).ply"),
            scanDate: scanDate,
            fruitCount: fruitCount,
            yieldKg: yieldKg,
            gpsLat: gpsLat,
            gpsLon: gpsLon,
            confidence: confidence,
            persistenceState: persistenceState
        )
    }
}
