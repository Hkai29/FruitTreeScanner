// DesignReviewGalleryTests.swift
// 逐页原生截图：把每个真实页面挂进一个真实 UIWindow，渲染后作为附件保存。
//
// 为什么放在单元测试目标里：仓库的 scheme 的 test plan 只包含
// FruitTreeScannerTests，UITests 目标不在其中（"isn't a member of the specified
// test plan or scheme"）。单元测试目标本身带宿主 App，可以挂载真实 SwiftUI 页面
// 并把窗口层级渲染成 PNG——这与仓库既有的 RootLaunch/RootSettings 附件做法一致。
//
// 规则：
//   1. 截图前必须确认该页的**真实内容**已出现（标题文本 / 真实控件）；
//   2. 数据来自真实 Store 与真实写入的 PLY 文件，不用假数据替代界面；
//   3. 任何一次确认失败都让测试失败。

import SwiftUI
import UIKit
import XCTest
@testable import FruitTreeScanner

@MainActor
final class DesignReviewGalleryTests: XCTestCase {
    private var window: UIWindow!
    private var controller: UIHostingController<AnyView>!
    private var directory: URL!
    private var defaults: UserDefaults!
    private var settings: SettingsStore!
    private var parameters: FruitParametersStore!
    private var tags: TagStore!
    private var repository: ScanRepository!
    private var historyStore: ScanHistoryStore!
    private var previousKeyWindow: UIWindow?

    // MARK: - 生命周期

