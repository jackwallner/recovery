import XCTest

/// Regression tests for the bug catalog of 2026-11-20
/// (`project-docs/audits/2026-11-20-bug-ux.html`). Each test is named for the
/// behaviour the fix restores and was run against the unfixed code first.
@MainActor
final class AuditFixesUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = false
    }

    private func launch(
        scene: String,
        contentSize: String? = nil,
        environment: [String: String] = [:]
    ) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RECHARGE_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["RECHARGE_SCREENSHOT_SCENE"] = scene
        for (key, value) in environment { app.launchEnvironment[key] = value }
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

    /// The trial offer's headline. It appears on no other screen, so its
    /// presence is the offer and nothing else.
    private func offerIsShowing(_ app: XCUIApplication, timeout: TimeInterval) -> Bool {
        app.staticTexts["Make it yours"].firstMatch.waitForExistence(timeout: timeout)
    }

    private func tapWhenHittable(_ element: XCUIElement, in app: XCUIApplication, file: StaticString = #filePath, line: UInt = #line) {
        for _ in 0..<6 where !element.isHittable { app.swipeUp() }
        XCTAssertTrue(element.isHittable, "\(element) cannot be reached", file: file, line: line)
        element.tap()
    }

    // MARK: - B1: the detail sheet's upgrade card

    /// A free user taps "Correct this session" on the detail sheet raised from
    /// Today. The sheet closes, and the offer has to follow it. It used to be
    /// dropped because Today still reported its sheet as up when the request
    /// arrived.
    func testCorrectThisSessionFromTodayRaisesTheOffer() {
        let app = launch(scene: "recovering")
        let hero = app.buttons["today.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        hero.tap()

        let teaser = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Correct this session")
        ).firstMatch
        XCTAssertTrue(teaser.waitForExistence(timeout: 15), "the upgrade card is missing from the detail sheet")
        tapWhenHittable(teaser, in: app)

        XCTAssertTrue(offerIsShowing(app, timeout: 8), "the detail sheet closed and no offer followed")
        attach(app, named: "b1-offer-from-today")
    }

    /// The same card on the detail raised from a History row.
    func testCorrectThisSessionFromHistoryRaisesTheOffer() {
        // Opens on History, as a free user. The row is the fixture's strength
        // session, whose name appears nowhere on Today.
        let app = launch(scene: "history")
        let row = app.buttons.matching(
            NSPredicate(format: "label CONTAINS[c] %@", "Functional Session")
        ).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 15), "History has no session to open")
        tapWhenHittable(row, in: app)

        let teaser = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Correct this session")
        ).firstMatch
        XCTAssertTrue(teaser.waitForExistence(timeout: 15), "the upgrade card is missing from the detail sheet")
        tapWhenHittable(teaser, in: app)

        XCTAssertTrue(offerIsShowing(app, timeout: 8), "the detail sheet closed and no offer followed")
        attach(app, named: "b1-offer-from-history")
    }

    // MARK: - B4: the offer at the largest text size

    private static let onboardingPrimaries = ["Continue", "Skip this one", "I understand"]

    private func advanceToTheOffer(_ app: XCUIApplication) {
        for _ in 0..<12 {
            if app.buttons["Continue with Recharge+"].firstMatch.exists { return }
            guard let next = Self.onboardingPrimaries
                .map({ app.buttons[$0].firstMatch })
                .first(where: { $0.exists })
            else { return }
            wait(
                for: [expectation(for: NSPredicate(format: "hittable == true"), evaluatedWith: next)],
                timeout: 10
            )
            next.tap()
            Thread.sleep(forTimeInterval: 0.6)
        }
    }

    /// Everything below the pitch has to be reachable at AX5: the purchase
    /// button, the free exit, Restore, and the legal links. They sat outside the
    /// page's scroll view, so on a short screen they were clipped with nothing
    /// to scroll.
    func testEveryControlOnTheOnboardingOfferIsReachableAtTheLargestTextSize() {
        let app = launch(
            scene: "onboarding",
            contentSize: "UICTContentSizeCategoryAccessibilityXXXL"
        )
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))
        advanceToTheOffer(app)
        XCTAssertTrue(app.buttons["Continue with Recharge+"].firstMatch.waitForExistence(timeout: 10))
        attach(app, named: "b4-offer-ax5-top")

        XCTAssertTrue(
            app.staticTexts["Make it yours"].firstMatch.isHittable,
            "the pitch collapsed: its headline is not on screen"
        )
        for title in ["Get Started", "Continue with Recharge+", "Restore", "Terms", "Privacy"] {
            let control = app.descendants(matching: .any).matching(identifier: title).firstMatch
            XCTAssertTrue(control.exists, "\(title) is missing from the offer")
            for _ in 0..<8 where !control.isHittable { app.swipeUp() }
            XCTAssertTrue(control.isHittable, "\(title) cannot be reached at the largest text size")
        }
        attach(app, named: "b4-offer-ax5-bottom")
    }

    /// The same page as a sheet, raised from the detail's upgrade card. The
    /// sheet carries its own Close button and the same terms and buttons.
    func testEveryControlOnTheOfferSheetIsReachableAtTheLargestTextSize() {
        let app = launch(scene: "recovering", contentSize: "UICTContentSizeCategoryAccessibilityXXXL")
        let hero = app.buttons["today.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        hero.tap()

        let teaser = app.buttons.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "Correct this session")
        ).firstMatch
        XCTAssertTrue(teaser.waitForExistence(timeout: 15), "the upgrade card is missing from the detail sheet")
        for _ in 0..<14 where !teaser.isHittable { app.swipeUp() }
        XCTAssertTrue(teaser.isHittable, "the upgrade card cannot be reached")
        teaser.tap()

        XCTAssertTrue(
            app.buttons["Continue with Recharge+"].firstMatch.waitForExistence(timeout: 10),
            "the offer sheet did not appear"
        )
        attach(app, named: "b4-offer-sheet-ax5-top")
        XCTAssertTrue(app.buttons["Close"].firstMatch.isHittable, "the sheet's Close button is not reachable")
        for title in ["Not now", "Continue with Recharge+", "Restore", "Terms", "Privacy"] {
            let control = app.descendants(matching: .any).matching(identifier: title).firstMatch
            XCTAssertTrue(control.exists, "\(title) is missing from the offer sheet")
            for _ in 0..<8 where !control.isHittable { app.swipeUp() }
            XCTAssertTrue(control.isHittable, "\(title) cannot be reached at the largest text size")
        }
        attach(app, named: "b4-offer-sheet-ax5-bottom")
    }

    // MARK: - B5: a purchase Apple holds as pending

    /// Ask to Buy: RevenueCat throws `paymentPendingError`, and the page has to
    /// say the purchase is pending, not that it failed. When the parent
    /// approves, the entitlement arrives on its own and the offer has to get out
    /// of the way of somebody who now has Recharge+.
    ///
    /// `RECHARGE_DEFER_PURCHASE=1` makes the simulator purchase throw exactly
    /// what RevenueCat throws and grant the entitlement four seconds later, the
    /// way `PurchasesDelegate` delivers an approval.
    func testAnAskToBuyPurchaseSaysPendingAndTheOfferClosesOnApproval() {
        let app = launch(scene: "onboarding", environment: ["RECHARGE_DEFER_PURCHASE": "1"])
        XCTAssertTrue(app.buttons["Continue"].waitForExistence(timeout: 20))
        advanceToTheOffer(app)
        let cta = app.buttons["Continue with Recharge+"].firstMatch
        XCTAssertTrue(cta.waitForExistence(timeout: 10))
        tapWhenHittable(cta, in: app)

        let pending = app.staticTexts.containing(
            NSPredicate(format: "label CONTAINS[c] %@", "pending")
        ).firstMatch
        XCTAssertTrue(pending.waitForExistence(timeout: 4), "a pending purchase was not reported as pending")
        attach(app, named: "b5-pending")
        XCTAssertFalse(
            app.staticTexts.containing(NSPredicate(format: "label BEGINSWITH[c] %@", "Couldn't")).firstMatch.exists,
            "a pending purchase was reported as a failure"
        )

        XCTAssertTrue(
            app.buttons["Today"].firstMatch.waitForExistence(timeout: 15),
            "the offer stayed up after the purchase was approved"
        )
        attach(app, named: "b5-approved")
    }

    // MARK: - B11: a widget tap with a sheet open

    /// The widget opens `recharge://today`. With Settings up, the tap used to
    /// switch the tab underneath and leave Settings in front of the answer.
    func testAWidgetTapClosesSettingsToShowToday() {
        let app = launch(scene: "recovering")
        let gear = app.buttons["Settings"].firstMatch
        XCTAssertTrue(gear.waitForExistence(timeout: 15))
        gear.tap()
        XCTAssertTrue(app.navigationBars["Settings"].waitForExistence(timeout: 15))

        // Through the system, as a widget tap arrives: the running app gets the
        // URL in `onOpenURL` with its state intact. `XCUIApplication.open`
        // brought the app back without the sheet and proved nothing.
        XCUIDevice.shared.system.open(URL(string: "recharge://today")!)
        // iOS may ask before a URL opens an app. Answer it if it does.
        let springboard = XCUIApplication(bundleIdentifier: "com.apple.springboard")
        let open = springboard.buttons["Open"]
        if open.waitForExistence(timeout: 3) { open.tap() }

        let closed = expectation(
            for: NSPredicate(format: "exists == false"),
            evaluatedWith: app.navigationBars["Settings"]
        )
        wait(for: [closed], timeout: 8)
        XCTAssertTrue(app.buttons["today.hero"].isHittable, "Today is not in front after the widget tap")
        attach(app, named: "b11-after-widget-tap")
    }
}
