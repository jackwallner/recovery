import XCTest

final class RecoveryResolverTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func estimate(
        id: String,
        hoursFromNow: Double,
        endedHoursAgo: Double = 1,
        hours: Double = 20,
        profile: WorkoutProfile = .endurance
    ) -> RecoveryEstimate {
        RecoveryEstimate(
            sessionID: id,
            profile: profile,
            activityLabel: "run",
            calculatedAt: now,
            sessionEnd: now.addingTimeInterval(-endedHoursAgo * 3600),
            readyAt: now.addingTimeInterval(hoursFromNow * 3600),
            hours: hours,
            windowLowHours: hours * 0.85,
            windowHighHours: hours * 1.15,
            load: SessionLoad(value: 100, source: .heartRate, heartRateCoverage: 0.9),
            relativeLoad: 1.4,
            category: .hard,
            confidence: .high,
            reasons: ["Hard for you: 60-minute run."]
        )
    }

    // MARK: - Concurrent windows

    func testTheLatestReadyTimeWins() {
        let short = estimate(id: "short", hoursFromNow: 4)
        let long = estimate(id: "long", hoursFromNow: 22, profile: .mixed)
        XCTAssertEqual(RecoveryResolver.active(in: [short, long], now: now)?.sessionID, "long")
        XCTAssertEqual(RecoveryResolver.active(in: [long, short], now: now)?.sessionID, "long")
    }

    func testExpiredWindowsAreIgnoredForTheActiveCountdown() {
        let expired = estimate(id: "expired", hoursFromNow: -3)
        let live = estimate(id: "live", hoursFromNow: 6)
        XCTAssertEqual(RecoveryResolver.active(in: [expired, live], now: now)?.sessionID, "live")
    }

    func testNoActiveWindowReturnsNil() {
        let expired = estimate(id: "expired", hoursFromNow: -3)
        XCTAssertNil(RecoveryResolver.active(in: [expired], now: now))
    }

    func testZeroHourEstimatesNeverBecomeTheActiveCountdown() {
        let walk = estimate(id: "walk", hoursFromNow: 0, hours: 0, profile: .easy)
        let run = estimate(id: "run", hoursFromNow: 12)
        XCTAssertEqual(RecoveryResolver.active(in: [walk, run], now: now)?.sessionID, "run")
        XCTAssertNil(RecoveryResolver.active(in: [walk], now: now))
    }

    // MARK: - Current (for the explanation surface)

    func testCurrentFallsBackToTheMostRecentSessionOnceEverythingHasExpired() {
        let older = estimate(id: "older", hoursFromNow: -30, endedHoursAgo: 50)
        let newer = estimate(id: "newer", hoursFromNow: -2, endedHoursAgo: 22)
        XCTAssertEqual(RecoveryResolver.current(in: [older, newer], now: now)?.sessionID, "newer")
    }

    func testCurrentPrefersAnActiveWindowOverAMoreRecentExpiredOne() {
        let activeButOlder = estimate(id: "active", hoursFromNow: 5, endedHoursAgo: 20)
        let expiredButNewer = estimate(id: "expired", hoursFromNow: -1, endedHoursAgo: 2, hours: 1)
        XCTAssertEqual(
            RecoveryResolver.current(in: [activeButOlder, expiredButNewer], now: now)?.sessionID,
            "active"
        )
    }

    // MARK: - Phases

    func testPhases() {
        XCTAssertEqual(RecoveryResolver.phase(in: [], now: now), .noRecentWorkout)
        XCTAssertEqual(RecoveryResolver.phase(in: [estimate(id: "a", hoursFromNow: 10)], now: now), .recovering)
        XCTAssertEqual(RecoveryResolver.phase(in: [estimate(id: "a", hoursFromNow: 1)], now: now), .readySoon)
        XCTAssertEqual(RecoveryResolver.phase(in: [estimate(id: "a", hoursFromNow: -1)], now: now), .ready)
    }

    func testAStaleSessionReadsAsNoRecentWorkoutRatherThanAMisleadingReady() {
        let ancient = estimate(id: "ancient", hoursFromNow: -100, endedHoursAgo: 24 * 9)
        XCTAssertEqual(RecoveryResolver.phase(in: [ancient], now: now), .noRecentWorkout)
    }

    // MARK: - What a screen may explain

    func testAStaleSessionIsStillCurrentButNoLongerExplained() {
        // Nine days old, and its 20-hour window long since expired. History and
        // the snapshot still need it; Today must not narrate it beside a
        // "no workout yet" hero.
        let ancient = estimate(id: "ancient", hoursFromNow: -100, endedHoursAgo: 24 * 9)
        XCTAssertEqual(RecoveryResolver.current(in: [ancient], now: now)?.sessionID, "ancient")
        XCTAssertNil(RecoveryResolver.explanation(in: [ancient], now: now))
    }

    func testARecentSessionIsExplained() {
        let live = estimate(id: "live", hoursFromNow: 6)
        let expired = estimate(id: "expired", hoursFromNow: -2, endedHoursAgo: 22)
        XCTAssertEqual(RecoveryResolver.explanation(in: [live], now: now)?.sessionID, "live")
        XCTAssertEqual(RecoveryResolver.explanation(in: [expired], now: now)?.sessionID, "expired")
    }

    func testAnEasySessionWithNoCountdownIsStillExplained() {
        // The walk that deliberately produced no countdown is exactly the case
        // the Why card exists to explain.
        let walk = estimate(id: "walk", hoursFromNow: 0, hours: 0, profile: .easy)
        XCTAssertEqual(RecoveryResolver.explanation(in: [walk], now: now)?.sessionID, "walk")
    }

    func testExplanationAgreesWithThePhaseAcrossTheStalenessBoundary() {
        let insideCutoff = estimate(id: "inside", hoursFromNow: -50, endedHoursAgo: 24 * 3.9)
        let outsideCutoff = estimate(id: "outside", hoursFromNow: -50, endedHoursAgo: 24 * 4.1)
        XCTAssertNotNil(RecoveryResolver.explanation(in: [insideCutoff], now: now))
        XCTAssertNil(RecoveryResolver.explanation(in: [outsideCutoff], now: now))
    }

    func testReadySoonBoundaryIsExactlyTwoHours() {
        let justInside = estimate(id: "a", hoursFromNow: 1.99)
        let justOutside = estimate(id: "b", hoursFromNow: 2.01)
        XCTAssertEqual(RecoveryResolver.phase(in: [justInside], now: now), .readySoon)
        XCTAssertEqual(RecoveryResolver.phase(in: [justOutside], now: now), .recovering)
    }

    // MARK: - Feedback prompt

    func testExpiredWindowsBecomeEligibleForTheReadinessQuestion() {
        let expired = estimate(id: "expired", hoursFromNow: -4)
        XCTAssertEqual(
            RecoveryResolver.awaitingFeedback(in: [expired], answered: [], now: now)?.sessionID,
            "expired"
        )
    }

    func testAlreadyAnsweredWindowsAreNotAskedAgain() {
        let expired = estimate(id: "expired", hoursFromNow: -4)
        XCTAssertNil(RecoveryResolver.awaitingFeedback(in: [expired], answered: ["expired"], now: now))
    }

    func testActiveWindowsAreNotAskedAbout() {
        let live = estimate(id: "live", hoursFromNow: 4)
        XCTAssertNil(RecoveryResolver.awaitingFeedback(in: [live], answered: [], now: now))
    }

    func testWeDoNotAskAboutSomethingTheUserCannotRemember() {
        let ancient = estimate(id: "ancient", hoursFromNow: -24 * 5, endedHoursAgo: 24 * 7)
        XCTAssertNil(RecoveryResolver.awaitingFeedback(in: [ancient], answered: [], now: now))
    }
}
