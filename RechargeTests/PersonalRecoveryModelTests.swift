import XCTest

/// The thirty-day analysis: the part of Recharge+ that has to be more than a
/// number with a nice label on it.
///
/// The tests are organised the way the model is: each signal on its own with
/// the others held out, then the blend, then the bounds.
final class PersonalRecoveryModelTests: XCTestCase {

    private let now = RecoveryFixtures.now

    // MARK: - Builders

    private func session(
        daysAgo: Double,
        profile: WorkoutProfile = .endurance,
        load: Double = 80,
        intensity: Double? = 0.62,
        standardHours: Double = 24,
        id: String? = nil
    ) -> PersonalRecoveryModel.HistorySession {
        PersonalRecoveryModel.HistorySession(
            id: id ?? "s-\(daysAgo)",
            profile: profile,
            endDate: now.addingTimeInterval(-daysAgo * 86_400),
            load: load,
            intensityFraction: intensity,
            standardHours: standardHours
        )
    }

    /// A flat month of overnight readings at baseline, which every rebound test
    /// then perturbs around its own sessions.
    ///
    /// `hrv` defaults to nil so a test that perturbs only resting heart rate
    /// measures only that channel. Leaving HRV present and flat is not a neutral
    /// choice: an HRV that never moved after a hard session is real evidence of
    /// a fast response, and it would be averaged into the answer.
    private func flatDays(restingHeartRate: Double? = 52, hrv: Double? = nil) -> [PersonalRecoveryModel.DayPoint] {
        (0...30).map { offset in
            PersonalRecoveryModel.DayPoint(
                date: now.addingTimeInterval(-Double(offset) * 86_400),
                restingHeartRate: restingHeartRate,
                heartRateVariability: hrv
            )
        }
    }

    private func setHRV(
        _ days: [PersonalRecoveryModel.DayPoint],
        daysAgo: Double,
        to value: Double
    ) -> [PersonalRecoveryModel.DayPoint] {
        let key = DateHelpers.dayKey(for: now.addingTimeInterval(-daysAgo * 86_400))
        return days.map { point in
            guard DateHelpers.dayKey(for: point.date) == key else { return point }
            return PersonalRecoveryModel.DayPoint(
                date: point.date,
                restingHeartRate: point.restingHeartRate,
                heartRateVariability: value
            )
        }
    }

    private func setResting(
        _ days: [PersonalRecoveryModel.DayPoint],
        daysAgo: Double,
        to value: Double
    ) -> [PersonalRecoveryModel.DayPoint] {
        let key = DateHelpers.dayKey(for: now.addingTimeInterval(-daysAgo * 86_400))
        return days.map { point in
            guard DateHelpers.dayKey(for: point.date) == key else { return point }
            return PersonalRecoveryModel.DayPoint(
                date: point.date,
                restingHeartRate: value,
                heartRateVariability: point.heartRateVariability
            )
        }
    }

    // MARK: - No input at all

    func testNothingKnownIsExactlyNeutral() {
        let analysis = PersonalRecoveryModel.analyse(
            profile: .empty, sessions: [], days: [], now: now
        )
        XCTAssertEqual(analysis.factor, 1)
        XCTAssertNil(analysis.prior)
        XCTAssertFalse(analysis.isPersonalised)
        XCTAssertTrue(PersonalRecoveryModel.summary(analysis).isEmpty)
    }

    // MARK: - The questionnaire prior

    /// The day-one case: a Recharge+ user with no history yet still gets a
    /// number that came from their answers, because that is the whole reason
    /// onboarding asks.
    func testTheQuestionnaireAloneMovesTheFactor() {
        let fastResponder = PersonalRecoveryModel.analyse(
            profile: AthleteProfile(
                age: 24, experience: .threeToTenYears,
                bounceBack: .nextDay, weeklyVolume: .sevenPlus
            ),
            sessions: [], days: [], now: now
        )
        let slowResponder = PersonalRecoveryModel.analyse(
            profile: AthleteProfile(
                age: 58, experience: .underOneYear,
                bounceBack: .threeOrMoreDays, weeklyVolume: .oneOrTwo
            ),
            sessions: [], days: [], now: now
        )
        XCTAssertLessThan(fastResponder.factor, 0.95)
        XCTAssertGreaterThan(slowResponder.factor, 1.05)
        XCTAssertEqual(fastResponder.evidenceWeight, 0)
    }