    override func setUpWithError() throws {
        continueAfterFailure = false
        let scene = try XCTUnwrap(UIApplication.shared.connectedScenes
            .compactMap { $0 as? UIWindowScene }
            .first { $0.activationState == .foregroundActive })
        previousKeyWindow = scene.keyWindow

        controller = UIHostingController(rootView: AnyView(EmptyView()))
        window = UIWindow(windowScene: scene)
        window.frame = CGRect(x: 0, y: 0, width: 402, height: 874)
        window.rootViewController = controller
        window.makeKeyAndVisible()

        directory = FileManager.default.temporaryDirectory
            .appendingPathComponent("design-review-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defaults = try XCTUnwrap(UserDefaults(suiteName: "design-review-\(UUID().uuidString)"))
        settings = SettingsStore(defaults: defaults)
        parameters = FruitParametersStore(defaults: defaults)
        tags = TagStore(defaults: defaults)
        repository = ScanRepository(scansDirectory: directory)
        historyStore = ScanHistoryStore(repository: repository)
    }

    override func tearDownWithError() throws {
        window?.isHidden = true
        window?.rootViewController = nil
        previousKeyWindow?.makeKey()
        if let directory { try? FileManager.default.removeItem(at: directory) }
    }

    // MARK: - 工具

    private func mount<V: View>(_ view: V) {
        controller.rootView = AnyView(view)
        window.layoutIfNeeded()
    }

    /// 改变宿主窗口尺寸：横屏 / 平板用的是同一套原生布局，只是可用空间不同。
    private func resizeWindow(to size: CGSize) {
        window.frame = CGRect(origin: .zero, size: size)
        window.layoutIfNeeded()
    }

    /// 渲染当前窗口（不落盘）。
    private func renderImage() -> UIImage {
        window.layoutIfNeeded()
        return UIGraphicsImageRenderer(bounds: window.bounds).image { _ in
            window.drawHierarchy(in: window.bounds, afterScreenUpdates: true)
        }
    }

    /// 画面落定：连续两帧像素完全一致才算稳定。
    ///
    /// AX 元素存在**不等于**画面已经稳定：入场动画、转场叠影、半透明淡入
    /// 都会让像素继续变化。只等"标题出现"就截图，会拍到动画中途的帧
    /// （向导第 3 步拍成第 4 步、启动页只剩网格）。
    private func waitForStableRender(attempts: Int = 15) async -> Bool {
        var previous = renderImage().pngData()
        for _ in 0..<attempts {
            try? await Task.sleep(nanoseconds: 200_000_000)
            let current = renderImage().pngData()
            if current == previous { return true }
            previous = current
        }
        return false
    }

    /// 截图：先等画面落定，再保存附件。
    @discardableResult
    private func snapshot(_ slug: String) async -> Data {
        let stable = await waitForStableRender()
        XCTAssertTrue(stable, "the screen never settled before the capture: \(slug)")
        let image = renderImage()
        let attachment = XCTAttachment(image: image)
        attachment.name = "design-review-\(slug)"
        attachment.lifetime = .keepAlways
        add(attachment)
        return image.pngData() ?? Data()
    }

    private var elements: [NSObject] {
        var seen = Set<ObjectIdentifier>()
        var result: [NSObject] = []
        func visit(_ object: NSObject, depth: Int = 0) {
            guard depth < 32, seen.insert(ObjectIdentifier(object)).inserted else { return }
            result.append(object)
            let count = object.accessibilityElementCount()
            if count > 0 && count < 100 {
                for index in 0..<count {
                    if let child = object.accessibilityElement(at: index) as? NSObject { visit(child, depth: depth + 1) }
                }
            }
            if let view = object as? UIView {
                for child in view.subviews { visit(child, depth: depth + 1) }
            }
        }
        var current = controller as UIViewController
        while let presented = current.presentedViewController { current = presented }
        visit(current.view)
        return result
    }

    /// 按无障碍标签找元素。
    private func element(label: String) -> NSObject? {
        let matches = elements.filter { $0.accessibilityLabel == label }
        return matches.first { $0.accessibilityTraits.contains(.button) } ?? matches.first
    }

    /// 按无障碍标识找真实控件。
    /// SwiftUI 的 Button 标识落在可访问元素上，而不是 UIView，两处都要查。
    private func element(identifier: String) -> NSObject? {
        for object in elements {
            if let element = object as? UIAccessibilityElement,
               element.accessibilityIdentifier == identifier { return element }
            if let view = object as? UIView,
               view.accessibilityIdentifier == identifier { return view }
        }
        return nil
    }

    private func hasElement(label: String) -> Bool {
        element(label: label) != nil
    }

    /// SwiftUI 会把标签与取值合并成一个可访问标签，因此按"包含"匹配更稳。
    private func hasElement(containing fragment: String) -> Bool {
        elements.contains { object in
            guard let value = object.accessibilityLabel else { return false }
            return value.contains(fragment)
        }
    }

    private func hasElement(identifierPrefix: String) -> Bool {
        for object in elements {
            if let element = object as? UIAccessibilityElement,
               element.accessibilityIdentifier?.hasPrefix(identifierPrefix) == true { return true }
            if let view = object as? UIView,
               view.accessibilityIdentifier?.hasPrefix(identifierPrefix) == true { return true }
        }
        return false
    }

    private func waitFor(_ condition: () -> Bool, timeout: TimeInterval = 6) async -> Bool {
        let deadline = Date().addingTimeInterval(timeout)
        while Date() < deadline {
            if condition() { return true }
            try? await Task.sleep(nanoseconds: 60_000_000)
        }
        return condition()
    }

    @discardableResult
    private func activate(_ label: String) async -> Bool {
        var target = element(label: label)
        if target == nil {
            // SwiftUI 组合按钮的无障碍标签可能是子元素标签的拼接。
            target = elements.first { object in
                guard let value = object.accessibilityLabel else { return false }
                return value.contains(label) && object.accessibilityTraits.contains(.button)
            }
        }
        guard let target else { return false }
        let ok = target.accessibilityActivate()
        // 0.6 毫秒只够让 AX 树更新，画面上的转场还没走完。
        try? await Task.sleep(nanoseconds: 500_000_000)
        window.layoutIfNeeded()
        return ok
    }

    /// 滚动当前呈现的滚动容器（懒加载的工具格需要先滚出来）。
    private func scrollPresentedContent(down: Bool) {
        var current = controller as UIViewController
        while let presented = current.presentedViewController { current = presented }
        guard let scroll = findScroll(current.view) else { return }
        let offset = down
            ? CGPoint(x: 0, y: scroll.contentOffset.y + scroll.bounds.height * 0.6)
            : CGPoint(x: 0, y: max(0, scroll.contentOffset.y - scroll.bounds.height * 0.6))
        scroll.setContentOffset(offset, animated: false)
        window.layoutIfNeeded()
    }

    private func findScroll(_ view: UIView) -> UIScrollView? {
        if let scroll = view as? UIScrollView { return scroll }
        for child in view.subviews {
            if let scroll = findScroll(child) { return scroll }
        }
        return nil
    }

    // MARK: - 真实数据

    /// 写入一棵合成树形的 PLY 与配套结果文件（界面评审用，**不是**实机采集）。
    private func writeScan(
        treeID: String,
        dayOffset: Int,
        fruitCount: Int,
        yieldKg: Float,
        confidence: String,
        lat: Double,
        lon: Double
    ) throws -> URL {
        let stamp = Calendar.current.date(byAdding: .day, value: -dayOffset, to: Date()) ?? Date()
        let formatter = DateFormatter()
        formatter.locale = Locale(identifier: "en_US_POSIX")
        formatter.dateFormat = "yyyyMMdd_HHmmss"
        let id = "\(treeID)_\(formatter.string(from: stamp))_lat\(String(format: "%.4f", lat))_lon\(String(format: "%.4f", lon))"
        let plyURL = directory.appendingPathComponent("\(id).ply")

        var rng = SystemRandomNumberGenerator()
        var lines: [String] = [
            "ply",
            "format ascii 1.0",
            "comment tree_id \(treeID)",
            "comment source design review synthetic fixture (not a device capture)",
            "comment not_app_lidar_or_yield_evidence",
            "element vertex 9000",
            "property float x",
            "property float y",
            "property float z",
            "property uchar red",
            "property uchar green",
            "property uchar blue",
            "comment scan_date \(ISO8601DateFormatter().string(from: stamp))",
            "comment gps_lat \(lat)",
            "comment gps_lon \(lon)",
            "end_header"
        ]
        for index in 0..<9000 {
            let t = Double(index) / 9000.0
            if t < 0.2 {
                let angle = Double.random(in: 0...(2 * .pi), using: &rng)
                let radius = 0.08 * Double.random(in: 0...1, using: &rng)
                lines.append(String(
                    format: "%.4f %.4f %.4f %d %d %d",
                    radius * cos(angle), t / 0.2 * 1.9, radius * sin(angle),
                    120, 88, 58
                ))
            } else {
                let angle = Double.random(in: 0...(2 * .pi), using: &rng)
                let radius = 1.35 * Double.random(in: 0...1, using: &rng)
                let height = 2.4 + Double.random(in: 0...1.6, using: &rng)
                let shade = Int(Double.random(in: 90...150, using: &rng))
                lines.append(String(
                    format: "%.4f %.4f %.4f %d %d %d",
                    radius * cos(angle), height, radius * sin(angle),
                    52 + shade / 6, shade, 44 + shade / 8
                ))
            }
        }
        try lines.joined(separator: "\n").write(to: plyURL, atomically: true, encoding: .utf8)

        let resultURL = directory.appendingPathComponent("\(id)_result.json")
        let payload: [String: Any] = [
            "fruitCount": fruitCount,
            "yieldKg": yieldKg,
            "fruitType": "apple",
            "confidence": confidence
        ]
        let data = try JSONSerialization.data(withJSONObject: payload, options: [.prettyPrinted])
        try data.write(to: resultURL)
        return plyURL
    }

    private func seedArchive(trees: Int) throws {
        let ids = ["A-01", "A-02", "A-03", "B-01", "B-02", "B-03"]
        for index in 0..<trees {
            let id = ids[index % ids.count]
            // 评审夹具的坐标：铺开成几百米的范围，点位在地图上才分得开。
            // 这些坐标是**合成的**，不是现场测量。
            let lat = 35.7600 + Double(index % 3) * 0.0032
            let lon = 109.4400 + Double(index / 3) * 0.0038
            let count = 90 + index * 23
            let confidence = ["high", "high", "medium", "high", "manual_review", "high"][index % 6]
            try writeScan(
                treeID: id,
                dayOffset: index % 6,
                fruitCount: count,
                yieldKg: Float(count) * 0.11,
                confidence: confidence,
                lat: lat,
                lon: lon
            )
        }
    }

    private func makeDashboard() -> some View {
        DashboardView(
            router: NavigationRouter(defaults: defaults, notificationCenter: NotificationCenter()),
            historyStore: historyStore
        )
        .environmentObject(AppDependencies(
            settings: settings,
            scanRepository: repository,
            tagStore: tags
        ))
    }

    // MARK: - 页面

    /// 工作台三个分栏。
    func testCaptureWorkspaceTabs() async throws {
        try seedArchive(trees: 8)
        historyStore.loadRecords()
        mount(makeDashboard())

        var ready = await waitFor { self.element(label: L10n.Dashboard.scanMode) != nil }
        XCTAssertTrue(ready, "the workspace never appeared")

        ready = await waitFor { self.element(label: WorkspaceText.evidence) != nil }
        XCTAssertTrue(ready, "the orchard evidence card is missing")
        // 等点云真正载入，截图才反映真实状态而不是加载中。
        ready = await waitFor {
            guard let preview = self.element(label: "点云预览") else { return false }
            guard let value = preview.accessibilityValue else { return false }
            return !value.contains("正在读取")
        }
        XCTAssertTrue(ready, "the dashboard point cloud never finished loading")
        await snapshot("01-workspace-orchard")

        var activated = await activate("档案")
        XCTAssertTrue(activated, "the archive tab could not be activated")
        ready = await waitFor { self.hasElement(label: "A-01") }
        XCTAssertTrue(ready, "the archive tab shows no scan record row")
        await snapshot("02-workspace-archive")

        activated = await activate("分析")
        XCTAssertTrue(activated, "the analysis tab could not be activated")
        ready = await waitFor { self.hasElement(label: "累计档案") }
        XCTAssertTrue(ready, "the analysis tab shows no archive totals")
        await snapshot("03-workspace-analysis")
    }

    /// 空档案状态。
    func testCaptureEmptyArchiveStates() async throws {
        historyStore.loadRecords()
        mount(makeDashboard())

        var ready = await waitFor { self.element(label: L10n.Dashboard.scanMode) != nil }
        XCTAssertTrue(ready, "the workspace never appeared")
        ready = await waitFor { self.hasElement(label: "还没有扫描记录") }
        XCTAssertTrue(ready, "the empty orchard state never appeared")
        await snapshot("24-workspace-empty")

        let activated = await activate("档案")
        XCTAssertTrue(activated, "the archive tab could not be activated")
        ready = await waitFor { self.hasElement(label: L10n.Dashboard.noScans) }
        XCTAssertTrue(ready, "the empty archive state never appeared")
        await snapshot("25-archive-empty")
    }

    /// 辅助大字号下的工作台。
    func testCaptureLargeTypeLayouts() async throws {
        try seedArchive(trees: 8)
        historyStore.loadRecords()
        mount(makeDashboard().dynamicTypeSize(.accessibility3))

        var ready = await waitFor { self.element(label: WorkspaceText.evidence) != nil }
        XCTAssertTrue(ready, "the orchard evidence card is missing at accessibility size")
        await snapshot("largetype-01-workspace-orchard")

        let activated = await activate("分析")
        XCTAssertTrue(activated, "the analysis tab could not be activated")
        ready = await waitFor { self.hasElement(label: "累计档案") }
        XCTAssertTrue(ready, "the analysis tab shows no archive totals at accessibility size")
        await snapshot("largetype-03-workspace-analysis")
    }

    /// 工具页：校准、导入、设置、品种、帮助。
    func testCaptureToolScreens() async throws {
        try seedArchive(trees: 6)
        historyStore.loadRecords()

        mount(NavigationStack {
            CalibrationView(
                scanSource: .production(repository: repository, historyStore: historyStore),
                settings: settings,
                parametersStore: parameters
            )
        })
        var ready = await waitFor { self.hasElement(label: L10n.Calibration.parametersTitle) }
        XCTAssertTrue(ready, "the calibration screen never appeared")
        // 校准记录是异步读取的：等到"正在读取"消失再截图，否则拍到的是加载态。
        ready = await waitFor(timeout: 20) { !self.hasElement(label: L10n.Calibration.loadingRecords) }
        XCTAssertTrue(ready, "the calibration records never finished loading")
        await snapshot("04-calibration")

        mount(NavigationStack {
            ImportFileView(operations: .production(repository: repository, historyStore: historyStore))
        })
        ready = await waitFor { self.hasElement(label: L10n.Import.selectButton) }
        XCTAssertTrue(ready, "the import screen never appeared")
        await snapshot("05-import")

        mount(NavigationStack { SettingsView(settings: settings, parametersStore: parameters) })
        ready = await waitFor { self.hasElement(label: L10n.Settings.title) }
        XCTAssertTrue(ready, "the settings screen never appeared")
        await snapshot("13-settings")

        mount(NavigationStack { VarietyDatabaseView(settings: settings, store: parameters) })
        ready = await waitFor { self.hasElement(label: L10n.VarietyDatabase.title) }
        XCTAssertTrue(ready, "the variety database never appeared")
        await snapshot("14-variety")

        mount(NavigationStack { HelpView() })
        ready = await waitFor { self.hasElement(label: HelpCopy.title) }
        XCTAssertTrue(ready, "the help screen never appeared")
        await snapshot("16-help")
    }

    /// 档案页：历史、标签、导出、地图、报告、趋势、对比。
    func testCaptureArchiveScreens() async throws {
        try seedArchive(trees: 6)
        historyStore.loadRecords()

        mount(NavigationStack {
            ScanHistoryView(
                customTitle: L10n.History.navigationTitle,
                onStartScan: nil,
                onRescanTree: nil,
                onImportFile: nil,
                historyStore: historyStore,
                tagStore: tags
            )
        })
        var ready = await waitFor { self.hasElement(label: L10n.History.allPlots) }
        XCTAssertTrue(ready, "the scan history screen never appeared")
        await snapshot("06-history")

        mount(NavigationStack { TagManagementView(onStartScan: nil, tagStore: tags) })
        ready = await waitFor { self.hasElement(label: L10n.TagManagement.navigationTitle) }
        XCTAssertTrue(ready, "the tag management screen never appeared")
        await snapshot("07-tag-management")

        mount(NavigationStack {
            BatchExportView(
                onStartScan: nil,
                onImportFile: nil,
                store: historyStore,
                tagStore: tags,
                operations: .production
            )
        })
        ready = await waitFor { self.hasElement(label: L10n.Export.navigationTitle) }
        XCTAssertTrue(ready, "the batch export screen never appeared")
        await snapshot("08-batch-export")

        if #available(iOS 17.0, *) {
            mount(NavigationStack { MapSheet(onStartScan: nil, historyStore: historyStore) })
            ready = await waitFor { self.hasElement(label: L10n.Dashboard.mapTitle) }
            XCTAssertTrue(ready, "the orchard map never appeared")
            await snapshot("12-orchard-map")
        }

        mount(NavigationStack { YieldReportSheet(onStartScan: nil, historyStore: historyStore) })
        ready = await waitFor { self.hasElement(label: L10n.Dashboard.yieldReportTitle) }
        XCTAssertTrue(ready, "the yield report never appeared")
        // 聚合是异步的：等真实汇总出现，不要截到空状态。
        ready = await waitFor(timeout: 15) { !self.hasElement(label: "暂无可靠产量数据") }
        XCTAssertTrue(ready, "the yield report never showed its aggregated figures")
        await snapshot("09-yield-report")

        mount(NavigationStack { TrendsSheet(onStartScan: nil, historyStore: historyStore) })
        ready = await waitFor { self.hasElement(label: L10n.Dashboard.trendsTitle) }
        XCTAssertTrue(ready, "the trends sheet never appeared")
        ready = await waitFor(timeout: 15) { !self.hasElement(label: "暂无可靠趋势数据") }
        XCTAssertTrue(ready, "the trends sheet never showed its aggregated figure")
        await snapshot("10-trends")

        mount(NavigationStack { HistoricalCompareView(onStartScan: nil, historyStore: historyStore) })
        ready = await waitFor { self.hasElement(label: "历史对比") }
        XCTAssertTrue(ready, "the comparison sheet never appeared")
        ready = await waitFor(timeout: 15) { !self.hasElement(label: "至少需要两条完整扫描") }
        XCTAssertTrue(ready, "the comparison sheet never showed its records")
        await snapshot("11-compare")

        // 已选两条记录的真实对比态：空态之外还必须有"可比"的状态。
        let slotA = await activate("扫描 A")
        XCTAssertTrue(slotA, "the scan A slot could not be activated")
        ready = await waitFor { self.hasElement(label: "树 A-01") }
        XCTAssertTrue(ready, "the scan picker never listed the archived scans")
        let pickedA = await activate("树 A-01")
        XCTAssertTrue(pickedA, "the first archived scan could not be selected")
        // 选择面板要先收起来，下面的槽位才可点。
        let dismissed = await waitFor { self.controller.presentedViewController == nil }
        XCTAssertTrue(dismissed, "the scan picker never closed after the first selection")
        let slotB = await activate("扫描 B")
        XCTAssertTrue(slotB, "the scan B slot could not be activated")
        ready = await waitFor { self.hasElement(label: "树 A-02") }
        XCTAssertTrue(ready, "the scan B picker never listed the remaining scans")
        let pickedB = await activate("树 A-02")
        XCTAssertTrue(pickedB, "the second archived scan could not be selected")
        ready = await waitFor { self.hasElement(label: "扫描证据") }
        XCTAssertTrue(ready, "the comparison never showed its evidence section")
        await snapshot("11b-compare-selected")
    }

