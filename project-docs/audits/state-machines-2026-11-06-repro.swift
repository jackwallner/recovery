import XCTest

/// State machine audit repro suite (2026-11-06). Failing tests are expected:
/// each `testBUG_*` asserts the behaviour the app promises, and a `testControl_*`
/// beside it passes to show the setup is sound.
final class StateMachineAuditRepro: XCTestCase {

    private let now = RecoveryFixtures.now

    private func run(_ id: String, endingHoursAgo: Double, minutes: Double = 60, reserve: Double = 0.78) -> SessionInput {
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

    private func estimate(_ session: SessionInput, carried: Double = 0) -> RecoveryEstimate {
        RecoveryCalculator.estimate(
            for: session, baseline: .standard(for: .endurance), carriedHours: carried, now: now
        )
    }

    /// Two runs where the second starts inside the first one's countdown, built
    /// exactly as `RecoveryEngine.rescore` builds them (the second is handed the
    /// first's `readyAt` as its residual). The first one's own countdown ran out
    /// one hour ago; the second one's is still running.
    private func stackedPair() -> (first: RecoveryEstimate, second: RecoveryEstimate) {
        let firstHours = estimate(run("A", endingHoursAgo: 0)).hours
        let first = estimate(run("A", endingHoursAgo: firstHours + 1))
        let secondSession = run("B", endingHoursAgo: 3)
        let carried = RecoveryCalculator.carriedHours(into: secondSession, from: first.readyAt)
        let second = estimate(secondSession, carried: carried)
        return (first, second)
    }

    // MARK: - BUG-1: readiness question about a countdown that has not ended

    func testBUG1_readinessQuestionIsNotAskedWhileTheShownCountdownIsStillRunning() {
        let (first, second) = stackedPair()
        let estimates = [first, second]

        // Preconditions: the shown countdown is B's, still running with more
        // than two hours left, and A's own window ended an hour ago.
        XCTAssertLessThanOrEqual(first.readyAt, now, "A's own window should have ended")
        XCTAssertGreaterThan(second.carriedHours, 0, "B must be stacked on A")
        XCTAssertGreaterThan(second.readyAt.timeIntervalSince(now), 2 * 3600, "B must still be running")
        XCTAssertEqual(RecoveryResolver.active(in: estimates, now: now)?.sessionID, "B")
        XCTAssertEqual(RecoveryResolver.phase(in: estimates, now: now), .recovering)

        // Promise (RecoveryResolver.awaitingFeedback, ReadinessFeedbackSheet):
        // "The one-tap question asked once a countdown expires." The countdown
        // on screen has not expired, so nothing is awaiting an answer.
        let pending = RecoveryResolver.awaitingFeedback(in: estimates, answered: [], eligibleFrom: nil, now: now)
        XCTAssertNil(
            pending,
            "asked about \(pending?.sessionID ?? "-") (own readyAt \(first.readyAt.timeIntervalSince(now) / 3600)h from now) "
            + "while the shown countdown has \(second.readyAt.timeIntervalSince(now) / 3600)h left "
            + "(A hours \(first.hours), B hours \(second.hours) + carried \(second.carriedHours))"
        )
    }

    func testControl_readinessQuestionIsAskedWhenTheOnlyCountdownHasEnded() {
        let (first, second) = stackedPair()
        // A alone, countdown over: the question is legitimate.
        XCTAssertEqual(
            RecoveryResolver.awaitingFeedback(in: [first], answered: [], eligibleFrom: nil, now: now)?.sessionID, "A"
        )
        // Both over: it is about the one that set the shown countdown.
        let later = second.readyAt.addingTimeInterval(60)
        XCTAssertEqual(
            RecoveryResolver.awaitingFeedback(in: [first, second], answered: [], eligibleFrom: nil, now: later)?.sessionID, "B"
        )
    }

    // MARK: - BUG-2: widget and complication timeline across the staleness cutoff

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

    func testBUG2_timelineCarriesTheReadyToNoWorkoutFlip() {
        let snapshot = runningSnapshot()
        let readyAt = snapshot.readyAt!
        let staleFrom = max(
            snapshot.sessionEnd!.addingTimeInterval(RecoveryResolver.stalenessCutoff),
            readyAt.addingTimeInterval(RecoveryResolver.readyGrace)
        )

        // Preconditions: running now, Ready after readyAt, "No workout" after the cutoff.
        XCTAssertEqual(snapshot.phase(at: now), .recovering)
        XCTAssertEqual(snapshot.phase(at: readyAt.addingTimeInterval(61)), .ready)
        XCTAssertEqual(snapshot.phase(at: staleFrom.addingTimeInterval(60)), .noRecentWorkout)

        // Promise (CountdownTimeline doc): "the timeline must remain correct
        // without any [refresh]: each entry carries the instant it represents".
        // AGENTS.md: isStale is "the one staleness rule for Today, the snapshot,
        // the widgets and the Watch". So some entry must sit at or after the cutoff.
        let dates = CountdownTimeline.entryDates(for: snapshot, now: now)
        let last = dates.last!
        XCTAssertGreaterThanOrEqual(
            last, staleFrom,
            "last entry is \(last.timeIntervalSince(readyAt))s after readyAt; the cutoff is "
            + "\(staleFrom.timeIntervalSince(readyAt) / 3600)h after readyAt, so the face stays on "
            + "\(snapshot.phase(at: last)) until WidgetKit grants a refresh"
        )
    }

    func testControl_timelineCarriesTheRecoveringToReadyFlip() {
        let snapshot = runningSnapshot()
        let dates = CountdownTimeline.entryDates(for: snapshot, now: now)
        XCTAssertEqual(snapshot.phase(at: dates.last!), .ready)
        XCTAssertTrue(dates.contains(snapshot.readyAt!))
        // And the refresh the system is asked for after Ready is six hours out.
        let afterFlip = snapshot.readyAt!.addingTimeInterval(121)
        XCTAssertEqual(CountdownTimeline.refreshDate(for: snapshot, now: afterFlip).timeIntervalSince(afterFlip), 6 * 3600)
    }
}