    /// Four mild multipliers must combine into one mild multiplier. A product
    /// would compound 1.08 x 1.16 x 1.07 x 1.18 into 1.58, which is a different
    /// model wearing the same constants.
    func testThePriorIsAGeometricMeanRatherThanAProduct() {
        let profile = AthleteProfile(
            age: 58, experience: .underOneYear,
            bounceBack: .threeOrMoreDays, weeklyVolume: .oneOrTwo
        )
        let prior = try? XCTUnwrap(profile.prior)
        XCTAssertNotNil(prior)
        XCTAssertLessThan(prior ?? 99, 1.20)
        XCTAssertGreaterThan(prior ?? 0, 1.05)
    }

    func testAnEmptyProfileHasNoPriorAtAll() {
        XCTAssertNil(AthleteProfile.empty.prior)
        XCTAssertFalse(AthleteProfile.empty.isUsable)
    }

    // MARK: - Signal 1: rebound

    /// Resting heart rate spikes the day after every hard session and is back to
    /// baseline the day after that. That is a fast responder, and the model has
    /// to say so.
    func testFullyNormalisedByDayTwoReadsAsAFastResponder() {
        let sessionDays: [Double] = [4, 9, 14, 19]
        var days = flatDays()
        for day in sessionDays {
            days = setResting(days, daysAgo: day - 1, to: 58)
        }
        let sessions = sessionDays.map { session(daysAgo: $0) }
        let rebound = PersonalRecoveryModel.reboundEvidence(sessions: sessions, days: days)

        XCTAssertEqual(rebound.samples, sessionDays.count)
        let factor = try? XCTUnwrap(rebound.factor)
        XCTAssertNotNil(factor)
        XCTAssertLessThan(factor ?? 99, 0.90)
    }

    /// The same spike, still there on day two. Slow responder.
    func testAPersistentDisturbanceReadsAsASlowResponder() {
        let sessionDays: [Double] = [4, 9, 14, 19]
        var days = flatDays()
        for day in sessionDays {
            days = setResting(days, daysAgo: day - 1, to: 58)
            days = setResting(days, daysAgo: day - 2, to: 58)
        }
        let sessions = sessionDays.map { session(daysAgo: $0) }
        let rebound = PersonalRecoveryModel.reboundEvidence(sessions: sessions, days: days)

        let factor = try? XCTUnwrap(rebound.factor)
        XCTAssertNotNil(factor)
        XCTAssertGreaterThan(factor ?? 0, 1.25)
    }

    func testContextDaysOutsideTheAnalysisWindowDoNotAffectTheResult() {
        let sessionDays: [Double] = [4, 9, 14, 19]
        var recentDays = flatDays()
        for day in sessionDays {
            recentDays = setResting(recentDays, daysAgo: day - 1, to: 58)
            recentDays = setResting(recentDays, daysAgo: day - 2, to: 58)
        }
        let sessions = sessionDays.map { session(daysAgo: $0) }
        let oldOutlier = PersonalRecoveryModel.DayPoint(
            date: now.addingTimeInterval(-40 * 86_400),
            restingHeartRate: 500,
            heartRateVariability: 0
        )

        let withoutOldData = PersonalRecoveryModel.analyse(
            profile: .empty, sessions: sessions, days: recentDays, now: now
        )
        let withOldData = PersonalRecoveryModel.analyse(
            profile: .empty, sessions: sessions, days: recentDays + [oldOutlier], now: now
        )

        XCTAssertEqual(withOldData.factor, withoutOldData.factor, accuracy: 0.0001)
        XCTAssertEqual(withOldData.reboundSamples, withoutOldData.reboundSamples)
    }

