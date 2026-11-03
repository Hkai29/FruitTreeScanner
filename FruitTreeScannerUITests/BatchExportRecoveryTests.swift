import XCTest
import UIKit

final class BatchExportRecoveryTests: XCTestCase {
    private let app = XCUIApplication()
    private var token = ""
    private var coordination: URL {
        FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("BatchExportRecovery/\(token)", isDirectory: true)
    }

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let expected = try XCTUnwrap(environment["FRUIT_NATIVE_UI_SIMULATOR_ID"])
        token = try XCTUnwrap(environment["FRUIT_BATCH_UI_TOKEN"])
        guard !expected.isEmpty, environment["SIMULATOR_UDID"] == expected,
              UUID(uuidString: token) != nil,
              environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("FruitTreeScanner-NativeUI-") == true else {
            throw NSError(domain: "BatchExportRecoveryTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Run tools/validate_batch_export_ui.py with its isolated fixture"])
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        // XCUIApplication installs the app on its first launch, independently
        // of installing the UI runner. Relaunch preserves its data container.
        app.launch()
        app.terminate()
        try FileManager.default.createDirectory(at: coordination, withIntermediateDirectories: true)
        try Data("fixture".utf8).write(to: coordination.appendingPathComponent("request-fixture"), options: .atomic)
        waitUntil("The host must prepare the installed app's fixture before launch") {
            FileManager.default.fileExists(atPath: self.coordination.appendingPathComponent("fixture-ready").path)
        }
        app.launch()
    }

    private func waitUntil(_ description: String, _ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        let result = XCTWaiter.wait(for: [expectation], timeout: 30)
        if result != .completed {
            attach("timeout")
            let hierarchy = XCTAttachment(string: app.debugDescription)
            hierarchy.name = description
            hierarchy.lifetime = .keepAlways
            add(hierarchy)
        }
        XCTAssertEqual(result, .completed, description)
    }

    private func attach(_ phase: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "BatchExportRecovery-\(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tapAlertAction(_ identifier: String, in alert: XCUIElement) throws {
        // iOS 27 exposes the same identifier on an outer button and its
        // nested button. Target the unique leaf action, verified as hittable.
        let actions = alert.buttons.matching(identifier: identifier).allElementsBoundByIndex
            .filter { $0.descendants(matching: .button).count == 0 }
        XCTAssertEqual(actions.count, 1)
        let action = try XCTUnwrap(actions.first)
        XCTAssertTrue(action.isHittable)
        action.tap()
    }

    func testFailureCancelThenRetryAfterStorageRepairCompletesAndCleansExport() throws {
        app.buttons["dashboard.tab.history"].tap()
        let entry = app.buttons["dashboard.action.batchExport"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        let export = app.buttons["batchExport.export"]
        waitUntil("The valid fixture must be selected and exportable") { export.exists && export.isEnabled && export.isHittable }
        export.tap()
        let alert = app.alerts["无法导出记录"]
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["无法写入导出文件。请检查可用存储空间后重试。"].exists)
        attach("cancel-alert")
        try tapAlertAction("batchExport.failure.cancel", in: alert)
        waitUntil("Cancel must close the failure and restore the export action") { !alert.exists && export.exists && export.isEnabled }
        export.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["无法写入导出文件。请检查可用存储空间后重试。"].exists)

        // The host repairs only its disposable fixture, while this real alert
        // stays open. No app launch argument or production fault hook is used.
        let coordination = coordination
        try Data("repair".utf8).write(to: coordination.appendingPathComponent("request-repair"), options: .atomic)
        waitUntil("The host must acknowledge the storage repair") {
            FileManager.default.fileExists(atPath: coordination.appendingPathComponent("repaired").path)
        }
        attach("retry-alert")
        try tapAlertAction("batchExport.failure.retry", in: alert)
        let completed = app.buttons["batchExport.completion.dismiss"]
        let copyAction = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "拷贝")).firstMatch
        waitUntil("Retry must finish and present a share sheet") {
            !alert.exists && copyAction.exists && copyAction.isHittable
        }
        attach("share-completed")
        let close = app.buttons["header.closeButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        // iOS 27 reports this visible system control as not hittable. Use its
        // observed accessibility frame for a real touch, as in the settings UI test.
        let closeFrame = close.frame
        XCTAssertTrue(closeFrame.width > 0 && closeFrame.height > 0 && app.frame.contains(closeFrame))
        app.coordinate(withNormalizedOffset: .zero)
            .withOffset(CGVector(dx: closeFrame.midX, dy: closeFrame.midY)).tap()
        waitUntil("Dismissing sharing must retain the completed export") { completed.exists && completed.isHittable }
        attach("completed")
        try Data("complete".utf8).write(to: coordination.appendingPathComponent("request-inspection"), options: .atomic)
        waitUntil("The host must inspect completed file contents before cleanup") {
            FileManager.default.fileExists(atPath: coordination.appendingPathComponent("inspected").path)
        }
        completed.tap()
        waitUntil("Clear must remove the completed result and restore export") { !completed.exists && export.exists && export.isEnabled }
        try Data("clear".utf8).write(to: coordination.appendingPathComponent("cleared"), options: .atomic)
        waitUntil("The host must confirm the product removed the completed file") {
            FileManager.default.fileExists(atPath: coordination.appendingPathComponent("clear-inspected").path)
        }
        attach("cleared")

        // The same complete legacy record remains valid for CSV but has no
        // replay input. Exercise the real format-specific failure on this
        // compact simulator after storage is healthy again.
        let replay = app.buttons["batchExport.format.replay"]
        for _ in 0..<8 where !replay.isHittable { app.swipeDown() }
        XCTAssertTrue(replay.isHittable)
        let treeField = app.buttons["batchExport.option.treeID"]
        let originalTreeFieldValue = try XCTUnwrap(treeField.value as? String)
        replay.tap()
        waitUntil("Replay must be selected and hide ordinary export fields") {
            replay.value as? String == "已选择"
                && self.app.staticTexts["batchExport.replay.description"].exists
                && !treeField.exists && export.isEnabled && export.isHittable
        }
        attach("legacy-replay-selected")
        export.tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 10))
        XCTAssertTrue(alert.staticTexts["所选扫描中有记录缺少完整回放输入，请选择启用输入留存后采集的扫描。"].exists)
        attach("legacy-replay-unavailable")
        try tapAlertAction("batchExport.failure.cancel", in: alert)
        waitUntil("Cancel must restore the replay export action without a completed file") {
            !alert.exists && !completed.exists && export.isEnabled
        }
        try Data("unavailable".utf8).write(to: coordination.appendingPathComponent("request-unavailable-inspection"), options: .atomic)
        waitUntil("The host must confirm replay failure preserved archives and left no export") {
            FileManager.default.fileExists(atPath: coordination.appendingPathComponent("unavailable-inspected").path)
        }
        let csv = app.buttons["batchExport.format.csv"]
        XCTAssertTrue(csv.isHittable)
        csv.tap()
        waitUntil("CSV must restore the original field selection after replay failure") {
            csv.value as? String == "已选择" && treeField.exists
                && treeField.value as? String == originalTreeFieldValue
                && !self.app.staticTexts["batchExport.replay.description"].exists
        }
        attach("csv-restored-after-replay-failure")
    }
}