    /// 建档、快速采集与点云。
    func testCaptureCaptureFlows() async throws {
        try seedArchive(trees: 4)
        historyStore.loadRecords()

        mount(StartView(settings: settings, tagStore: tags) { _ in })
        var ready = await waitFor { self.hasElement(label: L10n.StartSetup.text(.identifierTitle)) }
        XCTAssertTrue(ready, "the start flow never appeared")
        await snapshot("18-start-scan")

        // 建档各步：填入有效树号后逐步前进。
        //
        // 每一步都要确认两件**真实可见**的事：步序标签（第 N 步，共 5 步）
        // 与本步专属标题。只等"标题出现"会拍到上一步或转场中途的半透明帧。
        let field = elements.compactMap { $0 as? UITextField }.first
        XCTAssertNotNil(field, "the tree id field never appeared")
        field?.insertText("ROOT40")
        window.layoutIfNeeded()

        let steps: [(slug: String, step: Int, title: String)] = [
            ("18b-start-plot", 2, L10n.StartSetup.text(.plotToolTitle)),
            ("18c-start-season", 3, L10n.StartSetup.text(.seasonTitle)),
            ("18d-start-tags", 4, L10n.StartSetup.text(.tagsToolTitle)),
            ("18e-start-confirm", 5, L10n.StartSetup.text(.confirmationToolTitle))
        ]
        for entry in steps {
            let advanced = await activate(L10n.StartFlow.next)
            XCTAssertTrue(advanced, "the next-step button could not be activated before \(entry.slug)")
            let stepLabel = L10n.StartFlow.stepCountAccessibility(currentStep: entry.step, totalSteps: 5)
            let counted = await waitFor { self.hasElement(label: stepLabel) }
            XCTAssertTrue(counted, "step \(entry.slug) never reached \(stepLabel)")
            let titled = await waitFor { self.hasElement(label: entry.title) }
            XCTAssertTrue(titled, "step \(entry.slug) never showed its own title")
            await snapshot(entry.slug)
        }

        mount(QuickScanView(settings: settings) { _ in })
        ready = await waitFor { self.hasElement(label: L10n.QuickScan.navigationTitle) }
        XCTAssertTrue(ready, "the quick scan screen never appeared")
        await snapshot("19-quick-scan")

        let plyURL = try writeScan(
            treeID: "A-01", dayOffset: 0, fruitCount: 142, yieldKg: 16.4,
            confidence: "high", lat: 35.76, lon: 109.44
        )
        mount(PointCloudView(plyFileURL: plyURL, onClose: {}, treeID: "A-01", provenance: .archivedScan))
        ready = await waitFor { self.hasElement(label: L10n.PointCloud.toolsTitle) }
        XCTAssertTrue(ready, "the point cloud viewer never appeared")
        // 点云读完之后再截图。
        ready = await waitFor(timeout: 20) { !self.hasElement(containing: L10n.PointCloud.loadingTitle) }
        XCTAssertTrue(ready, "the point cloud never finished loading")
        await snapshot("17-point-cloud")

        // 点云工具
        var activated = await activate(L10n.PointCloud.toolsTitle)
        XCTAssertTrue(activated, "the point cloud tools entry could not be activated")
        ready = await waitFor { self.hasElement(label: L10n.PointCloud.zoomIn) || self.hasElement(label: L10n.PointCloud.color) }
        XCTAssertTrue(ready, "the point cloud tools sheet never appeared")
        await snapshot("30-point-cloud-tools")

        // 点云测量：从工具面板进入。工具格是懒加载的，需要先滚到测量项。
        ready = await waitFor {
            guard let entry = self.element(label: L10n.PointCloud.measure) else {
                self.scrollPresentedContent(down: true)
                return false
            }
            return !entry.accessibilityTraits.contains(.notEnabled)
        }
        XCTAssertTrue(ready, "the measurement tool never became available")
        activated = await activate(L10n.PointCloud.measure)
        XCTAssertTrue(activated, "the measurement tool could not be activated")
        ready = await waitFor { self.hasElement(label: L10n.PointCloud.measurementInstruction) }
        XCTAssertTrue(ready, "the measurement overlay never appeared")
        await snapshot("31-point-cloud-measure")
    }

