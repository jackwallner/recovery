import XCTest

/// Regression tests for the state machine audit of 2026-11-06
/// (`project-docs/audits/state-machines-2026-11-06-fixes.md`). B1 and B4 reuse
/// the audit's repro tests, which the review judged sound.
final class StateMachineRegressionTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func run(
        _ id: String,
        endingHoursAgo: Double,
        minutes: Double = 60,
        reserve: Double = 0.78
    ) -> SessionInput {
        let resting = 55.0, max = 185.0
        let end = now.addingTimeInterval(-endingHoursAgo * 3600)
        return SessionInput(
            id: id,
            profile: .endurance,
            startDate: end.addingTimeInterval(-minutes * 60),
            endDate: end,
            durationMinutes: minutes,
            averageHeartRate: resting + reserve * (max - resting),
            restingHeartRate: resting,
            maxHeartRate: max,
            heartRateCoverage: 1,
            activityLabel: "run"
        )
    }

    private func estimate(_ session: SessionInput, after previous: RecoveryEstimate? = nil) -> RecoveryEstimate {
        let carried = RecoveryCalculator.carriedHours(into: session, from: previous?.readyAt)
        return RecoveryCalculator.estimate(
            for: session, baseline: .standard(for: .endurance), carriedHours: carried, now: now
        )
    }

    /// The audit's pair: B stacks on A, A's own window ended an hour ago and
    /// B's is still running.
    private func stackedPair() -> (first: RecoveryEstimate, second: RecoveryEstimate) {
        let firstHours = estimate(run("A", endingHoursAgo: 0)).hours
        let first = estimate(run("A", endingHoursAgo: firstHours + 1))
        let second = estimate(run("B", endingHoursAgo: 3), after: first)
        return (first, second)
    }

    // MARK: - B1: the readiness question about a stacked session

    func testTheReadinessQuestionIsNotAskedWhileTheShownCountdownIsStillRunning() {
        let (first, second) = stackedPair()
        let estimates = [first, second]
        XCTAssertLessThanOrEqual(first.readyAt, now, "A's own window should have ended")
        XCTAssertGreaterThan(second.carriedHours, 0, "B must be stacked on A")
        XCTAssertGreaterThan(second.readyAt.timeIntervalSince(now), 2 * 3600, "B must still be running")
        XCTAssertEqual(RecoveryResolver.active(in: estimates, now: now)?.sessionID, "B")

        let pending = RecoveryResolver.awaitingFeedback(in: estimates, answered: [], eligibleFrom: nil, now: now)
        XCTAssertNil(pending, "asked about \(pending?.sessionID ?? "-") while B's countdown is on screen")
    }

    /// The review's ordinary double day, and its route (ii): answering B used
    /// to raise the question about A straight away.
    func testAnsweringTheStackedSessionDoesNotRaiseTheQuestionAboutTheOneUnderIt() {
        let hard = estimate(run("A", endingHoursAgo: 60))
        let moderate = estimate(run("B", endingHoursAgo: 46, minutes: 45, reserve: 0.62), after: hard)
        let estimates = [hard, moderate]
        XCTAssertGreaterThan(moderate.carriedHours, 0, "B must be stacked on A")
        XCTAssertGreaterThan(moderate.readyAt, hard.readyAt)

        let midCountdown = hard.readyAt.addingTimeInterval(60)
        XCTAssertNil(RecoveryResolver.awaitingFeedback(in: estimates, answered: [], now: midCountdown))

        let afterB = moderate.readyAt.addingTimeInterval(60)
        XCTAssertLessThan(afterB.timeIntervalSince(hard.readyAt), 2 * 86_400, "A must still be inside its window")
        XCTAssertEqual(RecoveryResolver.awaitingFeedback(in: estimates, answered: [], now: afterB)?.sessionID, "B")
        XCTAssertNil(RecoveryResolver.awaitingFeedback(in: estimates, answered: ["B"], now: afterB))
    }

    func testControl_aCountdownThatRanOutBeforeTheNextSessionIsStillAskedAbout() {
        let first = estimate(run("A", endingHoursAgo: 60))
        let laterSession = run("B", endingHoursAgo: now.timeIntervalSince(first.readyAt) / 3600 - 1)
        let later = estimate(laterSession, after: first)
        XCTAssertEqual(later.carriedHours, 0, "B starts after A ran out, so nothing is stacked")
        let afterLater = later.readyAt.addingTimeInterval(60)
        XCTAssertEqual(RecoveryResolver.awaitingFeedback(in: [first, later], answered: [], now: afterLater)?.sessionID, "B")
        XCTAssertEqual(RecoveryResolver.awaitingFeedback(in: [first, later], answered: ["B"], now: afterLater)?.sessionID, "A")
        XCTAssertEqual(RecoveryResolver.awaitingFeedback(in: [first], answered: [], now: first.readyAt)?.sessionID, "A")
    }

    // MARK: - B3: a Ready moment counted at the onboarding import

    func testTheOnboardingImportDoesNotCountAReadyMoment() {
        let old = estimate(run("old", endingHoursAgo: 30 * 24))
        XCTAssertTrue(old.producesCountdown)
        XCTAssertLessThanOrEqual(old.readyAt, now)
        XCTAssertEqual(RecoveryResolver.current(in: [old], now: now)?.sessionID, "old")
        // During onboarding setup has not stamped the window yet.
        XCTAssertNil(RecoveryResolver.readyMoment(in: [old], eligibleFrom: nil, now: now))
        // Once setup finishes, a countdown that ran out before it is still not one the user watched.
        XCTAssertNil(RecoveryResolver.readyMoment(in: [old], eligibleFrom: now, now: now.addingTimeInterval(60)))
    }

    func testACountdownThatRanOutAfterSetupStillCounts() {
        let setup = now.addingTimeInterval(-10 * 86_400)
        let session = estimate(run("recent", endingHoursAgo: 40))
        XCTAssertLessThanOrEqual(session.readyAt, now)
        XCTAssertGreaterThan(session.readyAt, setup)
        XCTAssertEqual(RecoveryResolver.readyMoment(in: [session], eligibleFrom: setup, now: now)?.sessionID, "recent")
        let running = estimate(run("running", endingHoursAgo: 1))
        XCTAssertNil(RecoveryResolver.readyMoment(in: [running], eligibleFrom: setup, now: now))
    }

    // MARK: - B4: widget and complication timeline across the staleness cutoff

    private func runningSnapshot() -> RecoverySnapshot {
        RecoverySnapshot(
            readyAt: now.addingTimeInterval(3 * 3600),
            sessionEnd: now.addingTimeInterval(-3600),
            hours: 4,
            windowLowHours: 3,
            windowHighHours: 5,
            profile: .endurance,
            activityLabel: "run",
            calculatedAt: now
        )
    }

    func testTheTimelineCarriesTheReadyToNoWorkoutFlip() {
        let snapshot = runningSnapshot()
        let readyAt = snapshot.readyAt!
        let staleFrom = RecoveryResolver.staleFrom(sessionEnd: snapshot.sessionEnd!, readyAt: readyAt)
        XCTAssertEqual(snapshot.phase(at: now), .recovering)
        XCTAssertEqual(snapshot.phase(at: readyAt.addingTimeInterval(61)), .ready)

        let dates = CountdownTimeline.entryDates(for: snapshot, now: now)
        XCTAssertTrue(dates.contains(readyAt))
        XCTAssertEqual(snapshot.phase(at: readyAt.addingTimeInterval(60)), .ready)
        let last = dates.last!
        XCTAssertGreaterThan(last, staleFrom)
        XCTAssertEqual(snapshot.phase(at: last), .noRecentWorkout)
        XCTAssertEqual(snapshot.phase(at: dates[dates.count - 2]), .ready, "Ready must hold until the cutoff")
    }

    func testAnIdleTimelineBuiltAfterReadyStillFlipsAtTheCutoff() {
        let snapshot = runningSnapshot()
        let staleFrom = RecoveryResolver.staleFrom(sessionEnd: snapshot.sessionEnd!, readyAt: snapshot.readyAt)
        let built = staleFrom.addingTimeInterval(-60)
        let dates = CountdownTimeline.entryDates(for: snapshot, now: built)
        XCTAssertEqual(dates.map { snapshot.phase(at: $0) }, [.ready, .noRecentWorkout])

        // A session with no countdown of its own reads Ready until it goes stale too.
        var easy = snapshot
        easy.readyAt = nil
        let easyStale = RecoveryResolver.staleFrom(sessionEnd: easy.sessionEnd!, readyAt: nil)
        XCTAssertEqual(CountdownTimeline.entryDates(for: easy, now: now), [now, easyStale.addingTimeInterval(1)])

        // Past the cutoff, and with nothing at all, there is nothing left to flip.
        XCTAssertEqual(CountdownTimeline.entryDates(for: snapshot, now: staleFrom.addingTimeInterval(1)), [staleFrom.addingTimeInterval(1)])
        XCTAssertEqual(CountdownTimeline.entryDates(for: .empty, now: now), [now])
    }
}
