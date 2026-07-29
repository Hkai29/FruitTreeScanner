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
