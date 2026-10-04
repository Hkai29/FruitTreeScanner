import XCTest

final class VarietyConfirmationTests: XCTestCase {
    private let app = XCUIApplication()

    override func setUpWithError() throws {
        try super.setUpWithError()
        continueAfterFailure = false
        let environment = ProcessInfo.processInfo.environment
        let expected = try XCTUnwrap(environment["FRUIT_NATIVE_UI_SIMULATOR_ID"],
                                    "Run tools/validate_native_ui.py to create an isolated fixture")
        guard !expected.isEmpty, environment["SIMULATOR_UDID"] == expected,
              environment["SIMULATOR_DEVICE_NAME"]?.hasPrefix("FruitTreeScanner-NativeUI-") == true else {
            throw NSError(domain: "VarietyConfirmationTests", code: 1,
                          userInfo: [NSLocalizedDescriptionKey: "Refusing to edit an existing simulator"])
        }
        app.launchArguments = ["-AppleLanguages", "(zh-Hans)", "-AppleLocale", "zh_CN"]
        app.launch()
    }

    private func reveal(_ element: XCUIElement) {
        for _ in 0..<10 {
            if element.exists && element.isHittable { return }
            app.swipeUp()
        }
        XCTAssertTrue(element.exists && element.isHittable, "Control must be reachable: \(element)")
    }

    private func openDatabase() {
        let settings = app.buttons["gearshape.fill"]
        XCTAssertTrue(settings.waitForExistence(timeout: 10))
        // The dashboard supplies a 44 pt control. Wait for its final layout and
        // actual hit testing before deriving a touch from the accessibility frame.
        let ready = XCTNSPredicateExpectation(predicate: NSPredicate { _, _ in
            settings.isHittable && settings.frame.width >= 44 && settings.frame.height >= 44
        }, object: settings)
        XCTAssertEqual(XCTWaiter.wait(for: [ready], timeout: 10), .completed)
        let frame = settings.frame
        XCTAssertTrue(frame.width > 0 && frame.height > 0 && app.frame.contains(frame))
        let origin = app.coordinate(withNormalizedOffset: .zero)
        let coordinate = origin.withOffset(CGVector(dx: frame.midX, dy: frame.midY))
        XCTAssertEqual(coordinate.screenPoint.x, frame.midX, accuracy: 0.5)
        XCTAssertEqual(coordinate.screenPoint.y, frame.midY, accuracy: 0.5)
        let coordinates = XCTAttachment(string: "app=\(app.frame) target=\(frame) origin=\(origin.screenPoint) computed=\(coordinate.screenPoint) screen=\(XCUIScreen.main.screenshot().image.size)")
        coordinates.name = "SettingsCoordinate"
        coordinates.lifetime = .keepAlways
        add(coordinates)
        coordinate.tap()
        let database = app.buttons["品种参数库"]
        XCTAssertTrue(database.waitForExistence(timeout: 5))
        reveal(database)
        database.tap()
        XCTAssertTrue(app.buttons["编辑苹果参数"].waitForExistence(timeout: 5))
    }

    private func edit(_ category: String) {
        let button = app.buttons["编辑\(category)参数"]
        reveal(button)
        button.tap()
        XCTAssertTrue(app.sliders["最大直径"].waitForExistence(timeout: 5))
    }

    private func weight() -> XCUIElement {
        let slider = app.sliders["平均单果重量"]
        reveal(slider)
        return slider
    }

    private func setWeightToBoundary(_ grams: Int) {
        precondition(grams == 1 || grams == 2000)
        let slider = weight()
        slider.adjust(toNormalizedSliderPosition: CGFloat(grams - 1) / 1999)
        // Normalized adjustment is best effort. Drag the real thumb past its
        // track endpoint so UIKit clamps this boundary fixture exactly.
        let thumb = slider.coordinate(withNormalizedOffset: CGVector(dx: slider.normalizedSliderPosition, dy: 0.5))
        let endpoint = slider.coordinate(withNormalizedOffset: CGVector(dx: grams == 1 ? -0.05 : 1.05, dy: 0.5))
        thumb.press(forDuration: 0.1, thenDragTo: endpoint)
        XCTAssertEqual(slider.value as? String, "\(grams) g")
    }

    private func save(_ category: String) {
        app.buttons["保存"].tap()
        XCTAssertTrue(app.buttons["编辑\(category)参数"].waitForExistence(timeout: 5))
    }

    private func attach(_ phase: String) {
        let image = XCTAttachment(screenshot: app.screenshot())
        image.name = "VarietyConfirmation-\(phase)"
        image.lifetime = .keepAlways
        add(image)
    }

    func testResetConfirmationPreservesCancelAndOtherCategoryThenPersistsReset() {
        // The runner provides a new simulator, so these edits belong only to this fixture.
        openDatabase()
        edit("苹果")
        setWeightToBoundary(1)
        save("苹果")
        edit("梨")
        setWeightToBoundary(2000)
        save("梨")
        edit("梨")
        XCTAssertEqual(weight().value as? String, "2000 g")
        app.buttons["重置为默认值"].tap()
        let alert = app.alerts["重置参数"]
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        attach("cancel-alert")
        alert.buttons["取消"].tap()
        XCTAssertFalse(alert.exists)
        XCTAssertEqual(weight().value as? String, "2000 g", "Cancelling must retain the saved pear parameters")
        app.buttons["重置为默认值"].tap()
        XCTAssertTrue(alert.waitForExistence(timeout: 5))
        alert.buttons["重置"].tap()
        XCTAssertTrue(app.buttons["编辑梨参数"].waitForExistence(timeout: 5))
        edit("梨")
        XCTAssertEqual(weight().value as? String, "180 g", "Actual destructive action must reset pear to its established default")
        attach("reset-reopened")
        app.buttons["取消"].tap()
        XCTAssertTrue(app.buttons["编辑苹果参数"].waitForExistence(timeout: 5))
        edit("苹果")
        XCTAssertEqual(weight().value as? String, "1 g", "Resetting pear must preserve the other category")
        app.terminate()
        app.launch()
        openDatabase()
        edit("梨")
        XCTAssertEqual(weight().value as? String, "180 g", "Reset must survive a fresh app launch")
        attach("relaunch")
    }
}
