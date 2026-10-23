import XCTest

/// A skeptical free user working out what is paid, what the paid half is worth,
/// and how to get back out: restore, lapse, cancel. Screenshots for a person to
/// read; assertions only keep the walk honest.
///
/// Simulator purchases flip a local override (no RevenueCat, no customer), so
/// "buy" and "lapse" here are the app's own local Pro switch.
@MainActor
final class SubscriptionAuditUITests: XCTestCase {

    override func setUp() {
        continueAfterFailure = true
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(scene: String, contentSize: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RECHARGE_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["RECHARGE_SCREENSHOT_SCENE"] = scene
        if let contentSize {
            app.launchArguments += ["-UIPreferredContentSizeCategoryName", contentSize]
        }
        app.launch()
        return app
    }

    private func settle(_ seconds: TimeInterval = 0.8) {
        Thread.sleep(forTimeInterval: seconds)
    }

    private func log(_ name: String, _ app: XCUIApplication) {
        let screen = app.windows.firstMatch.frame
        let buttons = app.buttons.allElementsBoundByIndex
            .filter { $0.exists && $0.isHittable && screen.intersects($0.frame) }
            .map(\.label)
        let texts = app.staticTexts.allElementsBoundByIndex.prefix(60).map(\.label)
        let attachment = XCTAttachment(string: "buttons=\(buttons)\ntexts=\(texts)")
        attachment.name = "\(name)-elements"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func button(_ app: XCUIApplication, containing text: String) -> XCUIElement {
        app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", text)).firstMatch
    }

    /// Scrolls until the element is on screen, up to `tries` swipes.
    @discardableResult
    private func scrollTo(_ element: XCUIElement, in app: XCUIApplication, tries: Int = 10) -> Bool {
        for _ in 0..<tries {
            if element.exists, element.isHittable { return true }
            app.swipeUp()
            settle(0.4)
        }
        return element.exists && element.isHittable
    }

    private func scrollShots(_ app: XCUIApplication, _ prefix: String, count: Int) {
        for index in 1...count {
            app.swipeUp()
            settle(0.5)
            attach(app, "\(prefix)-scroll-\(index)")
        }
    }

    // MARK: - Free user: what is locked, what does the offer say

    func testFreeUserWhatIsPaid() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 30))
        settle(1.5)
        attach(app, "free-01-today")
        log("free-01-today", app)

        // The locked card.
        let card = button(app, containing: "Your own recharge time")
        XCTAssertTrue(card.waitForExistence(timeout: 5), "no locked card on Today")
        if scrollTo(card, in: app) {
            attach(app, "free-02-locked-card")
            card.tap()
            settle(2)
            attach(app, "free-03-after-card-tap")
            log("free-03-after-card-tap", app)
            scrollShots(app, "free-03", count: 2)
            // Anything on the offer that leads to all plans.
            let plans = button(app, containing: "plans")
            if plans.exists, plans.isHittable {
                plans.tap()
                settle(2)
                attach(app, "free-04-all-plans")
                log("free-04-all-plans", app)
            }
            // Dismiss whichever sheet is up.
            for label in ["Close", "Not now", "Done"] {
                let b = app.buttons[label].firstMatch
                if b.exists, b.isHittable { b.tap(); settle(1); break }
            }
            if app.buttons["today.hero"].exists == false { app.swipeDown(); settle(1) }
            attach(app, "free-05-after-dismiss")
        }

        // The Upgrade tab (the full paywall).
        let upgrade = app.buttons["Upgrade"]
        XCTAssertTrue(upgrade.waitForExistence(timeout: 5))
        upgrade.tap()
        settle(2.5)
        attach(app, "free-06-upgrade-tab")
        log("free-06-upgrade-tab", app)
        scrollShots(app, "free-06", count: 3)