/// Uses only a production-committed synthetic fixture in the invocation-owned
/// simulator created by tools/validate_replay_export_ui.py.
final class ReplayExportUITests: XCTestCase {
    private let app = XCUIApplication()
    private var coordination: URL!

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let token = try XCTUnwrap(environment["FRUIT_REPLAY_UI_TOKEN"])
        let expected = try XCTUnwrap(environment["FRUIT_NATIVE_UI_SIMULATOR_ID"])
        guard !expected.isEmpty, expected == environment["SIMULATOR_UDID"],
              UUID(uuidString: token) != nil,
              environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("FruitTreeScanner-NativeUI-") == true else {
            throw NSError(domain: "ReplayExportUITests", code: 1)
        }
        coordination = FileManager.default.urls(for: .documentDirectory, in: .userDomainMask)[0]
            .appendingPathComponent("ReplayExport/\(token)", isDirectory: true)
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
        app.terminate()
        try FileManager.default.createDirectory(at: coordination, withIntermediateDirectories: true)
        try signal("request-fixture")
        waitUntil { FileManager.default.fileExists(atPath: self.coordination.appendingPathComponent("fixture-ready").path) }
        app.launch()
    }

    private func signal(_ name: String) throws {
        try Data(name.utf8).write(to: coordination.appendingPathComponent(name), options: .atomic)
    }

    private func waitUntil(_ condition: @escaping () -> Bool) {
        let expectation = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in condition() }, object: nil)
        XCTAssertEqual(XCTWaiter.wait(for: [expectation], timeout: 30), .completed)
    }

    private func attach(_ phase: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = "ReplayExport66-\(phase)"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCompleteReplayExportPresentsShareAndCleansOnlyTemporaryFile() throws {
        app.buttons["dashboard.tab.history"].tap()
        let entry = app.buttons["dashboard.action.batchExport"]
        XCTAssertTrue(entry.waitForExistence(timeout: 10))
        for _ in 0..<8 where !entry.isHittable { app.swipeUp() }
        XCTAssertTrue(entry.isHittable)
        entry.tap()
        let replay = app.buttons["batchExport.format.replay"]
        for _ in 0..<8 where !replay.isHittable { app.swipeDown() }
        XCTAssertTrue(replay.isHittable)
        replay.tap()
        let export = app.buttons["batchExport.export"]
        waitUntil {
            replay.value as? String == "已选择" && self.app.staticTexts["batchExport.replay.description"].exists
                && export.isEnabled && export.isHittable
        }
        attach("ready")
        export.tap()
        let copy = app.descendants(matching: .any).matching(NSPredicate(format: "label == %@", "拷贝")).firstMatch
        waitUntil { copy.exists && copy.isHittable }
        XCTAssertFalse(app.alerts["无法导出记录"].exists)
        attach("share")
        let close = app.buttons["header.closeButton"]
        XCTAssertTrue(close.waitForExistence(timeout: 5))
        let frame = close.frame
        XCTAssertTrue(frame.width > 0 && frame.height > 0 && app.frame.contains(frame))
        app.coordinate(withNormalizedOffset: .zero).withOffset(CGVector(dx: frame.midX, dy: frame.midY)).tap()
        let clear = app.buttons["batchExport.completion.dismiss"]
        waitUntil { clear.exists && clear.isHittable }
        attach("complete")
        try signal("request-inspection")
        waitUntil { FileManager.default.fileExists(atPath: self.coordination.appendingPathComponent("inspected").path) }
        clear.tap()
        waitUntil { !clear.exists && export.isEnabled }
        try signal("cleared")
        waitUntil { FileManager.default.fileExists(atPath: self.coordination.appendingPathComponent("clear-inspected").path) }
        attach("cleared")
    }
}

