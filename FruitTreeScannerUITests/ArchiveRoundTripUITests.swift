import XCTest

/// 归档详情往返：档案行 → 归档详情 → **系统返回按钮** → 档案列表。
///
/// 夹具由 `tools/validate_archive_round_trip_ui.py` 播种进**本次调用自有**的模拟器：
/// 只动那个一次性模拟器里的应用容器，不碰真实历史、不碰默认用户数据、不改全局设备设置。
///
/// 覆盖的既定验收条件：
/// 1. 从真实根入口进入档案页，选一个地块筛选，滚到**非顶部**的一条；
/// 2. 按存档身份打开详情（同一棵树有两份档案时不能串）；
/// 3. 用**真实系统导航返回按钮**返回；
/// 4. 断言：筛选仍在、回到**同一条**存档、目标可见且位置符合已承诺的复位策略
///    （把刚才那条放回视口中部）、再次打开仍是同一份存档；
/// 5. 循环至少两次；
/// 6. 详情里的点云预览 / 分享弹层关闭后，详情不能变空，返回后列表状态还在。
///
/// 无障碍焦点**分层**说明：普通 XCUITest 只能证明 AX 元素存在与可点击，
/// 它读不到系统无障碍焦点（XCTest 没有这个 API），
/// 因此焦点本身由宿主测试用 `UIAccessibility.focusedElement` 取证；
/// VoiceOver 实读仍未验证。
final class ArchiveRoundTripUITests: XCTestCase {
    private let app = XCUIApplication()
    private var coordination: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ArchiveRoundTrip/\(token)", isDirectory: true)
    }
    private var token = ""

    private struct Fixture: Decodable {
        struct Archive: Decodable {
            let archiveID: String
            let treeID: String
            /// 这一份存档自己的产量读数（行里显示的那一串）。
            let yieldText: String
        }
        /// 一段记录号查询命中后，各分组各有几份。
        struct Counts: Decodable {
            let today: Int
            let yesterday: Int
            let earlier: Int
        }
        let plot: String
        let otherPlot: String
        let target: Archive
        let sameTreeOtherArchive: Archive
        /// 另一棵树的存档：用来证明搜索真的把别人筛掉了。
        let otherArchiveID: String
        /// 今天 / 昨天各一份：用来证明日期分组在真机里真的分了组。
        let todayArchiveID: String
        let yesterdayArchiveID: String
        /// 一段记录号查询，以及它命中后各分组的份数。
        let broadQuery: String
        let broadCounts: Counts
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let expected = try XCTUnwrap(
            environment["FRUIT_NATIVE_UI_SIMULATOR_ID"],
            "Run tools/validate_archive_round_trip_ui.py to create an isolated fixture"
        )
        token = try XCTUnwrap(environment["FRUIT_ARCHIVE_UI_TOKEN"])
        guard !expected.isEmpty, environment["SIMULATOR_UDID"] == expected,
              UUID(uuidString: token) != nil,
              environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("FruitTreeScanner-NativeUI-") == true else {
            throw NSError(domain: "ArchiveRoundTripUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Refusing to edit an existing simulator"])
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        // The first launch installs the app. The host then seeds the archive
        // fixture into that container, so the install can never overwrite it.
        app.launch()
        app.terminate()
        try FileManager.default.createDirectory(at: coordination, withIntermediateDirectories: true)
        try Data("request-fixture".utf8).write(
            to: coordination.appendingPathComponent("request-fixture"), options: .atomic)
        waitUntil("The host must prepare the installed app's fixture before launch") {
            FileManager.default.fileExists(atPath: self.coordination.appendingPathComponent("fixture-ready").path)
        }
        app.launch()
    }

    // MARK: - 夹具与工具

    private func fixture() throws -> Fixture {
        let raw = try XCTUnwrap(
            ProcessInfo.processInfo.environment["FRUIT_ARCHIVE_UI_FIXTURE"],
            "The runner must describe the seeded archive fixture"
        )
        return try JSONDecoder().decode(Fixture.self, from: Data(raw.utf8))
    }

    private func attach(_ phase: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "ArchiveRoundTrip-\(phase)"
        image.lifetime = .keepAlways
        add(image)
    }

    /// 附加当前的 AX 树：证明行确实在树上、带着什么 trait。
    /// 这**不是** VoiceOver 焦点证据，只是 AX 结构证据。
    private func attachAccessibilityTree(_ phase: String) {
        let tree = XCTAttachment(string: app.debugDescription)
        tree.name = "ArchiveRoundTrip-\(phase)-accessibility"
        tree.lifetime = .keepAlways
        add(tree)
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 30)
        if result != .completed {
            attachAccessibilityTree(description)
        }
        XCTAssertEqual(result, .completed, description)
    }

    /// 等条件成立，返回是否在超时前成立。
    ///
    /// 用于「要不要重试」这类判断：条件不成立时**不**直接判失败，
    /// 但会把当时的 AX 树留下来当证据。
    @discardableResult
    private func waitFor(_ description: String,
                         timeout: TimeInterval = 15,
                         _ condition: @escaping () -> Bool) -> Bool {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: timeout)
        if result != .completed {
            attachAccessibilityTree(description)
        }
        return result == .completed
    }

    /// 按存档编号找到那一行（用 label 精确定位，不靠索引）。
    private func row(_ archiveID: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label == %@", archiveID)).firstMatch
    }

    /// 把目标行滚到可点击。
    ///
    /// 返回 (元素, 目标一开始是否在折叠线以下) —— 后者用来证明
    /// 「非顶部目标」不是一句恒真的话：目标必须本来就滚不到。
    private func reveal(_ archiveID: String) -> (element: XCUIElement, wasBelowTheFold: Bool) {
        let target = row(archiveID)
        let initiallyHittable = target.exists && target.isHittable
        for _ in 0..<12 {
            if target.exists && target.isHittable { break }
            app.swipeUp()
        }
        if !(target.exists && target.isHittable) {
            // 失败时把当时的界面留下来：滚动位置、行的位置、键盘在不在。
            attachAccessibilityTree("reveal-failed-\(archiveID)")
            attach("reveal-failed-\(archiveID)")
        }
        XCTAssertTrue(target.exists && target.isHittable,
                      "目标行必须能滚到并点得着：\(archiveID)（键盘挡着时先收键盘：\(app.keyboards.count)）")
        return (target, !initiallyHittable)
    }

    // MARK: - 搜索

    /// 搜索框。
    private var searchField: XCUIElement {
        app.textFields["historySearch.field"]
    }

    /// 输入搜索词，并**确认它真的进了输入框**。
    ///
    /// 只靠「列表变了」间接判断是不够的：打字没进去时列表看着也对，
    /// 断言会跟着失真。
    private func typeSearch(_ text: String) throws {
        let field = searchField
        XCTAssertTrue(field.waitForExistence(timeout: 15), "档案页必须有搜索框")
        field.tap()
        field.typeText(text)
        XCTAssertTrue(waitFor("搜索词必须真的输入进去", timeout: 10) {
            (self.searchField.value as? String ?? "").contains(text)
        }, "搜索词没有进输入框：\(searchField.value as? String ?? "")")
    }

    /// 清除搜索，并**确认输入框真的空了**。
    private func clearSearch() throws {
        let before = searchField.value as? String ?? ""
        let clear = app.buttons["historySearch.clear"]
        XCTAssertTrue(clear.waitForExistence(timeout: 10), "有查询时必须有清除入口")
        clear.tap()
        XCTAssertTrue(waitFor("清除后输入框要空", timeout: 10) {
            let now = self.searchField.value as? String ?? ""
            // 输入框空了以后，取值可能是空串，也可能是占位文字 ——
            // 判定只认「不再是刚才那个查询」。
            return now != before && !now.contains("T-07") && !now.contains("2026")
        }, "清除后输入框里还留着搜索词：\(searchField.value as? String ?? "")")
    }

    /// 收起键盘：用键盘上的**搜索键**（产品里搜索键 = 搜索 + 收键盘）。
    ///
    /// 键盘浮在列表上方时，下面几行会被挡住；不收键盘就没法点到它们。
    private func dismissKeyboard() throws {
        let keyboard = app.keyboards.firstMatch
        guard keyboard.waitForExistence(timeout: 5) else { return }
        var tapped = false
        for label in ["搜索", "search", "Search", "前往", "Go", "return", "Return"] {
            let key = keyboard.buttons[label]
            if key.exists {
                key.tap()
                tapped = true
                break
            }
        }
        if !tapped {
            // 退路：键盘最末一个键就是回车/搜索。
            let buttons = keyboard.buttons
            if buttons.count > 0 {
                buttons.element(boundBy: buttons.count - 1).tap()
            }
        }
        XCTAssertTrue(waitFor("键盘必须收起来", timeout: 10) { !self.app.keyboards.firstMatch.exists },
                      "键盘没收起来")
    }

    // MARK: - 档案页

    private func openHistory() {
        // 真实根入口：仪表盘右上角的「扫描历史」。
        // 底部的「档案」标签只是仪表盘上的档案区（最近扫描 + 功能入口），
        // 完整档案列表在这个入口后面。
        let entry = app.buttons["dashboard.action.history"]
        XCTAssertTrue(entry.waitForExistence(timeout: 15), "必须能从真实根入口进入档案")
        entry.tap()
        // 打开后的实况先留证：截图 + AX 树。失败时才知道屏幕上到底是什么。
        attach("history-opened")
        attachAccessibilityTree("history-opened")
        waitUntil("档案页必须带地块筛选") { self.app.buttons["全部地块"].exists }
    }

    /// 选一个地块筛选。芯片的标题会变成选中的地块名。
    private func selectPlot(_ plot: String) {
        let chip = app.buttons["全部地块"]
        XCTAssertTrue(chip.waitForExistence(timeout: 10))
        chip.tap()
        let item = app.buttons[plot]
        XCTAssertTrue(item.waitForExistence(timeout: 10), "筛选菜单里必须有地块：\(plot)")
        item.tap()
        waitUntil("地块筛选必须生效") {
            self.app.buttons[plot].firstMatch.exists && !self.app.buttons["全部地块"].exists
        }
    }

    // MARK: - 详情

    private func openDetail(_ archiveID: String) {
        let target = reveal(archiveID).element
        target.tap()
        XCTAssertTrue(app.navigationBars["归档详情"].waitForExistence(timeout: 15),
                      "必须推进到归档详情")
        XCTAssertTrue(app.staticTexts[archiveID].waitForExistence(timeout: 15),
                      "详情必须显示这一条自己的存档编号")
    }

    /// 关掉**系统分享面板**，并且证明它**真的关掉了**。
    ///
    /// 两个已知事实（都是实测，不是猜测）：
    /// 1. iOS 27 把这个系统控件报成不可点，所以只能用它的真实可达矩形去点，
    ///    不能直接 `close.tap()`；
    /// 2. 合成点击偶尔会在面板还在落定时被吞掉 —— 面板仍然完整地留在屏幕上，
    ///    而"底下的详情还在"这种检查**发现不了**（面板盖住详情时，
    ///    底下的详情文本同样"存在"）。
    ///
    /// 所以这里点完必须验证面板**从无障碍树里消失**，不行就重试，
    /// 并且在最终失败时留下截图与 AX 树。
    private func dismissShareSheet() {
        let close = app.buttons["header.closeButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "系统分享面板必须真的打开")

        // 先等面板落定：面板里的真实动作按钮可点，说明面板已经能接收点击。
        // 等不到也不算失败（系统动作集合可能变），后面的重试才是真正的门禁。
        let copyAction = app.descendants(matching: .any)
            .matching(NSPredicate(format: "label == %@", "拷贝")).firstMatch
        _ = waitFor("分享面板落定", timeout: 8) { copyAction.exists && copyAction.isHittable }

        for attempt in 1...3 {
            XCTAssertTrue(close.exists, "系统分享面板必须真的打开")
            let frame = close.frame
            XCTAssertTrue(frame.width > 0 && frame.height > 0 && app.frame.contains(frame),
                          "关闭按钮必须有一个真实的可达矩形")
            app.coordinate(withNormalizedOffset: .zero)
                .withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
            // 面板必须真的消失 —— 这才是"关掉了"的证据。
            if waitFor("分享面板必须真正关闭", timeout: 10) { !close.exists } {
                return
            }
            attach("share-still-open-attempt\(attempt)")
        }
        XCTFail("系统分享面板点了关闭之后仍然没有关掉")
    }

    /// 点**真实系统导航返回按钮**。
    private func tapSystemBack() {
        let back = app.navigationBars["归档详情"].buttons.firstMatch
        XCTAssertTrue(back.waitForExistence(timeout: 15), "详情必须有系统返回按钮")
        // 返回按钮要在**可点**的时候才算就绪：弹层或转场还在时它会被盖住，
        // 那时候"存在"是真的，"可点"不是真的。
        XCTAssertTrue(waitFor("系统返回按钮必须可点", timeout: 15) { back.exists && back.isHittable },
                      "系统返回按钮必须可点")
        back.tap()
        XCTAssertTrue(app.buttons["全部状态"].waitForExistence(timeout: 15),
                      "返回后必须回到档案列表")
    }

    // MARK: - 往返

    /// 回归：档案行 → 详情 → 系统返回 → 列表状态恢复。
    func testArchiveDetailRoundTripRestoresFilterScrollAndIdentity() throws {
        let fixture = try fixture()
        openHistory()
        selectPlot(fixture.plot)

        // 准备：滚到**非顶部**的目标。
        // 「一开始就在折叠线以下」是这条验收的前提 —— 否则这一轮根本没测到滚动。
        let (scrolledTo, wasBelowTheFold) = reveal(fixture.target.archiveID)
        XCTAssertTrue(wasBelowTheFold,
                      "目标必须本来就在折叠线以下（否则这轮没测到滚动）")
        XCTAssertTrue(scrolledTo.exists && scrolledTo.isHittable)

        for cycle in 1...2 {
            let target = row(fixture.target.archiveID)
            XCTAssertTrue(target.exists && target.isHittable,
                          "第 \(cycle) 轮：目标必须可见可点")
            target.tap()
            XCTAssertTrue(app.navigationBars["归档详情"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts[fixture.target.archiveID].waitForExistence(timeout: 15),
                          "第 \(cycle) 轮：详情必须是这一条存档")
            XCTAssertFalse(app.staticTexts[fixture.sameTreeOtherArchive.archiveID].exists,
                           "第 \(cycle) 轮：不能串到同树的另一份档案")
            attach("cycle\(cycle)-detail")

            // 真实系统返回。
            tapSystemBack()

            // 1) 筛选仍在
            let chip = app.buttons[fixture.plot].firstMatch
            XCTAssertTrue(chip.waitForExistence(timeout: 15),
                          "第 \(cycle) 轮：返回后地块筛选必须还在")
            XCTAssertTrue(chip.isSelected,
                          "第 \(cycle) 轮：返回后地块筛选必须仍是选中状态")
            XCTAssertFalse(app.buttons["全部地块"].exists,
                           "第 \(cycle) 轮：地块筛选不能被重置成全部")

            // 2) 回到同一条存档，且可见可点
            let restored = row(fixture.target.archiveID)
            XCTAssertTrue(restored.waitForExistence(timeout: 15),
                          "第 \(cycle) 轮：返回后必须回到同一份存档")
            XCTAssertTrue(restored.isHittable,
                          "第 \(cycle) 轮：返回后目标必须可见可点")
            // 回到的是**刚打开的那一份**：读数必须对得上，同树另一份的读数不能出现。
            let restoredValue = restored.value as? String ?? ""
            XCTAssertTrue(restoredValue.contains(fixture.target.yieldText),
                          "第 \(cycle) 轮：恢复回来的必须是刚打开那一份的读数：\(restoredValue)")
            XCTAssertFalse(restoredValue.contains(fixture.sameTreeOtherArchive.yieldText),
                           "第 \(cycle) 轮：不能落到同树的另一份档案上：\(restoredValue)")

            // 3) 位置符合已承诺的复位策略：把刚才那条放回视口中部。
            let frame = restored.frame
            XCTAssertTrue(app.frame.contains(frame),
                          "第 \(cycle) 轮：返回后目标必须在视口内：\(frame)")
            XCTAssertEqual(frame.midY, app.frame.midY, accuracy: app.frame.height * 0.15,
                           "第 \(cycle) 轮：返回后目标应当被放回视口中部（已承诺的复位策略）")
            attach("cycle\(cycle)-restored")
            attachAccessibilityTree("cycle\(cycle)-restored")

            // 4) 再次打开仍是同一份存档
            restored.tap()
            XCTAssertTrue(app.navigationBars["归档详情"].waitForExistence(timeout: 15))
            XCTAssertTrue(app.staticTexts[fixture.target.archiveID].waitForExistence(timeout: 15),
                          "第 \(cycle) 轮：再次打开必须仍是同一份存档")
            attach("cycle\(cycle)-reopened")
            tapSystemBack()
        }
    }

    /// 回归：详情里的点云预览 / 分享弹层关闭后，详情不能变空、不能长期停在 idle、
    /// 不能串到同树的另一份档案；再返回，列表状态还在。
    func testArchiveDetailSurvivesPointCloudAndShareDismissal() throws {
        let fixture = try fixture()
        openHistory()
        selectPlot(fixture.plot)
        openDetail(fixture.target.archiveID)
        attach("detail-before-sheets")

        // 点云预览：打开再关闭。
        let preview = app.buttons["archiveDetail.previewPointCloud"]
        XCTAssertTrue(preview.waitForExistence(timeout: 15))
        preview.tap()
        let close = app.buttons["pointCloud.close"]
        XCTAssertTrue(close.waitForExistence(timeout: 20), "点云预览必须真的打开")
        attach("point-cloud")
        close.tap()
        // 预览必须真的关掉：只看"底下的详情还在"发现不了被盖住的弹层。
        XCTAssertTrue(waitFor("点云预览必须真正关闭", timeout: 15) { !close.exists },
                      "点云预览必须真正关闭")
        waitUntil("关闭点云预览后详情必须还在") {
            self.app.staticTexts["这次读数"].exists
                && self.app.staticTexts[fixture.target.archiveID].exists
        }
        XCTAssertFalse(app.staticTexts[fixture.sameTreeOtherArchive.archiveID].exists,
                       "关闭预览后不能串到同树的另一份档案")
        attach("detail-after-point-cloud")

        // 分享：系统分享面板打开再关闭。
        let share = app.buttons["archiveDetail.sharePointCloud"]
        XCTAssertTrue(share.waitForExistence(timeout: 15))
        share.tap()
        let shareClose = app.buttons["header.closeButton"]
        XCTAssertTrue(shareClose.waitForExistence(timeout: 20), "系统分享面板必须真的打开")
        attach("share")
        // 关掉面板，并且证明它真的关掉了（合成点击会被吞，必须验证 + 重试）。
        dismissShareSheet()
        waitUntil("关闭分享后详情必须还在") {
            self.app.staticTexts["这次读数"].exists
                && self.app.staticTexts[fixture.target.archiveID].exists
        }
        attach("detail-after-share")

        // 返回：列表状态还在。
        tapSystemBack()
        let chip = app.buttons[fixture.plot].firstMatch
        XCTAssertTrue(chip.waitForExistence(timeout: 15))
        XCTAssertTrue(chip.isSelected, "关闭弹层再返回后，地块筛选必须仍然是选中状态")
        XCTAssertTrue(row(fixture.target.archiveID).waitForExistence(timeout: 15),
                      "关闭弹层再返回后，必须回到同一份存档")
        attach("restored-after-sheets")
    }

    /// 回归：档案搜索（树号 + 存档编号）、日期分组，以及
    /// 「详情返回后 query、筛选、身份、位置都还在」。
    ///
    /// 覆盖的既定验收条件：
    /// 1. 搜索框在真实页面上、点得到、能真的打字；
    /// 2. 树号与存档编号**两个身份**都能搜到；
    /// 3. 清除搜索后档案都回来，且**地块筛选还在**；
    /// 4. 日期分组标题（今天/昨天/更早）在真机里真的分组了；
    /// 5. 筛到一个更宽的条件后，滚到**非顶部**的档案 → 进详情 →
    ///    **真实系统返回按钮** → query、筛选、身份、位置都还在；
    /// 6. 搜不到时有**自己的**文案，并能清除。
    func testArchiveSearchAndDateGroupsSurviveDetailRoundTrip() throws {
        let fixture = try fixture()
        openHistory()

        // 查询有命中但被地块筛空：清筛选必须保留查询，不能谎报树号不存在。
        selectPlot(fixture.otherPlot)
        try typeSearch(fixture.target.treeID)
        XCTAssertTrue(app.staticTexts["匹配记录被当前筛选排除"].waitForExistence(timeout: 15))
        XCTAssertFalse(app.staticTexts["没有匹配的记录"].exists)
        let clearFilters = app.buttons["historyEmpty.clearFilters"]
        XCTAssertTrue(clearFilters.isHittable)
        attach("search-excluded-by-filters")
        clearFilters.tap()
        XCTAssertTrue(row(fixture.target.archiveID).waitForExistence(timeout: 15))
        XCTAssertEqual(searchField.value as? String, fixture.target.treeID)
        XCTAssertTrue(app.buttons["全部地块"].exists)
        try clearSearch()
        selectPlot(fixture.plot)

        // 1) 搜索框在页面上、点得到。
        XCTAssertTrue(searchField.waitForExistence(timeout: 15), "档案页必须有搜索框")
        XCTAssertTrue(searchField.isHittable, "搜索框必须点得到")
        attach("search-field")

        // 2) 日期分组：今天 / 昨天 / 更早三段都要在真机里出现。
        XCTAssertTrue(app.staticTexts["historyGroup.header.today"].waitForExistence(timeout: 15),
                      "今天这一段必须有组标题")
        XCTAssertTrue(app.staticTexts["historyGroup.header.yesterday"].exists,
                      "昨天这一段必须有组标题")
        XCTAssertTrue(app.staticTexts["historyGroup.header.earlier"].exists,
                      "更早这一段必须有组标题")
        attach("date-groups")

        // 3) 按**树号**搜：同树的两份都命中，别的一份都不命中。
        try typeSearch(fixture.target.treeID)
        XCTAssertTrue(waitFor("按树号搜索后目标必须在", timeout: 20) { self.row(fixture.target.archiveID).exists })
        XCTAssertTrue(row(fixture.sameTreeOtherArchive.archiveID).exists,
                      "同一棵树的另一份也要命中")
        XCTAssertFalse(row(fixture.otherArchiveID).exists, "别的树必须被筛掉")
        attach("search-by-tree")

        // 4) 清除搜索：档案都回来，地块筛选**还在**。
        try clearSearch()
        XCTAssertTrue(waitFor("清除后别的档案要回来", timeout: 20) { self.row(fixture.otherArchiveID).exists })
        XCTAssertTrue(app.buttons[fixture.plot].firstMatch.isSelected,
                      "清除搜索不能把地块筛选一起清掉")
        attach("search-cleared")

        // 5) 按**存档编号**搜（不是树号）：只命中那一份。
        try typeSearch("20261020_090000")
        XCTAssertTrue(waitFor("按存档编号搜索后目标必须在", timeout: 20) { self.row(fixture.target.archiveID).exists })
        XCTAssertFalse(row(fixture.sameTreeOtherArchive.archiveID).exists,
                       "同树的另一份不该被命中")
        XCTAssertFalse(row(fixture.otherArchiveID).exists, "别的档案不该被命中")
        attach("search-by-record-id")

        // 6) 换成一个更宽的条件（记录号的一段）：命中十多条，
        //    目标因此落在折叠线以下 —— 滚动与复位才有东西可证。
        try clearSearch()
        try typeSearch(fixture.broadQuery)
        // 键盘浮着会挡住下面几行：先收键盘，再看份数、再滚。
        try dismissKeyboard()
        // 份数写在组标题上：这是「筛出来的正好是这些」最硬的证据
        //（行会被 LazyVStack 裁掉，标题不会）。
        let earlierHeader = app.staticTexts["historyGroup.header.earlier"]
        XCTAssertTrue(earlierHeader.waitForExistence(timeout: 20), "更早这一段必须在")
        XCTAssertEqual(earlierHeader.label, "更早 · \(fixture.broadCounts.earlier) 份",
                       "更早这一段的份数必须正好（同树的另一份不在这一段里）")
        XCTAssertEqual(app.staticTexts["historyGroup.header.today"].label,
                       "今天 · \(fixture.broadCounts.today) 份")
        XCTAssertEqual(app.staticTexts["historyGroup.header.yesterday"].label,
                       "昨天 · \(fixture.broadCounts.yesterday) 份")
        let (scrolledTo, wasBelowTheFold) = reveal(fixture.target.archiveID)
        XCTAssertTrue(wasBelowTheFold, "目标必须本来就在折叠线以下（否则这轮没测到滚动）")
        XCTAssertTrue(scrolledTo.exists && scrolledTo.isHittable)
        attach("search-scrolled")

        // 7) 进详情，用**真实系统返回按钮**回来。
        scrolledTo.tap()
        XCTAssertTrue(app.navigationBars["归档详情"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts[fixture.target.archiveID].waitForExistence(timeout: 15),
                      "详情必须是这一条存档")
        XCTAssertFalse(app.staticTexts[fixture.sameTreeOtherArchive.archiveID].exists,
                       "不能串到同树的另一份档案")
        attach("search-detail")

        tapSystemBack()

        // 8) 返回后：query、筛选、身份、位置都还在。
        XCTAssertTrue((searchField.value as? String ?? "").contains(fixture.broadQuery),
                      "返回后搜索词必须还在：\(searchField.value as? String ?? "")")
        XCTAssertTrue(app.buttons[fixture.plot].firstMatch.isSelected,
                      "返回后地块筛选必须还在")
        let restored = row(fixture.target.archiveID)
        XCTAssertTrue(restored.waitForExistence(timeout: 15), "返回后必须回到同一份存档")
        let restoredValue = restored.value as? String ?? ""
        XCTAssertTrue(restoredValue.contains(fixture.target.yieldText),
                      "恢复回来的必须是刚打开那一份的读数：\(restoredValue)")
        XCTAssertFalse(restoredValue.contains(fixture.sameTreeOtherArchive.yieldText),
                       "不能落到同树的另一份档案上：\(restoredValue)")
        let frame = restored.frame
        XCTAssertTrue(app.frame.contains(frame), "返回后目标必须在视口内：\(frame)")
        attach("search-restored")
        attachAccessibilityTree("search-restored")

        // 9) 搜不到时有**自己的**文案，并能清除。
        try typeSearch("ZZZ")
        XCTAssertTrue(waitFor("无匹配文案必须出现", timeout: 20) { self.app.staticTexts["没有匹配的记录"].exists },
                      "搜索没命中必须有自己的文案")
        XCTAssertTrue(app.buttons["historySearch.clear"].exists, "无匹配时也要能清除")
        attach("search-no-match")
        try clearSearch()
        XCTAssertTrue(waitFor("清除后档案要回来", timeout: 20) { self.row(fixture.otherArchiveID).exists })
        XCTAssertTrue(app.buttons[fixture.plot].firstMatch.isSelected,
                      "清除搜索仍然不能动地块筛选")
    }
}