    /// 编辑表单：品种参数、地块、标签、树体归档。
    ///
    /// 这些表单在真实使用中都是"从列表里点开"的独立编辑页，
    /// 因此这里直接挂载真实编辑视图，参数与标签用评审夹具。
    func testCaptureEditingForms() async throws {
        // 品种参数编辑
        mount(NavigationStack {
            VarietyEditView(
                category: .apple,
                params: parameters.param(for: .apple),
                onSave: { _ in },
                onReset: {}
            )
        })
        var ready = await waitFor {
            self.hasElement(label: L10n.VarietyDatabase.editTitle(L10n.Fruit.name(for: .apple)))
        }
        XCTAssertTrue(ready, "the variety edit form never appeared")
        await snapshot("15-variety-edit")

        // 地块编辑表单
        mount(NavigationStack { PlotEditView(plot: nil, onSave: { _ in }) })
        ready = await waitFor { self.hasElement(label: L10n.TagManagement.addPlot) }
        XCTAssertTrue(ready, "the plot edit form never appeared")
        await snapshot("27-plot-edit")

        // 标签编辑表单
        mount(NavigationStack { TagEditView(tag: nil, onSave: { _ in }) })
        ready = await waitFor { self.hasElement(label: L10n.TagManagement.addTag) }
        XCTAssertTrue(ready, "the tag edit form never appeared")
        await snapshot("28-tag-edit")

        // 树体归档：地块 / 标签 / 状态分配。
        // 用**完全隔离**的 TagStore（本次测试自己的 defaults suite），
        // 不写也不清 TagStore.shared —— 共享库里可能有模拟器上原有的元数据。
        tags.addPlot(name: "北区", colorHex: "#4D7588")
        tags.addTag(name: "盛果期", colorHex: "#6F8F63")
        mount(GalleryTaggingHost(tagStore: tags))
        ready = await waitFor { self.hasElement(label: L10n.QuickTagging.title) }
        XCTAssertTrue(ready, "the tree tagging card never appeared")
        await snapshot("29-tree-tagging")
    }

