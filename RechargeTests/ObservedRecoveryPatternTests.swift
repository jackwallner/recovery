import XCTest

/// The free tier's whole statistic: how long this person actually leaves
/// between sessions of comparable size.
final class ObservedRecoveryPatternTests: XCTestCase {

    private let now = RecoveryFixtures.now

    // MARK: - Helpers

    /// A session `daysAgo` days back, `minutes` long, at `load`.
    private func session(
        daysAgo: Double,
        minutes: Double = 60,
        load: Double,
        profile: WorkoutProfile = .endurance
    ) -> ObservedRecoveryPattern.Session {
        let end = now.addingTimeInterval(-daysAgo * 86_400)
        return ObservedRecoveryPattern.Session(
            profile: profile,
            startDate: end.addingTimeInterval(-minutes * 60),
            endDate: end,
            load: load
        )
    }

    /// Sessions every `everyDays` days at the same size, most recent last.
    private func regular(
        count: Int, everyDays: Double, load: Double, profile: WorkoutProfile = .endurance
    ) -> [ObservedRecoveryPattern.Session] {
        (0..<count).map { session(daysAgo: Double(count - $0) * everyDays, load: load, profile: profile) }
    }

    // MARK: - The gap itself

    /// The number is the median gap, and it is measured end of one session to
    /// start of the next, so the session's own hour is not counted as recovery.
    func testTheUsualGapIsTheMedianOfComparableGaps() {
        let pattern = ObservedRecoveryPattern.analyse(
            sessions: regular(count: 8, everyDays: 2, load: 80), now: now
        )
        let hours = pattern.usualGapHours(for: .moderate)
        XCTAssertNotNil(hours)
        // Two days apart, minus the 60 minutes the session itself ran.
        XCTAssertEqual(hours ?? 0, 47, accuracy: 0.5)
    }

    /// The rule the whole statistic turns on. A hard Monday, an easy Tuesday and
    /// a hard Wednesday is a 48-hour gap between the two efforts that matter;
    /// counting the walk would report that this person recovers in a day.
    func testALighterSessionInBetweenDoesNotEndTheGap() {
        var sessions: [ObservedRecoveryPattern.Session] = []
        for week in 0..<4 {
            let base = Double(week) * 7
            sessions.append(session(daysAgo: 30 - base, load: 100))
            sessions.append(session(daysAgo: 29 - base, load: 25))
            sessions.append(session(daysAgo: 28 - base, load: 100))
        }
        let pattern = ObservedRecoveryPattern.analyse(sessions: sessions, now: now)
        let hard = pattern.usualGapHours(for: .hard)
        XCTAssertNotNil(hard)
        XCTAssertGreaterThan(hard ?? 0, 36, "the walk in between is not evidence of going again")
    }

    /// An active-recovery session is neither something to recover from nor
    /// evidence of having recovered, on either side of a gap.
    func testEasySessionsAreExcludedEntirely() {
        let walks = (0..<10).map {
            session(daysAgo: Double(20 - $0), load: 20, profile: .easy)
        }
        XCTAssertFalse(ObservedRecoveryPattern.analyse(sessions: walks, now: now).hasEvidence)
    }

    /// A fortnight off is a holiday, an injury, or a phone left at home. It is
    /// not a recovery time, and letting it into a median would move the number
    /// for months.
    func testAGapLongerThanTheCapIsNotCounted() {
        var sessions = regular(count: 6, everyDays: 2, load: 80)
        sessions.append(session(daysAgo: 40, load: 80))
        let pattern = ObservedRecoveryPattern.analyse(sessions: sessions, now: now)
        XCTAssertEqual(pattern.pooled?.sampleCount, 5, "the 30-day gap must not be a sample")
    }

    /// Fewer than `minimumGaps` observations is not a pattern, and the free tier
    /// falls back to the modelled estimate rather than printing a median of one.
    func testTooLittleHistoryReportsNoPattern() {
        let pattern = ObservedRecoveryPattern.analyse(
            sessions: regular(count: 2, everyDays: 2, load: 80), now: now
        )
        XCTAssertNil(pattern.usualGapHours(for: .moderate))
        XCTAssertNil(pattern.window(forLoad: 80, referenceLoad: 70))
    }

    /// Somebody who trains twice a week has a real, long, believable gap, and
    /// the countdown says so rather than clamping it to the model's ceiling.
    func testALongHabitSurvivesUpToTheObservedCeiling() {
        let pattern = ObservedRecoveryPattern.analyse(
            sessions: regular(count: 8, everyDays: 3.5, load: 90), now: now
        )
        XCTAssertEqual(pattern.usualGapHours(for: .moderate) ?? 0, 83, accuracy: 1)
    }

