import XCTest

final class RemoteConfigTests: XCTestCase {

    // MARK: - The reader

    func testAMissingKeyIsTheControl() {
        XCTAssertEqual(TrialCTA.from(metadata: nil), .control)
        XCTAssertEqual(TrialCTA.from(metadata: [:]), .control)
    }

    func testANonStringValueIsTheControl() {
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": 7]), .control)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": true]), .control)
    }

    func testAnUnknownValueIsTheControl() {
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "my"]), .control)
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": ""]), .control)
    }

    func testTheKnownValueIsRead() {
        XCTAssertEqual(TrialCTA.metadataKey, "trial_cta")
        XCTAssertEqual(TrialCTA.from(metadata: ["trial_cta": "seven_day"]), .control)
        XCTAssertEqual(TrialCTA.control.rawValue, "seven_day")
    }

    // MARK: - The wording

    func testTheControlIsExactlyTodaysButton() {
        // Character for character what the onboarding trial page, the trial
        // sheet and the paywall showed before the reader existed.
        XCTAssertEqual(TrialCTA.control.title(trialEligible: true), "Continue with Recharge+")
        XCTAssertEqual(
            RechargeConversionCopy.ctaLabel(trial: nil, priceLabel: "$29.99 / year", eligibleForTrial: true),
            "Continue with Recharge+"
        )
    }

    func testAnAccountThatUsedItsTrialIsPromisedNoTrial() {
        let title = TrialCTA.control.title(trialEligible: false)
        XCTAssertEqual(title, "Continue with Recharge+")
        XCTAssertFalse(title.localizedCaseInsensitiveContains("free"))
        XCTAssertFalse(title.localizedCaseInsensitiveContains("trial"))
    }

    // MARK: - The switch

    func testTheRatingSwitchIsOnByDefault() {
        XCTAssertEqual(RemoteSwitch.ratingPrompt.rawValue, "rating_prompt")
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: nil))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: [:]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "on"]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": 0]))
        XCTAssertTrue(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "OFF"]))
    }

    func testTheRatingSwitchIsOffOnlyForOff() {
        XCTAssertFalse(RemoteConfig.isOn(.ratingPrompt, in: ["rating_prompt": "off"]))
    }
}
