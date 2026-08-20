import XCTest

/// Screenshots of every screen the redesign touched, under screenshot mode.
///
/// Fast and deterministic, which is the trade against `SeededWalkthroughTests`:
/// this never runs the HealthKit import, so it proves nothing about
/// classification or coverage — but it renders every state in seconds, which is
/// what makes it usable while a screen is being worked on.
@MainActor
final class RedesignCaptureTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(scene: String, pro: Bool = false) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RECHARGE_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["RECHARGE_SCREENSHOT_SCENE"] = scene
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    func testCaptureToday() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "today-recovering")

        // The explanation is a sheet now rather than four cards down the page.
        app.buttons["today.hero"].tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "today-detail")
    }

    func testCaptureReady() {
        let app = launch(scene: "ready")
        XCTAssertTrue(app.buttons["Today"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "today-ready")
    }

    func testCaptureHistory() {
        let app = launch(scene: "history")
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 20))
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "history")
        app.swipeUp()
        attach(app, named: "history-scrolled")
    }

    func testCaptureUpgradeTab() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.buttons["Upgrade"].waitForExistence(timeout: 20))
        app.buttons["Upgrade"].tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "upgrade-tab")
    }

    func testCaptureRechargePlusTab() {
        let app = launch(scene: "premiumActive")
        XCTAssertTrue(app.buttons["Recharge+"].waitForExistence(timeout: 20))
        app.buttons["Recharge+"].tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "plus-tab")
        app.swipeUp()
        attach(app, named: "plus-tab-scrolled")
    }

    func testCaptureSettings() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.buttons["Settings"].waitForExistence(timeout: 20))
        app.buttons["Settings"].tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "settings")
        app.swipeUp()
        app.swipeUp()
        attach(app, named: "settings-scrolled")
    }

    func testCaptureOnboarding() {
        let app = launch(scene: "onboarding")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))
        attach(app, named: "onboarding-1-welcome")

        app.buttons["Continue"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 1)
        attach(app, named: "onboarding-2-health")

        app.buttons["Connect Apple Health"].firstMatch.tap()
        Thread.sleep(forTimeInterval: 2)
        attach(app, named: "onboarding-3-readout")

        // Walk to the end of the flow, capturing the offer page — the one screen
        // in the flow that takes money and the one the pitch was rebuilt around.
        for _ in 0..<8 {
            let next = app.buttons.matching(
                NSPredicate(format: "label IN {'Continue', 'Skip this one', 'I understand'}")
            ).firstMatch
            guard next.exists, next.isHittable else { break }
            next.tap()
            Thread.sleep(forTimeInterval: 0.8)
        }
        attach(app, named: "onboarding-4-offer")
    }
}
