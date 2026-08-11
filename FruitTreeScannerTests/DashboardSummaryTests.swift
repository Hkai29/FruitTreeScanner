import SwiftUI
import UIKit
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
        XCTAssertEqual(report.totalScans, 2)
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
        XCTAssertTrue(report.visibleRecords.isEmpty)
        XCTAssertEqual(report.totalScans, 0)
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
        XCTAssertEqual(report.visibleRecords.count, 20)
        XCTAssertEqual(report.visibleRecords.first?.id, "complete-0")
        XCTAssertEqual(report.visibleRecords.last?.id, "complete-19")
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

final class HistoricalComparePresentationTests: XCTestCase {
    func testCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "historical_compare.title": "Compare Trees",
                "historical_compare.subtitle": "Select two complete scans to compare yield, fruit count, and scan date side by side.",
                "historical_compare.navigation_title": "Historical Comparison",
                "historical_compare.empty_title": "Two Complete Scans Required",
                "historical_compare.empty_message_one": "Only 1 complete scan is currently available. Complete and save another scan to compare yield, fruit count, and scan date.",
                "historical_compare.empty_message_other_format": "Only %@ complete scans are currently available. Complete and save two scans to compare yield, fruit count, and scan date.",
                "historical_compare.start_scan": "Start Scanning",
                "historical_compare.prompt": "Select two scan records to compare yield, fruit count, and scan date side by side.",
                "historical_compare.scan_a": "Scan A",
                "historical_compare.scan_b": "Scan B",
                "historical_compare.versus": "versus",
                "historical_compare.select_scan": "Select Scan",
                "historical_compare.no_scan_selected": "No scan selected",
                "historical_compare.selection_hint_format": "Selects a complete scan record for %@.",
                "historical_compare.picker_title": "Select Scan",
                "historical_compare.picker.selection_hint_format": "Uses this record for %@.",
                "historical_compare.picker.value_format": "%@; %@",
                "historical_compare.yield_change": "Yield Change",
                "historical_compare.lidar_detections": "LiDAR Detections",
                "historical_compare.average_diameter": "Average Diameter",
                "historical_compare.confidence": "Confidence",
                "historical_compare.scan_date": "Scan Date",
                "historical_compare.tree_title_format": "Tree %@",
                "historical_compare.scan_summary_format": "%@, %@, %@",
                "historical_compare.comparison_values_format": "%@: %@; %@: %@.",
                "historical_compare.comparison_value_format": "%@: %@; %@: %@; %@.",
                "historical_compare.yield_accessibility_value_format": "%@ %@: %@; %@ %@: %@; change %@, %@.",
                "historical_compare.unit.fruit_one": "fruit",
                "historical_compare.unit.fruit_other": "fruits",
                "historical_compare.unit.kilograms": "kg",
                "historical_compare.unit.centimeters": "cm",
                "historical_compare.unavailable": "Unavailable",
                "historical_compare.confidence.high": "High",
                "historical_compare.confidence.medium": "Medium",
                "historical_compare.confidence.low": "Low",
                "historical_compare.confidence.manual_review": "Manual review",
                "historical_compare.confidence.unknown": "Unknown",
                "historical_compare.trend.increased": "Increased",
                "historical_compare.trend.decreased": "Decreased",
                "historical_compare.trend.unchanged": "No change",
                "historical_compare.trend.unavailable": "Change unavailable",
                "historical_compare.picker.selected": "Selected",
                "historical_compare.picker.not_selected": "Not selected"
            ],
            "zh": [
                "historical_compare.title": "树体对比",
                "historical_compare.subtitle": "选择两条完整扫描，并排比较产量、果数和扫描日期。",
                "historical_compare.navigation_title": "历史对比",
                "historical_compare.empty_title": "至少需要两条完整扫描",
                "historical_compare.empty_message_one": "当前只有 1 条完整扫描。完成并保存另一次扫描后，就可以比较产量、果数和扫描日期。",
                "historical_compare.empty_message_other_format": "当前只有 %@ 条完整扫描。完成并保存两次扫描后，就可以比较产量、果数和扫描日期。",
                "historical_compare.start_scan": "开始扫描",
                "historical_compare.prompt": "选择两条扫描记录后，会显示产量、果数和扫描日期的并排对比。",
                "historical_compare.scan_a": "扫描 A",
                "historical_compare.scan_b": "扫描 B",
                "historical_compare.versus": "对比",
                "historical_compare.select_scan": "选择扫描",
                "historical_compare.no_scan_selected": "尚未选择扫描",
                "historical_compare.selection_hint_format": "为%@选择一条完整扫描记录。",
                "historical_compare.picker_title": "选择扫描",
                "historical_compare.picker.selection_hint_format": "将这条记录用于%@。",
                "historical_compare.picker.value_format": "%@；%@",
                "historical_compare.yield_change": "产量变化",
                "historical_compare.lidar_detections": "LiDAR 检测",
                "historical_compare.average_diameter": "平均直径",
                "historical_compare.confidence": "置信度",
                "historical_compare.scan_date": "扫描日期",
                "historical_compare.tree_title_format": "树 %@",
                "historical_compare.scan_summary_format": "%@，%@，%@",
                "historical_compare.comparison_values_format": "%@：%@；%@：%@。",
                "historical_compare.comparison_value_format": "%@：%@；%@：%@；%@。",
                "historical_compare.yield_accessibility_value_format": "%@ %@：%@；%@ %@：%@；变化%@，%@。",
                "historical_compare.unit.fruit_one": "个果实",
                "historical_compare.unit.fruit_other": "个果实",
                "historical_compare.unit.kilograms": "kg",
                "historical_compare.unit.centimeters": "cm",
                "historical_compare.unavailable": "不可用",
                "historical_compare.confidence.high": "高",
                "historical_compare.confidence.medium": "中",
                "historical_compare.confidence.low": "低",
                "historical_compare.confidence.manual_review": "需人工复核",
                "historical_compare.confidence.unknown": "未知",
                "historical_compare.trend.increased": "上升",
                "historical_compare.trend.decreased": "下降",
                "historical_compare.trend.unchanged": "无变化",
                "historical_compare.trend.unavailable": "变化不可用",
                "historical_compare.picker.selected": "已选择",
                "historical_compare.picker.not_selected": "未选择"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
            let actualValues = try localizedTable(language)
                .filter { $0.key.hasPrefix("historical_compare.") }
            XCTAssertEqual(actualValues, expectedValues)
        }
    }

    func testPresentationUsesRegionalDatesNumbersUnitsAndConservativeUnknownStates() throws {
        let scanDate = try makeDate()
        let english = HistoricalComparePresentation(bundle: try localizedBundle("en"))
        let chinese = HistoricalComparePresentation(bundle: try localizedBundle("zh"))
        let enUS = Locale(identifier: "en_US")
        let enGB = Locale(identifier: "en_GB")
        let zhCN = Locale(identifier: "zh_CN")

        XCTAssertEqual(english.dateText(scanDate, locale: enUS), "06/01/2026")
        XCTAssertEqual(english.dateText(scanDate, locale: enGB), "01/06/2026")
        XCTAssertEqual(chinese.dateText(scanDate, locale: zhCN), "2026/06/01")
        XCTAssertEqual(english.yieldText(9_876.5, locale: enUS), "9,876.5 kg")
        XCTAssertEqual(english.fruitCountText(1, locale: enUS), "1 fruit")
        XCTAssertEqual(english.fruitCountText(12_345, locale: enUS), "12,345 fruits")
        XCTAssertEqual(chinese.fruitCountText(12_345, locale: zhCN), "12,345 个果实")
        XCTAssertEqual(english.percentageText(0.25, locale: enUS), "+25.0%")
        XCTAssertEqual(english.percentageText(nil, locale: enUS), "Unavailable")
        XCTAssertEqual(english.confidenceText("unexpected"), "Unknown")
        XCTAssertEqual(chinese.confidenceText(""), "不可用")
        XCTAssertEqual(english.trendText(.unavailable), "Change unavailable")
        XCTAssertEqual(
            english.comparisonValue(value1: "High", value2: "Low", trend: nil),
            "Scan A: High; Scan B: Low."
        )
    }

    @MainActor
    func testComponentsRenderInEnglishAndChineseAtLargestAccessibilityTextSize() throws {
        let scanDate = try makeDate()
        let first = ScanItem(
            id: "first",
            treeID: "TREE-123456789",
            scanDate: scanDate,
            yieldKg: 9_876.5,
            nLidar: 1,
            meanDiameterCm: nil,
            confidence: "unexpected"
        )
        let second = ScanItem(
            id: "second",
            treeID: "TREE-SECOND-LONG-ID",
            scanDate: scanDate,
            yieldKg: 12_345.6,
            nLidar: 12_345,
            meanDiameterCm: 8.4,
            confidence: "high"
        )

        for language in ["en", "zh"] {
            let locale = Locale(identifier: language == "en" ? "en_US" : "zh_CN")
            let presentation = HistoricalComparePresentation(bundle: try localizedBundle(language))
            let empty = AnyView(
                HistoricalCompareEmptyState(scanCount: 1, onStartScan: {})
                    .padding(16)
                    .environment(\.historicalComparePresentation, presentation)
                    .environment(\.locale, locale)
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.colorScheme, .dark)
                    .background(Design.Colors.Dark.bgDeep)
            )
            attachRender(
                of: empty,
                size: CGSize(width: 390, height: 844),
                name: "HistoricalCompareEmpty-\(language)-AX5"
            )

            let components = AnyView(
                VStack(alignment: .leading, spacing: 16) {
                    ScanSelectionCard(scan: first, label: presentation.scanA, onTap: {})
                    ScanSelectionCard(scan: nil, label: presentation.scanB, onTap: {})
                    HistoricalComparePrompt()
                    HistoricalYieldComparisonCard(scan1: first, scan2: second, proportionalChange: 0.25)
                    StatCompareCard(
                        title: presentation.lidarDetections,
                        value1: presentation.fruitCountText(first.nLidar, locale: locale),
                        value2: presentation.fruitCountText(second.nLidar, locale: locale),
                        icon: "cube.fill",
                        trend: .up
                    )
                    StatCompareCard(
                        title: presentation.averageDiameter,
                        value1: presentation.diameterText(first.meanDiameterCm, locale: locale),
                        value2: presentation.diameterText(second.meanDiameterCm, locale: locale),
                        icon: "circle.dotted",
                        trend: .unavailable
                    )
                    StatCompareCard(
                        title: presentation.confidence,
                        value1: presentation.confidenceText(first.confidence),
                        value2: presentation.confidenceText(second.confidence),
                        icon: "checkmark.seal.fill",
                        trend: nil
                    )
                    ScanPickerRow(scan: second, isSelected: true, slot: presentation.scanB)
                    Spacer(minLength: 0)
                }
                .padding(16)
                .environment(\.historicalComparePresentation, presentation)
                .environment(\.locale, locale)
                .environment(\.dynamicTypeSize, .accessibility5)
                .environment(\.colorScheme, .dark)
                .background(Design.Colors.Dark.bgDeep)
            )
            attachRender(
                of: components,
                size: CGSize(width: 390, height: 4_200),
                name: "HistoricalCompareComponents-\(language)-AX5"
            )
        }
    }

    private func localizedBundle(_ language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
            "Missing \(language) localization bundle"
        )
    }

    private func localizedTable(_ language: String) throws -> [String: String] {
        let bundle = try localizedBundle(language)
        let url = try XCTUnwrap(bundle.url(forResource: "Localizable", withExtension: "strings"))
        let propertyList = try PropertyListSerialization.propertyList(from: Data(contentsOf: url), format: nil)
        return try XCTUnwrap(propertyList as? [String: String])
    }

    private func makeDate() throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 6
        components.day = 1
        components.hour = 12
        return try XCTUnwrap(components.date)
    }

    @MainActor
    private func attachRender(of view: AnyView, size: CGSize, name: String) {
        let renderer = ImageRenderer(
            content: view.frame(width: size.width, height: size.height, alignment: .top)
        )
        renderer.scale = 1
        renderer.proposedSize = ProposedViewSize(size)
        guard let renderedImage = renderer.uiImage else {
            return XCTFail("Unable to render \(name)")
        }

        XCTAssertEqual(renderedImage.size, size)
        assertImageHasVisibleContent(renderedImage, name: name)
        let attachment = XCTAttachment(image: renderedImage)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func assertImageHasVisibleContent(_ image: UIImage, name: String) {
        let sampleSize = CGSize(width: 64, height: 64)
        let sample = UIGraphicsImageRenderer(size: sampleSize).image { _ in
            image.draw(in: CGRect(origin: .zero, size: sampleSize))
        }
        guard let cgImage = sample.cgImage,
              let data = cgImage.dataProvider?.data,
              let bytes = CFDataGetBytePtr(data) else {
            return XCTFail("Unable to inspect rendered pixels for \(name)")
        }

        let byteCount = CFDataGetLength(data)
        var colors = Set<UInt32>()
        for offset in stride(from: 0, to: byteCount - 3, by: 4) {
            let color = UInt32(bytes[offset])
                | (UInt32(bytes[offset + 1]) << 8)
                | (UInt32(bytes[offset + 2]) << 16)
                | (UInt32(bytes[offset + 3]) << 24)
            colors.insert(color)
            if colors.count > 8 { break }
        }

        XCTAssertGreaterThan(colors.count, 8, "\(name) rendered without visible component content")
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
