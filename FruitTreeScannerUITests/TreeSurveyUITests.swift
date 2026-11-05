import XCTest

final class TreeSurveyUITests: XCTestCase {
    private let app = XCUIApplication()
    private var coordination: URL!

    override func setUpWithError() throws {
        continueAfterFailure = false
        let env = ProcessInfo.processInfo.environment
        let expected = try XCTUnwrap(env["FRUIT_NATIVE_UI_SIMULATOR_ID"])
        let token = try XCTUnwrap(env["FRUIT_TREE_UI_TOKEN"])
        guard env["SIMULATOR_UDID"] == expected, UUID(uuidString: token) != nil,
              env["SIMULATOR_DEVICE_NAME"]?.hasPrefix("FruitTreeScanner-NativeUI-TreeSurvey-") == true else {
            throw NSError(domain: "TreeSurveyUITests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Requires an invocation-owned tree survey fixture"])
        }
        coordination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("TreeSurveyUI/\(token)")
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<8 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable)
    }

    private func openTreePositions() {
        let manage = app.buttons["dashboard.action.tagManagement"]
        XCTAssertTrue(app.buttons["dashboard.tab.history"].waitForExistence(timeout: 15))
        app.buttons["dashboard.tab.history"].tap()
        reveal(manage)
        manage.tap()
        let entry = app.buttons["orchard.treeSurvey"]
        XCTAssertTrue(entry.waitForExistence(timeout: 5))
        entry.tap()
        XCTAssertTrue(app.buttons["treeSurvey.import"].waitForExistence(timeout: 5))
    }

    private func attach(_ phase: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "TreeSurvey-\(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testEmptyImportCancelReloadMeasuredPointAndScanKeepsTreeIdentity() throws {
        app.launch()
        openTreePositions()
        XCTAssertTrue(app.staticTexts["尚无树干测量点"].exists)
        attach("empty")
        app.buttons["treeSurvey.import"].tap()
        let cancel = app.buttons["取消"].firstMatch
        XCTAssertTrue(cancel.waitForExistence(timeout: 5))
        cancel.tap()
        XCTAssertTrue(app.staticTexts["尚无树干测量点"].waitForExistence(timeout: 5))
        attach("import-cancel")
        app.terminate()

        try FileManager.default.createDirectory(at: coordination, withIntermediateDirectories: true)
        try Data().write(to: coordination.appendingPathComponent("request-fixture"))
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            FileManager.default.fileExists(atPath: self.coordination.appendingPathComponent("ready").path)
        }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 30), .completed)
        app.launch()
        openTreePositions()
        let point = app.buttons["treeSurvey.point.QA-TREE-001"]
        reveal(point)
        point.tap()
        let scan = app.buttons["treeSurvey.scan"]
        reveal(scan)
        XCTAssertTrue(app.staticTexts["报告精度达到 1 m 目标 · 现场待核验"].exists)
        attach("measured-point")
        scan.tap()
        // This invocation owns the simulator. Deny optional GPS access; the
        // measured-tree route must retain its identity without phone GPS.
        let deny = XCUIApplication(bundleIdentifier: "com.apple.springboard").alerts.buttons["不允许"]
        if deny.waitForExistence(timeout: 5) { deny.tap() }
        let session = app.descendants(matching: .any).matching(identifier: "scan.session.QA-TREE-001").firstMatch
        XCTAssertTrue(session.waitForExistence(timeout: 15))
        attach("scan-same-tree")
    }
}
