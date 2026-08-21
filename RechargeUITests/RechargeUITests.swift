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
        // The ring and the sentence naming the session that set it. "Why" used
        // to be a card on this screen and is now the sheet behind the ring —
        // Today is the number, not the explanation of the number.
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.staticTexts.containing(
                NSPredicate(format: "label CONTAINS[c] %@", "from your run")
            ).firstMatch.exists,
            "the countdown does not name the session that set it"
        )
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
            app.staticTexts["Recharge+"].firstMatch.waitForExistence(timeout: 25),
            "the paywall never appeared"
        )

        // The neutral CTA (Apple 3.1.2(c): no pricing words on the button) is
        // pinned rather than parked at the end of the scroll view, because the
        // hero, features, and three plan cards are taller than the sheet. It has
        // to be pressable on the first frame, with no scrolling: this assertion
        // is the regression guard for a purchase surface that showed prices but
        // hid its action.
        // By identifier, not by label: "Continue with Recharge+" is also the
        // locked-card capsule on Today, which sits behind this sheet, and
        // `firstMatch` on the label can pick that one and then truthfully report
        // that it is not hittable.
        let cta = app.buttons["paywall-cta"].firstMatch
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
        // Fourteen rather than eight. Settings grew a "Read from Apple Health"
        // section of up to nine explained rows, and a row below it needs more
        // swipes to reach than the sections above it ever did.
        for _ in 0..<14 {
            if element.exists { return true }
            app.swipeUp()
        }
        return element.exists
    }

    func testSettingsExposesTheComplicationStyleSetting() {
        let app = launch(scene: "settings")
        XCTAssertTrue(app.staticTexts["Apple Health"].waitForExistence(timeout: 15))
        attach(app, named: "settings")

        // Scrolled to, not asserted in place. The Recharge+ pitch and the
        // recovery-model section now sit above Apple Health, so its rows start
        // below the fold — and a row below the fold in a SwiftUI `Form` is not
        // in the accessibility tree at all, which reports as absent rather than
        // as off-screen.
        XCTAssertTrue(scrollToFind(app.buttons["Request Apple Health access"], in: app))

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

    /// The offer page's own primary. Named separately because it is the one the
    /// walk stops at, and because it is the button the frame check exists for:
    /// it is the only CTA in the flow with legal text anywhere near it.
    private static let offerPrimary = "Continue with Recharge+"

    @discardableResult
    private func advanceToTheOffer(_ app: XCUIApplication) -> [CGRect] {
        var primaryFrames: [CGRect] = []

        for _ in 0..<12 {
            if app.buttons[Self.offerPrimary].firstMatch.exists { break }
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

        // The offer page's CTA, measured like every other one.
        //
        // The previous version of this helper broke out of the loop the moment
        // that button appeared and returned without its frame, so the check
        // below covered the four Continue buttons and stopped one page short of
        // the only page in the flow with anything underneath its CTA. The bug it
        // was written to catch had moved onto the page it could not see.
        let offer = app.buttons[Self.offerPrimary].firstMatch
        if offer.waitForExistence(timeout: 10) {
            wait(
                for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: offer)],
                timeout: 10
            )
            primaryFrames.append(offer.frame)
        }
        return primaryFrames
    }

    /// The regression guard for the reported bug: the primary button moved
    /// between onboarding pages.
    ///
    /// It has moved for two different reasons now. First because only the Health
    /// page carried a secondary action and its height was not reserved anywhere
    /// else. Then because the trial page appended a subscription disclosure and a
    /// Restore/Terms/Privacy row *below* its CTA, lifting it clear of the four
    /// Continue buttons that had just trained the thumb — on the one screen in
    /// the flow that takes money. Nothing that varies between pages may sit below
    /// the primary button; see `OnboardingActions`.
    ///
    /// Frames, not screenshots: this is a geometry claim, and a screenshot cannot
    /// fail on a four-point shift.
    func testTheOnboardingButtonStaysInOnePlace() {
        let app = launch(scene: "onboarding")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))

        let frames = advanceToTheOffer(app)
        XCTAssertGreaterThanOrEqual(frames.count, 4, "onboarding ended before it could be measured")

        guard let first = frames.first else { return XCTFail("no primary button was found") }
        for (index, frame) in frames.enumerated().dropFirst() {
            XCTAssertEqual(
                frame.minY, first.minY, accuracy: 1,
                "the primary button moved between pages (page \(index + 1) of \(frames.count))"
            )
            XCTAssertEqual(
                frame.height, first.height, accuracy: 1,
                "the primary button changed height (page \(index + 1) of \(frames.count))"
            )
        }
    }

    /// The same claim, stated where it actually broke: the last frame in the walk
    /// is the purchase CTA, and it has to sit exactly where the Continue button
    /// on the page before it sat.
    ///
    /// Separate from the loop above so a failure names the real defect rather
    /// than "page 5 of 5 moved".
    func testThePurchaseCTALandsWhereTheContinueButtonWas() {
        let app = launch(scene: "onboarding")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))

        let frames = advanceToTheOffer(app)
        guard frames.count >= 2, let offer = frames.last, let previous = frames.dropLast().last else {
            return XCTFail("the walk never reached the offer page")
        }
        XCTAssertEqual(
            offer.minY, previous.minY, accuracy: 1,
            "the purchase CTA sits \(offer.minY - previous.minY)pt from where the thumb was just trained to reach"
        )
        attach(app, named: "onboarding-cta-alignment")
    }

    /// The last onboarding decision is choosing a tier, not postponing one, so
    /// the way past it reads as starting rather than declining.
    func testTheFinalOnboardingDecisionOffersTheFreeTier() {
        let app = launch(scene: "onboarding")
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))
        advanceToTheOffer(app)

        XCTAssertTrue(
            app.buttons["Continue with Recharge+"].firstMatch.waitForExistence(timeout: 10),
            "the offer page never appeared"
        )
        let getStarted = app.buttons["Get Started"].firstMatch
        XCTAssertTrue(getStarted.exists, "the free path is not offered by name")
        XCTAssertTrue(app.buttons["Restore"].exists, "restore is missing from the onboarding purchase point")
        for legal in ["Terms", "Privacy"] {
            XCTAssertTrue(
                app.descendants(matching: .any).matching(identifier: legal).firstMatch.exists,
                "\(legal) is missing from the onboarding purchase point"
            )
        }
        attach(app, named: "onboarding-offer")

        if !getStarted.isHittable { app.swipeUp() }
        XCTAssertTrue(getStarted.isHittable, "the free path cannot be reached")
        getStarted.tap()
        XCTAssertTrue(
            // Not `app.tabBars`: the bar is a floating translucent capsule of
            // plain buttons over the content, not a system `TabView`, so the
            // system bar element does not exist to query.
            app.buttons["Today"].firstMatch.waitForExistence(timeout: 15),
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

        let cta = app.buttons["Continue with Recharge+"].firstMatch
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

    // MARK: - The comparison card

    /// A countdown on its own is unreadable: "18h" gives no way to tell whether
    /// that is a lot, a little, or what you were going to do anyway. One card on
    /// Today answers it with two numbers — the average recovery time for
    /// somebody at this training level, and theirs.
    ///
    /// It replaces a three-column rest-pattern table that tried to answer the
    /// same question with nine figures, three of which were measurements, three
    /// estimates, and three blurred. Nobody could hold that in their head, and
    /// the column that mattered was the one under the blur.
    func testTodayShowsTheRecoveryTimeComparison() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(
            app.staticTexts["Your own recharge time"].waitForExistence(timeout: 15),
            "the comparison that makes the countdown mean something is missing"
        )
        // `.textCase(.uppercase)` is a rendering transform: the accessibility
        // label stays as it was written.
        for column in ["Usual", "Optimal"] {
            XCTAssertTrue(app.staticTexts[column].firstMatch.exists, "the \(column) column is missing")
        }
        attach(app, named: "today-comparison")
    }

    /// The right-hand figure is the pitch, and on the free tier it is a **real**
    /// number under a blur rather than a mock-up — `RecoveryEngine` computes it
    /// on both tiers precisely so this can be honest. What the test can see is
    /// the lock: the blur itself is not in the accessibility tree.
    func testTheComparisonLocksThePersonalizedFigureOnTheFreeTier() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.staticTexts["Your own recharge time"].waitForExistence(timeout: 15))
        XCTAssertTrue(
            app.staticTexts["Hidden until you upgrade"].firstMatch.exists,
            "the free tier is not being shown a locked personalized figure"
        )
    }

    /// And a subscriber must not be sold what they already have.
    func testTheComparisonIsUnlockedForASubscriber() {
        let app = launch(scene: "premiumActive")
        XCTAssertTrue(app.staticTexts["Your recharge time"].waitForExistence(timeout: 15))
        XCTAssertFalse(
            app.staticTexts["Hidden until you upgrade"].firstMatch.exists,
            "a subscriber is still being shown the blur they are paying to remove"
        )
        attach(app, named: "today-comparison-pro")
    }

    /// The third tab is the paywall before purchase and the feature page after
    /// it — the Vitals arrangement, and the reason the thing somebody bought
    /// keeps a place in the navigation instead of dissolving into settings rows.
    func testTheThirdTabIsTheUpgradeBeforePurchaseAndRechargePlusAfter() {
        let free = launch(scene: "recovering")
        XCTAssertTrue(free.buttons["Upgrade"].waitForExistence(timeout: 15))
        XCTAssertFalse(free.buttons["Recharge+"].exists)

        let pro = launch(scene: "premiumActive")
        XCTAssertTrue(pro.buttons["Recharge+"].waitForExistence(timeout: 15))
        XCTAssertFalse(pro.buttons["Upgrade"].exists)
        pro.buttons["Recharge+"].tap()
        XCTAssertTrue(pro.staticTexts["Recharge+ active"].waitForExistence(timeout: 15))
        attach(pro, named: "recharge-plus-tab")
    }

    /// **Settings is not a tab any more.** It is a gear button on Today, which
    /// is what freed the third slot for Recharge+.
    ///
    /// Asserted by opening it, not by looking for the button: the gear is the
    /// only "Settings" element on the screen either way, so an existence check
    /// would pass on a build where tapping it did nothing.
    func testSettingsOpensFromTheGearButtonOnToday() {
        let app = launch(scene: "recovering")
        let gear = app.buttons["Settings"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 15), "the Settings gear is missing from Today")
        gear.tap()

        XCTAssertTrue(
            app.navigationBars["Settings"].waitForExistence(timeout: 15),
            "the gear button did not open Settings"
        )
        // A sheet needs a way out, and a `Form` inside one has no navigation
        // bar back button to fall back on.
        XCTAssertTrue(app.buttons["Done"].exists, "Settings has no way to dismiss")
    }

    /// App Review 1.4.1: the non-diagnostic disclaimer has to be present and
    /// readable.
    ///
    /// It is no longer on Today. Today is the ring and one card, and a paragraph
    /// of legal copy pinned under a screen whose whole point is one number is
    /// exactly the furniture that redesign removed. It lives where the estimate
    /// is *explained* instead — the detail sheet a tap on the ring opens — which
    /// is also the first place a user asking "what does this number mean" ends
    /// up, and therefore a better place for it than the bottom of a page nobody
    /// scrolls.
    func testTheDisclaimerIsPresentOnTheExplanation() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 15))
        app.buttons["today.hero"].tap()

        let disclaimer = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "not medical advice")
        ).firstMatch
        XCTAssertTrue(
            disclaimer.waitForExistence(timeout: 15),
            "the non-diagnostic disclaimer is not reachable from the countdown"
        )
        attach(app, named: "estimate-detail")
    }

    // MARK: - The floating tab bar must not sit on top of anything

    /// The three tab buttons, whose own labels have to be excluded from any
    /// "what is lowest on screen" question: they sit below the bar's top edge by
    /// construction, so counting them measures the bar against itself and the
    /// assertion can never pass.
    private func tabBarButtons(in app: XCUIApplication) -> [CGRect] {
        ["Today", "History", "Settings"].map { app.buttons[$0].firstMatch.frame }
    }

    /// The bottom-most on-screen content once a tab has been scrolled to its
    /// end, ignoring the tab bar itself.
    ///
    /// Asked as "whatever is lowest" rather than about a named row, because a
    /// `#if DEBUG` section sits below the Settings disclaimer: asserting on the
    /// disclaimer would clear the bar in a test build whether or not the fix
    /// were there.
    ///
    /// Two filters, and both were needed. Scoping to the scroll `container`
    /// drops the app-level chrome, one item of which is a static text spanning
    /// the whole window and would answer this question with the window height
    /// every time. Excluding frames *contained in* a tab button drops the bar's
    /// own labels, which sit below the bar's top edge by construction and would
    /// otherwise measure the bar against itself.
    ///
    /// Containment rather than matching on the label text, because a day heading
    /// in History can legitimately read "Today". A tab label is wholly inside
    /// its button; real content is not: even the narrow centred "Show N light
    /// sessions" row starts to the left of any single tab button.
    ///
    /// Off-screen rows report frames far below the window and are filtered out.
    /// A row *under the bar* is still inside the window, which is exactly the
    /// case that has to fail.
    private func lowestVisibleContent(
        in container: XCUIElement,
        of app: XCUIApplication
    ) -> CGRect? {
        let window = app.windows.firstMatch.frame
        let bar = tabBarButtons(in: app)
        return container.staticTexts.allElementsBoundByIndex
            .map(\.frame)
            .filter { frame in
                frame.minY >= 0
                    && frame.maxY <= window.maxY
                    && frame.height > 0
                    && !bar.contains { $0.contains(frame) }
            }
            .max { $0.maxY < $1.maxY }
    }

    /// Fixed-count scrolling, not "stop when the frame stops moving". The
    /// adaptive version returned early against a `Form`, whose reported frames
    /// lag a swipe, and a scroll test that silently fails to scroll asserts
    /// nothing.
    private func scrollToBottom(of app: XCUIApplication) {
        for _ in 0..<14 { app.swipeUp() }
    }

    /// The bar floats over the content, so every scrollable tab has to reserve
    /// room for it at rest.
    ///
    /// The Recharge+ tab is where that is easiest to get wrong now, because it
    /// is two different screens in one slot: a `ScrollView` when subscribed and
    /// the paywall when not, and the paywall keeps its CTA in its own bottom bar
    /// rather than inside the scroll view — so it cannot reserve its own room
    /// the way a scroll view can, and `RootView` has to hand it an inset.
    ///
    /// Settings used to be the third tab and the one this check was written for.
    /// It is a sheet now, raised from Today's gear button, so nothing about it
    /// can be covered by a bar that is not on screen while it is up.
    func testTheTabBarDoesNotCoverTheBottomOfRechargePlus() {
        let app = launch(scene: "premiumActive")
        XCTAssertTrue(app.buttons["Recharge+"].waitForExistence(timeout: 15))
        app.buttons["Recharge+"].tap()
        XCTAssertTrue(app.staticTexts["Recharge+ active"].waitForExistence(timeout: 15))
        scrollToBottom(of: app)
        attach(app, named: "recharge-plus-bottom")

        let tabBar = app.buttons["Recharge+"].firstMatch
        let lastRow = app.buttons["Manage subscription"].firstMatch
        XCTAssertTrue(lastRow.exists, "the account row is missing from Recharge+")
        XCTAssertLessThanOrEqual(
            lastRow.frame.maxY, tabBar.frame.minY,
            "the floating tab bar is covering the bottom of Recharge+"
        )
    }

    /// Same claim on the paywall, which is the same tab before purchase.
    func testTheTabBarDoesNotCoverTheUpgradeTabsCTA() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.buttons["Upgrade"].waitForExistence(timeout: 15))
        app.buttons["Upgrade"].tap()

        let cta = app.buttons["paywall-cta"].firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 20), "the paywall CTA is missing from the Upgrade tab")
        attach(app, named: "upgrade-tab-bottom")

        let tabBar = app.buttons["Upgrade"].firstMatch
        XCTAssertLessThanOrEqual(
            cta.frame.maxY, tabBar.frame.minY,
            "the floating tab bar is covering the Upgrade tab's purchase button"
        )
    }

    /// Same claim on Today, whose bottom-most element is now the comparison card
    /// rather than the disclaimer paragraph that used to close the page.
    ///
    /// It cleared the bar before by a hand-copied 72 points; it clears it now
    /// because `tabBarClearance()` reserves the room from the same constants
    /// that lay the bar out.
    func testTheTabBarDoesNotCoverTheBottomOfToday() {
        let app = launch(scene: "recovering")
        let caption = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Usual is read from your own history")
        ).firstMatch
        XCTAssertTrue(caption.waitForExistence(timeout: 15))
        scrollToBottom(of: app)

        let tabBar = app.buttons["Today"].firstMatch
        XCTAssertTrue(tabBar.exists)
        XCTAssertLessThanOrEqual(
            caption.frame.maxY, tabBar.frame.minY,
            "the floating tab bar is covering the bottom of Today"
        )
    }

    /// And History, the third tab, which reserved 96 points for a 68-point bar.
    func testTheTabBarDoesNotCoverTheBottomOfHistory() {
        let app = launch(scene: "history")
        XCTAssertTrue(app.staticTexts["Run"].firstMatch.waitForExistence(timeout: 15))
        scrollToBottom(of: app)
        attach(app, named: "history-bottom")

        let tabBar = app.buttons["History"].firstMatch
        XCTAssertTrue(tabBar.exists)
        // The oldest session in the fixture is the last row of the list, so it
        // is the row with nothing below it to be pushed clear by. Named rather
        // than discovered, because History's scroll view reports the tab bar's
        // own labels among its descendants and "the lowest thing" then means the
        // bar.
        //
        // There used to be a "Show N light sessions" toggle here to measure
        // against, and it is gone with the collapsing that made it necessary:
        // every session carries a cost now, so a light one is an ordinary row
        // rather than one of a wall of the word "None" that had to be hidden.
        let rows = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Functional Session")
        ).allElementsBoundByIndex
        XCTAssertFalse(rows.isEmpty, "no rows in History to measure")
        guard let lastRow = rows.last else { return }
        XCTAssertLessThanOrEqual(
            lastRow.frame.maxY, tabBar.frame.minY,
            "the floating tab bar is covering the bottom of History"
        )
    }
}
