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

        // Everything outside the plan region is StoreKit-independent, so it is
        // asserted unconditionally: the neutral CTA (Apple 3.1.2(c) — no pricing
        // words on the button), Restore, and the compliance footer.
        XCTAssertTrue(app.buttons["Continue with Recharge Pro"].exists)
        XCTAssertTrue(app.buttons["Restore"].exists)
        // Terms and Privacy are SwiftUI `Link`s, which surface as links rather
        // than buttons. Querying `buttons` here never matches.
        XCTAssertTrue(app.links["Terms"].exists)
        XCTAssertTrue(app.links["Privacy"].exists)

        attach(app, named: "paywall-layout")

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

    func testSettingsExposesTheComplicationStyleSetting() {
        let app = launch(scene: "settings")
        XCTAssertTrue(app.staticTexts["Watch complication"].waitForExistence(timeout: 15))
        XCTAssertTrue(app.staticTexts["Apple Health"].exists)
        XCTAssertTrue(app.buttons["Request Apple Health access"].exists)
        XCTAssertTrue(app.staticTexts["Style"].exists)
        attach(app, named: "settings")
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
    func testTheTrialOfferIsLegibleAtTheLargestTextSize() {
        let app = launch(
            scene: "onboarding",
            contentSize: "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
        )

        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))
        app.buttons["Continue"].tap()
        XCTAssertTrue(app.buttons["Not now"].waitForExistence(timeout: 10))
        app.buttons["Not now"].tap()
        XCTAssertTrue(app.buttons["I understand"].waitForExistence(timeout: 10))
        app.buttons["I understand"].tap()

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
