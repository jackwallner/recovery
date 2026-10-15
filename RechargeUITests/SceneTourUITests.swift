import XCTest

/// A screenshot tour of every phone scene, for a person to look at.
///
/// Not an assertion suite, and four minutes long, so it only runs when asked:
/// `TEST_RUNNER_RECHARGE_SCENE_TOUR=1` on the xcodebuild line, then export the
/// attachments from the result bundle.
@MainActor
final class SceneTourUITests: XCTestCase {

    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(
            ProcessInfo.processInfo.environment["RECHARGE_SCENE_TOUR"] == "1",
            "set TEST_RUNNER_RECHARGE_SCENE_TOUR=1 to take the tour"
        )
    }

    private func launch(scene: String) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RECHARGE_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["RECHARGE_SCREENSHOT_SCENE"] = scene
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func tourToday(_ scene: String) {
        let app = launch(scene: scene)
        _ = app.buttons["today.hero"].waitForExistence(timeout: 15)
        sleep(1)
        attach(app, "\(scene)-01-today")
        app.swipeUp(); app.swipeUp()
        attach(app, "\(scene)-02-today-bottom")
        app.swipeDown(); app.swipeDown()
        if app.buttons["today.hero"].exists {
            app.buttons["today.hero"].tap()
            sleep(1)
            attach(app, "\(scene)-03-detail")
            app.swipeUp(); app.swipeUp()
            attach(app, "\(scene)-04-detail-bottom")
            app.swipeUp(); app.swipeUp()
            attach(app, "\(scene)-05-detail-bottom2")
            if app.buttons["Done"].exists { app.buttons["Done"].tap() }
            sleep(1)
        }
        if app.buttons["History"].exists {
            app.buttons["History"].tap(); sleep(1)
            attach(app, "\(scene)-06-history")
            app.swipeUp(); app.swipeUp()
            attach(app, "\(scene)-07-history-bottom")
        }
        let third = app.buttons["Upgrade"].exists ? app.buttons["Upgrade"] : app.buttons["Recharge+"]
        if third.exists {
            third.tap(); sleep(2)
            attach(app, "\(scene)-08-third-tab")
            app.swipeUp(); app.swipeUp()
            attach(app, "\(scene)-09-third-tab-bottom")
        }
    }

    func testTourRecovering() { tourToday("recovering") }
    func testTourReady() { tourToday("ready") }
    func testTourPremium() { tourToday("premiumActive") }
    func testTourStale() { tourToday("stale") }
    func testTourPremiumSettings() {
        let app = launch(scene: "premiumActive")
        _ = app.buttons["Settings"].waitForExistence(timeout: 15)
        app.buttons["Settings"].tap(); sleep(2)
        for index in 1...6 {
            attach(app, "premiumSettings-\(index)")
            app.swipeUp()
        }
        let pin = app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@ AND label CONTAINS[c] %@", "Hard", "Recharge decides")).firstMatch
        for _ in 0..<4 where !pin.isHittable { app.swipeDown() }
        if pin.exists && pin.isHittable {
            pin.tap(); sleep(1)
            attach(app, "premiumSettings-pin-hard")
            app.swipeUp()
            attach(app, "premiumSettings-pin-hard-scrolled")
        }
    }

    func testTourHistory() {
        let app = launch(scene: "history"); sleep(3)
        attach(app, "history-01")
        app.swipeUp(); app.swipeUp()
        attach(app, "history-02")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "walk"))
        if rows.firstMatch.exists { rows.firstMatch.tap(); sleep(1); attach(app, "history-03-walk-detail") }
    }
    func testTourSettings() {
        let app = launch(scene: "settings"); sleep(3)
        for index in 1...7 {
            attach(app, "settings-\(index)")
            app.swipeUp()
        }
    }
    func testTourPaywall() {
        let app = launch(scene: "paywall"); sleep(4)
        attach(app, "paywall-01")
        app.swipeUp()
        attach(app, "paywall-02")
    }
    func testTourOnboarding() {
        let app = launch(scene: "onboarding"); sleep(3)
        for index in 1...12 {
            attach(app, String(format: "onboarding-%02d", index))
            let buttons = ["Continue", "I understand", "Next"]
            var tapped = false
            for title in buttons where app.buttons[title].firstMatch.exists && app.buttons[title].firstMatch.isHittable {
                app.buttons[title].firstMatch.tap(); tapped = true; break
            }
            if !tapped {
                let option = app.buttons.element(boundBy: 2)
                if option.exists { option.tap() }
            }
            sleep(1)
        }
    }
}
