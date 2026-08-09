import CoreLocation
import SwiftUI
import UIKit
import XCTest
@testable import FruitTreeScanner

final class DashboardSummaryTests: XCTestCase {
    @MainActor
    func testSharedDashboardToolPresentationRendersAtAccessibilityTextSize() {
        let rootView = ScrollView {
            VStack(spacing: 16) {
                DashboardToolHeader(
                    imageName: "FeatureImportFile",
                    title: "Import Point Cloud",
                    subtitle: "Choose an existing PLY scan for preview, comparison, and export.",
                    icon: "square.and.arrow.down",
                    accent: Design.Colors.harvest
                )

                DashboardSheetEmptyState(
                    icon: "clock.arrow.circlepath",
                    imageName: "FeatureScanHistory",
                    title: "No Scan Records",
                    message: "Complete a scan or import a PLY file, then review, share, or recover it here.",
                    primaryAction: DashboardSheetAction(
                        title: "Start Scanning",
                        icon: "viewfinder",
                        action: {}
                    ),
                    secondaryAction: DashboardSheetAction(
                        title: "Import PLY",
                        icon: "square.and.arrow.down",
                        action: {}
                    ),
                    outerPadding: false
                )
            }
            .padding(16)
        }
        .frame(width: 390, height: 844)
        .background(Design.Colors.Dark.bgDeep)
        .environment(\.dynamicTypeSize, .accessibility5)
        .environment(\.colorScheme, .dark)

        let hostingController = UIHostingController(rootView: rootView)
        hostingController.overrideUserInterfaceStyle = .dark
        let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
        window.rootViewController = hostingController
        window.makeKeyAndVisible()
        hostingController.view.frame = window.bounds
        hostingController.view.backgroundColor = .black
        hostingController.view.setNeedsLayout()
        hostingController.view.layoutIfNeeded()
        RunLoop.main.run(until: Date().addingTimeInterval(0.05))

        var didDraw = false
        let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
            .image { _ in
                didDraw = hostingController.view.drawHierarchy(
                    in: hostingController.view.bounds,
                    afterScreenUpdates: true
                )
            }

        XCTAssertTrue(didDraw)
        XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = "SharedDashboardToolPresentation-AX5"
        attachment.lifetime = .keepAlways
        add(attachment)
        window.resignKey()
    }

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

final class StartFlowChromeLocalizationTests: XCTestCase {
    func testStartFlowChromeCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "start.flow.cancel": "Cancel",
                "start.flow.navigation_title": "New Scan",
                "start.flow.previous": "Previous",
                "start.flow.next": "Next",
                "start.flow.launching": "Starting...",
                "start.flow.launch": "Start Scanning",
                "start.flow.progress.identifier": "ID",
                "start.flow.progress.plot": "Plot",
                "start.flow.progress.season": "Season",
                "start.flow.progress.tags": "Tags",
                "start.flow.progress.confirmation": "Confirm",
                "start.flow.step_count_format": "%1$d / %2$d",
                "start.flow.step_count_accessibility_format": "Step %1$d of %2$d",
                "start.flow.step_header_format": "Step %1$d/%2$d",
                "start.flow.progress_accessibility_format": "Step %1$d of %2$d: %3$@"
            ],
            "zh": [
                "start.flow.cancel": "取消",
                "start.flow.navigation_title": "新建扫描",
                "start.flow.previous": "上一步",
                "start.flow.next": "下一步",
                "start.flow.launching": "启动中...",
                "start.flow.launch": "开始扫描",
                "start.flow.progress.identifier": "编号",
                "start.flow.progress.plot": "地块",
                "start.flow.progress.season": "季节",
                "start.flow.progress.tags": "标签",
                "start.flow.progress.confirmation": "确认",
                "start.flow.step_count_format": "%1$d / %2$d",
                "start.flow.step_count_accessibility_format": "第 %1$d 步，共 %2$d 步",
                "start.flow.step_header_format": "步骤 %1$d/%2$d",
                "start.flow.progress_accessibility_format": "第 %1$d 步，共 %2$d 步：%3$@"
            ]
        ]

        let productionKeys = Set(L10n.StartFlow.Key.allCases.map(\.rawValue))

        for (language, expectedValues) in expectedCopy {
            XCTAssertEqual(Set(expectedValues.keys), productionKeys)
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

    func testStartFlowChromeFormatsProgressForEveryLocale() throws {
        let expected: [String: (header: String, count: String, progress: String)] = [
            "en": ("Step 2/5", "Step 2 of 5", "Step 2 of 5: Plot"),
            "zh": ("步骤 2/5", "第 2 步，共 5 步", "第 2 步，共 5 步：地块")
        ]

        for (language, copy) in expected {
            let localizedBundle = try XCTUnwrap(
                Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:))
            )
            let plot = L10n.StartFlow.text(.progressPlot, in: localizedBundle)

            XCTAssertEqual(L10n.StartFlow.stepHeader(step: 2, totalSteps: 5, in: localizedBundle), copy.header)
            XCTAssertEqual(L10n.StartFlow.stepCountAccessibility(currentStep: 2, totalSteps: 5, in: localizedBundle), copy.count)
            XCTAssertEqual(
                L10n.StartFlow.progressAccessibility(
                    currentStep: 2,
                    totalSteps: 5,
                    label: plot,
                    in: localizedBundle
                ),
                copy.progress
            )
        }
    }

    func testStartFlowChromeStacksControlsAtAccessibilityTextSizes() {
        XCTAssertFalse(StartFlowChromeLayoutPolicy(isAccessibilitySize: false).stacksVertically)
        XCTAssertTrue(StartFlowChromeLayoutPolicy(isAccessibilitySize: true).stacksVertically)
    }
}