    /// Resting heart rate and HRV are two views of the same night, so a session
    /// with both available is scored on their average rather than on whichever
    /// one happens to be listed first.
    func testTheTwoOvernightChannelsAreAveraged() {
        let sessionDays: [Double] = [4, 9, 14, 19]
        var days = flatDays(restingHeartRate: 52, hrv: 60)
        for day in sessionDays {
            // Resting heart rate stays elevated through day two; HRV is back to
            // baseline by day one. One slow channel, one fast.
            days = setResting(days, daysAgo: day - 1, to: 58)
            days = setResting(days, daysAgo: day - 2, to: 58)
            days = setHRV(days, daysAgo: day - 1, to: 60)
            days = setHRV(days, daysAgo: day - 2, to: 60)
        }
        let sessions = sessionDays.map { session(daysAgo: $0) }
        let mixed = PersonalRecoveryModel.reboundEvidence(sessions: sessions, days: days)

        // Ratio 1 on resting, ratio 0 on HRV, so the mean ratio is 0.5.
        XCTAssertEqual(mixed.factor ?? 0, 0.85 + 0.45 * 0.5, accuracy: 0.001)
    }

    /// Two or three sessions is not a pattern. Below the minimum the signal has
    /// to abstain rather than guess.
    func testReboundAbstainsBelowItsSampleMinimum() {
        var days = flatDays()
        days = setResting(days, daysAgo: 3, to: 58)
        let rebound = PersonalRecoveryModel.reboundEvidence(
            sessions: [session(daysAgo: 4), session(daysAgo: 9)], days: days
        )
        XCTAssertNil(rebound.factor)
    }

    /// A reading that never moved must not be divided into. Sensor noise on a
    /// baseline day would otherwise be amplified into a recovery verdict.
    func testANonExistentDisturbanceIsTreatedAsACompleteResponse() {
        XCTAssertEqual(PersonalRecoveryModel.normalisationRatio(day1: 0.002, day2: 0.001), 0)
        XCTAssertEqual(PersonalRecoveryModel.normalisationRatio(day1: -0.05, day2: 0.04), 0)
        XCTAssertEqual(PersonalRecoveryModel.normalisationRatio(day1: 0.10, day2: 0.05), 0.5, accuracy: 0.001)
        // Still worse on day two than day one: capped, not extrapolated.
        XCTAssertEqual(PersonalRecoveryModel.normalisationRatio(day1: 0.05, day2: 0.20), 1)
    }

    // MARK: - Signal 2: tolerance

    /// Training inside the window and holding the usual intensity is the
    /// strongest evidence a wrist can produce that the window was too long.
    func testHoldingIntensityInsideTheWindowReadsAsFastRecovery() {
        // Sessions 18 hours apart against a 30-hour standard window, all at the
        // person's usual intensity.
        let sessions = (0..<5).map { index in
            session(
                daysAgo: 20 - Double(index) * 0.75,
                intensity: 0.62,
                standardHours: 30,
                id: "held-\(index)"
            )
        }
        let tolerance = PersonalRecoveryModel.toleranceEvidence(sessions: sessions)
        let factor = try? XCTUnwrap(tolerance.factor)
        XCTAssertNotNil(factor)
        XCTAssertLessThan(factor ?? 99, 0.95)
    }

    /// The same cadence, but every follow-up session comes in well under the
    /// usual intensity. That is the window being right, not wrong.
    func testFadingIntensityInsideTheWindowReadsAsSlowRecovery() {
        var sessions = [session(daysAgo: 20, intensity: 0.70, standardHours: 30, id: "anchor-0")]
        sessions += (1..<5).map { index in
            session(
                daysAgo: 20 - Double(index) * 0.75,
                intensity: index.isMultiple(of: 2) ? 0.70 : 0.48,
                standardHours: 30,
                id: "faded-\(index)"
            )
        }
        let tolerance = PersonalRecoveryModel.toleranceEvidence(sessions: sessions)
        let factor = try? XCTUnwrap(tolerance.factor)
        XCTAssertNotNil(factor)
        XCTAssertGreaterThan(factor ?? 0, 1.0)
    }

