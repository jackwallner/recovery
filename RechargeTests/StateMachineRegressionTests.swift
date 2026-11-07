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
}
