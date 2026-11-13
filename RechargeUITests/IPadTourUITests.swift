import XCTest

/// iPad screenshots of every main surface in portrait and landscape, for a
/// person to look at. Skips itself on iPhone. `gh-sim` cannot rotate a
/// simulator, so the rotation happens here, and the frames come back as the
/// run's attachments.
@MainActor
final class IPadTourUITests: XCTestCase {
    override func setUpWithError() throws {
        continueAfterFailure = true
        try XCTSkipUnless(UIDevice.current.userInterfaceIdiom == .pad, "iPad only")
    }

    private func launch(scene: String, landscape: Bool) -> XCUIApplication {
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        let app = XCUIApplication()
        app.launchEnvironment["RECHARGE_SCREENSHOT_MODE"] = "1"
        app.launchEnvironment["RECHARGE_SCREENSHOT_SCENE"] = scene
        app.launchEnvironment["TZ"] = "America/Los_Angeles"
        app.launch()
        XCUIDevice.shared.orientation = landscape ? .landscapeLeft : .portrait
        return app
    }

    private func attach(_ app: XCUIApplication, _ name: String, _ landscape: Bool) {
        let tag = "\(name)-\(landscape ? "land" : "port")"
        for (suffix, image) in [("app", app.screenshot()), ("screen", XCUIScreen.main.screenshot())] {
            let attachment = XCTAttachment(screenshot: image)
            attachment.name = "\(tag)-\(suffix)"
            attachment.lifetime = .keepAlways
            add(attachment)
        }
        let info = XCTAttachment(string: "\(tag) window=\(app.windows.firstMatch.frame) orientation=\(XCUIDevice.shared.orientation.rawValue)")
        info.name = "\(tag)-info"
        info.lifetime = .keepAlways
        add(info)
    }

    private func orientations(_ body: (Bool) -> Void) {
        for landscape in [false, true] { body(landscape) }
    }

    func testPremiumToday() {
        orientations { landscape in
            let app = launch(scene: "premiumActive", landscape: landscape)
            _ = app.buttons["today.hero"].waitForExistence(timeout: 20)
            sleep(2)
            attach(app, "premium-today", landscape)
            app.buttons["today.hero"].tap(); sleep(2)
            attach(app, "premium-detail", landscape)
            app.terminate()
        }
    }

    func testPremiumSettings() {
        orientations { landscape in
            let app = launch(scene: "premiumActive", landscape: landscape)
            _ = app.buttons["Settings"].waitForExistence(timeout: 20)
            app.buttons["Settings"].tap(); sleep(2)
            attach(app, "premium-settings", landscape)
            app.terminate()
        }
    }

    func testPremiumPlusTab() {
        orientations { landscape in
            let app = launch(scene: "premiumActive", landscape: landscape)
            _ = app.buttons["today.hero"].waitForExistence(timeout: 20)
            app.buttons["Recharge+"].firstMatch.tap(); sleep(2)
            attach(app, "premium-plus", landscape)
            app.terminate()
        }
    }

    func testFreeToday() {
        orientations { landscape in
            let app = launch(scene: "recovering", landscape: landscape)
            _ = app.buttons["today.hero"].waitForExistence(timeout: 20)
            sleep(2)
            attach(app, "free-today", landscape)
            app.buttons.matching(NSPredicate(format: "label CONTAINS %@", "recharge time")).firstMatch.tap(); sleep(3)
            attach(app, "free-trial-offer", landscape)
            app.terminate()
        }
    }

    func testFreePaywallTab() {
        orientations { landscape in
            let app = launch(scene: "recovering", landscape: landscape)
            _ = app.buttons["today.hero"].waitForExistence(timeout: 20)
            app.buttons["Upgrade"].firstMatch.tap(); sleep(3)
            attach(app, "free-paywall-tab", landscape)
            app.terminate()
        }
    }

    func testPaywallSheet() {
        orientations { landscape in
            let app = launch(scene: "paywall", landscape: landscape)
            sleep(5)
            attach(app, "paywall-sheet", landscape)
            app.terminate()
        }
    }

    func testReady() {
        orientations { landscape in
            let app = launch(scene: "ready", landscape: landscape)
            _ = app.buttons["today.hero"].waitForExistence(timeout: 20)
            sleep(2)
            attach(app, "ready-today", landscape)
            app.terminate()
        }
    }

    func testOnboarding() {
        orientations { landscape in
            let app = launch(scene: "onboarding", landscape: landscape)
            sleep(3)
            for index in 1...8 {
                attach(app, String(format: "onboarding-%02d", index), landscape)
                var tapped = false
                for title in ["Continue", "I understand", "Next"] where app.buttons[title].firstMatch.exists && app.buttons[title].firstMatch.isHittable {
                    app.buttons[title].firstMatch.tap(); tapped = true; break
                }
                if !tapped {
                    let option = app.buttons.element(boundBy: 2)
                    if option.exists { option.tap() }
                }
                sleep(1)
            }
            app.terminate()
        }
    }
}
