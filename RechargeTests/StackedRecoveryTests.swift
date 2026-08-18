import XCTest

/// Recovery time is cumulative, and this is the file that says so.
///
/// Garmin documents the behaviour in one sentence: if eighteen hours were left
/// from yesterday's run and another session is done today, the new time stacks
/// on top. Recharge took the **maximum** of overlapping windows instead, which
/// is the simplest defensible rule and the wrong one — two hard sessions four
/// hours apart read exactly the same as one, and the number failed to move at
/// the one moment somebody coming from a Garmin would expect it to spike.
///
/// The rule now: a session done inside a running countdown starts its own from
/// where that countdown would have finished. `RecoveryEstimate.carriedHours` is
/// the residual, `totalHours` is what the countdown runs for, and `hours` is
/// untouched — it is still what *this session* cost, which is what the tier
/// comparison, the rest-pattern bands and the personalized preview are all
/// asking about.
final class StackedRecoveryTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func estimate(
        _ session: SessionInput,
        carried: Double = 0,
        baseline: RecoveryBaseline = .standard(for: .endurance)
    ) -> RecoveryEstimate {
        RecoveryCalculator.estimate(
            for: session, baseline: baseline, carriedHours: carried, now: now
        )
    }

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

    // MARK: - The rule

    /// The headline claim, and the one the old behaviour violated.
    func testASecondSessionInsideARunningWindowCostsMoreThanOne() {
        let first = estimate(run("first", endingHoursAgo: 4))
        XCTAssertTrue(first.producesCountdown)

        let second = run("second", endingHoursAgo: 0)
        let alone = estimate(second)
        let stacked = estimate(
            second,
            carried: RecoveryCalculator.carriedHours(into: second, from: first.readyAt)
        )

        XCTAssertGreaterThan(
            stacked.readyAt, alone.readyAt,
            "a session done four hours into a live countdown read the same as one done fresh"
        )
        XCTAssertGreaterThan(stacked.totalHours, alone.totalHours)
        XCTAssertEqual(
            stacked.totalHours, alone.hours + stacked.carriedHours, accuracy: 0.001,
            "the total is not the session plus what was carried"
        )
    }

    /// The session's own cost is untouched by what it landed on. Everything that
    /// compares the two tiers reads `hours`, and stacking is a property of the
    /// day rather than of the workout.
    func testStackingDoesNotChangeWhatTheSessionItselfCost() {
        let session = run("session", endingHoursAgo: 0)
        let alone = estimate(session)
        let stacked = estimate(session, carried: 20)

        XCTAssertEqual(stacked.hours, alone.hours, accuracy: 1e-9)
        XCTAssertEqual(stacked.standardHours, alone.standardHours, accuracy: 1e-9)
        XCTAssertEqual(stacked.relativeLoad, alone.relativeLoad, accuracy: 1e-9)
        XCTAssertEqual(stacked.category, alone.category)
        XCTAssertEqual(stacked.carriedHours, 20, accuracy: 1e-9)
    }

    /// An expired window carries nothing. Without this a session done a week
    /// after the last one would inherit a negative residual, or worse, be
    /// credited with one.
    func testAnExpiredWindowCarriesNothing() {
        let first = estimate(run("first", endingHoursAgo: 120))
        let second = run("second", endingHoursAgo: 0)
        XCTAssertLessThan(first.readyAt, second.endDate)
        XCTAssertEqual(RecoveryCalculator.carriedHours(into: second, from: first.readyAt), 0)
        XCTAssertEqual(
            estimate(second, carried: RecoveryCalculator.carriedHours(into: second, from: first.readyAt)).totalHours,
            estimate(second).totalHours,
            accuracy: 1e-9
        )
    }

    /// An active-recovery walk taken mid-window may neither start a countdown
    /// nor inherit one. This is the same guarantee `RecoveryResolver` gives, and
    /// stacking is exactly the mechanism that could have quietly broken it: a
    /// residual applied to a non-qualifying session would have manufactured a
    /// countdown out of an easy walk.
    func testAnEasySessionNeitherStartsNorInheritsACountdown() {
        let walk = SessionInput(
            id: "walk",
            profile: .easy,
            startDate: now.addingTimeInterval(-45 * 60),
            endDate: now,
            durationMinutes: 45,
            averageHeartRate: 95,
            restingHeartRate: 55,
            maxHeartRate: 185,
            heartRateCoverage: 1,
            activityLabel: "walk"
        )
        let stacked = RecoveryCalculator.estimate(
            for: walk, baseline: .standard(for: .easy), carriedHours: 30, now: now
        )
        XCTAssertFalse(stacked.producesCountdown)
        XCTAssertEqual(stacked.totalHours, 0)
        XCTAssertEqual(stacked.carriedHours, 0)
        XCTAssertEqual(stacked.readyAt, walk.endDate)
    }

    /// A session under the quiet threshold is the other non-qualifying case and
    /// must behave the same way.
    func testASessionBelowTheQuietThresholdDoesNotInheritEither() {
        let tiny = run("tiny", endingHoursAgo: 0, minutes: 8, reserve: 0.4)
        let stacked = estimate(tiny, carried: 30)
        XCTAssertFalse(stacked.producesCountdown)
        XCTAssertEqual(stacked.totalHours, 0)
    }

    // MARK: - Bounds

    /// Stacking obeys the same ceiling a single session does. Three hard
    /// sessions in a day must not produce a countdown longer than the app is
    /// willing to express.
    func testTheStackedTotalStillObeysTheCeiling() {
        let stacked = estimate(run("session", endingHoursAgo: 0), carried: 500)
        XCTAssertEqual(stacked.totalHours, RecoveryCalculator.maximumHours, accuracy: 1e-9)
        XCTAssertLessThanOrEqual(
            stacked.readyAt.timeIntervalSince(stacked.sessionEnd) / 3600,
            RecoveryCalculator.maximumHours + 1e-6
        )
    }

    /// The displayed range spreads around the countdown the user is looking at,
    /// not around the session's own cost, or a stacked window shows a band that
    /// excludes its own centre.
    func testTheDisplayedWindowSpreadsAroundTheStackedTotal() {
        let stacked = estimate(run("session", endingHoursAgo: 0), carried: 12)
        XCTAssertLessThanOrEqual(stacked.windowLowHours, stacked.totalHours)
        XCTAssertGreaterThanOrEqual(stacked.windowHighHours, stacked.totalHours)
        XCTAssertGreaterThan(stacked.windowLowHours, stacked.hours * 0.9)
    }

    /// Carrying more can only ever lengthen the countdown, never shorten it.
    func testTheCountdownIsMonotoneInWhatWasCarried() {
        var previous = -1.0
        for carried in stride(from: 0.0, through: 90.0, by: 3) {
            let total = estimate(run("session", endingHoursAgo: 0), carried: carried).totalHours
            XCTAssertGreaterThanOrEqual(total, previous)
            previous = total
        }
    }

    // MARK: - The chain

    /// Walked end to end, the way `RecoveryEngine.rescore` walks it: three hard
    /// sessions in one day against the same three spread over a week.
    func testTheSameThreeSessionsCostMoreOnOneDayThanSpreadOverAWeek() {
        func walk(_ endings: [Double]) -> Date {
            var readyAt: Date?
            for (index, hoursAgo) in endings.enumerated() {
                let session = run("s\(index)", endingHoursAgo: hoursAgo)
                let e = estimate(
                    session,
                    carried: RecoveryCalculator.carriedHours(into: session, from: readyAt)
                )
                if e.producesCountdown { readyAt = e.readyAt }
            }
            return readyAt ?? now
        }

        let crammed = walk([8, 4, 0])
        let spread = walk([14 * 24, 7 * 24, 0])
        XCTAssertGreaterThan(
            crammed, spread,
            "three hard sessions in a day left the user no worse off than three in a fortnight"
        )
    }

    /// And the chain never runs backwards: each session's ready time is at or
    /// after the one before it, which is what lets `RecoveryResolver.active`
    /// keep taking a maximum without knowing stacking exists.
    func testTheChainNeverRunsBackwards() {
        var readyAt: Date?
        var estimates: [RecoveryEstimate] = []
        for (index, hoursAgo) in [30.0, 26, 20, 14, 6, 0].enumerated() {
            let session = run("s\(index)", endingHoursAgo: hoursAgo)
            let e = estimate(
                session,
                carried: RecoveryCalculator.carriedHours(into: session, from: readyAt)
            )
            estimates.append(e)
            if e.producesCountdown {
                if let readyAt { XCTAssertGreaterThanOrEqual(e.readyAt, readyAt) }
                readyAt = e.readyAt
            }
        }
        XCTAssertEqual(
            RecoveryResolver.active(in: estimates, now: now)?.sessionID,
            estimates.last?.sessionID,
            "the resolver stopped agreeing with the chain"
        )
    }

    // MARK: - Copy

    func testTheStackedNoteExplainsTheArithmeticWithoutMakingAClaim() {
        let note = CountdownFormat.stackedNote(sessionHours: 18, carriedHours: 6)
        XCTAssertTrue(note.contains("18h"))
        XCTAssertTrue(note.contains("6h"))
        for banned in ["recovered", "safe to train", "injury", "your body", "cure", "diagnos"] {
            XCTAssertFalse(note.lowercased().contains(banned), note)
        }
    }
}
