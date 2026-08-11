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

final class OrchardMapPresentationTests: XCTestCase {
    func testCopyIsCompleteInEnglishAndChinese() throws {
        let expectedCopy: [String: [String: String]] = [
            "en": [
                "orchard_map.close": "Close Orchard Map",
                "orchard_map.close_hint": "Closes the orchard map.",
                "orchard_map.empty_title": "No Located Scans",
                "orchard_map.empty_message": "Complete scans with GPS locations appear on the orchard map so you can review reliable yield distribution.",
                "orchard_map.start_scan": "Start Scanning",
                "orchard_map.orchard_trees": "Orchard Trees",
                "orchard_map.estimated_yield": "Estimated Yield",
                "orchard_map.fruit_count": "Fruit Count",
                "orchard_map.confidence": "Confidence",
                "orchard_map.scan_date": "Scan Date",
                "orchard_map.yield_level": "Yield Level",
                "orchard_map.filter.selected": "Selected",
                "orchard_map.filter.not_selected": "Not selected",
                "orchard_map.filter.hint": "Shows only trees in this yield level.",
                "orchard_map.filter.selected_hint": "Clears this yield filter.",
                "orchard_map.filter.clear": "Clear Yield Filter",
                "orchard_map.filter.clear_hint": "Shows all located trees.",
                "orchard_map.details.close": "Close Tree Details",
                "orchard_map.details.close_hint": "Hides the selected tree's scan details.",
                "orchard_map.pin.select_hint": "Shows this tree's scan details.",
                "orchard_map.requires_ios17": "Orchard Map requires iOS 17 or later.",
                "orchard_map.confidence.high": "High",
                "orchard_map.confidence.medium": "Medium",
                "orchard_map.confidence.low": "Low",
                "orchard_map.confidence.unknown": "Unknown",
                "orchard_map.yield.high": "High yield",
                "orchard_map.yield.medium": "Medium yield",
                "orchard_map.yield.low": "Low yield",
                "orchard_map.tree_title_format": "Tree %@",
                "orchard_map.pin_value_format": "%@, %@, %@",
                "orchard_map.unit.tree_one": "tree",
                "orchard_map.unit.tree_other": "trees",
                "orchard_map.unit.fruit_one": "fruit",
                "orchard_map.unit.fruit_other": "fruits",
                "orchard_map.unit.kilograms": "kg"
            ],
            "zh": [
                "orchard_map.close": "关闭果园地图",
                "orchard_map.close_hint": "关闭果园地图视图。",
                "orchard_map.empty_title": "暂无定位扫描",
                "orchard_map.empty_message": "带 GPS 的完整扫描记录会显示在果园地图中，用于查看可靠产量分布。",
                "orchard_map.start_scan": "开始扫描",
                "orchard_map.orchard_trees": "园区树木",
                "orchard_map.estimated_yield": "预估产量",
                "orchard_map.fruit_count": "果实数",
                "orchard_map.confidence": "置信度",
                "orchard_map.scan_date": "扫描日期",
                "orchard_map.yield_level": "产量等级",
                "orchard_map.filter.selected": "已选择",
                "orchard_map.filter.not_selected": "未选择",
                "orchard_map.filter.hint": "仅显示此产量等级的树体。",
                "orchard_map.filter.selected_hint": "取消此产量等级筛选。",
                "orchard_map.filter.clear": "清除产量筛选",
                "orchard_map.filter.clear_hint": "显示全部有定位的树体。",
                "orchard_map.details.close": "关闭树体详情",
                "orchard_map.details.close_hint": "隐藏当前树体的扫描详情。",
                "orchard_map.pin.select_hint": "显示这棵树的扫描详情。",
                "orchard_map.requires_ios17": "果园地图需要 iOS 17 或更高版本。",
                "orchard_map.confidence.high": "高",
                "orchard_map.confidence.medium": "中",
                "orchard_map.confidence.low": "低",
                "orchard_map.confidence.unknown": "未知",
                "orchard_map.yield.high": "高产",
                "orchard_map.yield.medium": "中产",
                "orchard_map.yield.low": "低产",
                "orchard_map.tree_title_format": "树 %@",
                "orchard_map.pin_value_format": "%@，%@，%@",
                "orchard_map.unit.tree_one": "棵",
                "orchard_map.unit.tree_other": "棵",
                "orchard_map.unit.fruit_one": "个",
                "orchard_map.unit.fruit_other": "个",
                "orchard_map.unit.kilograms": "kg"
            ]
        ]

        for (language, expectedValues) in expectedCopy {
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

    func testPresentationMapsVisibleCopyYieldLevelsAndConfidenceStates() throws {
        let english = OrchardMapPresentation(bundle: try localizedBundle("en"))
        let chinese = OrchardMapPresentation(bundle: try localizedBundle("zh"))

        XCTAssertEqual(
            [
                english.closeMap,
                english.emptyTitle,
                english.startScan,
                english.orchardTrees,
                english.estimatedYield,
                english.yieldLevelTitle,
                english.filterSelectedHint,
                english.requiresIOS17
            ],
            [
                "Close Orchard Map",
                "No Located Scans",
                "Start Scanning",
                "Orchard Trees",
                "Estimated Yield",
                "Yield Level",
                "Clears this yield filter.",
                "Orchard Map requires iOS 17 or later."
            ]
        )
        XCTAssertEqual(english.yieldLevelLabel(.high), "High yield")
        XCTAssertEqual(english.yieldLevelLabel(.medium), "Medium yield")
        XCTAssertEqual(english.yieldLevelLabel(.low), "Low yield")
        XCTAssertEqual(english.confidenceLabel("high"), "High")
        XCTAssertEqual(english.confidenceLabel("unexpected"), "Unknown")

        XCTAssertEqual(chinese.treeTitle("TREE-8"), "树 TREE-8")
        XCTAssertEqual(chinese.yieldLevelLabel(.high), "高产")
        XCTAssertEqual(chinese.confidenceLabel("unexpected"), "未知")
    }

    func testPresentationUsesRegionalDatesNumbersPluralUnitsAndPinSemantics() throws {
        let scanDate = try scanDate()
        let tree = makeTree(
            id: "tree-many",
            treeID: "TREE-1234",
            weight: 9_876.5,
            confidence: "high",
            scanDate: scanDate,
            fruitCount: 12_345
        )

        let english = OrchardMapPresentation(bundle: try localizedBundle("en"))
        let englishUS = Locale(identifier: "en_US")
        XCTAssertEqual(english.treeTitle(tree.treeID), "Tree TREE-1234")
        XCTAssertEqual(english.treeCountText(1, locale: englishUS), "1 tree")
        XCTAssertEqual(english.treeCountText(12_345, locale: englishUS), "12,345 trees")
        XCTAssertEqual(english.fruitCountText(1, locale: englishUS), "1 fruit")
        XCTAssertEqual(english.fruitCountText(tree.fruitCount, locale: englishUS), "12,345 fruits")
        XCTAssertEqual(english.yieldText(tree.weight, locale: englishUS), "9,876.5 kg")
        XCTAssertEqual(english.scanDateText(scanDate, locale: englishUS), "06/01/2026")
        XCTAssertEqual(
            english.mapPinValue(for: tree, locale: englishUS),
            "High yield, 9,876.5 kg, 12,345 fruits"
        )
        XCTAssertEqual(
            english.scanDateText(scanDate, locale: Locale(identifier: "en_GB")),
            "01/06/2026"
        )

        let chinese = OrchardMapPresentation(bundle: try localizedBundle("zh"))
        let chineseLocale = Locale(identifier: "zh_CN")
        XCTAssertEqual(chinese.treeCountText(12_345, locale: chineseLocale), "12,345 棵")
        XCTAssertEqual(chinese.fruitCountText(tree.fruitCount, locale: chineseLocale), "12,345 个")
        XCTAssertEqual(chinese.scanDateText(scanDate, locale: chineseLocale), "2026/06/01")
        XCTAssertEqual(
            chinese.mapPinValue(for: tree, locale: chineseLocale),
            "高产，9,876.5 kg，12,345 个"
        )
    }

    @MainActor
    func testMapEmptyStateAndComponentsRenderInEnglishAndChineseAtLargestAccessibilityTextSize() throws {
        for language in ["en", "zh"] {
            let locale = Locale(identifier: language == "en" ? "en_US" : "zh_CN")
            let presentation = OrchardMapPresentation(bundle: try localizedBundle(language))
            let selectedTree = makeTree(
                id: "selected-\(language)",
                treeID: "TREE-1234",
                weight: 9_876.5,
                confidence: "unexpected",
                scanDate: try scanDate(),
                fruitCount: 12_345
            )
            let summaryTrees = [
                selectedTree,
                makeTree(id: "medium", treeID: "TREE-2", weight: 40, confidence: "medium", scanDate: try scanDate(), fruitCount: 2),
                makeTree(id: "low", treeID: "TREE-3", weight: 10, confidence: "low", scanDate: try scanDate(), fruitCount: 3)
            ]

            let emptyState = AnyView(
                OrchardMapEmptyState(onStartScan: {})
                    .environment(\.orchardMapPresentation, presentation)
                    .environment(\.locale, locale)
                    .environment(\.dynamicTypeSize, .accessibility5)
                    .environment(\.colorScheme, .dark)
            )
            attachRender(
                of: emptyState,
                size: CGSize(width: 390, height: 844),
                name: "OrchardMapEmpty-\(language)-AX5"
            )

            let components = AnyView(
                VStack(alignment: .leading, spacing: 18) {
                    OrchardMapTopBar(treeCount: 12_345, onDismiss: {})
                    OrchardMapLegend(filterYieldLevel: .constant(.high))

                    HStack(spacing: 24) {
                        ForEach(summaryTrees) { tree in
                            TreeMapPin(tree: tree, isSelected: tree.id == selectedTree.id)
                        }
                    }
                    .frame(maxWidth: .infinity)

                    TreeDetailCard(tree: selectedTree, onClose: {})
                    TreeCountCard(filteredTrees: summaryTrees)

                    Spacer(minLength: 0)
                }
                .padding(16)
                .background(Design.Colors.Dark.bgDeep)
                .environment(\.orchardMapPresentation, presentation)
                .environment(\.locale, locale)
                .environment(\.dynamicTypeSize, .accessibility5)
                .environment(\.colorScheme, .dark)
            )
            attachRender(
                of: components,
                size: CGSize(width: 390, height: 2_400),
                name: "OrchardMapComponents-\(language)-AX5"
            )
        }
    }

    private func localizedBundle(_ language: String) throws -> Bundle {
        try XCTUnwrap(
            Bundle.main.path(forResource: language, ofType: "lproj").flatMap(Bundle.init(path:)),
            "Missing \(language) localization bundle"
        )
    }

    private func scanDate() throws -> Date {
        var components = DateComponents()
        components.calendar = Calendar(identifier: .gregorian)
        components.timeZone = TimeZone(secondsFromGMT: 0)
        components.year = 2026
        components.month = 6
        components.day = 1
        return try XCTUnwrap(components.date)
    }

    private func makeTree(
        id: String,
        treeID: String,
        weight: Double,
        confidence: String,
        scanDate: Date,
        fruitCount: Int
    ) -> TreeAnnotation {
        TreeAnnotation(
            id: id,
            treeID: treeID,
            coordinate: CLLocationCoordinate2D(latitude: 31.2304, longitude: 121.4737),
            weight: weight,
            confidence: confidence,
            scanDate: scanDate,
            fruitCount: fruitCount
        )
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
        XCTAssertNotNil(renderedImage.cgImage)
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