    func testTheReportedGapIsBounded() {
        let hourly = (0..<10).map { session(daysAgo: Double(10 - $0) / 24, minutes: 30, load: 80) }
        let tooShort = ObservedRecoveryPattern.analyse(sessions: hourly, now: now)
            .usualGapHours(for: .moderate) ?? 0
        XCTAssertGreaterThanOrEqual(tooShort, RecoveryCalculator.minimumCountdownHours)

        let sparse = ObservedRecoveryPattern.analyse(
            sessions: regular(count: 8, everyDays: 6, load: 90), now: now
        ).usualGapHours(for: .moderate) ?? 0
        XCTAssertLessThanOrEqual(sparse, ObservedRecoveryPattern.maximumUsualHours)
    }

    // MARK: - Bands

    /// "Hard" means hard *for them*, which is the only scale the sentence the
    /// app prints can be checked against.
    func testBandsAreTercilesOfThePersonsOwnSessions() {
        var sessions: [ObservedRecoveryPattern.Session] = []
        for index in 0..<12 {
            sessions.append(session(daysAgo: Double(24 - index * 2), load: Double(20 + index * 10)))
        }
        let pattern = ObservedRecoveryPattern.analyse(sessions: sessions, now: now)
        XCTAssertEqual(pattern.band(forLoad: 25, referenceLoad: 70), .light)
        XCTAssertEqual(pattern.band(forLoad: 75, referenceLoad: 70), .moderate)
        XCTAssertEqual(pattern.band(forLoad: 130, referenceLoad: 70), .hard)
    }

    /// With no terciles to cut, the population reference is the split. Otherwise
    /// a first-week user's every session would land in the same band.
    func testAThinHistoryFallsBackToTheReferenceSplit() {
        let pattern = ObservedRecoveryPattern.empty
        XCTAssertEqual(pattern.band(forLoad: 30, referenceLoad: 70), .light)
        XCTAssertEqual(pattern.band(forLoad: 70, referenceLoad: 70), .moderate)
        XCTAssertEqual(pattern.band(forLoad: 120, referenceLoad: 70), .hard)
    }

    /// A band with two gaps in it is not a pattern. The pooled figure — every
    /// gap the person has — is a much better answer than a median of two, and
    /// the caller has to be told which one it got, because the sentence differs.
    func testAThinBandFallsBackToThePooledFigure() {
        var sessions = regular(count: 9, everyDays: 2, load: 60)
        sessions.append(session(daysAgo: 3, load: 200))
        sessions.append(session(daysAgo: 1, load: 200))
        let pattern = ObservedRecoveryPattern.analyse(sessions: sessions, now: now)

        XCTAssertFalse(pattern.isBandSpecific(.hard))
        let window = pattern.window(forLoad: 200, referenceLoad: 70)
        XCTAssertNotNil(window)
        XCTAssertEqual(window?.band, .hard)
        XCTAssertFalse(window?.isBandSpecific ?? true)
        XCTAssertEqual(window?.hours ?? 0, pattern.pooled.map { min(max($0.medianGapHours, 6), 96) } ?? 0, accuracy: 0.001)
    }

    // MARK: - The free tier reads it

    /// The point of the redesign: the free countdown *is* the habit. It is not a
    /// blend of the habit and the model, because a blend is a third number that
    /// is neither what the person does nor what the model says.
    func testTheStandardTierCountdownIsTheObservedGap() {
        let window = ObservedRecoveryPattern.Window(
            hours: 41, band: .hard, sampleCount: 7, isBandSpecific: true
        )
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: .standard(for: .endurance),
            observed: window,
            now: now
        )
        XCTAssertEqual(estimate.tier, .standard)
        XCTAssertEqual(estimate.hours, 41, accuracy: 0.001)
        XCTAssertTrue(
            estimate.reasons.contains { $0.contains("your own history") },
            "the free tier has to name the evidence: \(estimate.reasons)"
        )
    }

    /// Recharge+ recommends, so the habit is a sentence there rather than the
    /// countdown. If the observed window replaced the paid number too, the
    /// upgrade would buy the user their own calendar back.
    func testThePersonalizedTierRecommendsRatherThanDescribes() {
        let window = ObservedRecoveryPattern.Window(
            hours: 41, band: .hard, sampleCount: 7, isBandSpecific: true
        )
        let estimate = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60,
            baseline: .standard(for: .endurance),
            personalization: .personalized(factor: 1),
            observed: window,
            now: now
        )
        XCTAssertNotEqual(estimate.hours, 41, accuracy: 0.001)
        XCTAssertTrue(
            estimate.reasons.contains { $0.contains("usually go again") },
            "the recommendation is stated against the habit: \(estimate.reasons)"
        )
    }

    /// No pattern yet is not a reason to show nothing: the modelled estimate is
    /// what the free tier falls back to, and it says so in as many words.
    func testWithNoPatternTheFreeTierFallsBackToTheModel() {
        let modelled = RecoveryCalculator.estimate(
            for: RecoveryFixtures.thresholdRun60, baseline: .standard(for: .endurance), now: now
        )
        XCTAssertGreaterThan(modelled.hours, 0)
        XCTAssertTrue(
            modelled.reasons.contains { $0.contains("Not enough history yet") },
            "\(modelled.reasons)"
        )
    }
}
