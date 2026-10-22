import XCTest

/// Walks the app the way someone who has used it for weeks does: open the
/// countdown, drill into a session, compare tiers, change a setting, come back.
///
/// Attaches a screenshot at each step plus a text report of small hit targets,
/// so a person can read the run. Asserts only that each landmark exists.
@MainActor
final class ExperiencedAuditUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
    }

    private func launch(scene: String, contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RECHARGE_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["RECHARGE_SCREENSHOT_SCENE"] = scene
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func note(_ name: String, _ text: String) {
        let attachment = XCTAttachment(string: text)
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// Every hittable button or cell narrower or shorter than 44pt.
    private func smallTargets(_ app: XCUIApplication, _ name: String) {
        var lines: [String] = []
        for type in [XCUIElement.ElementType.button, .cell, .switch, .link] {
            for element in app.descendants(matching: type).allElementsBoundByIndex.prefix(80) where element.exists && element.isHittable {
                let f = element.frame
                if f.width < 44 || f.height < 44 {
                    lines.append("\(type.rawValue) '\(element.label)' \(Int(f.width))x\(Int(f.height)) at (\(Int(f.minX)),\(Int(f.minY)))")
                }
            }
        }
        note("targets-\(name)", lines.isEmpty ? "none under 44pt" : lines.joined(separator: "\n"))
    }

    private func dump(_ app: XCUIApplication, _ name: String) {
        note("tree-\(name)", app.debugDescription)
    }

    private func scrollDown(_ app: XCUIApplication, _ name: String, steps: Int = 3) {
        for index in 1...steps {
            app.swipeUp()
            attach(app, "\(name)-scroll\(index)")
        }
    }

    // MARK: Subscriber (the persona's likely tier)

    func testSubscriberTodayAndDetail() {
        let app = launch(scene: "premiumActive")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 20))
        sleep(1)
        attach(app, "a01-today")
        smallTargets(app, "today")
        dump(app, "today")
        scrollDown(app, "a02-today")
        for _ in 0..<3 { app.swipeDown() }
        app.buttons["today.hero"].tap()
        sleep(1)
        attach(app, "a03-detail")
        smallTargets(app, "detail")
        dump(app, "detail")
        scrollDown(app, "a04-detail", steps: 4)
    }

    func testSubscriberHistoryDrill() {
        let app = launch(scene: "premiumActive")
        XCTAssertTrue(app.buttons["History"].waitForExistence(timeout: 20))
        app.buttons["History"].tap()
        sleep(2)
        attach(app, "b01-history")
        smallTargets(app, "history")
        dump(app, "history")
        let rows = app.buttons.allElementsBoundByIndex.filter {
            $0.exists && $0.frame.height > 50 && $0.frame.minY > 150 && $0.frame.maxY < 760 && $0.identifier != "today.hero"
        }
        note("history-rows", rows.map { "'\($0.label)' \($0.frame)" }.joined(separator: "\n"))
        for (index, row) in rows.prefix(3).enumerated() where row.isHittable {
            row.tap()
            sleep(1)
            attach(app, "b02-row\(index)-detail")
            app.swipeUp()
            attach(app, "b02-row\(index)-detail-scrolled")
            if app.buttons["Done"].exists { app.buttons["Done"].tap() } else { app.swipeDown() }
            sleep(1)
        }
        scrollDown(app, "b03-history", steps: 4)
    }

    func testSubscriberPlusTabAndSettings() {
        let app = launch(scene: "premiumActive")
        XCTAssertTrue(app.buttons["Recharge+"].waitForExistence(timeout: 20))
        app.buttons["Recharge+"].tap()
        sleep(2)
        attach(app, "c01-plus")
        smallTargets(app, "plus")
        dump(app, "plus")
        scrollDown(app, "c02-plus", steps: 4)
        app.buttons["Today"].tap()
        sleep(1)
        let settings = app.buttons["Settings"]
        XCTAssertTrue(settings.waitForExistence(timeout: 5))
        settings.tap()
        sleep(2)
        attach(app, "c03-settings")
        smallTargets(app, "settings")
        dump(app, "settings")
        scrollDown(app, "c04-settings", steps: 8)
    }

    // MARK: Free tier and edge states

    func testFreeRecoveringAndReady() {
        let recovering = launch(scene: "recovering")
        XCTAssertTrue(recovering.buttons["today.hero"].waitForExistence(timeout: 20))
        sleep(1)
        attach(recovering, "d01-recovering")
        scrollDown(recovering, "d02-recovering", steps: 3)
        recovering.terminate()
        let ready = launch(scene: "ready")
        XCTAssertTrue(ready.buttons["today.hero"].waitForExistence(timeout: 20))
        sleep(1)
        attach(ready, "d03-ready")
        scrollDown(ready, "d04-ready", steps: 3)
    }

    func testStaleScene() {
        let app = launch(scene: "stale")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 20))
        sleep(1)
        attach(app, "e01-stale")
        scrollDown(app, "e02-stale", steps: 2)
    }

    func testLargeTextTodayAndHistory() {
        let app = launch(scene: "premiumActive", contentSize: "UICTContentSizeCategoryAccessibilityXL")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 20))
        sleep(1)
        attach(app, "f01-today-axl")
        scrollDown(app, "f02-today-axl", steps: 4)
        app.buttons["History"].tap()
        sleep(2)
        attach(app, "f03-history-axl")
        scrollDown(app, "f04-history-axl", steps: 2)
    }

    func testHistoryScene() {
        let app = launch(scene: "history")
        sleep(4)
        attach(app, "g01-history-scene")
        scrollDown(app, "g02-history-scene", steps: 3)
    }

    func testPaywallScene() {
        let app = launch(scene: "paywall")
        sleep(4)
        attach(app, "h01-paywall")
        smallTargets(app, "paywall")
        app.swipeUp()
        attach(app, "h02-paywall-scrolled")
    }
}