    /// 横屏与平板尺寸：同一套原生布局在更大/更扁的空间里重新排布。
    func testCaptureAdaptiveLayouts() async throws {
        try seedArchive(trees: 8)
        historyStore.loadRecords()
        let originalFrame = window.frame

        // 横屏
        resizeWindow(to: CGSize(width: 874, height: 402))
        mount(makeDashboard())
        var ready = await waitFor { self.hasElement(label: WorkspaceText.evidence) }
        XCTAssertTrue(ready, "the landscape workspace never appeared")
        await snapshot("landscape-01-workspace-orchard")

        // 平板竖屏
        resizeWindow(to: CGSize(width: 834, height: 1112))
        mount(makeDashboard())
        ready = await waitFor { self.hasElement(label: WorkspaceText.evidence) }
        XCTAssertTrue(ready, "the ipad workspace never appeared")
        await snapshot("ipad-01-workspace-orchard")

        window.frame = originalFrame
        window.layoutIfNeeded()
    }

    /// 启动页与校准录入表单。
    func testCaptureLaunchAndCalibrationForm() async throws {        mount(LaunchScreen())
        var ready = await waitFor { self.hasElement(label: "Fruit Tree Scanner") }
        XCTAssertTrue(ready, "the launch screen never appeared")
        await snapshot("00-launch")

        mount(NavigationStack {
            AddCalibrationRecordView(
                scanSource: .production(repository: repository, historyStore: historyStore),
                onSave: { _ in }
            )
        })
        ready = await waitFor { self.hasElement(label: L10n.Calibration.addNavigationTitle) }
        XCTAssertTrue(ready, "the add-calibration form never appeared")
        await snapshot("26-calibration-add")
    }

