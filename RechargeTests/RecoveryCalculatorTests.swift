import XCTest

/// The contract from the build plan, asserted directly:
///
/// - monotonic **within** each profile (harder or longer never returns a shorter
///   window under equal context);
/// - easy / active recovery never extends an active countdown;
/// - every output inside the documented bounds;
/// - the same input at the same `modelVersion` always returns the same window.
final class RecoveryCalculatorTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func hours(
        _ session: SessionInput,
        baseline: RecoveryBaseline,
        context: RecoveryContext = .empty,
        calibration: Double = RecoveryCalibration.neutral
    ) -> Double {
        RecoveryCalculator.estimate(
            for: session,
            baseline: baseline,
            context: context,
            calibration: calibration,
            now: now
        ).hours
    }

    // MARK: - Bounds

    func testEveryFixtureStaysInsideDocumentedBounds() {
        let cases: [(SessionInput, RecoveryBaseline)] = [
            (RecoveryFixtures.easyWalk30, RecoveryFixtures.settledEnduranceBaseline()),
            (RecoveryFixtures.easyRun45, RecoveryFixtures.settledEnduranceBaseline()),
            (RecoveryFixtures.thresholdRun60, RecoveryFixtures.settledEnduranceBaseline()),
            (RecoveryFixtures.longRun90, RecoveryFixtures.settledEnduranceBaseline()),
            (RecoveryFixtures.ride45, RecoveryFixtures.settledEnduranceBaseline()),
            (RecoveryFixtures.strengthNoHeartRate, RecoveryFixtures.settledStrengthBaseline()),
            (RecoveryFixtures.strengthWithEffort, RecoveryFixtures.settledStrengthBaseline()),
            (RecoveryFixtures.mixedHyrox, RecoveryFixtures.settledMixedBaseline()),
            (RecoveryFixtures.easyRun45, RecoveryFixtures.emptyBaseline()),
            (RecoveryFixtures.thresholdRun60, RecoveryFixtures.thinBaseline())
        ]

        for (session, baseline) in cases {
            for context in [RecoveryFixtures.noContext, RecoveryFixtures.goodContext, RecoveryFixtures.poorContext] {
                let estimate = RecoveryCalculator.estimate(
                    for: session, baseline: baseline, context: context, now: now
                )
                XCTAssertGreaterThanOrEqual(estimate.hours, 0, "\(session.id) went negative")
                XCTAssertLessThanOrEqual(
                    estimate.hours,
                    RecoveryCalculator.maximumHours,
                    "\(session.id) exceeded the 72h ceiling"
                )
                XCTAssertLessThanOrEqual(estimate.windowLowHours, estimate.hours)
                XCTAssertGreaterThanOrEqual(estimate.windowHighHours, estimate.hours)
                XCTAssertEqual(estimate.modelVersion, recoveryModelVersion)
            }
        }
    }

    func testWindowNeverExceedsCeilingEvenForAnAbsurdSession() {
        let monster = RecoveryFixtures.session(
            id: "ultra", profile: .mixed, minutes: 600, averageHR: 175,
            coverage: 1.0, energy: 6000, effort: 10, label: "ultra"
        )
        let estimate = RecoveryCalculator.estimate(
            for: monster,
            baseline: RecoveryFixtures.settledMixedBaseline(),
            context: RecoveryFixtures.poorContext,
            calibration: RecoveryCalibration.maximum,
            now: now
        )
        XCTAssertEqual(estimate.hours, RecoveryCalculator.maximumHours, accuracy: 0.001)
        XCTAssertEqual(estimate.category, .unusuallyHard)
    }

    // MARK: - Monotonicity within a profile

    func testLongerEnduranceSessionNeverShortensTheWindow() {
        let baseline = RecoveryFixtures.settledEnduranceBaseline()
        var previous = -1.0
        for minutes in stride(from: 10.0, through: 180.0, by: 5.0) {
            let session = RecoveryFixtures.session(
                id: "run-\(minutes)", profile: .endurance, minutes: minutes,
                averageHR: 150, coverage: 0.95, label: "run"
            )
            let value = hours(session, baseline: baseline)
            XCTAssertGreaterThanOrEqual(
                value, previous,
                "\(minutes)min produced a shorter window than the step before it"
            )
            previous = value
        }
    }

    func testHarderEnduranceSessionNeverShortensTheWindow() {
        let baseline = RecoveryFixtures.settledEnduranceBaseline()
        var previous = -1.0
        for heartRate in stride(from: 100.0, through: 185.0, by: 5.0) {
            let session = RecoveryFixtures.session(
                id: "run-hr-\(heartRate)", profile: .endurance, minutes: 60,
                averageHR: heartRate, coverage: 0.95, label: "run"
            )
            let value = hours(session, baseline: baseline)
            XCTAssertGreaterThanOrEqual(
                value, previous,
                "avg HR \(heartRate) produced a shorter window than the step before it"
            )
            previous = value
        }
    }

    func testHigherReportedEffortNeverShortensTheStrengthWindow() {
        let baseline = RecoveryFixtures.settledStrengthBaseline()
        var previous = -1.0
        for effort in stride(from: 1.0, through: 10.0, by: 1.0) {
            let session = RecoveryFixtures.session(
                id: "lift-rpe-\(effort)", profile: .strength, minutes: 60,
                coverage: 0.1, effort: effort, label: "lifting session"
            )
            let value = hours(session, baseline: baseline)
            XCTAssertGreaterThanOrEqual(value, previous, "RPE \(effort) shortened the window")
            previous = value
        }
    }

    func testMonotonicWithinEveryProfile() {
        let cases: [(WorkoutProfile, RecoveryBaseline)] = [
            (.endurance, RecoveryFixtures.settledEnduranceBaseline()),
            (.strength, RecoveryFixtures.settledStrengthBaseline()),
            (.mixed, RecoveryFixtures.settledMixedBaseline())
        ]
        for (profile, baseline) in cases {
            var previous = -1.0
            for minutes in stride(from: 15.0, through: 150.0, by: 5.0) {
                let session = RecoveryFixtures.session(
                    id: "\(profile.rawValue)-\(minutes)", profile: profile, minutes: minutes,
                    averageHR: 155, coverage: 0.9, effort: 7
                )
                let value = hours(session, baseline: baseline)
                XCTAssertGreaterThanOrEqual(value, previous, "\(profile) broke monotonicity at \(minutes)min")
                previous = value
            }
        }
    }

    // MARK: - Profile ordering

    func testMixedProducesTheLongestWindowAtEqualLoad() {
        // Same underlying session, scored against each profile's own baseline
        // scaled to make relative load identical. This checks the shape
        // multiplier, not the baselines.
        let flatBaseline = { (profile: WorkoutProfile) in
            RecoveryBaseline(loads: Array(repeating: 100.0, count: 12), profile: profile)
        }
        func window(_ profile: WorkoutProfile) -> Double {
            let session = RecoveryFixtures.session(
                id: "equal-\(profile.rawValue)", profile: profile, minutes: 60,
                averageHR: 160, coverage: 0.95, effort: 7
            )
            return hours(session, baseline: flatBaseline(profile))
        }
        XCTAssertGreaterThan(window(.mixed), window(.strength))
        XCTAssertGreaterThan(window(.strength), window(.endurance))
    }

    // MARK: - Easy / active recovery

    func testEasyProfileNeverProducesACountdown() {
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.easyWalk30,
            baseline: RecoveryFixtures.settledEnduranceBaseline(),
            now: now
        )
        XCTAssertEqual(estimate.hours, 0)
        XCTAssertFalse(estimate.producesCountdown)
        XCTAssertEqual(estimate.phase(at: now), .ready)
    }

    func testEasySessionCannotShortenAnActiveCountdown() {
        let baseline = RecoveryFixtures.settledEnduranceBaseline()
        let hard = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60, baseline: baseline, now: now
        )
        XCTAssertTrue(hard.producesCountdown)

        // A walk finished an hour after the run — later session, zero window.
        let walk = RecoveryFixtures.session(
            id: "walk-after", profile: .easy, minutes: 30, endedMinutesAgo: -60,
            averageHR: 95, coverage: 0.95, energy: 110, label: "walk"
        )
        let easy = RecoveryCalculator.estimate(for: walk, baseline: baseline, now: now)

        let active = RecoveryResolver.active(in: [hard, easy], now: now)
        XCTAssertEqual(active?.sessionID, hard.sessionID)
        XCTAssertEqual(active?.readyAt, hard.readyAt)
    }

    func testShortWalkBelowTheFloorStartsNoCountdownEvenForANewUser() {
        let stroll = RecoveryFixtures.session(
            id: "stroll", profile: .endurance, minutes: 20, averageHR: 96,
            coverage: 0.9, energy: 70, label: "walk"
        )
        let estimate = RecoveryCalculator.estimate(
            for: stroll, baseline: RecoveryFixtures.emptyBaseline(), now: now
        )
        XCTAssertEqual(estimate.hours, 0, "a 20-minute stroll must never start a countdown")
    }

    // MARK: - Determinism

    func testSameInputAtSameModelVersionAlwaysReturnsTheSameWindow() {
        let baseline = RecoveryFixtures.settledMixedBaseline()
        let first = RecoveryCalculator.estimate(
            for: RecoveryFixtures.mixedHyrox,
            baseline: baseline,
            context: RecoveryFixtures.poorContext,
            calibration: 1.05,
            now: now
        )
        for _ in 0..<25 {
            let repeated = RecoveryCalculator.estimate(
                for: RecoveryFixtures.mixedHyrox,
                baseline: baseline,
                context: RecoveryFixtures.poorContext,
                calibration: 1.05,
                now: now
            )
            XCTAssertEqual(repeated, first)
        }
    }

    func testDuplicateImportsProduceIdenticalWindows() {
        let baseline = RecoveryFixtures.settledEnduranceBaseline()
        let a = RecoveryCalculator.estimate(for: RecoveryFixtures.duplicateA, baseline: baseline, now: now)
        let b = RecoveryCalculator.estimate(for: RecoveryFixtures.duplicateB, baseline: baseline, now: now)
        XCTAssertEqual(a.hours, b.hours)
        XCTAssertEqual(a.readyAt, b.readyAt)
        XCTAssertEqual(a.category, b.category)
    }

    func testOverlappingWorkoutsResolveToTheLaterReadyTime() {
        let baseline = RecoveryFixtures.settledEnduranceBaseline()
        let outer = RecoveryCalculator.estimate(for: RecoveryFixtures.overlappingOuter, baseline: baseline, now: now)
        let inner = RecoveryCalculator.estimate(for: RecoveryFixtures.overlappingInner, baseline: baseline, now: now)
        let active = RecoveryResolver.active(in: [inner, outer], now: now)
        XCTAssertEqual(active?.readyAt, max(outer.readyAt, inner.readyAt))
    }

    // MARK: - Context

    func testPoorContextLengthensAndGoodContextShortens() {
        let baseline = RecoveryFixtures.settledEnduranceBaseline()
        let session = RecoveryFixtures.thresholdRun60
        let neutral = hours(session, baseline: baseline, context: .empty)
        let poor = hours(session, baseline: baseline, context: RecoveryFixtures.poorContext)
        let good = hours(session, baseline: baseline, context: RecoveryFixtures.goodContext)

        XCTAssertGreaterThan(poor, neutral)
        XCTAssertLessThan(good, neutral)
    }

    func testContextCannotSwingTheEstimateBeyondItsBounds() {
        let extreme = RecoveryContext(
            sleepHours: 0.5,
            heartRateVariability: 5,
            heartRateVariabilityBaseline: 80,
            restingHeartRate: 95,
            restingHeartRateBaseline: 50
        )
        let adjustment = RecoveryCalculator.contextAdjustment(extreme)
        XCTAssertLessThanOrEqual(adjustment, RecoveryCalculator.maximumContextAdjustment)

        let generous = RecoveryContext(
            sleepHours: 11,
            heartRateVariability: 200,
            heartRateVariabilityBaseline: 60,
            restingHeartRate: 38,
            restingHeartRateBaseline: 55
        )
        XCTAssertGreaterThanOrEqual(
            RecoveryCalculator.contextAdjustment(generous),
            RecoveryCalculator.minimumContextAdjustment
        )
    }

    func testMissingSleepAndMissingHrvAreNeutral() {
        XCTAssertEqual(RecoveryCalculator.contextAdjustment(.empty), 0)
        XCTAssertEqual(RecoveryCalculator.contextAdjustment(RecoveryContext(sleepHours: 6.8)), 0)
    }

    // MARK: - Confidence

    /// Only the personalized tier has a baseline to build. The standard tier
    /// never reports it, which `testStandardTierNeverReportsBuildingBaseline`
    /// pins down.
    func testNewUserIsLabelledAsBuildingBaseline() {
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: RecoveryFixtures.emptyBaseline(),
            personalization: .personalized(factor: 1),
            now: now
        )
        XCTAssertEqual(estimate.confidence, .buildingBaseline)
    }

    func testStrengthWithoutHeartRateOrEffortIsLowConfidence() {
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.strengthNoHeartRate,
            baseline: RecoveryFixtures.settledStrengthBaseline(),
            context: RecoveryFixtures.goodContext,
            now: now
        )
        XCTAssertEqual(estimate.load.source, .energy)
        XCTAssertEqual(estimate.confidence, .low)
    }

    func testEffortInputRaisesConfidenceOnTheSameStrengthSession() {
        let baseline = RecoveryFixtures.settledStrengthBaseline()
        let without = RecoveryCalculator.estimate(
            for: RecoveryFixtures.strengthNoHeartRate, baseline: baseline,
            context: RecoveryFixtures.goodContext, now: now
        )
        let with = RecoveryCalculator.estimate(
            for: RecoveryFixtures.strengthWithEffort, baseline: baseline,
            context: RecoveryFixtures.goodContext, now: now
        )
        XCTAssertEqual(with.load.source, .reportedEffort)
        XCTAssertGreaterThan(with.confidence, without.confidence)
        XCTAssertGreaterThan(with.hours, without.hours, "an RPE 8 lift should outrank its own kcal estimate")
    }

    /// High confidence is what knowing the person buys, so it is reachable only
    /// on the personalized tier.
    func testGoodHeartRateCoverageAndFullContextIsHighConfidence() {
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: RecoveryFixtures.settledEnduranceBaseline(),
            context: RecoveryFixtures.goodContext,
            personalization: .personalized(factor: 1),
            now: now
        )
        XCTAssertEqual(estimate.confidence, .high)
    }

    // MARK: - Calibration

    func testFeltReadyShortensFutureWindowsAndNotReadyLengthensThem() {
        let baseline = RecoveryFixtures.settledEnduranceBaseline()
        let session = RecoveryFixtures.thresholdRun60
        let neutral = hours(session, baseline: baseline)
        let shortened = hours(session, baseline: baseline, calibration: RecoveryCalibration.minimum)
        let lengthened = hours(session, baseline: baseline, calibration: RecoveryCalibration.maximum)

        XCTAssertLessThan(shortened, neutral)
        XCTAssertGreaterThan(lengthened, neutral)
    }

    func testCalibrationFactorIsBoundedNoMatterHowManyAnswersArrive() {
        var factor = RecoveryCalibration.neutral
        for _ in 0..<50 { factor = RecoveryCalibration.apply(.notReady, to: factor) }
        XCTAssertEqual(factor, RecoveryCalibration.maximum, accuracy: 0.0001)

        for _ in 0..<100 { factor = RecoveryCalibration.apply(.feltReady, to: factor) }
        XCTAssertEqual(factor, RecoveryCalibration.minimum, accuracy: 0.0001)
    }

    func testOkayButNotFreshLeavesCalibrationAlone() {
        XCTAssertEqual(RecoveryCalibration.apply(.okayNotFresh, to: 1.07), 1.07, accuracy: 0.0001)
    }

    // MARK: - Categories

    func testCategoryBoundariesLineUpWithTheCurve() {
        XCTAssertEqual(RecoveryCalculator.category(forRelativeLoad: 0.1), .easy)
        XCTAssertEqual(RecoveryCalculator.category(forRelativeLoad: 0.7), .typical)
        XCTAssertEqual(RecoveryCalculator.category(forRelativeLoad: 1.6), .hard)
        XCTAssertEqual(RecoveryCalculator.category(forRelativeLoad: 2.4), .unusuallyHard)
    }

    func testTheHoursCurveIsContinuousAtEveryAnchor() {
        for anchor in RecoveryCalculator.curve {
            let below = RecoveryCalculator.baseHours(forRelativeLoad: anchor.relativeLoad - 0.0001)
            let at = RecoveryCalculator.baseHours(forRelativeLoad: anchor.relativeLoad)
            XCTAssertEqual(below, at, accuracy: 0.01, "curve jumps at r=\(anchor.relativeLoad)")
        }
    }

    // MARK: - Reasons

    func testReasonsNeverMakeAMedicalClaim() {
        let banned = ["recovered", "safe to train", "injury", "your body", "cure", "diagnos", "heal"]
        let baselines: [(SessionInput, RecoveryBaseline)] = [
            (RecoveryFixtures.easyWalk30, RecoveryFixtures.settledEnduranceBaseline()),
            (RecoveryFixtures.thresholdRun60, RecoveryFixtures.settledEnduranceBaseline()),
            (RecoveryFixtures.strengthWithEffort, RecoveryFixtures.settledStrengthBaseline()),
            (RecoveryFixtures.mixedHyrox, RecoveryFixtures.settledMixedBaseline()),
            (RecoveryFixtures.easyRun45, RecoveryFixtures.emptyBaseline())
        ]
        for (session, baseline) in baselines {
            for context in [RecoveryFixtures.noContext, RecoveryFixtures.goodContext, RecoveryFixtures.poorContext] {
                let estimate = RecoveryCalculator.estimate(
                    for: session, baseline: baseline, context: context, now: now
                )
                let text = estimate.reasons.joined(separator: " ").lowercased()
                for phrase in banned {
                    XCTAssertFalse(text.contains(phrase), "\"\(phrase)\" appeared in: \(text)")
                }
                XCTAssertFalse(estimate.reasons.isEmpty, "\(session.id) produced no explanation")
            }
        }
    }

    func testTheWhyLineNamesTheSessionThatSetTheWindow() {
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: RecoveryFixtures.settledEnduranceBaseline(),
            now: now
        )
        XCTAssertTrue(estimate.reasons.first?.contains("run") == true)
        XCTAssertTrue(estimate.reasons.first?.contains("60-minute") == true)
    }

    /// Garmin documents its recovery time as spanning "a minimum of 6 hours to a
    /// maximum of 4 days" (Edge 840 and fenix 7 owner's manuals). The floor is
    /// the half that matters: a session either earns a countdown or it does not,
    /// and one that earns a three-hour countdown at 6pm is Ready before bedtime,
    /// which reads as the app having ignored the workout.
    func testEveryQualifyingSessionClearsTheDocumentedSixHourFloor() {
        for profile in [WorkoutProfile.endurance, .strength, .mixed] {
            for minutes in stride(from: 10.0, through: 240.0, by: 10.0) {
                for reserve in stride(from: 0.2, through: 0.95, by: 0.05) {
                    let session = RecoveryFixtures.session(
                        id: "s", profile: profile, minutes: minutes,
                        averageHR: 52 + reserve * (188 - 52), coverage: 0.95
                    )
                    let estimate = RecoveryCalculator.estimate(
                        for: session, baseline: .standard(for: profile)
                    )
                    guard estimate.producesCountdown else { continue }
                    XCTAssertGreaterThanOrEqual(
                        estimate.hours, RecoveryCalculator.minimumCountdownHours - 0.001,
                        "\(profile) \(Int(minutes))min at \(Int(reserve * 100))% reserve"
                    )
                }
            }
        }
    }

    /// The floor must not flatten the curve: two sessions that differ in load
    /// still have to differ in hours once both are clear of it.
    func testTheFloorDoesNotFlattenTheCurveAboveIt() {
        func hours(_ reserve: Double) -> Double {
            RecoveryCalculator.estimate(
                for: RecoveryFixtures.session(
                    id: "s", profile: .endurance, minutes: 60,
                    averageHR: 52 + reserve * (188 - 52), coverage: 0.95
                ),
                baseline: .standard(for: .endurance)
            ).hours
        }
        var previous = 0.0
        for reserve in stride(from: 0.3, through: 0.95, by: 0.05) {
            let value = hours(reserve)
            XCTAssertGreaterThanOrEqual(value, previous, "hours fell at reserve \(reserve)")
            previous = value
        }
        XCTAssertGreaterThan(hours(0.85), hours(0.55), "the curve collapsed onto the floor")
    }
}
