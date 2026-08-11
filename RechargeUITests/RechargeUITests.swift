import XCTest

@MainActor
final class RechargeUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(scene: String? = nil, contentSize: String? = nil) -> XCUIApplication {
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

    private func attach(_ app: XCUIApplication, named name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }
    func testAppLaunches() {
        let app = launch()
        XCTAssertTrue(app.wait(for: .runningForeground, timeout: 20))
    }

    func testTodayShowsTheCountdown() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.staticTexts["Why"].waitForExistence(timeout: 15))
        attach(app, named: "today-recovering")
    }

    func testTodayShowsReadyOnceTheCountdownExpires() {
        let app = launch(scene: "ready")
        XCTAssertTrue(
            app.staticTexts["Ready for another hard session."].waitForExistence(timeout: 15)
        )
        attach(app, named: "today-ready")
    }

    /// The paywall is empty under plain `simctl launch` — no RevenueCat on
    /// simulator and no StoreKit catalogue. This is the only place the *real*
    /// plan cards can be verified rather than the "couldn't load plans" state.
    /// Never sign off on paywall layout from a `simctl` screenshot.
    ///
    /// The plans come from `StoreService.screenshotPackages`, not StoreKit:
    /// StoreKit Testing does not activate under `xcodebuild test` no matter how
    /// the `.storekit` file is referenced, so it can never fill this in. See the
    /// doc comment on `screenshotPackages`.
    ///
    /// That makes this a **layout** check — card order, price hierarchy, trial
    /// copy, CTA, disclosure footer — against prices that mirror App Store
    /// Connect. Real StoreKit price formatting (localised currency, PPP
    /// territories) is still only observable on device.
    func testPaywallRendersRealProductsUnderStoreKitTesting() throws {
        let app = launch(scene: "paywall")

        XCTAssertTrue(
            app.staticTexts["Recharge Pro"].firstMatch.waitForExistence(timeout: 25),
            "the paywall never appeared"
        )

        // The neutral CTA (Apple 3.1.2(c): no pricing words on the button) is
        // pinned rather than parked at the end of the scroll view, because the
        // hero, features, and three plan cards are taller than the sheet. It has
        // to be pressable on the first frame, with no scrolling: this assertion
        // is the regression guard for a purchase surface that showed prices but
        // hid its action.
        let cta = app.buttons["Continue with Recharge Pro"].firstMatch
        XCTAssertTrue(cta.exists, "the paywall CTA is missing")
        XCTAssertTrue(cta.isHittable, "the paywall CTA is not reachable without scrolling")

        attach(app, named: "paywall-layout")

        // Restore, Terms, and Privacy only have to be reachable, not visible on
        // the first frame. Terms and Privacy are SwiftUI `Link`s, whose element
        // type is not stable across OS versions: they were links, and on the
        // current simulator they are not, which is what quietly broke this test.
        // Match on the label alone rather than betting on the type again.
        app.swipeUp()
        XCTAssertTrue(app.buttons["Restore"].waitForExistence(timeout: 5))
        for legal in ["Terms", "Privacy"] {
            XCTAssertTrue(
                app.descendants(matching: .any).matching(identifier: legal).firstMatch.exists,
                "\(legal) is not reachable on the paywall"
            )
        }

        XCTAssertTrue(
            app.staticTexts["Yearly"].waitForExistence(timeout: 15),
            "the plan cards never rendered"
        )

        // Every plan must be present, or the pricing hierarchy Apple 3.1.2(c)
        // requires cannot be judged at all.
        for plan in ["Yearly", "Monthly", "Lifetime"] {
            XCTAssertTrue(app.staticTexts[plan].exists, "\(plan) plan card is missing")
        }
        for feature in [
            "A recharge time built from your own history",
            "Sleep, HRV, and resting heart rate",
            "Weekly load against your 4-week average",
            "Correct a session's workout type",
            "A notification the moment you're Ready",
        ] {
            XCTAssertTrue(app.staticTexts[feature].exists, "\(feature) is missing")
        }
        XCTAssertFalse(app.staticTexts["Bands tuned to your own history"].exists)
        XCTAssertFalse(app.staticTexts["Every estimate, and how it landed"].exists)
        XCTAssertFalse(
            app.staticTexts["Couldn't load plans"].exists,
            "the paywall fell back to its empty state"
        )
        attach(app, named: "paywall-with-plans")
    }

    /// Scrolls a `Form` until `element` renders.
    ///
    /// Rows below the fold in a SwiftUI `Form` are not in the accessibility tree
    /// at all, so `exists` is false for them and a settings assertion breaks
    /// whenever a section is added above it — which says nothing about the row.
    @discardableResult
    private func scrollToFind(_ element: XCUIElement, in app: XCUIApplication) -> Bool {
        for _ in 0..<8 {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.exists
    }

    func testSettingsExposesTheComplicationStyleSetting() {
        let app = launch(scene: "settings")
        XCTAssertTrue(app.staticTexts["Apple Health"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.buttons["Request Apple Health access"].exists)
        attach(app, named: "settings")

        XCTAssertTrue(scrollToFind(app.staticTexts["Watch complication"], in: app))
        XCTAssertTrue(app.staticTexts["Style"].exists)
    }

    /// The tier split has to be legible from Settings: a free user is entitled
    /// to know their countdown is the standard one rather than one about them.
    func testSettingsNamesWhichRecoveryModelIsRunning() {
        let app = launch(scene: "settings")
        XCTAssertTrue(app.staticTexts["Recharge time"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Model"].exists)

        // Scrolled to one at a time, in the order they appear. A row that was
        // on screen for the previous assertion can be off the top by the time
        // the next one is reached, so a single scroll and three `exists` checks
        // would only ever be testing the scroll position.
        for row in ["About you", "Training for", "Sessions a week", "Ready again after"] {
            XCTAssertTrue(scrollToFind(app.staticTexts[row], in: app), "\(row) is missing from Settings")
        }
        attach(app, named: "settings-about-you")
    }

    func testHistoryListsScoredSessions() {
        let app = launch(scene: "history")
        XCTAssertTrue(app.staticTexts["Run"].firstMatch.waitForExistence(timeout: 15))
        attach(app, named: "history")
    }

    /// The purchase decision has to survive the largest accessibility text size.
    ///
    /// The trial page used to be a fixed `VStack`, and at this content size the
    /// stack overflowed the screen: SwiftUI resolved that by ellipsizing every
    /// text in it, so the headline, the price, the trial length, and the button
    /// label itself were all cut off. A user cannot consent to a subscription
    /// they cannot read. The page now scrolls, so each of those has to be
    /// reachable and hittable.
    /// Walks onboarding to the offer page, tapping whatever primary button the
    /// current step is showing.
    ///
    /// The step list is not fixed: it depends on what Apple Health managed to
    /// answer, so the questions that remain vary. Driving it by "press the
    /// primary action" rather than by a hardcoded script is the only way this
    /// stays true, and it is also what the user does.
    /// Every primary title onboarding can show, and *only* the primaries.
    ///
    /// "Not now" is deliberately absent. It is the Health page's secondary, and
    /// including it made the frame check measure a different element on that one
    /// page — which looked exactly like the layout bug the check exists to
    /// catch. Under screenshot mode the Health request resolves instantly, so
    /// pressing the real primary is both possible and the path a user takes.
    private static let onboardingPrimaries = [
        "Continue", "Connect Apple Health", "Skip this one", "I understand"
    ]

    @discardableResult
    private func advanceToTheOffer(_ app: XCUIApplication) -> [CGRect] {
        var primaryFrames: [CGRect] = []

        for _ in 0..<12 {
            if app.buttons["Continue with Recharge Pro"].firstMatch.exists { break }
            guard let next = Self.onboardingPrimaries
                .map({ app.buttons[$0].firstMatch })
                .first(where: { $0.exists })
            else { break }
            // The page TabView slides for a quarter of a second, and an element
            // caught mid-transition has no valid activation point — asking it
            // for `isHittable` throws outright, and asking it for a frame gets
            // one from halfway through the slide, which is precisely the
            // measurement this helper must not take.
            wait(
                for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: next)],
                timeout: 10
            )
            primaryFrames.append(next.frame)
            next.tap()
            // The outgoing page's button still exists during the slide, so
            // settle before picking the next one or the same button is tapped
            // twice.
            Thread.sleep(forTimeInterval: 0.6)
        }
        return primaryFrames
    }

    /// The regression guard for the reported bug: the primary button moved
    /// between onboarding pages, because only the Health page carried a
    /// secondary action and its height was not reserved anywhere else.
    ///
    /// Frames, not screenshots: this is a geometry claim, and a screenshot
    /// cannot fail on a four-point shift.
    func testTheOnboardingButtonStaysInOnePlace() {
        let app = launch(scene: "onboarding")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))

        let frames = advanceToTheOffer(app)
        XCTAssertGreaterThanOrEqual(frames.count, 3, "onboarding ended before it could be measured")

        guard let first = frames.first else { return XCTFail("no primary button was found") }
        for frame in frames.dropFirst() {
            XCTAssertEqual(frame.minY, first.minY, accuracy: 1, "the primary button moved between pages")
            XCTAssertEqual(frame.height, first.height, accuracy: 1, "the primary button changed height")
        }
    }

    /// The last onboarding decision is choosing a tier, not postponing one, so
    /// the way past it reads as starting rather than declining.
    func testTheFinalOnboardingDecisionOffersTheFreeTier() {
        let app = launch(scene: "onboarding")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))
        advanceToTheOffer(app)

        XCTAssertTrue(
            app.buttons["Continue with Recharge Pro"].firstMatch.waitForExistence(timeout: 10),
            "the offer page never appeared"
        )
        let getStarted = app.buttons["Get started with Standard"].firstMatch
        XCTAssertTrue(getStarted.exists, "the free path is not offered by name")
        attach(app, named: "onboarding-offer")

        getStarted.tap()
        XCTAssertTrue(
            app.tabBars.buttons["Today"].waitForExistence(timeout: 15),
            "the free path did not finish setup"
        )
    }

    func testTheTrialOfferIsLegibleAtTheLargestTextSize() {
        let app = launch(
            scene: "onboarding",
            contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))
        advanceToTheOffer(app)

        let cta = app.buttons["Continue with Recharge Pro"].firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 10), "the trial page never appeared")
        attach(app, named: "trial-offer-accessibility-xxxl")

        // Existence is not enough: an element the layout has pushed off the
        // screen still exists. It has to be scrollable into reach and pressable.
        if !cta.isHittable { app.swipeUp() }
        XCTAssertTrue(cta.isHittable, "the purchase button cannot be reached")

        let price = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "per year")
        ).firstMatch
        XCTAssertTrue(price.exists, "the billed amount is missing")
        attach(app, named: "trial-offer-accessibility-xxxl-cta")
    }

    /// App Review 1.4.1: the non-diagnostic disclaimer has to be present and
    /// readable, not buried under the tab bar.
    func testTheDisclaimerIsPresentOnToday() {
        let app = launch(scene: "recovering")
        let disclaimer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "not medical advice")
        ).firstMatch
        XCTAssertTrue(disclaimer.waitForExistence(timeout: 15))
    }
}
