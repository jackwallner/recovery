import XCTest

/// The timeline is the one piece with no precedent in the fleet: every other
/// complication here renders a number that only grows and needs a single entry.
/// A countdown has to be right at instants WidgetKit may never wake us for.
final class CountdownTimelineTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func snapshot(hoursRemaining: Double, totalHours: Double = 20) -> RecoverySnapshot {
        RecoverySnapshot(
            readyAt: now.addingTimeInterval(hoursRemaining * 3600),
            sessionEnd: now.addingTimeInterval((hoursRemaining - totalHours) * 3600),
            hours: totalHours,
            windowLowHours: totalHours * 0.85,
            windowHighHours: totalHours * 1.15,
            profile: .endurance,
            activityLabel: "run",
            category: .hard,
            confidence: .high,
            reasons: [],
            calculatedAt: now
        )
    }

    // MARK: - Shape

    func testAnIdleSnapshotProducesASingleEntry() {
        XCTAssertEqual(CountdownTimeline.entryDates(for: .empty, now: now), [now])
    }

    func testAnExpiredCountdownProducesASingleEntry() {
        XCTAssertEqual(CountdownTimeline.entryDates(for: snapshot(hoursRemaining: -2), now: now), [now])
    }

    func testEntriesAreStrictlyIncreasingAndDeduplicated() {
        for hours in [0.25, 1.0, 2.0, 5.0, 20.0, 72.0] {
            let dates = CountdownTimeline.entryDates(for: snapshot(hoursRemaining: hours), now: now)
            XCTAssertEqual(dates, dates.sorted(), "\(hours)h timeline was not sorted")
            XCTAssertEqual(Set(dates).count, dates.count, "\(hours)h timeline had duplicates")
        }
    }

    func testEveryEntryIsAtOrAfterNow() {
        for hours in [0.5, 3.0, 24.0, 72.0] {
            for date in CountdownTimeline.entryDates(for: snapshot(hoursRemaining: hours), now: now) {
                XCTAssertGreaterThanOrEqual(date, now)
            }
        }
    }

    func testTheTimelineIsBoundedSoWidgetKitIsNeverHandedThousandsOfEntries() {
        let dates = CountdownTimeline.entryDates(for: snapshot(hoursRemaining: 72, totalHours: 72), now: now)
        XCTAssertLessThanOrEqual(dates.count, CountdownTimeline.maximumEntries)
    }

    // MARK: - The flip

    func testTheTimelineAlwaysCoversTheMomentTheCountdownExpires() {
        for hours in [0.1, 0.9, 1.5, 4.0, 30.0] {
            let state = snapshot(hoursRemaining: hours)
            let dates = CountdownTimeline.entryDates(for: state, now: now)
            guard let readyAt = state.readyAt else { return XCTFail("fixture has no readyAt") }
            XCTAssertTrue(dates.contains(readyAt), "\(hours)h timeline skipped readyAt")
            XCTAssertTrue(
                dates.contains { $0 > readyAt },
                "\(hours)h timeline had no entry after readyAt, so a delayed refresh would show a stale countdown"
            )
        }
    }

    func testAnEntryAfterReadyAtRendersAsReady() {
        let state = snapshot(hoursRemaining: 3)
        let dates = CountdownTimeline.entryDates(for: state, now: now)
        guard let last = dates.last else { return XCTFail("empty timeline") }
        XCTAssertEqual(state.phase(at: last), .ready)
        XCTAssertEqual(state.remainingSeconds(at: last), 0)
    }

    // MARK: - Resolution

    func testTheFinalTwoHoursAreSampledFinelyEnoughToShowReadySoon() {
        let state = snapshot(hoursRemaining: 10)
        let dates = CountdownTimeline.entryDates(for: state, now: now)
        guard let readyAt = state.readyAt else { return XCTFail("fixture has no readyAt") }

        let lastStretch = dates.filter { $0 >= readyAt.addingTimeInterval(-2 * 3600) && $0 < readyAt }
        // Two hours at fifteen-minute steps, minus the boundary itself.
        XCTAssertGreaterThanOrEqual(lastStretch.count, 6)
        XCTAssertTrue(
            lastStretch.contains { state.phase(at: $0) == .readySoon },
            "no entry in the final stretch lands on Ready soon"
        )
    }

    func testALongCountdownStepsAtMostAnHourAtATimeBeforeTheFinalStretch() {
        let state = snapshot(hoursRemaining: 24, totalHours: 24)
        let dates = CountdownTimeline.entryDates(for: state, now: now)
        guard let readyAt = state.readyAt else { return XCTFail("fixture has no readyAt") }
        let coarse = dates.filter { $0 < readyAt.addingTimeInterval(-2 * 3600) }
        for (earlier, later) in zip(coarse, coarse.dropFirst()) {
            XCTAssertLessThanOrEqual(
                later.timeIntervalSince(earlier), 3600 + 1,
                "the countdown would visibly jump between entries"
            )
        }
    }

    // MARK: - Refresh policy

    func testAnIdleTimelineStillAsksToBeRefreshedEventually() {
        let refresh = CountdownTimeline.refreshDate(for: .empty, now: now)
        XCTAssertGreaterThan(refresh, now)
        XCTAssertLessThanOrEqual(refresh.timeIntervalSince(now), 6 * 3600 + 1)
    }

    func testARunningCountdownRefreshesShortlyAfterItExpires() {
        let state = snapshot(hoursRemaining: 3)
        let refresh = CountdownTimeline.refreshDate(for: state, now: now)
        guard let readyAt = state.readyAt else { return XCTFail("fixture has no readyAt") }
        XCTAssertGreaterThan(refresh, readyAt)
        XCTAssertLessThanOrEqual(refresh.timeIntervalSince(readyAt), 130)
    }

    func testALongCountdownStillRefreshesWithinAFewHours() {
        // A 60-hour countdown must not go untouched for 60 hours; the snapshot
        // can change underneath us (a second workout, an effort answer).
        let refresh = CountdownTimeline.refreshDate(for: snapshot(hoursRemaining: 60, totalHours: 60), now: now)
        XCTAssertLessThanOrEqual(refresh.timeIntervalSince(now), 4 * 3600 + 1)
    }

    // MARK: - Rendering from the entry, not the clock

    func testProgressAndRemainingAreDerivedFromTheEntryDate() {
        // The whole design depends on this: an entry rendered an hour late must
        // still show what it was built to show for its own instant.
        let state = snapshot(hoursRemaining: 20, totalHours: 20)
        let dates = CountdownTimeline.entryDates(for: state, now: now)
        for date in dates {
            let remaining = state.remainingSeconds(at: date)
            let expected = max((state.readyAt ?? date).timeIntervalSince(date), 0)
            XCTAssertEqual(remaining, expected, accuracy: 0.001)
        }
    }

    func testHourBoundaryHelperLandsOnAWholeHour() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let boundary = CountdownTimeline.nextHourBoundary(after: now, calendar: calendar)
        XCTAssertEqual(calendar.component(.minute, from: boundary), 0)
        XCTAssertGreaterThan(boundary, now)
    }
}
