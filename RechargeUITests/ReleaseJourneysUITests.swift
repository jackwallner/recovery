import XCTest

/// The release gate's journeys (`qa-gate run`): onboarding to the offer page and
/// the free path to Today, Today, History and Recharge+ on seeded data, the
/// Upgrade paywall for a free user, Settings, and a return visit with an
/// interruption. Each step ends in `QA.checkpoint`, which runs the fleet oracles
/// on the screen. Those assert reachability; `testCoreLoop…` asserts the
/// countdown itself.
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

    /// The core loop: a workout lands, Today counts down from what it cost,
    /// the explanation and History agree on that cost, the countdown keeps
    /// running (not restarting) across a relaunch, and it reads Ready once it
    /// has run out. The `recovering` fixture's lead row is a run 3h ago costing
    /// 21.7h on the free tier, so 22h on every surface and about 18h 42m left.
    func testCoreLoopCountdownFromAWorkoutToReady() {
        continueAfterFailure = false
        let app = launch(scene: "recovering")
        let hero = app.buttons["today.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 20), "Today never rendered")
        let before = countdown(hero)
        XCTAssertEqual(before.cost, 22, "Today names the wrong cost: \(hero.label)")
        XCTAssertEqual(before.session, "run", "Today names the wrong session: \(hero.label)")
        XCTAssertGreaterThan(before.leftMinutes, 0, "a fresh countdown already reads Ready: \(hero.label)")
        XCTAssertEqual(Double(before.leftMinutes + before.agoMinutes) / 60, Double(before.cost), accuracy: 0.5,
                       "time left plus time since the run is not the countdown it set: \(hero.label)")
        QA.checkpoint(app, "core-today-countdown")

        hero.tap()
        assertDetail(app, session: "Run", cost: "22h")
        QA.checkpoint(app, "core-detail")
        closeDetail(app)

        showHistory(app)
        let row = historyRow(app, session: "Run", countdown: "Countdown 22h")
        XCTAssertTrue(row.waitForExistence(timeout: 10), "History does not list the run with its 22h countdown")
        QA.checkpoint(app, "core-history")
        row.tap()
        assertDetail(app, session: "Run", cost: "22h")
        QA.checkpoint(app, "core-history-detail")
        closeDetail(app)

        QA.relaunch(app)
        XCTAssertTrue(hero.waitForExistence(timeout: 20), "Today never rendered after relaunch")
        let after = countdown(hero)
        XCTAssertEqual(after.cost, before.cost, "the cost changed across a relaunch: \(hero.label)")
        XCTAssertEqual(after.session, before.session, "the session changed across a relaunch: \(hero.label)")
        XCTAssertLessThanOrEqual(after.leftMinutes, before.leftMinutes, "the countdown restarted on relaunch: \(hero.label)")
        XCTAssertGreaterThanOrEqual(after.leftMinutes, before.leftMinutes - 10, "the countdown jumped on relaunch: \(hero.label)")
        QA.checkpoint(app, "core-today-after-relaunch")
        showHistory(app)
        XCTAssertTrue(historyRow(app, session: "Run", countdown: "Countdown 22h").waitForExistence(timeout: 10),
                      "the run left History after relaunch")
        QA.checkpoint(app, "core-history-after-relaunch")

        // The same history a day later: the lead run's countdown has run out.
        app.terminate()
        QA.launch(app, environment: ["RECHARGE_SCREENSHOT_MODE": "1", "RECHARGE_SCREENSHOT_SCENE": "ready"])
        XCTAssertTrue(hero.waitForExistence(timeout: 20), "Today never rendered once the countdown expired")
        XCTAssertTrue(hero.label.hasPrefix("Recovery estimate complete."), "an expired countdown is not Ready: \(hero.label)")
        XCTAssertTrue(hero.label.contains("from your run"), "Ready does not name the run that set it: \(hero.label)")
        QA.checkpoint(app, "core-today-ready")
        hero.tap()
        XCTAssertTrue(app.navigationBars["Run"].waitForExistence(timeout: 10), "the Ready explanation never opened")
        let ranOut = NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", "Your run set a", "ran out")
        XCTAssertTrue(app.descendants(matching: .any).matching(ranOut).firstMatch.exists,
                      "the explanation does not say the run's countdown ran out")
        QA.checkpoint(app, "core-ready-detail")
        closeDetail(app)
    }

    private struct Countdown {
        let leftMinutes: Int
        let cost: Int
        let session: String
        let agoMinutes: Int
    }

    /// Reads the hero's summary, "18h 42m left. <headline>. 22h from your run 3h ago."
    private func countdown(_ hero: XCUIElement) -> Countdown {
        let label = hero.label
        let pattern = #"^(.+?) left\..* (\d+)h from your (\w+) (.+?) ago"#
        guard let match = label.firstMatch(of: try! Regex(pattern)),
              let left = match.output[1].substring, let cost = match.output[2].substring,
              let session = match.output[3].substring, let ago = match.output[4].substring
        else {
            XCTFail("Today is not counting down from a session: \(label)")
            return Countdown(leftMinutes: 0, cost: 0, session: "", agoMinutes: 0)
        }
        return Countdown(leftMinutes: minutes(String(left)), cost: Int(cost) ?? 0,
                         session: String(session), agoMinutes: minutes(String(ago)))
    }

    /// `CountdownFormat.remaining`: "2d 3h", "18h 42m", "40m".
    private func minutes(_ text: String) -> Int {
        let units: [Character: Int] = ["d": 1440, "h": 60, "m": 1]
        return text.split(separator: " ").reduce(0) { total, part in
            guard let unit = part.last, let scale = units[unit], let value = Int(part.dropLast()) else { return total }
            return total + value * scale
        }
    }

    private func assertDetail(_ app: XCUIApplication, session: String, cost: String,
                              file: StaticString = #filePath, line: UInt = #line) {
        XCTAssertTrue(app.navigationBars[session].waitForExistence(timeout: 10),
                      "the \(session) explanation never opened", file: file, line: line)
        XCTAssertTrue(app.staticTexts[cost].firstMatch.exists,
                      "the \(session) explanation does not show its \(cost) cost", file: file, line: line)
    }

    private func closeDetail(_ app: XCUIApplication) {
        let done = app.buttons["Done"].firstMatch
        XCTAssertTrue(done.waitForExistence(timeout: 5), "the explanation has no Done")
        done.tap()
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 10))
    }

    /// History is a tab when folded and the trailing pane on an unfolded
    /// iPhone Duo, where its tab button is hidden.
    private func showHistory(_ app: XCUIApplication) {
        let tab = app.buttons["History"].firstMatch
        if tab.exists && tab.isHittable { tab.tap() }
        XCTAssertTrue(app.navigationBars["History"].waitForExistence(timeout: 10), "History never came forward")
    }

    /// A History row is one button whose label carries the session title and
    /// the row's "Countdown 22h." value.
    private func historyRow(_ app: XCUIApplication, session: String, countdown: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS %@ AND label CONTAINS %@", session, countdown)).firstMatch
    }

    private func launch(scene: String) -> XCUIApplication {
        let app = XCUIApplication(bundleIdentifier: Self.bundle)
        QA.launch(app, environment: ["RECHARGE_SCREENSHOT_MODE": "1", "RECHARGE_SCREENSHOT_SCENE": scene])
        return app
    }
}