final class StartSetupLocalizationTests: XCTestCase {

    func testStartSetupCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "start.setup.identifier.title": "Tree ID",
                "start.setup.identifier.tool_subtitle": "Use one ID to track this tree across scans.",
                "start.setup.identifier.subtitle": "Used in records, exports, and comparisons. Match the ID used in the orchard.",
                "start.setup.identifier.note": "The ID is saved in scan records and exports. It does not affect point-cloud capture.",
                "start.setup.identifier.field_label": "ID",
                "start.setup.identifier.placeholder": "Example: T001",
                "start.setup.identifier.status.available": "Available",
                "start.setup.identifier.status.invalid": "Invalid",
                "start.setup.identifier.status.required": "Required",
                "start.setup.identifier.error.empty": "Enter a tree ID",
                "start.setup.identifier.error.too_long": "Tree ID must be no more than %d characters",
                "start.setup.identifier.error.path_marker": "Tree ID cannot be a path marker",
                "start.setup.identifier.error.forbidden": "Tree ID cannot contain /, \\, :, or line breaks",
                "start.setup.plot.tool_title": "Plot Assignment",
                "start.setup.plot.tool_subtitle": "Assign a plot for filtering and summaries.",
                "start.setup.plot.title": "Plot",
                "start.setup.plot.subtitle": "Optional. Used to filter and summarize scans by plot.",
                "start.setup.plot.empty.title": "No plots yet",
                "start.setup.plot.empty.message": "You can skip this scan and manage plots later in Plot & Tag Management.",
                "start.setup.plot.create": "Create Plot",
                "start.setup.plot.none.title": "Do Not Assign",
                "start.setup.plot.none.subtitle": "Assign the plot after the scan",
                "start.setup.plot.assigned_subtitle": "Assign to this plot",
                "start.setup.plot.add": "Add Plot",
                "start.setup.season.title": "Estimation Stage",
                "start.setup.season.tool_subtitle": "Mature fusion is ready; canopy calibration pending.",
                "start.setup.season.subtitle": "Only mature-stage estimation currently has reliable inputs.",
                "start.setup.season.note": "Non-mature canopy estimation requires calibration with measured weights before it can report evidence-based yield.",
                "start.setup.season.mature.title": "Mature Stage",
                "start.setup.season.mature.subtitle": "RGB + LiDAR fruit fusion",
                "start.setup.season.off.title": "Non-Mature Stage (Calibration Pending)",
                "start.setup.season.off.subtitle": "Canopy regression lacks measured coefficients and cannot be selected yet",
                "start.setup.season.calibration_pending": "Calibration Pending",
                "start.setup.tags.tool_title": "Tag Groups",
                "start.setup.tags.tool_subtitle": "Group varieties, trials, or management status.",
                "start.setup.tags.title": "Tags",
                "start.setup.tags.subtitle": "Optional. Mark varieties, trial groups, or management status.",
                "start.setup.tags.empty.title": "No tags yet",
                "start.setup.tags.empty.message": "Tags are optional and do not affect scanning.",
                "start.setup.tags.create": "Create Tag",
                "start.setup.tags.add": "Add",
                "start.setup.tags.selected_count": "Selected tags: %d",
                "start.setup.confirmation.tool_title": "Start Scan",
                "start.setup.confirmation.tool_subtitle": "Review details, then start LiDAR capture.",
                "start.setup.confirmation.title": "Pre-Scan Check",
                "start.setup.confirmation.subtitle": "Confirm the ID, grouping, and location status.",
                "start.setup.confirmation.unassigned": "Unassigned",
                "start.setup.confirmation.season.mature": "Mature Stage (RGB + LiDAR Fusion)",
                "start.setup.confirmation.season.off": "Non-Mature Stage (Calibration Pending)",
                "start.setup.confirmation.none": "None",
                "start.setup.confirmation.tag_separator": ", ",
                "start.setup.confirmation.gps.available": "Acquired",
                "start.setup.confirmation.gps.pending": "Acquiring...",
                "start.setup.confirmation.note": "After starting, move slowly around the tree and keep the canopy and fruit steadily in view."
            ],
            "zh": [
                "start.setup.identifier.title": "果树编号",
                "start.setup.identifier.tool_subtitle": "先建立可追踪的树体档案，后续记录会自动归到这个编号。",
                "start.setup.identifier.subtitle": "用于记录、导出和后续对比，建议与果园现场编号一致。",
                "start.setup.identifier.note": "编号会写入扫描记录和导出文件，不会影响点云采集本身。",
                "start.setup.identifier.field_label": "编号",
                "start.setup.identifier.placeholder": "例：T001",
                "start.setup.identifier.status.available": "可用",
                "start.setup.identifier.status.invalid": "无效",
                "start.setup.identifier.status.required": "必填",
                "start.setup.identifier.error.empty": "请输入果树编号",
                "start.setup.identifier.error.too_long": "编号最多 %d 个字符",
                "start.setup.identifier.error.path_marker": "编号不能使用路径标记",
                "start.setup.identifier.error.forbidden": "编号不能包含 /、\\、: 或换行",
                "start.setup.plot.tool_title": "地块归档",
                "start.setup.plot.tool_subtitle": "把扫描挂到对应地块，便于之后按区域筛选和汇总。",
                "start.setup.plot.title": "地块",
                "start.setup.plot.subtitle": "可选。用于后续按地块筛选和汇总。",
                "start.setup.plot.empty.title": "还没有地块",
                "start.setup.plot.empty.message": "这次扫描可以跳过，之后也能在标签管理中维护。",
                "start.setup.plot.create": "创建地块",
                "start.setup.plot.none.title": "暂不分配",
                "start.setup.plot.none.subtitle": "扫描完成后再归档到地块",
                "start.setup.plot.assigned_subtitle": "分配到该地块",
                "start.setup.plot.add": "添加地块",
                "start.setup.season.title": "估算阶段",
                "start.setup.season.tool_subtitle": "当前开放成熟期融合估算；冠层回归完成实测标定后开放。",
                "start.setup.season.subtitle": "当前仅开放已具备可靠输入的成熟期估算。",
                "start.setup.season.note": "非成熟期冠层路线需先用真实称重数据完成模型标定，避免输出缺乏依据的产量。",
                "start.setup.season.mature.title": "成熟期",
                "start.setup.season.mature.subtitle": "RGB + LiDAR 果实融合估算",
                "start.setup.season.off.title": "非成熟期（待标定）",
                "start.setup.season.off.subtitle": "冠层回归尚缺实测系数，暂不可选择",
                "start.setup.season.calibration_pending": "待标定",
                "start.setup.tags.tool_title": "标签分组",
                "start.setup.tags.tool_subtitle": "用标签标记品种、试验组或管理状态，方便后续复盘。",
                "start.setup.tags.title": "标签",
                "start.setup.tags.subtitle": "可选。用于标记品种、试验组或管理状态。",
                "start.setup.tags.empty.title": "还没有标签",
                "start.setup.tags.empty.message": "标签可以跳过，不会影响扫描。",
                "start.setup.tags.create": "创建标签",
                "start.setup.tags.add": "添加",
                "start.setup.tags.selected_count": "已选 %d 个标签",
                "start.setup.confirmation.tool_title": "启动扫描",
                "start.setup.confirmation.tool_subtitle": "确认信息后进入 LiDAR 采集，请围绕树体缓慢移动。",
                "start.setup.confirmation.title": "启动前检查",
                "start.setup.confirmation.subtitle": "确认编号、分组和定位状态。",
                "start.setup.confirmation.unassigned": "未分配",
                "start.setup.confirmation.season.mature": "成熟期（RGB + LiDAR 融合）",
                "start.setup.confirmation.season.off": "非成熟期（待标定）",
                "start.setup.confirmation.none": "无",
                "start.setup.confirmation.tag_separator": "、",
                "start.setup.confirmation.gps.available": "已获取",
                "start.setup.confirmation.gps.pending": "获取中...",
                "start.setup.confirmation.note": "开始后请围绕树体缓慢移动，尽量让树冠与果实进入稳定视野。"
            ]
        ]

        let productionKeys = Set(L10n.StartSetup.Key.allCases.map(\.rawValue))

        for (language, expectedValues) in expectedCopy {
            XCTAssertEqual(productionKeys, Set(expectedValues.keys))
            let localizedBundle = try localizedBundle(language)

            for (key, expectedValue) in expectedValues {
                XCTAssertEqual(
                    localizedBundle.localizedString(forKey: key, value: nil, table: nil),
                    expectedValue,
                    "\(language) localization is missing or incorrect for \(key)"
                )
            }
        }
    }

    func testStartSetupFormatsDynamicCopyInBothLanguages() throws {
        let english = try localizedBundle("en")
        let chinese = try localizedBundle("zh")

        XCTAssertEqual(L10n.StartSetup.selectedTagCount(3, in: english), "Selected tags: 3")
        XCTAssertEqual(L10n.StartSetup.selectedTagCount(3, in: chinese), "已选 3 个标签")
        XCTAssertEqual(
            L10n.StartSetup.tagSummary(names: ["A", "B", "C"], remainingCount: 2, in: english),
            "A, B, C +2"
        )
        XCTAssertEqual(
            L10n.StartSetup.tagSummary(names: ["甲", "乙", "丙"], remainingCount: 2, in: chinese),
            "甲、乙、丙 +2"
        )
    }

    func testStartSetupMapsEveryTreeIdentifierIssueInBothLanguages() throws {
        let issues: [TreeIdentifierPolicy.ValidationIssue] = [
            .empty,
            .tooLong(maximumCharacterCount: 64),
            .pathMarker,
            .forbiddenCharacters
        ]

        for language in ["en", "zh"] {
            let bundle = try localizedBundle(language)
            let messages = issues.map { L10n.StartSetup.validationError(for: $0, in: bundle) }
            XCTAssertTrue(messages.allSatisfy { !$0.isEmpty })
            XCTAssertTrue(messages[1].contains("64"))
        }
    }

    private func localizedBundle(_ language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
            "Missing \(language) localization bundle"
        )
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

