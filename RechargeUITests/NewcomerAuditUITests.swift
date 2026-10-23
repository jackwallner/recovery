import XCTest

/// A first-time user who does not know the app's terminology and wants one
/// useful result immediately. Screenshots for a person to read; the assertions
/// only keep the walk honest (a tap landed, a screen came forward).
///
/// - `testNewcomerOnboardingTour` is the screenshot-mode onboarding, every page.
/// - `testNewcomerRealFirstRun` is the real app on an empty Health store: the
///   permission sheet, then whatever Today says to somebody with no workouts.
/// - `testNewcomerFirstResult` is the fixture countdown, read by someone who has
///   never seen a "recovery time" before.
@MainActor
final class NewcomerAuditUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(scene: String?, contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        if let scene {
            app.launchEnvironment["RECHARGE_SCREENSHOT_MODE"] = "1"
            app.launchEnvironment["RECHARGE_SCREENSHOT_SCENE"] = scene
        }
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        Thread.sleep(forTimeInterval: seconds)
    }

    /// Visible button labels, so the report can say what a newcomer is offered.
    private func visibleButtons(_ app: XCUIApplication) -> [String] {
        let screen = app.windows.firstMatch.frame
        return app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && screen.intersects($0.frame) }
            .map(\.label)
    }

    private func log(_ name: String, _ app: XCUIApplication) {
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(40).map(\.label)
        let note = "buttons=\(visibleButtons(app)) texts=\(texts)"
        let attachment = XCTAttachment(string: note)
        attachment.name = "\(name)-elements"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    // MARK: - Onboarding tour (screenshot mode)

    func testNewcomerOnboardingTour() {
        let app = launch(scene: "onboarding")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 30))
        let primaries = ["Continue", "Skip this one", "I understand"]
        for index in 1...10 {
            settle()
            attach(app, String(format: "onboarding-%02d", index))
            log(String(format: "onboarding-%02d", index), app)
            if app.buttons["Continue with Recharge+"].firstMatch.exists {
                app.swipeUp()
                settle(0.5)
                attach(app, String(format: "onboarding-%02d-offer-scrolled", index))
                break
            }
            guard let next = primaries.map({ app.buttons[$0].firstMatch }).first(where: { $0.exists && $0.isHittable }) else { break }
            next.tap()
            settle()
        }
        // The free way out of the offer.
        let start = app.buttons["Get Started"].firstMatch
        if start.waitForExistence(timeout: 5), start.isHittable {
            start.tap()
            settle(2)
            attach(app, "onboarding-after-get-started")
            log("onboarding-after-get-started", app)
        }
    }

    // MARK: - Real first run on an empty store

    private var healthSheet: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")
    }

    func testNewcomerRealFirstRun() {
        let app = launch(scene: nil)
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 60))
        settle()
        attach(app, "first-run-01-welcome")
        app.buttons["Continue"].firstMatch.tap()
        settle()
        attach(app, "first-run-02-health-primer")
        app.buttons["Continue"].firstMatch.tap()

        let sheet = healthSheet
        let turnOnAll = sheet.cells["UIA.Health.AuthSheet.AllCategoryButton"]
        if turnOnAll.waitForExistence(timeout: 60) {
            attach(app, "first-run-03-health-sheet")
            turnOnAll.tap()
            settle()
            attach(app, "first-run-04-health-sheet-all-on")
            let allow = sheet.buttons["UIA.Health.Allow.Button"]
            if allow.waitForExistence(timeout: 15) { allow.tap() }
            settle(1.5)
            let fullHistory = sheet.staticTexts["Full History"]
            if fullHistory.waitForExistence(timeout: 8) {
                attach(app, "first-run-05-health-history-page")
                fullHistory.tap()
                let allow2 = sheet.buttons["Allow"]
                if allow2.waitForExistence(timeout: 8) { allow2.tap() }
            }
        } else {
            attach(app, "first-run-03-no-sheet")
        }
        settle(3)

        let primaries = ["Continue", "Skip this one", "I understand"]
        for index in 6...16 {
            attach(app, String(format: "first-run-%02d", index))
            log(String(format: "first-run-%02d", index), app)
            if app.buttons["Get Started"].firstMatch.exists { break }
            guard let next = primaries.map({ app.buttons[$0].firstMatch }).first(where: { $0.exists && $0.isHittable }) else { break }
            next.tap()
            settle(1)
        }
        let start = app.buttons["Get Started"].firstMatch
        if start.waitForExistence(timeout: 5) {
            start.tap()
        }
        settle(4)
        // Notification alert (system) may sit over Today.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        attach(app, "first-run-20-after-onboarding")
        let allowNotifs = springboard.buttons["Allow"]
        if allowNotifs.waitForExistence(timeout: 3) {
            attach(app, "first-run-21-notification-alert")
            allowNotifs.tap()
            settle()
        }
        let today = app.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 30), "Today never appeared after onboarding")
        settle(2)
        attach(app, "first-run-22-today-empty")
        log("first-run-22-today-empty", app)

        let hero = app.descendants(matching: .any).matching(identifier: "today.hero").firstMatch
        if hero.exists {
            hero.tap()
            settle()
            attach(app, "first-run-23-tapped-empty-hero")
        }
        app.swipeUp()
        attach(app, "first-run-24-today-scrolled")

        let gear = app.buttons["Settings"]
        if gear.exists, gear.isHittable {
            gear.tap()
            settle(1.5)
            attach(app, "first-run-25-settings")
            app.swipeUp()
            attach(app, "first-run-26-settings-2")
            app.swipeUp()
            attach(app, "first-run-27-settings-3")
            if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
            settle()
        }

        if app.buttons["History"].exists {
            app.buttons["History"].tap()
            settle(1.5)
            attach(app, "first-run-28-history-empty")
            log("first-run-28-history-empty", app)
        }
        let third = app.buttons["Upgrade"].exists ? app.buttons["Upgrade"] : app.buttons["Recharge+"]
        if third.exists {
            third.tap()
            settle(2)
            attach(app, "first-run-29-upgrade-tab")
            app.swipeUp()
            attach(app, "first-run-30-upgrade-tab-2")
        }
    }

    // MARK: - The first result (fixture)

    func testNewcomerFirstResult() {
        let app = launch(scene: "recovering")
        let hero = app.buttons["today.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 30))
        settle(1.5)
        attach(app, "result-01-today")
        log("result-01-today", app)
        app.swipeUp()
        settle(0.5)
        attach(app, "result-02-today-scrolled")
        app.swipeDown()
        settle(0.5)

        hero.tap()
        settle(1.5)
        attach(app, "result-03-detail")
        log("result-03-detail", app)
        for step in 4...7 {
            app.swipeUp()
            settle(0.5)
            attach(app, String(format: "result-%02d-detail-scrolled", step))
        }
        if app.buttons["Done"].firstMatch.exists { app.buttons["Done"].firstMatch.tap() }
        settle()

        // The card that sells Recharge+, tapped as a curious newcomer would.
        app.buttons.matching(NSPredicate(format: "label BEGINSWITH %@", "Your own recharge time")).firstMatch.tap()
        settle(2)
        attach(app, "result-08-card-tap")
        log("result-08-card-tap", app)
        app.swipeUp()
        settle(0.5)
        attach(app, "result-09-card-tap-scrolled")

        if app.buttons["Today"].exists { app.buttons["Today"].tap(); settle() }
        if app.buttons["History"].exists {
            app.buttons["History"].tap()
            settle(1.5)
            attach(app, "result-10-history")
            let row = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "walk")).firstMatch
            if row.exists { row.tap(); settle(1); attach(app, "result-11-history-detail") }
        }
    }

    func testNewcomerFirstResultLargeText() {
        let app = launch(scene: "recovering", contentSize: "UICTContentSizeCategoryAccessibilityL")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 30))
        settle(1.5)
        attach(app, "largetext-01-today")
        app.swipeUp()
        attach(app, "largetext-02-today-scrolled")
    }

    func testNewcomerReadyState() {
        let app = launch(scene: "ready")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 30))
        settle(2)
        attach(app, "ready-01-today")
        log("ready-01-today", app)
    }
}
