import XCTest

/// Drives the app against a **real** simulator Health store seeded with 120 days
/// of training, and attaches a screenshot of every screen.
///
/// This is the only test in the suite that exercises the import path end to end:
/// classification, heart-rate coverage, the observed maximum, the quiet
/// threshold, day grouping, stacking, and the thirty-day analysis all run on
/// data that arrived through HealthKit rather than on a fixture array. The
/// screenshot scenes are reproducible and prove nothing about any of that — a
/// fixture that agrees with itself proves nothing — so this is what to run after
/// changing the model or the shape of a screen.
///
/// It is not an assertion suite. It asserts that each screen actually came
/// forward, by hittability rather than existence, and otherwise exists so a
/// person can look at the attachments.
@MainActor
final class SeededWalkthroughTests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launchSeeded() -> XCUIApplication {
        // **HealthKit never re-asks once a sheet has been answered**, so a run
        // that was denied write access stays denied on that simulator for every
        // later run, including the run that fixed the reason it was denied.
        //
        // Uninstalling is **not** enough: the authorization outlives the app on
        // current runtimes, which is how this test failed with "the Health
        // permission sheet never appeared" on a simulator that had answered the
        // sheet an hour earlier under a previous install. Erasing the device is
        // what actually resets it:
        //
        //     xcrun simctl shutdown <udid> && xcrun simctl erase <udid>
        //     xcodebuild test -scheme RechargeUITests -only-testing:…
        //
        // A sheet that never appears is not automatically a failure, though.
        // See `allowHealthAccess`.
        let app = XCUIApplication()
        app.launchEnvironment["RECHARGE_SEED_HEALTH"] = "1"
        // The seeder's own default, which is `HealthKitService.importDays`, so
        // the seeded store covers exactly the window the app imports.
        //
        // This used to be capped at three weeks, on the belief that
        // `HKWorkoutBuilder` writes were slow enough that sixty days "did not
        // finish inside six minutes". They are not: the run that finally got
        // past the permission sheet wrote three days of workouts in **0.16
        // seconds**, and the six minutes were the permission helper timing out
        // and then the tab-bar wait timing out behind it. There was never a
        // reason to seed less than the app reads.
        if let override = ProcessInfo.processInfo.environment["RECHARGE_SEED_DAYS"] {
            app.launchEnvironment["RECHARGE_SEED_DAYS"] = override
        }
        app.launch()
        allowHealthAccess()
        return app
    }

    /// The Health authorization sheet belongs to **another process**, and that
    /// is the whole reason this test never ran.
    ///
    /// It is presented into the app's own window through
    /// `_UIRemoteViewControllerSceneHostingImpl`, so on screen it looks like
    /// part of Recharge, and the previous version of this helper reasonably
    /// assumed it therefore turns up in the app under test's accessibility
    /// tree. It does not. `XCUIApplication()` reports the onboarding screen
    /// underneath and an empty `Other` where the sheet is hosted; every element
    /// of the sheet lives in `com.apple.HealthPrivacyService`.
    ///
    /// So `app.buttons["Turn On All"]` never existed, the 60-second
    /// `waitForExistence` timed out, and the helper's `guard … else { return }`
    /// returned **silently**, leaving the sheet up, `requestAuthorization`
    /// never resuming, and the app parked forever inside
    /// `HealthSeeder.seedIfRequested()`. The 364-second failure was 60 seconds
    /// of that wait plus the 300-second wait for the tab bar, which is exactly
    /// why it took the same time at 21, 60 and 120 days: the seeder had not
    /// written a single sample in any of them.
    ///
    /// Two rules follow, and they are what keep this from happening again.
    /// **Query the sheet's own application**, and **never return silently**.
    /// Every step here asserts, because a permission helper that gives up
    /// quietly hands the failure to whatever runs next, which then reports
    /// something that has nothing to do with the cause.
    private var healthSheet: XCUIApplication {
        XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")
    }

    /// The rows are `Cell`s, not `Button`s and not `Switch`es, and only the
    /// cell-level identifiers are trustworthy: the simulator hands the inner
    /// title and switch of one row the identifier of a different row (Active
    /// Energy's switch is called `UIA.Health.HeartRateVariability.SwitchCell.Switch`).
    /// The `UIA.Health.{Read,Write}.<Type>.SwitchCell` identifier on the cell
    /// itself is correct, and the cell carries the on/off value, so everything
    /// below works off the cells.
    private static let allCategoriesIdentifier = "UIA.Health.AuthSheet.AllCategoryButton"
    private static let allowIdentifier = "UIA.Health.Allow.Button"
    private static let switchCellPredicate = NSPredicate(
        format: "identifier BEGINSWITH 'UIA.Health.' AND identifier ENDSWITH '.SwitchCell'"
    )

    /// Returns without doing anything if the sheet does not appear, but only
    /// once it has established that the app got past it.
    ///
    /// A missing sheet has two causes and they are opposites. HealthKit does
    /// not re-present for a store that has already granted everything, which is
    /// the ordinary state of a simulator this test has run on before and is
    /// nothing to fail over. Or it was previously **denied**, in which case the
    /// seeder writes nothing, `HealthSeeder.seedIfRequested` returns false, and
    /// `hasCompletedSetup` is never set, so the app sits on onboarding forever.
    ///
    /// Those two are distinguishable from outside, by the tab bar. Waiting on
    /// it here is what keeps the "never return silently" rule while still
    /// letting a legitimately-authorized simulator through, and it names the
    /// remedy in the failure rather than handing a bare timeout to whatever
    /// runs next.
    private func allowHealthAccess() {
        let sheet = healthSheet
        let turnOnAll = sheet.cells[Self.allCategoriesIdentifier]
        guard turnOnAll.waitForExistence(timeout: 90) else {
            XCTAssertTrue(
                XCUIApplication().buttons["Today"].waitForExistence(timeout: 120),
                "The Health permission sheet never appeared and the app never got past onboarding, which is what a previously denied store looks like. Erase the simulator and run again: xcrun simctl shutdown <udid> && xcrun simctl erase <udid>"
            )
            return
        }
        waitUntilHittable(turnOnAll)
        turnOnAll.tap()

        turnEverythingOn(in: sheet)

        let allow = sheet.buttons[Self.allowIdentifier]
        XCTAssertTrue(allow.waitForExistence(timeout: 15), "the Allow button never appeared")
        // Allow stays disabled until at least one category is on, and the
        // toggles animate, so this is a real wait rather than a formality.
        waitUntilHittable(allow)
        allow.tap()

        // The sheet dismisses asynchronously and nothing downstream is
        // meaningful until it has: `requestAuthorization` does not resume until
        // the transaction ends, and the app is sitting on that continuation.
        let deadline = Date().addingTimeInterval(30)
        while allow.exists, Date() < deadline {
            if allow.isHittable { allow.tap() }
            Thread.sleep(forTimeInterval: 0.5)
        }
        XCTAssertFalse(allow.exists, "the Health permission sheet never dismissed")
    }

    /// "Turn On All" is the only control that reaches the rows below the fold
    /// (the table is about 1,860 points of content in an 812-point window, and
    /// the read section is entirely off screen), so it does the work and this
    /// checks it did.
    ///
    /// Every cell reports its own on/off value whether or not it is visible, so
    /// the check is complete without scrolling; anything still off that is
    /// reachable gets tapped, and anything still off that is not is a failure
    /// rather than a shrug. **Tapping "Turn On All" is not the same as
    /// everything being on**, and when they diverge the only symptom is one
    /// line in the device log reading `Seeding failed: Not authorized`.
    private func turnEverythingOn(in sheet: XCUIApplication) {
        let deadline = Date().addingTimeInterval(20)
        while Date() < deadline {
            let off = sheet.cells.matching(Self.switchCellPredicate)
                .allElementsBoundByIndex
                .filter { isOff($0) }
            if off.isEmpty { return }
            for cell in off where cell.isHittable { cell.switches.firstMatch.tap() }
            Thread.sleep(forTimeInterval: 0.5)
        }
        let stillOff = sheet.cells.matching(Self.switchCellPredicate)
            .allElementsBoundByIndex
            .filter { isOff($0) }
            .map(\.identifier)
        XCTAssertTrue(
            stillOff.isEmpty,
            "these Health categories were still off when Allow was tapped: \(stillOff)"
        )
    }

    /// The cell's value arrives as an `NSNumber` here and as a `String` in other
    /// places XCTest surfaces switch state, so it is compared as text.
    private func isOff(_ cell: XCUIElement) -> Bool {
        guard let value = cell.value else { return false }
        return String(describing: value) == "0"
    }

    /// Everything that can interrupt at launch, cleared in one place, in a
    /// loop, and **after** the import rather than only before it.
    ///
    /// The previous version ran once the moment the tab bar appeared and looked
    /// for four labels, which on seeded data was too early to catch the one
    /// interruption seeded data guarantees. The seeded history ends with a
    /// countdown that has already run out, so Today raises its readiness
    /// question ("How did that feel?") a beat after the first import lands. The
    /// half sheet then covered the floating tab bar for the rest of the
    /// walkthrough: every tap computed a hit point of {-1, -1}, fell back to the
    /// element's centre, and landed on the sheet instead of the tab.
    ///
    /// **And the test passed anyway**, which is the part worth remembering.
    /// `navigationBars["History"]` reported `exists` from behind the sheet, so
    /// three of the five attachments were the same screenshot of Today. It is
    /// the accessibility-tree trap the tab-bar frame tests are written around,
    /// arriving from a new direction: not an off-screen element this time, but
    /// a covered one.
    ///
    /// "Not now" is checked first on purpose. The trial offer carries both a
    /// decline and a purchase button, and the purchase one is what a careless
    /// label list taps.
    private func dismissInterrupts(in app: XCUIApplication) {
        // "Continue" is What's New's dismissal. It is not the trial offer's CTA,
        // which reads "Continue with Recharge+" and does not match by label.
        let dismissals = ["Not now", "Got it", "Continue", "Done", "Close"]
        for _ in 0..<6 {
            guard let button = dismissals
                .map({ app.buttons[$0] })
                .first(where: { $0.exists && $0.isHittable })
            else { return }
            button.tap()
            Thread.sleep(forTimeInterval: 1)
        }
    }

    /// Switches tab and proves it. `RootView` hides an unselected tab with
    /// `opacity(0)` and `allowsHitTesting(false)` rather than removing it, so
    /// `exists` cannot tell a visible screen from a hidden one and only
    /// `isHittable` can.
    private func show(_ tab: String, in app: XCUIApplication, landmark: XCUIElement) {
        let button = app.buttons[tab]
        XCTAssertTrue(button.exists, "the \(tab) tab is missing")
        waitUntilHittable(button, timeout: 30)
        XCTAssertTrue(button.isHittable, "the \(tab) tab is on screen but covered")
        button.tap()
        waitUntilHittable(landmark, timeout: 30)
        XCTAssertTrue(landmark.isHittable, "tapping \(tab) did not bring its screen forward")
    }

    private func waitUntilHittable(_ element: XCUIElement, timeout: TimeInterval = 20) {
        let deadline = Date().addingTimeInterval(timeout)
        while !element.isHittable, Date() < deadline {
            Thread.sleep(forTimeInterval: 0.25)
        }
    }

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    /// One pass through the whole app on seeded data.
    ///
    /// Deliberately one test rather than four: seeding writes several thousand
    /// samples and re-running it per test would cost minutes for nothing, and
    /// the point is to look at the screens in the order a user meets them.
    func testWalkthroughOnSeededHealthData() throws {
        let app = launchSeeded()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 30))

        // The import walks 120 days of workouts and runs a heart-rate query
        // against each one, so the first paint is a genuine wait. The seeding
        // itself is not: 120 days is about 600 workouts and it finishes in
        // roughly two seconds.
        let today = app.buttons["Today"]
        XCTAssertTrue(today.waitForExistence(timeout: 300), "the tab bar never appeared")
        dismissInterrupts(in: app)
        sleepForImport()
        // Again, because the readiness question follows the import rather than
        // the launch.
        dismissInterrupts(in: app)

        // `exists` is not `isHittable`, and the gap is real twice over here: the
        // shell cross-fades from onboarding to the tab bar over a quarter of a
        // second, and anything still presented sits on top of it.
        waitUntilHittable(today, timeout: 60)
        XCTAssertTrue(today.isHittable, "the tab bar is on screen but covered")
        attach(app, named: "01-today")

        show("History", in: app, landmark: app.navigationBars["History"])
        attach(app, named: "02-history")

        // The row that used to read "None". Scroll a little so the attachment
        // shows a mixed day rather than only the newest session.
        app.swipeUp()
        attach(app, named: "03-history-scrolled")

        // "Upgrade" before purchase, "Recharge+" after. On a seeded simulator
        // run it is always the former, because there is no RevenueCat.
        show("Upgrade", in: app, landmark: app.staticTexts["Recharge+"].firstMatch)
        attach(app, named: "04-upgrade")

        show("Today", in: app, landmark: today)

        // The ring opens the explanation, which is where everything that used
        // to clutter Today now lives. `today.hero` is the identifier on it; the
        // previous version tapped `app.otherElements.firstMatch`, which is
        // whatever container happens to come first and had no reason to be the
        // ring.
        // Matched by identifier across every element type rather than as
        // `otherElements`: the hero is a `Button` with
        // `accessibilityElement(children: .combine)`, and querying the wrong
        // collection reports a missing ring rather than a mistyped query.
        let hero = app.descendants(matching: .any)
            .matching(identifier: "today.hero")
            .firstMatch
        XCTAssertTrue(hero.waitForExistence(timeout: 15), "the countdown ring is missing")
        waitUntilHittable(hero, timeout: 15)
        hero.tap()
        attach(app, named: "05-detail")
    }

    /// The import is asynchronous and finishes without changing any element the
    /// test can wait on — the ring is on screen throughout, it just changes what
    /// it says. A fixed pause is the honest version of that.
    private func sleepForImport() {
        Thread.sleep(forTimeInterval: 12)
    }
}
