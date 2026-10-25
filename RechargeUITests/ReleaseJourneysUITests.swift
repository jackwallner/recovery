import XCTest

/// The release gate's journeys (`qa-gate run`): onboarding to the offer page and
/// the free path to Today, Today, History and Recharge+ on seeded data, the
/// Upgrade paywall for a free user, Settings, and a return visit with an
/// interruption. Each step ends in `QA.checkpoint`, which runs the fleet oracles
/// on the screen. Assert reachability only.
///
/// Screenshot scenes (`RECHARGE_SCREENSHOT_SCENE`) seed each surface and supply
/// the paywall's plans, since simulator runs never configure RevenueCat.
@MainActor
final class ReleaseJourneysUITests: XCTestCase {

    private static let bundle = "com.jackwallner.recovery"
    private static let primaries = ["Continue", "Skip this one", "I understand"]

    func test01OnboardingToOfferAndToday() {
        continueAfterFailure = false
        let app = launch(scene: "onboarding")
        XCTAssertTrue(app.buttons["Continue"].firstMatch.waitForExistence(timeout: 20), "welcome never rendered")
        QA.checkpoint(app, "welcome")

        let offer = app.buttons["Continue with Recharge+"].firstMatch
        for page in 1...12 {
            if offer.exists { break }
            guard let next = Self.primaries.map({ app.buttons[$0].firstMatch }).first(where: { $0.exists }) else { break }
            wait(for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: next)], timeout: 10)
            next.tap()
            Thread.sleep(forTimeInterval: 0.6)
            if !offer.exists { QA.checkpoint(app, "onboarding-\(page)") }
        }
        XCTAssertTrue(offer.waitForExistence(timeout: 10), "offer page never rendered")
        QA.checkpoint(app, "onboarding-offer", paywall: true)

        let start = app.buttons["Get Started"].firstMatch
        if !start.isHittable { app.swipeUp() }
        start.tap()
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 15), "free path never reached Today")
        QA.checkpoint(app, "first-today", paywall: false)
    }

    func test02TodayHistoryAndRechargePlus() {
        continueAfterFailure = false
        let app = launch(scene: "premiumActive")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 20), "Today never rendered")
        QA.checkpoint(app, "today")

        app.buttons["History"].firstMatch.tap()
        QA.checkpoint(app, "history")

        app.buttons["Recharge+"].firstMatch.tap()
        QA.checkpoint(app, "recharge-plus")
    }

    func test03UpgradePaywallForAFreeUser() {
        continueAfterFailure = false
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 20), "Today never rendered")
        QA.checkpoint(app, "today-free")

        let upgrade = app.buttons["Upgrade"].firstMatch
        XCTAssertTrue(upgrade.waitForExistence(timeout: 10))
        upgrade.tap()
        QA.checkpoint(app, "upgrade", paywall: true)

        app.buttons["Today"].firstMatch.tap()
        QA.checkpoint(app, "today-after-upgrade", paywall: false)
    }

    func test04Settings() {
        continueAfterFailure = false
        let app = launch(scene: "settings")
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
        sleep(2)
        QA.checkpoint(app, "settings")
    }

    func test05ReturnVisitWithInterruption() {
        continueAfterFailure = false
        let app = launch(scene: "premiumActive")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 20))
        app.buttons["History"].firstMatch.tap()
        QA.checkpoint(app, "history-before-interruption")

        QA.interrupt(app)
        QA.checkpoint(app, "history-after-interruption")

        QA.relaunch(app)
        XCTAssertTrue(app.buttons["Today"].firstMatch.waitForExistence(timeout: 20))
        QA.checkpoint(app, "today-after-relaunch")
    }

    private func launch(scene: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, environment: ["RECHARGE_SCREENSHOT_MODE": "1", "RECHARGE_SCREENSHOT_SCENE": scene])
        return app
    }
}