final class BatchExportHeaderLocalizationTests: XCTestCase {
    func testBatchExportHeaderCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.navigation_title": "Batch Export",
                "export.header_title": "Batch Export",
                "export.header_subtitle": "Select multiple scan records and export fields, yield, and plot tags.",
                "export.close": "Close",
                "export.select_all": "Select All",
                "export.deselect_all": "Deselect All",
                "export.selection_progress": "Export record selection",
                "export.selection_summary_one": "Selected %d of 1 exportable record",
                "export.selection_summary_other": "Selected %d of %d exportable records",
                "export.selection_summary_compact": "%d of %d selected",
                "export.selected_metrics_one": "%.1f kg · 1 fruit",
                "export.selected_metrics_other": "%.1f kg · %d fruits",
                "export.selected_metrics_compact_one": "%.1f kg · 1 fruit",
                "export.selected_metrics_compact_other": "%.1f kg · %d fruits",
                "export.unavailable_summary_one": "1 record is incomplete or invalid and won't be exported",
                "export.unavailable_summary_other": "%d records are incomplete or invalid and won't be exported",
                "export.unavailable_summary_compact_one": "1 unavailable",
                "export.unavailable_summary_compact_other": "%d unavailable"
            ],
            "zh": [
                "export.navigation_title": "批次导出",
                "export.header_title": "批量导出",
                "export.header_subtitle": "选择多条扫描记录，导出字段、产量和地块标签。",
                "export.close": "关闭",
                "export.select_all": "全选",
                "export.deselect_all": "取消全选",
                "export.selection_progress": "导出记录选择进度",
                "export.selection_summary_one": "已选择 %d / 1 条可导出记录",
                "export.selection_summary_other": "已选择 %d / %d 条可导出记录",
                "export.selection_summary_compact": "已选 %d / %d",
                "export.selected_metrics_one": "%.1f kg · 1 个果实",
                "export.selected_metrics_other": "%.1f kg · %d 个果实",
                "export.selected_metrics_compact_one": "%.1f kg · 1 果",
                "export.selected_metrics_compact_other": "%.1f kg · %d 果",
                "export.unavailable_summary_one": "1 条记录未完整保存或数据无效，未纳入导出",
                "export.unavailable_summary_other": "%d 条记录未完整保存或数据无效，未纳入导出",
                "export.unavailable_summary_compact_one": "1 条不可导出",
                "export.unavailable_summary_compact_other": "%d 条不可导出"
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

    func testBatchExportHeaderFormatsSingularPluralAndMetricCopy() throws {
        let englishBundle = try XCTUnwrap(
            Bundle.main.path(forResource: "en", ofType: "lproj").flatMap(Bundle.init(path:))
        )
        let chineseBundle = try XCTUnwrap(
            Bundle.main.path(forResource: "zh", ofType: "lproj").flatMap(Bundle.init(path:))
        )

        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 1, totalCount: 1, bundle: englishBundle),
            "Selected 1 of 1 exportable record"
        )
        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 0, totalCount: 0, bundle: englishBundle),
            "Selected 0 of 0 exportable records"
        )
        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 2, totalCount: 5, bundle: englishBundle),
            "Selected 2 of 5 exportable records"
        )
        XCTAssertEqual(
            L10n.Export.compactSelectionSummary(selectedCount: 2, totalCount: 5, bundle: englishBundle),
            "2 of 5 selected"
        )
        XCTAssertEqual(
            L10n.Export.selectedMetrics(totalYield: 1.25, totalFruitCount: 1, bundle: englishBundle),
            "1.2 kg · 1 fruit"
        )
        XCTAssertEqual(
            L10n.Export.selectedMetrics(totalYield: 8.75, totalFruitCount: 12, bundle: englishBundle),
            "8.8 kg · 12 fruits"
        )
        XCTAssertEqual(
            L10n.Export.compactSelectedMetrics(totalYield: 8.75, totalFruitCount: 12, bundle: englishBundle),
            "8.8 kg · 12 fruits"
        )
        XCTAssertEqual(
            L10n.Export.unavailableSummary(count: 1, bundle: englishBundle),
            "1 record is incomplete or invalid and won't be exported"
        )
        XCTAssertEqual(
            L10n.Export.unavailableSummary(count: 3, bundle: englishBundle),
            "3 records are incomplete or invalid and won't be exported"
        )
        XCTAssertEqual(
            L10n.Export.compactUnavailableSummary(count: 1, bundle: englishBundle),
            "1 unavailable"
        )
        XCTAssertEqual(
            L10n.Export.compactUnavailableSummary(count: 3, bundle: englishBundle),
            "3 unavailable"
        )

        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 2, totalCount: 5, bundle: chineseBundle),
            "已选择 2 / 5 条可导出记录"
        )
        XCTAssertEqual(
            L10n.Export.selectionSummary(selectedCount: 0, totalCount: 0, bundle: chineseBundle),
            "已选择 0 / 0 条可导出记录"
        )
        XCTAssertEqual(
            L10n.Export.compactSelectionSummary(selectedCount: 2, totalCount: 5, bundle: chineseBundle),
            "已选 2 / 5"
        )
        XCTAssertEqual(
            L10n.Export.selectedMetrics(totalYield: 8.75, totalFruitCount: 12, bundle: chineseBundle),
            "8.8 kg · 12 个果实"
        )
        XCTAssertEqual(
            L10n.Export.compactSelectedMetrics(totalYield: 8.75, totalFruitCount: 12, bundle: chineseBundle),
            "8.8 kg · 12 果"
        )
        XCTAssertEqual(
            L10n.Export.unavailableSummary(count: 3, bundle: chineseBundle),
            "3 条记录未完整保存或数据无效，未纳入导出"
        )
        XCTAssertEqual(
            L10n.Export.compactUnavailableSummary(count: 3, bundle: chineseBundle),
            "3 条不可导出"
        )
        XCTAssertEqual(
            L10n.Export.compactUnavailableSummary(count: 1, bundle: chineseBundle),
            "1 条不可导出"
        )
    }

    @MainActor
    func testBatchExportHeaderRendersAtStandardAndAccessibilityTextSizes() {
        let cases: [(name: String, size: DynamicTypeSize)] = [
            ("Large", .large),
            ("AX5", .accessibility5)
        ]

        for testCase in cases {
            let header = BatchExportHeaderBar(
                selectedCount: 2,
                totalCount: 5,
                unavailableCount: 2,
                totalYield: 8.75,
                totalFruitCount: 12
            )
            .environment(\.dynamicTypeSize, testCase.size)

            let rootView = VStack(spacing: 0) {
                header
                Spacer(minLength: 0)
            }
            .frame(width: 390, height: 844, alignment: .top)
            .background(Design.Colors.Dark.bgDeep)
            .environment(\.colorScheme, .dark)

            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
                .image { _ in
                    didDraw = hostingController.view.drawHierarchy(
                        in: hostingController.view.bounds,
                        afterScreenUpdates: true
                    )
                }

            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportHeader-\(Locale.preferredLanguages.first ?? "unknown")-\(testCase.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class BatchExportEmptyStateLocalizationTests: XCTestCase {
    func testBatchExportEmptyStateCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.empty.title": "No Records to Export",
                "export.empty.message": "Scan or import a PLY file, then select records here for CSV or Excel-compatible export.",
                "export.empty.message_compact": "Scan or import a PLY file to add exportable records.",
                "export.empty.start_scan": "Start Scan",
                "export.empty.start_scan_hint": "Open scan setup to create an exportable scan record.",
                "export.empty.import_ply": "Import PLY",
                "export.empty.import_ply_hint": "Open file import to add an existing point cloud to Scan History."
            ],
            "zh": [
                "export.empty.title": "暂无可导出的记录",
                "export.empty.message": "扫描或导入 PLY 文件后，可在这里批量选择并导出 CSV 或 Excel 兼容表格。",
                "export.empty.message_compact": "扫描或导入 PLY 文件以添加可导出记录。",
                "export.empty.start_scan": "开始扫描",
                "export.empty.start_scan_hint": "打开扫描设置，创建可导出的扫描记录。",
                "export.empty.import_ply": "导入 PLY",
                "export.empty.import_ply_hint": "打开文件导入，将已有点云加入扫描记录。"
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

    @MainActor
    func testBatchExportContentRendersProductionEmptyPathAtStandardAndAccessibilityTextSizes() {
        let cases: [(name: String, size: DynamicTypeSize)] = [
            ("Large", .large),
            ("AX5", .accessibility5)
        ]

        for testCase in cases {
            let content = BatchExportContentView(
                records: [],
                selectedRecords: [],
                exportFormat: .constant(.csv),
                exportOptions: .constant(BatchExportService.ExportOptions()),
                exportedURL: nil,
                isExporting: false,
                onStartScan: {},
                onImportFile: {},
                onToggleSelection: { _ in },
                onOptionsChanged: {},
                onShareExport: {},
                onClearExport: {},
                onPrimaryAction: {}
            )
            .environment(\.dynamicTypeSize, testCase.size)

            let rootView = content
                .frame(width: 390, height: 844, alignment: .top)
                .background(Design.Colors.Dark.bgDeep)
                .environment(\.colorScheme, .dark)

            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
                .image { _ in
                    didDraw = hostingController.view.drawHierarchy(
                        in: hostingController.view.bounds,
                        afterScreenUpdates: true
                    )
                }

            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportEmpty-\(Locale.preferredLanguages.first ?? "unknown")-\(testCase.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}

final class BatchExportCompletionPanelLocalizationTests: XCTestCase {
    func testBatchExportCompletionCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "export.completion.title": "Export Complete",
                "export.completion.file": "Exported file: %@",
                "export.completion.share": "Share",
                "export.completion.share_hint": "Open the share sheet for the exported file.",
                "export.completion.dismiss": "Dismiss",
                "export.completion.dismiss_hint": "Remove this completion status and delete the temporary export file."
            ],
            "zh": [
                "export.completion.title": "导出完成",
                "export.completion.file": "导出文件：%@",
                "export.completion.share": "分享",
                "export.completion.share_hint": "打开已导出文件的分享面板。",
                "export.completion.dismiss": "收起",
                "export.completion.dismiss_hint": "移除此完成状态，并删除临时导出文件。"
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

    @MainActor
    func testBatchExportCompletionPanelRendersAtStandardAndAccessibilityTextSizes() {
        let cases: [(name: String, size: DynamicTypeSize)] = [
            ("Large", .large),
            ("AX5", .accessibility5)
        ]
        let exportedURL = URL(
            fileURLWithPath: "/tmp/orchard-batch-export-2026-08-09-long-filename-for-accessibility.csv"
        )

        for testCase in cases {
            let panel = BatchExportCompletionPanel(
                url: exportedURL,
                onShare: {},
                onClear: {}
            )
            .environment(\.dynamicTypeSize, testCase.size)
            .padding(Design.Space.md)

            let rootView = panel
                .frame(width: 390, height: 844, alignment: .top)
                .background(Design.Colors.Dark.bgDeep)
                .environment(\.colorScheme, .dark)

            let hostingController = UIHostingController(rootView: rootView)
            hostingController.overrideUserInterfaceStyle = .dark
            let window = UIWindow(frame: CGRect(x: 0, y: 0, width: 390, height: 844))
            window.rootViewController = hostingController
            window.makeKeyAndVisible()
            hostingController.view.frame = window.bounds
            hostingController.view.backgroundColor = .black
            hostingController.view.setNeedsLayout()
            hostingController.view.layoutIfNeeded()
            RunLoop.main.run(until: Date().addingTimeInterval(0.05))

            var didDraw = false
            let renderedImage = UIGraphicsImageRenderer(bounds: window.bounds)
                .image { _ in
                    didDraw = hostingController.view.drawHierarchy(
                        in: hostingController.view.bounds,
                        afterScreenUpdates: true
                    )
                }

            XCTAssertTrue(didDraw)
            XCTAssertEqual(renderedImage.size, CGSize(width: 390, height: 844))
            let attachment = XCTAttachment(image: renderedImage)
            attachment.name = "BatchExportCompletion-\(Locale.preferredLanguages.first ?? "unknown")-\(testCase.name)"
            attachment.lifetime = .keepAlways
            add(attachment)
            window.resignKey()
        }
    }
}
