import CoreLocation
import XCTest
@testable import FruitTreeScanner

final class DashboardSummaryTests: XCTestCase {
    func testNextTreeNavigationWaitsForActiveScanDismissal() {
        var state = PostScanNavigationState()

        XCTAssertNil(state.transition(for: .nextTreeRequested))
        XCTAssertEqual(state.transition(for: .activeScanDismissed), .startScan)
    }

    func testNormalScanDismissalDoesNotOpenNextTreeSetup() {
        var state = PostScanNavigationState()

        XCTAssertNil(state.transition(for: .activeScanDismissed))
    }

    func testNextTreeNavigationConsumesRepeatedRequestsOnce() {
        var state = PostScanNavigationState()

        XCTAssertNil(state.transition(for: .nextTreeRequested))
        XCTAssertNil(state.transition(for: .nextTreeRequested))
        XCTAssertEqual(state.transition(for: .activeScanDismissed), .startScan)
        XCTAssertNil(
            state.transition(for: .activeScanDismissed),
            "A late or repeated dismissal must not reopen the scan setup"
        )
    }

    @MainActor
    func testScanLaunchSubmissionGateDeliversSynchronously() {
        let gate = ScanLaunchSubmissionGate()
        var events: [String] = []

        let accepted = gate.submit(
            makeRequest: {
                events.append("build")
                return "request"
            },
            deliver: { request in
                events.append("deliver:\(request)")
            }
        )
        events.append("return")

        XCTAssertTrue(accepted)
        XCTAssertTrue(gate.isSubmitting)
        XCTAssertEqual(events, ["build", "deliver:request", "return"])
    }

    @MainActor
    func testScanLaunchSubmissionGateRejectsDuplicateSubmission() {
        let gate = ScanLaunchSubmissionGate()
        var delivered: [Int] = []

        XCTAssertTrue(gate.submit(makeRequest: { 1 }, deliver: { delivered.append($0) }))
        XCTAssertFalse(gate.submit(makeRequest: { 2 }, deliver: { delivered.append($0) }))

        XCTAssertEqual(delivered, [1])
    }

    @MainActor
    func testScanLaunchSubmissionGateDoesNotLockAfterInvalidRequest() {
        let gate = ScanLaunchSubmissionGate()

        let accepted = gate.submit(
            makeRequest: { nil as Int? },
            deliver: { _ in XCTFail("Invalid requests must not be delivered") }
        )

        XCTAssertFalse(accepted)
        XCTAssertFalse(gate.isSubmitting)
    }

    func testStartScanSelectionDropsUnavailablePlotAndTagIDs() {
        let availablePlot = Plot(name: "North Block")
        let availableTag = GroupTag(name: "Priority")
        let stalePlotID = UUID()
        let staleTagID = UUID()

        let snapshot = StartScanSelectionPolicy.snapshot(
            selectedPlotId: stalePlotID,
            selectedTagIds: [availableTag.id, staleTagID],
            availablePlots: [availablePlot],
            availableTags: [availableTag]
        )

        XCTAssertNil(snapshot.plotId)
        XCTAssertEqual(snapshot.tagIds, [availableTag.id])
    }

    func testStartScanSelectionKeepsAvailablePlotAndUsesTagCatalogOrder() {
        let plot = Plot(name: "South Block")
        let firstTag = GroupTag(name: "First")
        let secondTag = GroupTag(name: "Second")

        let snapshot = StartScanSelectionPolicy.snapshot(
            selectedPlotId: plot.id,
            selectedTagIds: [firstTag.id, secondTag.id],
            availablePlots: [plot],
            availableTags: [secondTag, firstTag]
        )

        XCTAssertEqual(snapshot.plotId, plot.id)
        XCTAssertEqual(snapshot.tagIds, [secondTag.id, firstTag.id])
    }

