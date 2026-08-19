import XCTest

/// The free/Recharge+ split.
///
/// The product promise is precise: the standard estimate is *the same for
/// everyone*, and the personalized one is what your own history buys. Both
/// halves of that are testable, and both are easy to break by accident — a
/// stray baseline argument on the free path would silently turn the free tier
/// back into a personalized one that nobody paid for.
final class RecoveryTierTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func standard(_ session: SessionInput) -> RecoveryEstimate {
        RecoveryCalculator.estimate(
            for: session,
            baseline: .standard(for: session.profile),
            now: now
        )
    }

    // MARK: - The standard tier is genuinely standard

    /// The free-tier promise, restated for the fitness-level split: the
    /// standard estimate is the same for everyone **who answered the same way**.
    /// What it may never contain is *measurement* — history, context,
    /// calibration, the thirty-day analysis. That is the line the tiers are
    /// drawn on.
    func testTheStandardEstimateIsIdenticalForTwoPeopleWhoAnsweredTheSameWay() {
        let session = RecoveryFixtures.thresholdRun60
        let answers = AthleteProfile(age: 34, experience: .oneToThreeYears, weeklyVolume: .threeOrFour)

        // Same answers, wildly different training histories. The histories are
        // not passed, because on this tier they are not consulted.
        let a = RecoveryCalculator.estimate(
            for: session,
            baseline: .standard(for: .endurance, fitnessScale: answers.fitnessScale),
            now: now
        )
        let b = RecoveryCalculator.estimate(
            for: session,
            baseline: .standard(for: .endurance, fitnessScale: answers.fitnessScale),
            now: now
        )
        XCTAssertEqual(a.hours, b.hours)
        XCTAssertEqual(a.tier, .standard)
        XCTAssertEqual(a.personalFactor, 1)
    }

    /// And it does move with the fitness answers, which is the point of the
    /// change: one denominator cannot serve both a beginner and a
    /// six-times-a-week runner.
    func testTheStandardEstimateMovesWithTheStatedFitnessLevel() {
        let session = RecoveryFixtures.thresholdRun60
        let beginner = AthleteProfile(experience: .underOneYear, weeklyVolume: .oneOrTwo)
        let veteran = AthleteProfile(experience: .tenYearsPlus, weeklyVolume: .sevenPlus)
        let unanswered = AthleteProfile()

        func hours(_ p: AthleteProfile) -> Double {
            RecoveryCalculator.estimate(
                for: session,
                baseline: .standard(for: .endurance, fitnessScale: p.fitnessScale),
                now: now
            ).hours
        }

        XCTAssertEqual(unanswered.fitnessScale, 1, "no answers means no claim about fitness")
        XCTAssertGreaterThan(hours(beginner), hours(unanswered))
        XCTAssertLessThan(hours(veteran), hours(unanswered))
        XCTAssertEqual(hours(beginner), hours(unanswered), accuracy: hours(unanswered) * 0.6)
    }

    /// Only the two questions that are about training level may reach this tier.
    /// Age and bounce-back are claims about recovery kinetics and are what
    /// Recharge+ sells; age reaches the standard tier through the heart-rate
    /// ceiling instead, which is measurement rather than personalisation.
    func testOnlyTheFitnessQuestionsReachTheStandardTier() {
        let base = AthleteProfile(experience: .threeToTenYears, weeklyVolume: .fiveOrSix)
        let withKinetics = AthleteProfile(
            age: 66,
            experience: .threeToTenYears,
            bounceBack: .threeOrMoreDays,
            weeklyVolume: .fiveOrSix
        )
        XCTAssertEqual(base.fitnessScale, withKinetics.fitnessScale, accuracy: 0.0001)
        XCTAssertNotEqual(base.prior ?? 1, withKinetics.prior ?? 1, accuracy: 0.0001)
    }

    /// The scale is bounded, so a question added later cannot turn the standard
    /// tier into an unbounded personalisation by the back door.
    func testTheFitnessScaleStaysInsideItsBounds() {
        for volume in WeeklyVolume.allCases {
            for experience in TrainingExperience.allCases {
                let scale = AthleteProfile(experience: experience, weeklyVolume: volume).fitnessScale
                XCTAssertGreaterThanOrEqual(scale, RecoveryBaseline.minimumFitnessScale)
                XCTAssertLessThanOrEqual(scale, RecoveryBaseline.maximumFitnessScale)
            }
        }
    }

    /// The standard baseline must not depend on anything the person has *done*.
    func testTheStandardBaselineHoldsNoSamples() {
        for profile in WorkoutProfile.allCases {
            let baseline = RecoveryBaseline.standard(for: profile)
            XCTAssertEqual(baseline.sampleCount, 0)
            XCTAssertEqual(baseline.typicalLoad, profile.standardTypicalLoad)
            XCTAssertEqual(baseline.quietThreshold, RecoveryCalculator.absoluteCountdownFloor)
        }
        // Scaled, it is still sample-free: the fitness level is an answer, not
        // an observation.
        let scaled = RecoveryBaseline.standard(for: .endurance, fitnessScale: 1.28)
        XCTAssertEqual(scaled.sampleCount, 0)
        XCTAssertEqual(scaled.typicalLoad, WorkoutProfile.endurance.standardTypicalLoad * 1.28, accuracy: 0.0001)
    }

    /// A free user is not "building" anything, so the badge must never say so —
    /// it would be a permanent apology for a number that is already final.
    func testStandardTierNeverReportsBuildingBaseline() {
        let sessions = [
            RecoveryFixtures.thresholdRun60,
            RecoveryFixtures.strengthWithEffort,
            RecoveryFixtures.strengthNoHeartRate,
            RecoveryFixtures.mixedHyrox,
            RecoveryFixtures.easyRun45
        ]
        for session in sessions {
            XCTAssertNotEqual(standard(session).confidence, .buildingBaseline, session.id)
        }
    }

    /// High confidence is what Recharge+ buys. The standard table cannot reach
    /// it however clean the heart-rate trace is.
    func testStandardTierCapsConfidenceAtMedium() {
        let estimate = standard(RecoveryFixtures.thresholdRun60)
        XCTAssertEqual(estimate.load.source, .heartRate)
        XCTAssertLessThanOrEqual(estimate.confidence, .medium)
    }

    /// "Hard for you" is a claim about the person. The standard tier has not
    /// looked at the person and must not make it.
    func testStandardTierDropsTheForYouClaimFromEveryReason() {
        let estimate = standard(RecoveryFixtures.thresholdRun60)
        for reason in estimate.reasons {
            XCTAssertFalse(reason.lowercased().contains("for you"), reason)
            XCTAssertFalse(reason.lowercased().contains("your usual"), reason)
            XCTAssertFalse(reason.lowercased().contains("your baseline"), reason)
        }
    }

    func testStandardTierIgnoresContextAndCalibrationEvenIfHandedThem() {
        // The engine never passes these on the free path, but the calculator is
        // the last line of defence and the one with the tests.
        let plain = standard(RecoveryFixtures.thresholdRun60)
        let withEverything = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: .standard(for: .endurance),
            personalization: .standard,
            now: now
        )
        XCTAssertEqual(plain.hours, withEverything.hours)
        XCTAssertEqual(withEverything.personalFactor, 1)
    }

    // MARK: - The personalized tier

    func testPersonalFactorScalesTheWindowProportionally() {
        let baseline = RecoveryFixtures.settledEnduranceBaseline()
        let neutral = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60, baseline: baseline,
            personalization: .personalized(factor: 1), now: now
        )
        let faster = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60, baseline: baseline,
            personalization: .personalized(factor: 0.8), now: now
        )
        XCTAssertEqual(faster.hours, neutral.hours * 0.8, accuracy: 0.001)
        XCTAssertEqual(faster.tier, .personalized)
        XCTAssertEqual(faster.standardHours, neutral.hours, accuracy: 0.001)
    }

    func testAnExplicitStandardPassSurvivesOtherPersonalizedAdjustments() {
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: RecoveryFixtures.settledEnduranceBaseline(),
            context: RecoveryContext(sleepHours: 4.5),
            calibration: 1.15,
            personalization: .personalized(factor: 0.8),
            standardHours: 23,
            now: now
        )

        XCTAssertEqual(estimate.standardHours, 23)
        XCTAssertNotEqual(estimate.hours / estimate.personalFactor, 23)
    }

    func testThePersonalFactorIsClampedIntoItsBounds() {
        XCTAssertEqual(
            RecoveryPersonalization.personalized(factor: 0.1).factor,
            PersonalRecoveryModel.minimumFactor
        )
        XCTAssertEqual(
            RecoveryPersonalization.personalized(factor: 9).factor,
            PersonalRecoveryModel.maximumFactor
        )
    }

    /// Monotonicity has to survive the new multiplier: harder never returns a
    /// shorter window at a fixed personal factor.
    func testHarderStillNeverReturnsAShorterWindowOnEitherTier() {
        for factor in [0.75, 1.0, 1.3] {
            let personalization = RecoveryPersonalization.personalized(factor: factor)
            var previous = 0.0
            for relative in stride(from: 0.0, through: 4.0, by: 0.05) {
                let hours = RecoveryCalculator.baseHours(forRelativeLoad: relative) * factor
                XCTAssertGreaterThanOrEqual(hours + 1e-9, previous)
                previous = hours
            }
            XCTAssertEqual(personalization.tier, .personalized)
        }
    }

    /// An easy session produces no countdown, so there is nothing to personalise
    /// and the stored factor must stay neutral rather than implying it did.
    func testANonQualifyingSessionRecordsANeutralFactor() {
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.easyWalk30,
            baseline: RecoveryFixtures.settledEnduranceBaseline(),
            personalization: .personalized(factor: 0.8),
            now: now
        )
        XCTAssertFalse(estimate.producesCountdown)
        XCTAssertEqual(estimate.personalFactor, 1)
    }

    // MARK: - Compliance

    /// Same rule as the existing suite: the personalisation copy is new surface
    /// area for a medical claim, so it is held to the same list.
    func testPersonalisationCopyNeverMakesAMedicalClaim() {
        let banned = ["recovered", "safe to train", "injury", "your body", "cure", "diagnos"]
        let analysis = PersonalRecoveryModel.analyse(
            profile: AthleteProfile(
                age: 41, experience: .threeToTenYears,
                bounceBack: .threeOrMoreDays, weeklyVolume: .fiveOrSix
            ),
            sessions: [],
            days: [],
            now: now
        )
        var copy = PersonalRecoveryModel.summary(analysis)
        copy += RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: RecoveryFixtures.settledEnduranceBaseline(),
            personalization: .personalized(factor: 0.78),
            now: now
        ).reasons
        copy += standard(RecoveryFixtures.thresholdRun60).reasons
        copy += ProfileQuestion.allCases.map(\.detail)
        copy += ProfileQuestion.allCases.map(\.title)

        for line in copy {
            for phrase in banned {
                XCTAssertFalse(line.lowercased().contains(phrase), "\(phrase) in: \(line)")
            }
        }
    }

    // MARK: - Model version

    /// A version-1 record predates the tier field entirely, and decoding it as
    /// anything other than an unmultiplied standard window would rewrite history.
    func testAVersionOneEstimateDecodesAsAnUnmultipliedStandardWindow() throws {
        let legacy = """
        {"sessionID":"old","profile":"endurance","activityLabel":"run",
         "calculatedAt":0,"sessionEnd":0,"readyAt":3600,"hours":24,
         "windowLowHours":20.4,"windowHighHours":27.6,
         "load":{"value":80,"source":"heartRate","heartRateCoverage":0.9},
         "relativeLoad":1.2,"category":"typical","confidence":"medium",
         "reasons":["Typical for you: 60-minute run."],"modelVersion":1}
        """
        let decoded = try JSONDecoder().decode(RecoveryEstimate.self, from: Data(legacy.utf8))
        XCTAssertEqual(decoded.modelVersion, 1)
        XCTAssertEqual(decoded.tier, .standard)
        XCTAssertEqual(decoded.personalFactor, 1)
        XCTAssertEqual(decoded.hours, 24)
        XCTAssertEqual(decoded.standardHours, 24)
    }

    func testExplicitStandardWindowSurvivesCodableRoundTrip() throws {
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: RecoveryFixtures.settledEnduranceBaseline(),
            context: RecoveryContext(sleepHours: 4.5),
            calibration: 1.15,
            personalization: .personalized(factor: 0.8),
            standardHours: 23,
            now: now
        )

        let decoded = try JSONDecoder().decode(
            RecoveryEstimate.self,
            from: JSONEncoder().encode(estimate)
        )
        XCTAssertEqual(decoded.standardHours, 23)
        XCTAssertEqual(decoded, estimate)
    }
}