final class DashboardLayoutUITests: XCTestCase {
    func testCompactEnglishAnalyticsMetricsKeepWordsOnOneLine() throws {
        let environment = ProcessInfo.processInfo.environment
        let expected = try XCTUnwrap(environment["FRUIT_NATIVE_UI_SIMULATOR_ID"])
        guard expected == environment["SIMULATOR_UDID"],
              environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("FruitTreeScanner-NativeUI-") == true else {
            throw NSError(domain: "DashboardLayoutUITests", code: 1)
        }
        let app = XCUIApplication()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US"]
        app.launch()
        let analysis = app.buttons["dashboard.tab.analytics"]
        XCTAssertTrue(analysis.waitForExistence(timeout: 10))
        analysis.tap()
        var frames: [[String: Any]] = []
        // The analysis panel renders the three daily metrics as separate
        // label/value/unit texts. These are the English labels the panel
        // actually shows today; the metric must not wrap inside a word.
        for label in ["Yield", "Today's Scans", "Tree IDs"] {
            let element = app.staticTexts[label].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 10), label)
            let frame = element.frame
            frames.append(["label": label, "x": frame.minX, "y": frame.minY,
                           "width": frame.width, "height": frame.height])
            XCTAssertGreaterThan(frame.width, 0, label)
            XCTAssertGreaterThan(frame.height, 0, label)
            XCTAssertLessThanOrEqual(frame.height, 18, "\(label) must not wrap inside a word: \(frame)")
        }
        // The archive totals panel carries the same three readings under its
        // own labels; they must be legible in English too.
        for label in ["Total Yield", "Archive totals"] {
            let element = app.staticTexts[label].firstMatch
            XCTAssertTrue(element.waitForExistence(timeout: 10), label)
            let frame = element.frame
            frames.append(["label": label, "x": frame.minX, "y": frame.minY,
                           "width": frame.width, "height": frame.height])
            XCTAssertGreaterThan(frame.width, 0, label)
            XCTAssertGreaterThan(frame.height, 0, label)
            XCTAssertLessThanOrEqual(frame.height, 18, "\(label) must not wrap inside a word: \(frame)")
        }
        let geometry = XCTAttachment(data: try JSONSerialization.data(withJSONObject: frames),
                                     uniformTypeIdentifier: "public.json")
        geometry.name = "Workspace-EnglishMetricFrames"
        geometry.lifetime = .keepAlways
        add(geometry)
        let screenshot = XCTAttachment(screenshot: app.screenshot())
        screenshot.name = "Workspace-EnglishCompact"
        screenshot.lifetime = .keepAlways
        add(screenshot)
        app.buttons["dashboard.tab.scan"].tap()
        XCTAssertTrue(app.buttons["dashboard.action.startScan"].isHittable)
        XCTAssertTrue(app.buttons["dashboard.action.quickScan"].isHittable)
        XCTAssertGreaterThanOrEqual(app.buttons["dashboard.action.quickScan"].frame.height, 44)
        app.swipeUp()
        XCTAssertTrue(app.buttons["dashboard.action.importFile"].isHittable, "The last scan tool must remain reachable below the saved-tree evidence")

        app.buttons["dashboard.tab.history"].tap()
        let recent = app.buttons["dashboard.recentScan.batch-ui-60"]
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let chooseArchive = app.buttons["pointCloud.selectArchive"]
        XCTAssertTrue(chooseArchive.waitForExistence(timeout: 5), "The whitespace in the recent scan row must open its point cloud")
        chooseArchive.tap()
        XCTAssertTrue(app.navigationBars["Choose a scan"].waitForExistence(timeout: 5))
        // The dashboard's own recent-scan row carries the same tree id, so the
        // picker row must be looked up inside the picker's list. Otherwise the
        // query resolves to the dashboard row behind the sheet, which is never
        // the selected archive.
        let selectedRecord = app.collectionViews.cells.buttons["batch-ui-60"].firstMatch
        XCTAssertTrue(selectedRecord.waitForExistence(timeout: 5))
        XCTAssertTrue(selectedRecord.isSelected)
        XCTAssertFalse((selectedRecord.value as? String ?? "").isEmpty, "The record must expose its date and integrity")
        selectedRecord.tap()
        XCTAssertTrue(app.buttons["pointCloud.close"].waitForExistence(timeout: 5))
        app.buttons["pointCloud.close"].tap()

        app.terminate()
        app.launchArguments += ["-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryXXXL"]
        app.launch()
        XCTAssertTrue(app.buttons["dashboard.tab.history"].waitForExistence(timeout: 10))
        app.buttons["dashboard.tab.history"].tap()
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        let pointCloudClose = app.buttons["pointCloud.close"]
        let pointCloudShare = app.buttons["pointCloud.share"]
        XCTAssertTrue(pointCloudClose.waitForExistence(timeout: 5))
        XCTAssertTrue(app.frame.contains(pointCloudClose.frame), "XXXL point cloud metrics must not displace Close outside the viewport")
        XCTAssertTrue(app.frame.contains(pointCloudShare.frame), "Share must remain inside the viewport")
        XCTAssertTrue(pointCloudClose.isHittable)
        let toolsEntry = app.buttons["pointCloud.tools"]
        XCTAssertTrue(toolsEntry.waitForExistence(timeout: 5), "The point cloud must expose its tools entry")
        toolsEntry.tap()
        // The color and measurement controls live in the point-cloud tools
        // sheet. Every color mode is its own control now, and each carries a
        // localized name, so each one must fit its own full word.
        let captionFont = UIFont.preferredFont(
            forTextStyle: .caption2,
            compatibleWith: UITraitCollection(preferredContentSizeCategory: .extraExtraExtraLarge))
        let colorControls = [
            ("pointCloud.colorMode.高度", "Height"),
            ("pointCloud.colorMode.密度", "Brightness"),
            ("pointCloud.colorMode.果实", "Red emphasis"),
            ("pointCloud.colorMode.统一", "Uniform"),
        ]
        for (identifier, label) in colorControls {
            let control = app.buttons[identifier]
            XCTAssertTrue(control.waitForExistence(timeout: 5), label)
            let wordWidth = (label as NSString).size(withAttributes: [.font: captionFont]).width
            XCTAssertGreaterThanOrEqual(control.frame.width, wordWidth + 8,
                                        "XXXL must leave enough width for the full word: \(label)")
        }
        // The measurement tool is the last one in the sheet, so it only
        // becomes reachable after the sheet is scrolled.
        let measure = app.buttons["pointCloud.measure"]
        for _ in 0..<8 where !measure.exists { app.swipeUp() }
        XCTAssertTrue(measure.waitForExistence(timeout: 5), "The measurement tool must be reachable in the tools sheet")
        XCTAssertTrue(measure.isHittable, "The last point-cloud tool must remain reachable")
        let measureWordWidth = ("Measure" as NSString).size(withAttributes: [.font: captionFont]).width
        XCTAssertGreaterThanOrEqual(measure.frame.width, measureWordWidth + 8,
                                    "XXXL must leave enough width for the full word: Measure")
        let largePointCloud = XCTAttachment(screenshot: app.screenshot())
        largePointCloud.name = "Workspace-PointCloudXXXL"
        largePointCloud.lifetime = .keepAlways
        add(largePointCloud)
        let scrolledPointCloud = XCTAttachment(screenshot: app.screenshot())
        scrolledPointCloud.name = "Workspace-PointCloudXXXL-LastTool"
        scrolledPointCloud.lifetime = .keepAlways
        add(scrolledPointCloud)
        pointCloudClose.tap()

        app.terminate()
        app.launchArguments = ["-AppleLanguages", "(en)", "-AppleLocale", "en_US", "-UIPreferredContentSizeCategoryName", "UICTContentSizeCategoryAccessibilityXL"]
        app.launch()
        XCTAssertTrue(analysis.waitForExistence(timeout: 10))
        analysis.tap()
        let enlargedMetric = app.staticTexts["Today's Scans"].firstMatch
        XCTAssertTrue(enlargedMetric.waitForExistence(timeout: 5))
        XCTAssertGreaterThan(enlargedMetric.frame.height, 18, "The accessibility size override must actually enlarge the metric")
        XCTAssertEqual(app.buttons["dashboard.tab.scan"].label, "Scan")
        let enlargedScreenshot = XCTAttachment(screenshot: app.screenshot())
        enlargedScreenshot.name = "Workspace-EnglishAccessibility3"
        enlargedScreenshot.lifetime = .keepAlways
        add(enlargedScreenshot)
        app.buttons["dashboard.tab.history"].tap()
        XCTAssertTrue(recent.waitForExistence(timeout: 5))
        recent.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5)).tap()
        XCTAssertTrue(chooseArchive.waitForExistence(timeout: 5))
        chooseArchive.tap()
        XCTAssertTrue(selectedRecord.waitForExistence(timeout: 5))
        XCTAssertTrue(selectedRecord.isHittable)
        let pickerScreenshot = XCTAttachment(screenshot: app.screenshot())
        pickerScreenshot.name = "Workspace-ArchivePickerAccessibility3"
        pickerScreenshot.lifetime = .keepAlways
        add(pickerScreenshot)
    }
}