        // Plan cards, then restore, as somebody deciding between them.
        for plan in ["Monthly", "Lifetime", "Yearly"] {
            let card = button(app, containing: plan)
            if card.exists {
                if !card.isHittable { app.swipeDown(); app.swipeDown(); settle(0.5) }
                if card.isHittable {
                    card.tap()
                    settle(0.6)
                    attach(app, "free-07-plan-\(plan.lowercased())")
                }
            }
        }
        let restore = app.buttons["Restore"].firstMatch
        if scrollTo(restore, in: app) {
            attach(app, "free-08-before-restore")
            restore.tap()
            settle(0.3)
            attach(app, "free-09-restore-immediately")
            settle(2)
            attach(app, "free-10-restore-result")
            log("free-10-restore-result", app)
            app.swipeDown(); app.swipeDown(); settle(0.5)
        }
    }

    func testFreeUserSettingsAndRestore() {
        let app = launch(scene: "recovering")
        XCTAssertTrue(app.buttons["today.hero"].waitForExistence(timeout: 30))
        settle(1.5)
        let gear = app.buttons["Settings"]
        XCTAssertTrue(gear.waitForExistence(timeout: 5))
        gear.tap()
        settle(2)
        attach(app, "set-01-top")
        log("set-01-top", app)

        // The paid row at the top of Settings.
        let proRow = button(app, containing: "Recharge+")
        if proRow.exists, proRow.isHittable {
            proRow.tap()
            settle(2.5)
            attach(app, "set-02-paywall-from-settings")
            let close = app.buttons["Close"].firstMatch
            if close.exists { close.tap(); settle(1) }
        }

        let restore = button(app, containing: "Restore purchases")
        XCTAssertTrue(scrollTo(restore, in: app, tries: 14), "Settings has no reachable Restore purchases")
        attach(app, "set-03-before-restore")
        restore.tap()
        settle(0.3)
        attach(app, "set-04-restore-immediately")
        settle(2.5)
        attach(app, "set-05-restore-result")
        log("set-05-restore-result", app)
        app.swipeUp(); settle(0.5)
        attach(app, "set-06-bottom")
        log("set-06-bottom", app)
    }

    // MARK: - Buying, then lapsing (the local Pro switch stands in for both)

    func testBuyThenLapse() {
        let app = launch(scene: "paywall")
        let cta = app.buttons["paywall-cta"]
        XCTAssertTrue(cta.waitForExistence(timeout: 30), "paywall scene never showed the CTA")
        settle(2)
        attach(app, "buy-01-paywall")
        log("buy-01-paywall", app)
        let disclosure = app.staticTexts["paywall-disclosure"]
        if disclosure.exists {
            let note = XCTAttachment(string: "disclosure=\(disclosure.label)")
            note.name = "buy-01-disclosure"
            note.lifetime = .keepAlways
            add(note)
        }
        cta.tap()
        settle(0.2)
        attach(app, "buy-02-tapped")
        settle(2.5)
        attach(app, "buy-03-after-purchase")
        log("buy-03-after-purchase", app)

        // Now a subscriber: where did the app put me, and what does it say.
        let plus = app.buttons["Recharge+"]
        if plus.waitForExistence(timeout: 5), plus.isHittable {
            plus.tap()
            settle(2)
            attach(app, "buy-04-plus-tab")
            log("buy-04-plus-tab", app)
        }

        // Lapse: the debug switch in Settings.
        let today = app.buttons["Today"]
        if today.exists { today.tap(); settle(1) }
        let gear = app.buttons["Settings"]
        if gear.waitForExistence(timeout: 5) {
            gear.tap()
            settle(2)
            attach(app, "buy-05-settings-as-subscriber")
            log("buy-05-settings-as-subscriber", app)
            let toggle = app.switches["Pro unlocked (local)"]
            if scrollTo(toggle, in: app, tries: 16) {
                attach(app, "buy-06-debug-toggle")
                toggle.tap()
                settle(2)
                attach(app, "buy-07-after-lapse-settings")
                app.swipeDown(); app.swipeDown(); app.swipeDown(); app.swipeDown(); settle(0.8)
                attach(app, "buy-08-after-lapse-settings-top")
                log("buy-08-after-lapse-settings-top", app)
            }
            let done = app.buttons["Done"].firstMatch
            if done.exists { done.tap(); settle(1.5) }
            attach(app, "buy-09-today-after-lapse")
            log("buy-09-today-after-lapse", app)
        }
    }

    // MARK: - Subscriber: account, restore, manage, cancel

    func testSubscriberAccountAndExit() {
        let app = launch(scene: "premiumActive")
        let plus = app.buttons["Recharge+"]
        XCTAssertTrue(plus.waitForExistence(timeout: 30))
        settle(1.5)
        attach(app, "sub-01-today")
        log("sub-01-today", app)
        plus.tap()
        settle(2)
        attach(app, "sub-02-plus-tab")
        log("sub-02-plus-tab", app)
        scrollShots(app, "sub-02", count: 3)

        let restore = button(app, containing: "Restore purchases")
        if scrollTo(restore, in: app) {
            attach(app, "sub-03-account-card")
            restore.tap()
            settle(0.3)
            attach(app, "sub-04-restore-immediately")
            settle(2.5)
            attach(app, "sub-05-restore-result")
            log("sub-05-restore-result", app)
            let ok = app.buttons["OK"].firstMatch
            if ok.exists { ok.tap(); settle(0.8) }
        }
        let manage = button(app, containing: "Manage subscription")
        let note = XCTAttachment(string: "manage-subscription exists=\(manage.exists) hittable=\(manage.isHittable)")
        note.name = "sub-06-manage"
        note.lifetime = .keepAlways
        add(note)

        // Where a subscriber looks to cancel: Settings.
        let today = app.buttons["Today"]
        if today.exists { today.tap(); settle(1) }
        let gear = app.buttons["Settings"]
        if gear.waitForExistence(timeout: 5) {
            gear.tap()
            settle(2)
            attach(app, "sub-07-settings-top")
            log("sub-07-settings-top", app)
            let manageInSettings = button(app, containing: "Manage")
            let cancelInSettings = button(app, containing: "ancel")
            let n = XCTAttachment(string: "settings manage exists=\(manageInSettings.exists) cancel exists=\(cancelInSettings.exists)")
            n.name = "sub-08-settings-manage-search"
            n.lifetime = .keepAlways
            add(n)
            let r = button(app, containing: "Restore purchases")
            if scrollTo(r, in: app, tries: 14) {
                attach(app, "sub-09-settings-about")
                r.tap()
                settle(2.5)
                attach(app, "sub-10-settings-restore-result")
                log("sub-10-settings-restore-result", app)
            }
        }
    }

    func testPaywallLargeText() {
        let app = launch(scene: "paywall", contentSize: "UICTContentSizeCategoryAccessibilityL")
        XCTAssertTrue(app.buttons["paywall-cta"].waitForExistence(timeout: 30))
        settle(2)
        attach(app, "large-01-paywall")
        scrollShots(app, "large-01", count: 3)
    }
}
