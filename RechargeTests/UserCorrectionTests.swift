import XCTest

/// The two things the user is allowed to tell the model, and the one property
/// both of them have to satisfy: **the countdown has to move.**
///
/// Both were reported the same way, from real use. A profile picker that turned
/// a walk into an endurance session left the ring exactly where it was, because
/// the load came from the same sensors either way; and the standard figure and
/// the Recharge+ figure sat 23h and 8h apart with a "-6%" underneath them,
/// because the one term the app printed was the smallest of the three that
/// separated them. A control that appears to do nothing and an explanation that
/// contradicts the screen are the same failure with different symptoms.
final class UserCorrectionTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func baseline(_ profile: WorkoutProfile) -> RecoveryBaseline {
        RecoveryBaseline.standard(for: profile, fitnessScale: 1)
    }

    private func estimate(
        _ session: SessionInput,
        tier: RecoveryPersonalization = .standard,
        manualHours: Double? = nil
    ) -> RecoveryEstimate {
        RecoveryCalculator.estimate(
            for: session,
            baseline: baseline(session.profile),
            personalization: tier,
            manualHours: manualHours,
            now: now
        )
    }

    // MARK: - Intensity overrides

    /// The whole report: a walk marked Hard has to start a countdown.
    ///
    /// `easy` is the only profile whose window multiplier is zero, so without
    /// the promotion in `SessionIntensity.profile(promoting:)` the load changes,
    /// the cost changes, and the ring stays at Ready — which reads as the app
    /// having ignored the tap.
    func testAWalkMarkedHardStartsACountdown() {
        let asRecorded = RecoveryFixtures.easyWalk30
        XCTAssertFalse(estimate(asRecorded).producesCountdown)

        let promoted = SessionIntensity.hard.profile(promoting: .easy)
        XCTAssertEqual(promoted, .endurance, "a walk marked hard must leave the easy curve")

        let corrected = RecoveryFixtures.session(
            id: asRecorded.id, profile: promoted, minutes: 30,
            averageHR: 92, coverage: 0.95, energy: 110,
            intensity: .hard, label: "walk"
        )
        XCTAssertTrue(
            estimate(corrected).producesCountdown,
            "marking a walk hard changed the label and left the countdown alone"
        )
    }

    /// And back again, or the control is one-way.
    func testAnEnduranceSessionMarkedLightStopsProducingACountdown() {
        let run = RecoveryFixtures.thresholdRun60
        XCTAssertTrue(estimate(run).producesCountdown)

        XCTAssertEqual(SessionIntensity.light.profile(promoting: .endurance), .easy)
        let corrected = RecoveryFixtures.session(
            id: run.id, profile: .easy, minutes: 60,
            averageHR: 165, coverage: 0.98, energy: 680,
            intensity: .light, label: "run"
        )
        XCTAssertFalse(estimate(corrected).producesCountdown)
    }

    /// A lift and a ride keep their own curve. The override is a statement about
    /// effort, not about what kind of work it was.
    func testTheOverrideNeverChangesWhatKindOfSessionItWas() {
        for profile in [WorkoutProfile.endurance, .strength, .mixed] {
            for intensity in [SessionIntensity.moderate, .hard] {
                XCTAssertEqual(intensity.profile(promoting: profile), profile)
            }
        }
        XCTAssertEqual(SessionIntensity.light.profile(promoting: .strength), .strength)
        XCTAssertEqual(SessionIntensity.light.profile(promoting: .mixed), .mixed)
    }

    /// Monotone in the three bands, which is what makes moving the control
    /// change the number in the direction the label promises.
    func testTheThreeBandsAreMonotone() {
        let hours = SessionIntensity.allCases.map { intensity -> Double in
            let session = RecoveryFixtures.session(
                id: "run-\(intensity.rawValue)", profile: .endurance, minutes: 60,
                averageHR: 150, coverage: 0.95, energy: 600,
                intensity: intensity, label: "run"
            )
            return estimate(session).recoveryCostHours
        }
        XCTAssertLessThan(hours[0], hours[1], "light must not cost more than moderate")
        XCTAssertLessThan(hours[1], hours[2], "moderate must not cost more than hard")
    }

    /// **The override outranks every sensor, including a clean heart-rate
    /// trace.** Every other input is a reading or an inference from one, and the
    /// reason somebody reaches for this control is that those were wrong.
    func testTheOverrideOutranksACleanHeartRateTrace() {
        let measured = RecoveryFixtures.thresholdRun60
        XCTAssertEqual(estimate(measured).load.source, .heartRate)

        let corrected = RecoveryFixtures.session(
            id: measured.id, profile: .endurance, minutes: 60,
            averageHR: 165, coverage: 0.98, energy: 680,
            intensity: .light, label: "run"
        )
        let load = SessionLoadCalculator.profiledLoad(for: corrected)
        XCTAssertEqual(load.source, .reportedEffort)
        XCTAssertLessThan(
            load.value,
            SessionLoadCalculator.profiledLoad(for: measured).value,
            "a clean heart-rate trace outbid the user's own answer"
        )
    }

    /// Strength takes the maximum across four sources, so it is the profile most
    /// likely to swallow a correction. It must not.
    func testTheOverrideOutranksTheStrengthMaximum() {
        let lift = RecoveryFixtures.session(
            id: "lift", profile: .strength, minutes: 60,
            averageHR: 150, coverage: 0.9, energy: 700, effort: 9, label: "lifting session"
        )
        let corrected = RecoveryFixtures.session(
            id: "lift", profile: .strength, minutes: 60,
            averageHR: 150, coverage: 0.9, energy: 700, effort: 9,
            intensity: .light, label: "lifting session"
        )
        XCTAssertLessThan(
            SessionLoadCalculator.profiledLoad(for: corrected).value,
            SessionLoadCalculator.profiledLoad(for: lift).value
        )
    }

    /// A session the user has already rated by hand must not then be asked about.
    func testAnOverriddenSessionStopsAskingForAnEffortRating() {
        let record = WorkoutRecord(
            healthKitUUID: "lift", activityCode: 20,
            startDate: now.addingTimeInterval(-3600), endDate: now,
            durationMinutes: 60, activeEnergy: 300,
            loadSource: .energy, profile: .strength
        )
        XCTAssertTrue(record.wantsEffortInput)
        record.intensityOverride = .hard
        XCTAssertFalse(record.wantsEffortInput)
        XCTAssertEqual(record.effectiveProfile, .strength)
    }

    // MARK: - Pinned windows

    /// A pinned band replaces the modelled window outright.
    func testAPinnedBandReplacesTheModelledWindow() {
        let run = RecoveryFixtures.thresholdRun60
        let modelled = estimate(run, tier: .personalized(factor: 1))
        let pinned = estimate(run, tier: .personalized(factor: 1), manualHours: 30)

        XCTAssertNotEqual(modelled.hours, 30, accuracy: 0.01)
        XCTAssertEqual(pinned.hours, 30, accuracy: 0.01)
        XCTAssertEqual(
            pinned.readyAt.timeIntervalSince(run.endDate) / 3600, 30, accuracy: 0.01,
            "the countdown has to end where the pinned window says"
        )
    }

    /// **Never on the free tier.** Its one claim is that the figure came from
    /// the user's own training, and a typed number is not that.
    func testAPinnedBandNeverReachesTheStandardTier() {
        let run = RecoveryFixtures.thresholdRun60
        XCTAssertEqual(
            estimate(run, manualHours: 30).hours,
            estimate(run).hours,
            accuracy: 0.01
        )
    }

    /// History and the countdown must agree. A pinned window that moved the ring
    /// and left the row printing the model's own figure is the same
    /// contradiction `carriedHours` was fixed for.
    func testThePinnedWindowIsAlsoWhatHistoryReports() {
        let pinned = estimate(RecoveryFixtures.thresholdRun60, tier: .personalized(factor: 1), manualHours: 30)
        XCTAssertEqual(pinned.recoveryCostHours, pinned.hours, accuracy: 0.01)
    }

    /// The same bounds every other window obeys, so a pinned figure cannot put
    /// the app outside the range its own copy describes.
    func testPinnedHoursAreBoundedByTheModelsOwnFloorAndCeiling() {
        var windows = ManualRecoveryWindows()
        windows.set(1, for: .light)
        windows.set(500, for: .hard)
        XCTAssertEqual(windows.hours(for: .light), RecoveryCalculator.minimumCountdownHours)
        XCTAssertEqual(windows.hours(for: .hard), RecoveryCalculator.maximumHours)
        XCTAssertNil(windows.hours(for: .moderate))

        windows.set(.nan, for: .moderate)
        XCTAssertNil(windows.hours(for: .moderate), "a non-finite figure must never reach a countdown")
    }

    func testAnUnpinnedBandIsTheModelsAnswerRatherThanZero() {
        let run = RecoveryFixtures.thresholdRun60
        let windows = ManualRecoveryWindows(hard: 30)
        let unpinned = estimate(
            run,
            tier: .personalized(factor: 1),
            manualHours: windows.hours(for: .light)
        )
        XCTAssertGreaterThan(unpinned.hours, 0)
        XCTAssertTrue(ManualRecoveryWindows.empty.isEmpty)
        XCTAssertEqual(windows.pinned.count, 1)
    }

    /// The pinned figure has to be explained where the number is, or it looks
    /// like the model produced it.
    func testAPinnedWindowSaysSoInTheReasons() {
        let pinned = estimate(RecoveryFixtures.thresholdRun60, tier: .personalized(factor: 1), manualHours: 30)
        XCTAssertTrue(
            pinned.reasons.contains { $0.contains("pinned") },
            "a pinned window never told the user it was theirs: \(pinned.reasons)"
        )
    }

    func testAnOverriddenSessionSaysSoInTheReasons() {
        let corrected = RecoveryFixtures.session(
            id: "run", profile: .endurance, minutes: 60,
            averageHR: 150, coverage: 0.95, intensity: .hard, label: "run"
        )
        XCTAssertTrue(
            estimate(corrected).reasons.contains { $0.contains("marked this session hard") },
            "the correction is invisible in the explanation"
        )
    }

    // MARK: - The readiness question

    /// Onboarding imports a hundred and twenty days at once, so every countdown
    /// in that history has already expired by the time the user reaches Today.
    /// Asking how one of them felt is asking about something they never saw.
    func testTheReadinessQuestionIsNotAskedAboutACountdownFromBeforeSetup() {
        let old = RecoveryEstimate(
            sessionID: "before-install",
            profile: .endurance,
            activityLabel: "run",
            calculatedAt: now,
            sessionEnd: now.addingTimeInterval(-40 * 3600),
            readyAt: now.addingTimeInterval(-16 * 3600),
            hours: 24,
            windowLowHours: 20,
            windowHighHours: 28,
            load: SessionLoad(value: 120, source: .heartRate, heartRateCoverage: 0.9),
            relativeLoad: 1.6,
            category: .hard,
            confidence: .high,
            reasons: []
        )

        XCTAssertNotNil(
            RecoveryResolver.awaitingFeedback(in: [old], answered: [], now: now),
            "the unbounded behaviour every earlier test assumes must survive"
        )
        XCTAssertNil(
            RecoveryResolver.awaitingFeedback(
                in: [old], answered: [], eligibleFrom: now.addingTimeInterval(-3600), now: now
            ),
            "a brand-new user was asked how a session they did before installing felt"
        )
        XCTAssertNotNil(
            RecoveryResolver.awaitingFeedback(
                in: [old], answered: [], eligibleFrom: now.addingTimeInterval(-48 * 3600), now: now
            ),
            "a countdown the user did watch expire must still be asked about"
        )
    }
}