    func testGPSLocationPolicyRejectsStaleInaccurateAndInvalidFixes() {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let good = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            altitude: 0,
            horizontalAccuracy: GPSLocationPolicy.maximumHorizontalAccuracy,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-GPSLocationPolicy.maximumLocationAge)
        )
        let stale = CLLocation(
            coordinate: good.coordinate,
            altitude: 0,
            horizontalAccuracy: 4,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-GPSLocationPolicy.maximumLocationAge - 0.1)
        )
        let inaccurate = CLLocation(
            coordinate: good.coordinate,
            altitude: 0,
            horizontalAccuracy: GPSLocationPolicy.maximumHorizontalAccuracy + 0.1,
            verticalAccuracy: 5,
            timestamp: now
        )
        let invalidAccuracy = CLLocation(
            coordinate: good.coordinate,
            altitude: 0,
            horizontalAccuracy: -1,
            verticalAccuracy: 5,
            timestamp: now
        )
        let invalidCoordinate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 91, longitude: 181),
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 5,
            timestamp: now
        )
        let future = CLLocation(
            coordinate: good.coordinate,
            altitude: 0,
            horizontalAccuracy: 1,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(
                GPSLocationPolicy.maximumFutureTimestampSkew + 0.1
            )
        )

        XCTAssertTrue(GPSLocationPolicy.isAcceptable(good, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(stale, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(inaccurate, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(invalidAccuracy, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(invalidCoordinate, at: now))
        XCTAssertFalse(GPSLocationPolicy.isAcceptable(future, at: now))
    }

    func testGPSLocationPolicyChoosesMostAccurateThenNewestFix() throws {
        let now = Date(timeIntervalSince1970: 1_800_000_000)
        let lessAccurate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.1, longitude: 121.1),
            altitude: 0,
            horizontalAccuracy: 7,
            verticalAccuracy: 5,
            timestamp: now
        )
        let olderAccurate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.2, longitude: 121.2),
            altitude: 0,
            horizontalAccuracy: 3,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-2)
        )
        let newerAccurate = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: 31.3, longitude: 121.3),
            altitude: 0,
            horizontalAccuracy: 3,
            verticalAccuracy: 5,
            timestamp: now.addingTimeInterval(-1)
        )

        let best = try XCTUnwrap(
            GPSLocationPolicy.bestLocation(
                from: [lessAccurate, olderAccurate, newerAccurate],
                at: now
            )
        )

        XCTAssertEqual(best.coordinate.latitude, newerAccurate.coordinate.latitude)
        XCTAssertEqual(best.coordinate.longitude, newerAccurate.coordinate.longitude)
    }

    func testGPSLocationPolicySnapshotDropsFixAfterItExpires() throws {
        let timestamp = Date(timeIntervalSince1970: 1_800_000_000)
        let location = CLLocation(
            coordinate: CLLocationCoordinate2D(latitude: -33.8688, longitude: 151.2093),
            altitude: 0,
            horizontalAccuracy: 4,
            verticalAccuracy: 5,
            timestamp: timestamp
        )

        let freshSnapshot = try XCTUnwrap(
            GPSLocationPolicy.snapshot(
                from: location,
                at: timestamp.addingTimeInterval(5)
            )
        )
        let expiredSnapshot = GPSLocationPolicy.snapshot(
            from: location,
            at: timestamp.addingTimeInterval(GPSLocationPolicy.maximumLocationAge + 1)
        )

        XCTAssertEqual(freshSnapshot.latitude, -33.8688, accuracy: 0.000_001)
        XCTAssertEqual(freshSnapshot.longitude, 151.2093, accuracy: 0.000_001)
        XCTAssertEqual(freshSnapshot.horizontalAccuracy, 4)
        XCTAssertNil(expiredSnapshot)
    }

    @MainActor
    func testQuickScanTreeIdentifierDraftUsesLatestValidValueSynchronously() {
        let draft = QuickScanTreeIdentifierDraft(value: "Q1000")

        draft.value = "  TREE-NEW  "

        XCTAssertEqual(draft.normalizedValue, "TREE-NEW")
        XCTAssertEqual(draft.validatedValue, "TREE-NEW")
        XCTAssertTrue(draft.isValid)
    }

    @MainActor
    func testQuickScanTreeIdentifierDraftRejectsLatestInvalidValueSynchronously() {
        let draft = QuickScanTreeIdentifierDraft(value: "Q1000")

        draft.value = " .. "

        XCTAssertEqual(draft.normalizedValue, "..")
        XCTAssertEqual(draft.validationIssue, .pathMarker)
        XCTAssertNil(draft.validatedValue)
        XCTAssertFalse(draft.isValid)
    }

    @MainActor
    func testQuickScanTreeIdentifierDraftKeepsFinalRapidUpdate() {
        let draft = QuickScanTreeIdentifierDraft(value: "Q1000")

        draft.value = "TREE-A"
        draft.value = "TREE-B"
        draft.value = "TREE-C"

        XCTAssertEqual(draft.validatedValue, "TREE-C")
    }

    func testStartTreeIdentifierDraftUsesLatestValidValueSynchronously() {
        var draft = StartTreeIdentifierDraft(value: "TREE-OLD")

        draft.value = "  TREE-NEW  "

        XCTAssertEqual(draft.normalizedValue, "TREE-NEW")
        XCTAssertEqual(draft.validatedValue, "TREE-NEW")
        XCTAssertTrue(draft.isValid)
    }

    func testStartTreeIdentifierDraftRejectsLatestInvalidValueSynchronously() {
        var draft = StartTreeIdentifierDraft(value: "TREE-OLD")

        draft.value = " .. "

        XCTAssertEqual(draft.normalizedValue, "..")
        XCTAssertEqual(draft.validationIssue, .pathMarker)
        XCTAssertNil(draft.validatedValue)
        XCTAssertFalse(draft.isValid)
    }

    func testStartTreeIdentifierDraftRejectsEmptyValueSynchronously() {
        var draft = StartTreeIdentifierDraft(value: "TREE-OLD")

        draft.value = "   "

        XCTAssertEqual(draft.validationIssue, .empty)
        XCTAssertNil(draft.validatedValue)
        XCTAssertFalse(draft.isValid)
    }

    func testStartTreeIdentifierDraftKeepsFinalRapidUpdate() {
        var draft = StartTreeIdentifierDraft(value: "TREE-OLD")

        draft.value = "TREE-A"
        draft.value = "TREE-B"
        draft.value = "TREE-C"

        XCTAssertEqual(draft.validatedValue, "TREE-C")
    }

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

    func testYieldReportDataIncludesOnlyCompleteRecordsAndPreservesOrder() {
        let records = [
            makeRecord(
                id: "complete-a",
                treeID: "A",
                scanDate: Date(timeIntervalSince1970: 4),
                fruitCount: 12,
                yieldKg: 3.5
            ),
            makeRecord(
                id: "incomplete",
                treeID: "B",
                scanDate: Date(timeIntervalSince1970: 3),
                fruitCount: 99,
                yieldKg: 99,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "C",
                scanDate: Date(timeIntervalSince1970: 2),
                fruitCount: 88,
                yieldKg: 88,
                persistenceState: .invalid
            ),
            makeRecord(
                id: "complete-b",
                treeID: "D",
                scanDate: Date(timeIntervalSince1970: 1),
                fruitCount: 8,
                yieldKg: 2
            )
        ]

        let report = YieldReportData(records: records)

        XCTAssertEqual(report.completeRecords.map(\.id), ["complete-a", "complete-b"])
        XCTAssertEqual(report.latestRecordsByTree.map(\.id), ["complete-a", "complete-b"])
        XCTAssertEqual(report.totalScans, 2)
        XCTAssertEqual(report.totalTrees, 2)
        XCTAssertEqual(report.totalYield, 5.5, accuracy: 0.001)
        XCTAssertEqual(report.averageYield, 2.75, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 20)
        XCTAssertFalse(report.isEmpty)
    }

    func testYieldReportDataIsEmptyWhenOnlyIncompleteRecordsExist() {
        let records = [
            makeRecord(
                id: "incomplete",
                treeID: "A",
                scanDate: Date(),
                fruitCount: 99,
                yieldKg: 99,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "B",
                scanDate: Date(),
                fruitCount: 88,
                yieldKg: 88,
                persistenceState: .invalid
            )
        ]

        let report = YieldReportData(records: records)

        XCTAssertTrue(report.isEmpty)
        XCTAssertTrue(report.completeRecords.isEmpty)
        XCTAssertTrue(report.latestRecordsByTree.isEmpty)
        XCTAssertTrue(report.visibleRecords.isEmpty)
        XCTAssertEqual(report.totalScans, 0)
        XCTAssertEqual(report.totalTrees, 0)
        XCTAssertEqual(report.totalYield, 0, accuracy: 0.001)
        XCTAssertEqual(report.averageYield, 0, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 0)
    }

    func testYieldReportDataLimitsRowsAfterFilteringIncompleteRecords() {
        let completeRecords = (0..<22).map { index in
            makeRecord(
                id: "complete-\(index)",
                treeID: "T-\(index)",
                scanDate: Date(timeIntervalSince1970: TimeInterval(100 - index)),
                yieldKg: 1
            )
        }
        let incompleteRecords = (0..<8).map { index in
            makeRecord(
                id: "incomplete-\(index)",
                treeID: "I-\(index)",
                scanDate: Date(timeIntervalSince1970: TimeInterval(200 - index)),
                yieldKg: 99,
                persistenceState: .incomplete
            )
        }

        let report = YieldReportData(records: incompleteRecords + completeRecords)

        XCTAssertEqual(report.totalScans, 22)
        XCTAssertEqual(report.totalTrees, 22)
        XCTAssertEqual(report.visibleRecords.count, 20)
        XCTAssertEqual(report.visibleRecords.first?.id, "complete-0")
        XCTAssertEqual(report.visibleRecords.last?.id, "complete-19")
    }

    func testYieldReportDataUsesLatestCompleteRecordPerTreeForTotals() {
        let report = YieldReportData(records: [
            makeRecord(
                id: "tree-a-old",
                treeID: " A ",
                scanDate: Date(timeIntervalSince1970: 100),
                fruitCount: 10,
                yieldKg: 2
            ),
            makeRecord(
                id: "tree-b",
                treeID: "B",
                scanDate: Date(timeIntervalSince1970: 200),
                fruitCount: 20,
                yieldKg: 4
            ),
            makeRecord(
                id: "tree-a-new",
                treeID: "A",
                scanDate: Date(timeIntervalSince1970: 300),
                fruitCount: 15,
                yieldKg: 3
            ),
            makeRecord(
                id: "tree-a-incomplete-newest",
                treeID: "A",
                scanDate: Date(timeIntervalSince1970: 400),
                fruitCount: 999,
                yieldKg: 999,
                persistenceState: .incomplete
            )
        ])

        XCTAssertEqual(report.completeRecords.count, 3)
        XCTAssertEqual(report.totalScans, 3)
        XCTAssertEqual(report.totalTrees, 2)
        XCTAssertEqual(report.latestRecordsByTree.map(\.id), ["tree-a-new", "tree-b"])
        XCTAssertEqual(report.visibleRecords.map(\.id), ["tree-a-new", "tree-b"])
        XCTAssertEqual(report.totalYield, 7, accuracy: 0.001)
        XCTAssertEqual(report.averageYield, 3.5, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 35)
    }

    func testYieldReportDataUsesStableTieBreakForSameTreeAndTimestamp() {
        let scanDate = Date(timeIntervalSince1970: 100)
        let report = YieldReportData(records: [
            makeRecord(
                id: "scan-b",
                treeID: "A",
                scanDate: scanDate,
                fruitCount: 20,
                yieldKg: 2
            ),
            makeRecord(
                id: "scan-a",
                treeID: "A",
                scanDate: scanDate,
                fruitCount: 10,
                yieldKg: 1
            )
        ])

        XCTAssertEqual(report.totalScans, 2)
        XCTAssertEqual(report.totalTrees, 1)
        XCTAssertEqual(report.latestRecordsByTree.map(\.id), ["scan-a"])
        XCTAssertEqual(report.totalYield, 1, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 10)
    }

    func testYieldReportDataKeepsLatestCompleteZeroYieldPerTree() {
        let report = YieldReportData(records: [
            makeRecord(
                id: "older-positive",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 100),
                fruitCount: 12,
                yieldKg: 3
            ),
            makeRecord(
                id: "latest-zero",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 200),
                fruitCount: 0,
                yieldKg: 0
            ),
            makeRecord(
                id: "incomplete-newest",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 300),
                fruitCount: 99,
                yieldKg: 99,
                persistenceState: .incomplete
            )
        ])

        XCTAssertEqual(report.totalScans, 2)
        XCTAssertEqual(report.totalTrees, 1)
        XCTAssertEqual(report.latestRecordsByTree.map(\.id), ["latest-zero"])
        XCTAssertEqual(report.visibleRecords.map(\.id), ["latest-zero"])
        XCTAssertEqual(report.totalYield, 0, accuracy: 0.001)
        XCTAssertEqual(report.averageYield, 0, accuracy: 0.001)
        XCTAssertEqual(report.totalFruit, 0)
    }

    func testTrendsDataIncludesOnlyCompleteRecordsAndSortsChronologically() {
        let oldestDate = Date(timeIntervalSince1970: 100)
        let middleDate = Date(timeIntervalSince1970: 200)
        let newestDate = Date(timeIntervalSince1970: 300)
        let records = [
            makeRecord(
                id: "complete-newer",
                treeID: "T-002",
                scanDate: newestDate,
                fruitCount: 42,
                yieldKg: 8.4
            ),
            makeRecord(
                id: "incomplete",
                treeID: "T-ERR-1",
                scanDate: middleDate,
                fruitCount: 999,
                yieldKg: 99,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "T-ERR-2",
                scanDate: oldestDate,
                fruitCount: 888,
                yieldKg: 88,
                persistenceState: .invalid
            ),
            makeRecord(id: "complete-older", treeID: "T-001", scanDate: oldestDate, fruitCount: 13, yieldKg: 2.5)
        ]

        let trendsData = TrendsData(records: records)

        XCTAssertEqual(trendsData.records.map(\.id), ["complete-older", "complete-newer"])
        XCTAssertEqual(trendsData.maxYield, 8.4, accuracy: 0.001)
        XCTAssertFalse(trendsData.isEmpty)
    }

    func testTrendsDataIsEmptyWhenOnlyIncompleteRecordsExist() {
        let trendsData = TrendsData(records: [
            makeRecord(
                id: "incomplete",
                treeID: "T-ERR",
                scanDate: Date(),
                fruitCount: 999,
                yieldKg: 99,
                persistenceState: .incomplete
            )
        ])

        XCTAssertTrue(trendsData.records.isEmpty)
        XCTAssertEqual(trendsData.maxYield, 1, accuracy: 0.001)
        XCTAssertTrue(trendsData.isEmpty)
    }

    func testTrendsDataUsesOneAsMinimumScaleForZeroYieldCompleteRecords() {
        let trendsData = TrendsData(records: [
            makeRecord(id: "complete", treeID: "T-001", scanDate: Date(), fruitCount: 0, yieldKg: 0)
        ])

        XCTAssertEqual(trendsData.records.map(\.id), ["complete"])
        XCTAssertEqual(trendsData.maxYield, 1, accuracy: 0.001)
        XCTAssertFalse(trendsData.isEmpty)
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
                yieldKg: 0,
                gpsLat: 31.2315,
                gpsLon: 121.4748,
                persistenceState: .incomplete
            ),
            makeRecord(
                id: "invalid",
                treeID: "T-ERR-2",
                scanDate: Date(timeIntervalSince1970: 300),
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

    func testOrchardMapDataKeepsOnlyLatestLocatedCompleteScanPerTree() {
        let records = [
            makeRecord(
                id: "tree-1-older",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 100),
                fruitCount: 10,
                yieldKg: 3,
                gpsLat: 31.1,
                gpsLon: 121.1
            ),
            makeRecord(
                id: "tree-2-latest",
                treeID: "T-002",
                scanDate: Date(timeIntervalSince1970: 400),
                fruitCount: 30,
                yieldKg: 7,
                gpsLat: 31.4,
                gpsLon: 121.4
            ),
            makeRecord(
                id: "tree-1-newer",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 300),
                fruitCount: 20,
                yieldKg: 5,
                gpsLat: 31.3,
                gpsLon: 121.3
            ),
            makeRecord(
                id: "tree-1-incomplete-newest",
                treeID: "T-001",
                scanDate: Date(timeIntervalSince1970: 500),
                fruitCount: 99,
                yieldKg: 99,
                gpsLat: 31.5,
                gpsLon: 121.5,
                persistenceState: .incomplete
            )
        ]

        let trees = OrchardMapData(records: records).trees

        XCTAssertEqual(trees.map(\.id), ["tree-2-latest", "tree-1-newer"])
        XCTAssertEqual(trees.map(\.treeID), ["T-002", "T-001"])
        XCTAssertEqual(trees.last?.fruitCount, 20)
        XCTAssertEqual(trees.last?.weight ?? -1, 5, accuracy: 0.001)
    }

    func testOrchardMapDataUsesStableTieBreakForSameTreeAndTimestamp() {
        let timestamp = Date(timeIntervalSince1970: 100)
        let mapData = OrchardMapData(records: [
            makeRecord(
                id: "scan-b",
                treeID: "T-001",
                scanDate: timestamp,
                yieldKg: 2,
                gpsLat: 31.2,
                gpsLon: 121.2
            ),
            makeRecord(
                id: "scan-a",
                treeID: "T-001",
                scanDate: timestamp,
                yieldKg: 1,
                gpsLat: 31.1,
                gpsLon: 121.1
            )
        ])

        XCTAssertEqual(mapData.trees.map(\.id), ["scan-a"])
    }

    func testOrchardMapDataAcceptsAZeroCoordinateComponentButNotMissingLocation() {
        let mapData = OrchardMapData(records: [
            makeRecord(
                id: "equator",
                treeID: "T-EQUATOR",
                scanDate: Date(timeIntervalSince1970: 300),
                yieldKg: 1,
                gpsLat: 0,
                gpsLon: 121.5
            ),
            makeRecord(
                id: "prime-meridian",
                treeID: "T-PRIME",
                scanDate: Date(timeIntervalSince1970: 200),
                yieldKg: 1,
                gpsLat: 31.5,
                gpsLon: 0
            ),
            makeRecord(
                id: "missing",
                treeID: "T-MISSING",
                scanDate: Date(timeIntervalSince1970: 100),
                yieldKg: 1
            )
        ])

        XCTAssertEqual(mapData.trees.map(\.id), ["equator", "prime-meridian"])
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

final class QuickScanLocalizationTests: XCTestCase {

    func testQuickScanCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "quick_scan.navigation_title": "Quick Scan",
                "quick_scan.header_title": "Quick Capture",
                "quick_scan.header_subtitle": "Tree ID is auto-generated. Confirm field status, then scan.",
                "quick_scan.close": "Close",
                "quick_scan.gps_available": "Current location recorded",
                "quick_scan.gps_unavailable": "GPS not locked. You can still scan.",
                "quick_scan.launching": "Starting...",
                "quick_scan.launch": "Start Quick Scan",
                "quick_scan.tree_id": "Tree ID",
                "quick_scan.tree_id_valid": "Available",
                "quick_scan.tree_id_invalid": "Invalid",
                "quick_scan.tree_id_required": "Required",
                "quick_scan.tree_id_placeholder": "Auto-generated",
                "quick_scan.tree_id_empty_error": "Enter a tree ID",
                "quick_scan.tree_id_too_long_error": "Tree ID must be no more than %d characters",
                "quick_scan.tree_id_path_marker_error": "Tree ID cannot be a path marker",
                "quick_scan.tree_id_forbidden_error": "Tree ID cannot contain /, \\, :, or line breaks"
            ],
            "zh": [
                "quick_scan.navigation_title": "快速扫描",
                "quick_scan.header_title": "快速采集",
                "quick_scan.header_subtitle": "自动生成树编号，只确认现场状态后直接进入扫描。",
                "quick_scan.close": "关闭",
                "quick_scan.gps_available": "已记录当前位置",
                "quick_scan.gps_unavailable": "未锁定 GPS，仍可先扫描",
                "quick_scan.launching": "启动中...",
                "quick_scan.launch": "开始快速扫描",
                "quick_scan.tree_id": "树编号",
                "quick_scan.tree_id_valid": "可用",
                "quick_scan.tree_id_invalid": "无效",
                "quick_scan.tree_id_required": "必填",
                "quick_scan.tree_id_placeholder": "自动生成",
                "quick_scan.tree_id_empty_error": "请输入果树编号",
                "quick_scan.tree_id_too_long_error": "编号最多 %d 个字符",
                "quick_scan.tree_id_path_marker_error": "编号不能使用路径标记",
                "quick_scan.tree_id_forbidden_error": "编号不能包含 /、\\、: 或换行"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testQuickScanMapsEveryTreeIdentifierIssueToDisplayableCopy() {
        let messages = [
            L10n.QuickScan.validationError(for: .empty),
            L10n.QuickScan.validationError(for: .tooLong(maximumCharacterCount: 64)),
            L10n.QuickScan.validationError(for: .pathMarker),
            L10n.QuickScan.validationError(for: .forbiddenCharacters)
        ]

        XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
        XCTAssertTrue(messages[1].contains("64"))
    }
}

final class DashboardHomeLocalizationTests: XCTestCase {

    func testDashboardHomeCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "dashboard.history_accessibility_label": "Scan history",
                "dashboard.history_accessibility_one": "Scan history, 1 record",
                "dashboard.history_accessibility_count": "Scan history, %d records",
                "dashboard.settings_accessibility_label": "Settings",
                "dashboard.today_scans": "Today's Scans",
                "dashboard.total_yield": "Total Yield",
                "dashboard.recent_scans": "Recent Scans",
                "dashboard.no_scans": "No scan records yet",
                "dashboard.workbench_title": "Orchard Scan Workbench",
                "dashboard.workbench_subtitle": "LiDAR Capture · Point Clouds · Yield",
                "dashboard.field_mode": "Field",
                "dashboard.today": "Today",
                "dashboard.yield": "Yield",
                "dashboard.trees": "Trees",
                "dashboard.scan_unit_one": "scan",
                "dashboard.scan_unit_other": "scans",
                "dashboard.tree_unit_one": "tree",
                "dashboard.tree_unit_other": "trees",
                "dashboard.start_scan": "Start Scan",
                "dashboard.quick_capture": "Quick Scan",
                "dashboard.tools": "Tools",
                "dashboard.mode.scan": "Scanning",
                "dashboard.mode.history": "Records",
                "dashboard.mode.analytics": "Analytics",
                "dashboard.action.calibration.title": "Calibration",
                "dashboard.action.calibration.description": "Fruit size and clustering",
                "dashboard.action.import_file.title": "Import PLY",
                "dashboard.action.import_file.description": "Add an existing scan",
                "dashboard.action.scan_history.title": "Scan History",
                "dashboard.action.scan_history.description": "View, delete, and share records",
                "dashboard.action.point_cloud.title": "Point Clouds",
                "dashboard.action.point_cloud.description": "Open recent point clouds",
                "dashboard.action.tag_management.title": "Plots & Tags",
                "dashboard.action.tag_management.description": "Manage plots, tags, and status",
                "dashboard.action.batch_export.title": "Batch Export",
                "dashboard.action.batch_export.description": "Export multiple records",
                "dashboard.action.yield_report.title": "Yield Report",
                "dashboard.action.yield_report.description": "Fruit counts and weight",
                "dashboard.action.compare.title": "Compare Trees",
                "dashboard.action.compare.description": "Compare scan results",
                "dashboard.action.trends.title": "Trends",
                "dashboard.action.trends.description": "Track yield changes",
                "dashboard.action.map.title": "Orchard Map",
                "dashboard.action.map.description": "View trees by location",
                "dashboard.quick_action_accessibility": "%@, %@",
                "dashboard.view_all": "View All",
                "dashboard.view_point_cloud_accessibility": "View point cloud for %@",
                "dashboard.empty_description": "Your recent trees, yields, and point clouds will appear here.",
                "dashboard.start_first_scan": "Start First Scan",
                "dashboard.fruit_count_one": "%d fruit",
                "dashboard.fruit_count_other": "%d fruits",
                "dashboard.today_overview": "Today’s Overview",
                "dashboard.tree_ids": "Tree IDs"
            ],
            "zh": [
                "dashboard.history_accessibility_label": "扫描历史",
                "dashboard.history_accessibility_one": "扫描历史，1条记录",
                "dashboard.history_accessibility_count": "扫描历史，%d条记录",
                "dashboard.settings_accessibility_label": "设置",
                "dashboard.today_scans": "扫描数量",
                "dashboard.total_yield": "总产量",
                "dashboard.recent_scans": "最近扫描",
                "dashboard.no_scans": "还没有扫描记录",
                "dashboard.workbench_title": "果园扫描工作台",
                "dashboard.workbench_subtitle": "LiDAR 采集 · 点云记录 · 产量分析",
                "dashboard.field_mode": "现场",
                "dashboard.today": "今日",
                "dashboard.yield": "产量",
                "dashboard.trees": "树体",
                "dashboard.scan_unit_one": "次",
                "dashboard.scan_unit_other": "次",
                "dashboard.tree_unit_one": "棵",
                "dashboard.tree_unit_other": "棵",
                "dashboard.start_scan": "新建扫描",
                "dashboard.quick_capture": "快速采集",
                "dashboard.tools": "功能",
                "dashboard.mode.scan": "扫描",
                "dashboard.mode.history": "历史",
                "dashboard.mode.analytics": "分析",
                "dashboard.action.calibration.title": "校准参数",
                "dashboard.action.calibration.description": "水果尺寸、聚类与误差记录",
                "dashboard.action.import_file.title": "导入点云",
                "dashboard.action.import_file.description": "加入已有 PLY 扫描文件",
                "dashboard.action.scan_history.title": "扫描记录",
                "dashboard.action.scan_history.description": "查看、删除和分享记录",
                "dashboard.action.point_cloud.title": "点云查看",
                "dashboard.action.point_cloud.description": "打开最近或指定点云",
                "dashboard.action.tag_management.title": "地块标签",
                "dashboard.action.tag_management.description": "维护地块、标签和状态",
                "dashboard.action.batch_export.title": "批量导出",
                "dashboard.action.batch_export.description": "导出多条扫描数据",
                "dashboard.action.yield_report.title": "产量报告",
                "dashboard.action.yield_report.description": "汇总果数和重量",
                "dashboard.action.compare.title": "树体对比",
                "dashboard.action.compare.description": "横向比较扫描结果",
                "dashboard.action.trends.title": "趋势",
                "dashboard.action.trends.description": "观察产量变化",
                "dashboard.action.map.title": "果园地图",
                "dashboard.action.map.description": "按位置查看树体",
                "dashboard.quick_action_accessibility": "%@，%@",
                "dashboard.view_all": "查看全部",
                "dashboard.view_point_cloud_accessibility": "查看 %@ 点云",
                "dashboard.empty_description": "完成第一次扫描后，这里会显示最近树体、产量和点云入口。",
                "dashboard.start_first_scan": "开始第一次扫描",
                "dashboard.fruit_count_one": "%d 个果实",
                "dashboard.fruit_count_other": "%d 个果实",
                "dashboard.today_overview": "今日概览",
                "dashboard.tree_ids": "树编号"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
                "Missing \(language) localization bundle"
            )

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testDashboardHomeFormatsDynamicAndAccessibilityCopy() {
        let emptyHistory = L10n.Dashboard.scanHistoryAccessibilityLabel(recordCount: 0)
        let oneHistory = L10n.Dashboard.scanHistoryAccessibilityLabel(recordCount: 1)
        let multipleHistory = L10n.Dashboard.scanHistoryAccessibilityLabel(recordCount: 12)
        let quickAction = L10n.Dashboard.quickActionAccessibilityLabel(
            title: "Action Title",
            description: "Action Description"
        )
        let oneScanUnit = L10n.Dashboard.scanCountUnit(1)
        let multipleScanUnit = L10n.Dashboard.scanCountUnit(12)
        let oneTreeUnit = L10n.Dashboard.treeCountUnit(1)
        let multipleTreeUnit = L10n.Dashboard.treeCountUnit(12)
        let pointCloud = L10n.Dashboard.viewPointCloudAccessibilityLabel(treeID: "TREE-17")
        let oneFruit = L10n.Dashboard.fruitCountLabel(1)
        let multipleFruit = L10n.Dashboard.fruitCountLabel(12)

        XCTAssertFalse(emptyHistory.isEmpty)
        XCTAssertNotEqual(emptyHistory, oneHistory)
        XCTAssertTrue(oneHistory.contains("1"))
        XCTAssertTrue(multipleHistory.contains("12"))
        XCTAssertTrue(quickAction.contains("Action Title"))
        XCTAssertTrue(quickAction.contains("Action Description"))
        XCTAssertEqual(oneScanUnit, NSLocalizedString("dashboard.scan_unit_one", comment: ""))
        XCTAssertEqual(multipleScanUnit, NSLocalizedString("dashboard.scan_unit_other", comment: ""))
        XCTAssertEqual(oneTreeUnit, NSLocalizedString("dashboard.tree_unit_one", comment: ""))
        XCTAssertEqual(multipleTreeUnit, NSLocalizedString("dashboard.tree_unit_other", comment: ""))
        XCTAssertTrue(pointCloud.contains("TREE-17"))
        XCTAssertTrue(oneFruit.contains("1"))
        XCTAssertTrue(multipleFruit.contains("12"))
        XCTAssertNotEqual(oneFruit, multipleFruit)
    }

    func testDashboardHomeModesUseLocalizedCopy() {
        XCTAssertEqual(AppMode.scan.title, L10n.Dashboard.scanMode)
        XCTAssertEqual(AppMode.history.title, L10n.Dashboard.historyMode)
        XCTAssertEqual(AppMode.analytics.title, L10n.Dashboard.analyticsMode)
    }
}