    /// Sessions spaced beyond the window say nothing about tolerance: holding
    /// intensity after a full rest is unremarkable.
    func testSessionsOutsideTheWindowContributeNothing() {
        let sessions = (0..<6).map { index in
            session(daysAgo: 25 - Double(index) * 3, standardHours: 24, id: "rested-\(index)")
        }
        XCTAssertNil(PersonalRecoveryModel.toleranceEvidence(sessions: sessions).factor)
    }

    /// A session that merely happened early proves nothing without a quality
    /// measurement. People train tired.
    func testSessionsWithoutAnIntensityMeasurementAreIgnored() {
        let sessions = (0..<6).map { index in
            session(
                daysAgo: 20 - Double(index) * 0.5,
                intensity: nil,
                standardHours: 30,
                id: "unmeasured-\(index)"
            )
        }
        XCTAssertNil(PersonalRecoveryModel.toleranceEvidence(sessions: sessions).factor)
    }

    // MARK: - Signal 3: density

    func testDensityIsSymmetricOnTheLogScale() {
        let reference = PersonalRecoveryModel.referenceWeeklyLoad
        let double = try? XCTUnwrap(PersonalRecoveryModel.densityFactor(weeklyLoad: reference * 2))
        let half = try? XCTUnwrap(PersonalRecoveryModel.densityFactor(weeklyLoad: reference / 2))
        let same = try? XCTUnwrap(PersonalRecoveryModel.densityFactor(weeklyLoad: reference))
        XCTAssertEqual(same ?? 0, 1.0, accuracy: 0.001)
        XCTAssertEqual(double ?? 0, 0.90, accuracy: 0.001)
        XCTAssertEqual(half ?? 0, 1.10, accuracy: 0.001)
    }

    func testDensityIsBoundedForExtremeVolumes() {
        XCTAssertEqual(PersonalRecoveryModel.densityFactor(weeklyLoad: 20_000), 0.90)
        XCTAssertEqual(PersonalRecoveryModel.densityFactor(weeklyLoad: 1), 1.10)
        XCTAssertNil(PersonalRecoveryModel.densityFactor(weeklyLoad: 0))
    }

    // MARK: - The blend

    /// Evidence must move the answer away from the prior, and must never fully
    /// replace it: the prior carries age, which nothing in the history observes.
    func testEvidenceMovesTheAnswerWithoutEverReplacingThePrior() {
        let slowPrior = AthleteProfile(
            age: 55, experience: .underOneYear,
            bounceBack: .threeOrMoreDays, weeklyVolume: .oneOrTwo
        )
        // A month of fast, clean rebounds contradicting that prior.
        let sessionDays = stride(from: 3.0, through: 27.0, by: 3.0).map { $0 }
        var days = flatDays()
        for day in sessionDays { days = setResting(days, daysAgo: day - 1, to: 59) }
        let sessions = sessionDays.map { session(daysAgo: $0) }

        let priorOnly = PersonalRecoveryModel.analyse(
            profile: slowPrior, sessions: [], days: [], now: now
        )
        let withEvidence = PersonalRecoveryModel.analyse(
            profile: slowPrior, sessions: sessions, days: days, now: now
        )

        XCTAssertLessThan(withEvidence.factor, priorOnly.factor)
        XCTAssertGreaterThan(withEvidence.evidenceWeight, 0)
        XCTAssertLessThanOrEqual(withEvidence.evidenceWeight, PersonalRecoveryModel.maximumEvidenceWeight)
        // Not fully replaced: still above what the evidence alone would give.
        XCTAssertGreaterThan(withEvidence.factor, 0.85)
    }

    func testEvidenceWeightGrowsWithTheAmountOfEvidence() {
        let profile = AthleteProfile(age: 35, experience: .oneToThreeYears)
        func weight(sessionCount: Int) -> Double {
            let sessionDays = (0..<sessionCount).map { 3.0 + Double($0) * 2 }
            var days = flatDays()
            for day in sessionDays { days = setResting(days, daysAgo: day - 1, to: 58) }
            return PersonalRecoveryModel.analyse(
                profile: profile,
                sessions: sessionDays.map { session(daysAgo: $0) },
                days: days,
                now: now
            ).evidenceWeight
        }
        XCTAssertLessThan(weight(sessionCount: 4), weight(sessionCount: 12))
    }