    /// 采集 HUD 与结果页（DEBUG 设计评审预览）。
    func testCaptureDesignReviewPreviews() async throws {
        mount(DesignReviewHUDPreview())
        var ready = await waitFor { self.hasElement(label: "设计评审预览 · 合成读数，非实机采集") }
        XCTAssertTrue(ready, "the HUD design-review preview never appeared")
        await snapshot("20-scan-hud")

        // 三种结果形态必须**真的渲染出不同的页面**：
        //   1. 传参用枚举（类型安全，字符串 rawValue 不匹配会静默退回 .reliable）；
        //   2. 断言该形态**专属**的正文：可靠性标题、零估产理由、保存恢复面板；
        //   3. 断言三张图互不相同——否则"三种状态"只是同一个状态拍了三次。
        var rendered: [Data] = []
        for (slug, scenario, expectedTitle, exclusiveText) in [
            (
                "21-result",
                DesignReviewResultPreview.Scenario.reliable,
                L10n.Result.detail(.reliabilityReliableTitle),
                L10n.Result.detail(.reliabilityReliableSummary)
            ),
            (
                "22-result-review",
                DesignReviewResultPreview.Scenario.review,
                L10n.Result.detail(.reliabilityReviewTitle),
                L10n.ScanResultPersistence.text(.failureTitle)
            ),
            (
                "23-result-no-estimate",
                DesignReviewResultPreview.Scenario.noEstimate,
                L10n.Result.detail(.reliabilityNoEstimateTitle),
                L10n.Result.detail(.reasonDepthUnavailable)
            )
        ] {
            mount(DesignReviewResultPreview(initialScenario: scenario).id(slug))
            ready = await waitFor { self.hasElement(label: "设计评审预览 · 合成结果，非实机采集") }
            XCTAssertTrue(ready, "the result design-review preview never appeared")
            let titled = await waitFor { self.hasElement(containing: expectedTitle) }
            XCTAssertTrue(titled, "the result page never showed the \(scenario.label) reliability title")
            let exclusive = await waitFor { self.hasElement(containing: exclusiveText) }
            XCTAssertTrue(exclusive, "the \(scenario.label) result page never showed \(exclusiveText)")
            rendered.append(await snapshot(slug))
        }
        XCTAssertEqual(
            Set(rendered).count, 3,
            "the reliable / review / no-estimate result pages rendered identical images"
        )
    }
}

// MARK: - 评审宿主

/// 树体归档卡的宿主：结果页里的"地块 / 标签 / 状态"分配表单。
///
/// 标签库由外部注入，评审时用**隔离的** TagStore，不碰共享库。
private struct GalleryTaggingHost: View {
    let tagStore: TagStore
    @State private var selectedPlotId: UUID?
    @State private var selectedTagIds: Set<UUID> = []
    @State private var selectedStatus: ScanStatus = .scanned

    var body: some View {
        NavigationStack {
            ScrollView {
                QuickTaggingCard(
                    treeID: "A-01",
                    selectedPlotId: $selectedPlotId,
                    selectedTagIds: $selectedTagIds,
                    selectedStatus: $selectedStatus,
                    tagStore: tagStore
                )
                .padding(20)
            }
            .navigationTitle(L10n.QuickTagging.title)
        }
    }
}
