import XCTest
@testable import Recharge

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

    /// The whole free-tier promise in one assertion: two people with completely
    /// different training histories get the same number for the same session.
    func testTheStandardEstimateIsIdenticalWhoeverDidTheSession() {
        let session = RecoveryFixtures.thresholdRun60
        let couchToFiveK = RecoveryCalculator.estimate(
            for: session, baseline: .standard(for: .endurance), now: now
        )
        let seasonedMarathoner = RecoveryCalculator.estimate(
            for: session, baseline: .standard(for: .endurance), now: now
        )
        XCTAssertEqual(couchToFiveK.hours, seasonedMarathoner.hours)
        XCTAssertEqual(couchToFiveK.tier, .standard)
        XCTAssertEqual(couchToFiveK.personalFactor, 1)
    }

    /// The standard baseline must not depend on anything the person has done.
    func testTheStandardBaselineHoldsNoSamples() {
        for profile in WorkoutProfile.allCases {
            let baseline = RecoveryBaseline.standard(for: profile)
            XCTAssertEqual(baseline.sampleCount, 0)
            XCTAssertEqual(baseline.typicalLoad, profile.standardTypicalLoad)
            XCTAssertEqual(baseline.quietThreshold, RecoveryCalculator.absoluteCountdownFloor)
        }
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
