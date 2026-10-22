import XCTest

/// Evidence for the larger-text / one-handed-reach persona audit.
///
/// These tests photograph and measure rather than judge. Failures are recorded
/// but do not stop the walk, so one clipped screen does not hide the next.
@MainActor
final class AccessibilityAuditUITests: XCTestCase {
    private static let xxxl = "UICTContentSizeCategoryAccessibilityExtraExtraExtraLarge"
    private static let ax1 = "UICTContentSizeCategoryAccessibilityMedium"

    private var notes: [String] = []

    override func setUp() {
        continueAfterFailure = true
        notes = []
    }

    override func tearDown() {
        let attachment = XCTAttachment(string: notes.joined(separator: "\n"))
        attachment.name = "measurements"
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func launch(scene: String, size: String? = nil) -> XCUIApplication {
        let app = XCUIApplication()
        app.launchEnvironment["RECHARGE_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["RECHARGE_SCREENSHOT_SCENE"] = scene
        if let size { app.launchArguments += ["-UIPreferredContentSizeCategoryName", size] }
        app.launch()
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String) {
        let attachment = XCTAttachment(screenshot: app.screenshot())
        attachment.name = name
        attachment.lifetime = .keepAlways
        add(attachment)
    }

    private func measure(_ label: String, _ element: XCUIElement, in app: XCUIApplication) {
        guard element.exists else { notes.append("\(label): MISSING"); return }
        let f = element.frame
        let screen = app.frame
        let visible = f.intersects(screen)
        notes.append(String(
            format: "%@: x=%.0f y=%.0f w=%.0f h=%.0f hittable=%@ onscreen=%@ (screen %.0fx%.0f)",
            label, f.minX, f.minY, f.width, f.height,
            element.isHittable ? "yes" : "no", visible ? "yes" : "no", screen.width, screen.height
        ))
    }

    private func settle(_ app: XCUIApplication) {
        _ = app.buttons["Today"].firstMatch.waitForExistence(timeout: 20)
        sleep(2)
    }

    // MARK: - Today

    func testTodayAtDefaultSizeTargets() {
        let app = launch(scene: "recovering")
        settle(app)
        attach(app, "today-default")
        measure("gear", app.buttons["Settings"], in: app)
        measure("hero", app.buttons["today.hero"], in: app)
        for tab in ["Today", "History", "Upgrade"] {
            measure("tab-\(tab)", app.buttons[tab].firstMatch, in: app)
        }
    }

    func testTodayAtLargestTextSize() {
        for scene in ["recovering", "ready", "premiumActive", "stale"] {
            let app = launch(scene: scene, size: Self.xxxl)
            settle(app)
            attach(app, "today-\(scene)-xxxl-1")
            measure("\(scene) gear", app.buttons["Settings"], in: app)
            measure("\(scene) hero", app.buttons["today.hero"], in: app)
            for tab in ["Today", "History", "Upgrade", "Recharge+"] {
                measure("\(scene) tab-\(tab)", app.buttons[tab].firstMatch, in: app)
            }
            app.swipeUp()
            attach(app, "today-\(scene)-xxxl-2")
            app.swipeUp()
            attach(app, "today-\(scene)-xxxl-3")
            app.terminate()
        }
    }

    func testTodayAtFirstAccessibilitySize() {
        let app = launch(scene: "recovering", size: Self.ax1)
        settle(app)
        attach(app, "today-ax1")
        measure("gear", app.buttons["Settings"], in: app)
        measure("hero", app.buttons["today.hero"], in: app)
    }

    func testExplanationSheetAtLargestTextSize() {
        let app = launch(scene: "recovering", size: Self.xxxl)
        settle(app)
        let hero = app.buttons["today.hero"]
        XCTAssertTrue(hero.waitForExistence(timeout: 15))
        hero.tap()
        sleep(2)
        for index in 1...5 {
            attach(app, "detail-xxxl-\(index)")
            measure("detail Done", app.buttons["Done"].firstMatch, in: app)
            app.swipeUp()
        }
    }

    // MARK: - History, Settings, Recharge+

    func testHistoryAtLargestTextSize() {
        let app = launch(scene: "history", size: Self.xxxl)
        sleep(4)
        attach(app, "history-xxxl-1")
        app.swipeUp()
        attach(app, "history-xxxl-2")
        app.swipeUp()
        attach(app, "history-xxxl-3")
    }

    func testHistoryAtDefaultSizeTargets() {
        let app = launch(scene: "history")
        sleep(4)
        attach(app, "history-default")
        let rows = app.buttons.matching(NSPredicate(format: "label CONTAINS[c] %@", "h"))
        for index in 0..<min(rows.count, 6) {
            measure("history row \(index) \(rows.element(boundBy: index).label.prefix(30))", rows.element(boundBy: index), in: app)
        }
    }

    func testSettingsAtLargestTextSize() {
        let app = launch(scene: "settings", size: Self.xxxl)
        sleep(4)
        for index in 1...10 {
            attach(app, "settings-xxxl-\(index)")
            app.swipeUp()
        }
    }

    func testPlusTabAtLargestTextSize() {
        let app = launch(scene: "premiumActive", size: Self.xxxl)
        settle(app)
        let tab = app.buttons["Recharge+"].firstMatch
        XCTAssertTrue(tab.waitForExistence(timeout: 10))
        tab.tap()
        sleep(2)
        for index in 1...4 {
            attach(app, "plus-xxxl-\(index)")
            app.swipeUp()
        }
    }

    func testPaywallAtLargestTextSize() {
        let app = launch(scene: "paywall", size: Self.xxxl)
        sleep(5)
        attach(app, "paywall-xxxl-1")
        measure("paywall cta", app.buttons["paywall-cta"].firstMatch, in: app)
        measure("paywall close", app.buttons["Close"].firstMatch, in: app)
        for index in 2...5 {
            app.swipeUp()
            attach(app, "paywall-xxxl-\(index)")
        }
    }

    // MARK: - Onboarding

    func testOnboardingAtLargestTextSize() {
        let app = launch(scene: "onboarding", size: Self.xxxl)
        sleep(3)
        let primaries = ["Continue", "Skip this one", "I understand"]
        for index in 1...10 {
            attach(app, String(format: "onboarding-xxxl-%02d", index))
            guard let next = primaries.map({ app.buttons[$0].firstMatch }).first(where: { $0.exists }) else { break }
            measure("onboarding \(index) primary", next, in: app)
            guard next.isHittable else { break }
            next.tap()
            sleep(1)
        }
    }

    func testOnboardingAtDefaultSizeFirstPage() {
        let app = launch(scene: "onboarding")
        sleep(3)
        attach(app, "onboarding-default-01")
        measure("primary", app.buttons["Continue"].firstMatch, in: app)
    }
}