    // MARK: - Bounds

    /// Whatever the signals say, the answer stays inside a range three
    /// observations can support.
    func testTheFactorIsAlwaysInsideItsBounds() {
        let extremes = [
            AthleteProfile(age: 95, experience: .underOneYear, bounceBack: .threeOrMoreDays, weeklyVolume: .oneOrTwo),
            AthleteProfile(age: 12, experience: .tenYearsPlus, bounceBack: .nextDay, weeklyVolume: .sevenPlus)
        ]
        for profile in extremes {
            let analysis = PersonalRecoveryModel.analyse(
                profile: profile, sessions: [], days: [], now: now
            )
            XCTAssertGreaterThanOrEqual(analysis.factor, PersonalRecoveryModel.minimumFactor)
            XCTAssertLessThanOrEqual(analysis.factor, PersonalRecoveryModel.maximumFactor)
        }
    }

    /// Sessions older than the window must not vote.
    func testOnlyTheLastThirtyDaysCount() {
        let ancient = (0..<20).map { session(daysAgo: 40 + Double($0), id: "old-\($0)") }
        let analysis = PersonalRecoveryModel.analyse(
            profile: .empty, sessions: ancient, days: flatDays(), now: now
        )
        XCTAssertEqual(analysis.qualifyingSessions, 0)
        XCTAssertEqual(analysis.factor, 1)
    }

    /// Active recovery is not training, and must not inflate weekly volume into
    /// a claim that the person is adapted to more work than they are.
    func testEasySessionsAreExcludedFromTheWindow() {
        let analysis = PersonalRecoveryModel.analyse(
            profile: .empty,
            sessions: (0..<10).map { session(daysAgo: Double($0) + 1, profile: .easy, id: "walk-\($0)") },
            days: flatDays(),
            now: now
        )
        XCTAssertEqual(analysis.qualifyingSessions, 0)
    }

    // MARK: - Health-derived profile

    func testMaximumHeartRateUsesTheSexSpecificFormula() {
        let woman = AthleteProfile(age: 40, sex: .female)
        let man = AthleteProfile(age: 40, sex: .male)
        // Gulati: 206 - 0.88 x 40 = 170.8 -> 171.
        XCTAssertEqual(woman.predictedMaxHeartRate, 171)
        // Tanaka: 208 - 0.7 x 40 = 180.
        XCTAssertEqual(man.predictedMaxHeartRate, 180)
        XCTAssertNil(AthleteProfile(age: nil).predictedMaxHeartRate)
    }

    /// The gap list is the contract between Health and onboarding: anything
    /// Health answered must drop out of it.
    func testOnlyUnansweredQuestionsAreAsked() {
        XCTAssertEqual(AthleteProfile.empty.gaps, [.age, .experience, .weeklyVolume, .bounceBack])

        let healthKnowsAgeAndVolume = AthleteProfile(
            age: 33,
            weeklyVolume: .fiveOrSix,
            healthDerivedFields: [AthleteProfile.ageField, AthleteProfile.weeklyVolumeField]
        )
        XCTAssertEqual(healthKnowsAgeAndVolume.gaps, [.experience, .bounceBack])

        let complete = AthleteProfile(
            age: 33, experience: .threeToTenYears,
            bounceBack: .aboutTwoDays, weeklyVolume: .fiveOrSix
        )
        XCTAssertTrue(complete.gaps.isEmpty)
    }

    func testWeeklyVolumeBucketsAtTheStatedBoundaries() {
        XCTAssertEqual(WeeklyVolume.forSessionsPerWeek(1.0), .oneOrTwo)
        XCTAssertEqual(WeeklyVolume.forSessionsPerWeek(2.4), .oneOrTwo)
        XCTAssertEqual(WeeklyVolume.forSessionsPerWeek(3.0), .threeOrFour)
        XCTAssertEqual(WeeklyVolume.forSessionsPerWeek(5.0), .fiveOrSix)
        XCTAssertEqual(WeeklyVolume.forSessionsPerWeek(8.0), .sevenPlus)
    }
}
