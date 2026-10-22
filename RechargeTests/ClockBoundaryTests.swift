import XCTest

/// Countdowns, staleness and day buckets driven by a fixed clock and an explicit
/// calendar (America/Los_Angeles), never the machine's. DST days: 2026-11-01 is
/// 25 hours long, 2027-03-14 is 23.
final class ClockBoundaryTests: XCTestCase {
    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private func at(
        _ year: Int, _ month: Int, _ day: Int,
        _ hour: Int = 0, _ minute: Int = 0, _ second: Int = 0
    ) -> Date {
        la.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute, second: second))!
    }

    private func run(
        _ id: String, endingAt end: Date, minutes: Double = 75, profile: WorkoutProfile = .endurance, hr: Double = 168
    ) -> SessionInput {
        SessionInput(
            id: id, profile: profile,
            startDate: end.addingTimeInterval(-minutes * 60), endDate: end,
            averageHeartRate: hr, restingHeartRate: 52, maxHeartRate: 188,
            heartRateCoverage: 0.97, activeEnergyKilocalories: 800, activityLabel: "run"
        )
    }

    private func estimate(
        _ session: SessionInput, carried: Double = 0, now: Date? = nil
    ) -> RecoveryEstimate {
        RecoveryCalculator.estimate(
            for: session, baseline: .standard(for: session.profile), carriedHours: carried,
            now: now ?? session.endDate
        )
    }

    private func snapshot(readyAt: Date?, sessionEnd: Date?, hours: Double = 20) -> RecoverySnapshot {
        RecoverySnapshot(
            readyAt: readyAt, sessionEnd: sessionEnd, hours: hours,
            windowLowHours: hours * 0.85, windowHighHours: hours * 1.15,
            profile: .endurance, activityLabel: "run", category: .hard, confidence: .high, reasons: [],
            calculatedAt: sessionEnd ?? .distantPast
        )
    }

    // MARK: - Countdowns across midnight and DST

    // 2de1c28 (window length is a function of the session): a window is
    // exactly its hours of real time whatever the local clock does in between.
    func testWindowIsTheSameRealHoursAcrossFallBackAndSpringForward() {
        let plain = estimate(run("plain", endingAt: at(2026, 7, 10, 22)))
        let fall = estimate(run("fall", endingAt: at(2026, 10, 31, 22)))
        let spring = estimate(run("spring", endingAt: at(2027, 3, 13, 22)))
        XCTAssertGreaterThan(plain.totalHours, 6)
        for item in [fall, spring] {
            XCTAssertEqual(item.totalHours, plain.totalHours, accuracy: 1e-9)
            XCTAssertEqual(item.readyAt.timeIntervalSince(item.sessionEnd), item.totalHours * 3_600, accuracy: 1e-6)
        }
    }

    // bf02fab4 / 12b2f71d: the phase flips on the exact second a countdown that
    // crosses midnight runs out, and the label says Ready from that second.
    func testPhaseFlipsOnTheExactSecondAcrossMidnight() {
        let item = estimate(run("late", endingAt: at(2026, 7, 21, 23, 30)))
        XCTAssertEqual(item.phase(at: item.sessionEnd), .recovering)
        XCTAssertEqual(item.phase(at: item.readyAt.addingTimeInterval(-2 * 3_600 - 1)), .recovering)
        XCTAssertEqual(item.phase(at: item.readyAt.addingTimeInterval(-2 * 3_600)), .readySoon)
        XCTAssertEqual(item.phase(at: item.readyAt.addingTimeInterval(-1)), .readySoon)
        XCTAssertEqual(item.phase(at: item.readyAt), .ready)
        XCTAssertEqual(CountdownFormat.remaining(item.remainingSeconds(at: item.readyAt)), "Ready")
        XCTAssertEqual(CountdownFormat.remaining(item.remainingSeconds(at: item.readyAt.addingTimeInterval(-1))), "1m")
    }

    // MARK: - Overlapping sessions

    // 12b2f71d / 0e7e6bb7: a session inside a running countdown inherits the real
    // hours left, measured across the spring-forward midnight, and one that starts
    // after Ready inherits nothing.
    func testOverlapAcrossSpringForwardCarriesRealHoursLeft() {
        let first = estimate(run("evening", endingAt: at(2027, 3, 13, 21)))
        let second = run("night", endingAt: at(2027, 3, 14, 4), minutes: 45, profile: .endurance, hr: 150)
        let carried = RecoveryCalculator.carriedHours(into: second, from: first.readyAt)
        XCTAssertEqual(carried, first.readyAt.timeIntervalSince(second.endDate) / 3_600, accuracy: 1e-9)
        XCTAssertGreaterThan(carried, 0)

        let stacked = estimate(second, carried: carried)
        XCTAssertGreaterThanOrEqual(stacked.totalHours, estimate(second).totalHours)
        XCTAssertLessThanOrEqual(stacked.totalHours, RecoveryCalculator.maximumHours)

        let justReady = run("later", endingAt: first.readyAt)
        XCTAssertEqual(RecoveryCalculator.carriedHours(into: justReady, from: first.readyAt), 0)
        let aSecondBefore = run("earlier", endingAt: first.readyAt.addingTimeInterval(-1))
        XCTAssertEqual(RecoveryCalculator.carriedHours(into: aSecondBefore, from: first.readyAt), 1.0 / 3_600, accuracy: 1e-9)
    }

    // 0e7e6bb7: a chain of hard sessions every few hours stays under the ceiling
    // however many nights it crosses.
    func testAChainOfOverlappingSessionsNeverPassesTheCeiling() {
        var readyAt: Date?
        var end = at(2026, 10, 30, 20)
        for index in 0..<12 {
            let session = run("chain-\(index)", endingAt: end, minutes: 120, hr: 175)
            let carried = RecoveryCalculator.carriedHours(into: session, from: readyAt)
            let item = estimate(session, carried: carried)
            XCTAssertLessThanOrEqual(item.totalHours, RecoveryCalculator.maximumHours + 1e-9, "step \(index)")
            XCTAssertLessThanOrEqual(item.carriedHours + item.hours, RecoveryCalculator.maximumHours + 1e-9)
            readyAt = item.readyAt
            end = end.addingTimeInterval(5 * 3_600)
        }
    }

    // MARK: - The resolver and staleness

    // bf02fab4: Ready stays a day after a 96 hour countdown. The cutoff is exact
    // to the second, with the window ending at midnight.
    func testReadyStaysExactlyADayPastALongCountdown() {
        let end = at(2026, 10, 30, 12)
        let readyAt = end.addingTimeInterval(96 * 3_600)
        XCTAssertFalse(RecoveryResolver.isStale(sessionEnd: end, readyAt: readyAt, now: readyAt.addingTimeInterval(86_400)))
        XCTAssertTrue(RecoveryResolver.isStale(sessionEnd: end, readyAt: readyAt, now: readyAt.addingTimeInterval(86_401)))
        // A short window is cut at four days after the session instead.
        let shortReady = end.addingTimeInterval(10 * 3_600)
        XCTAssertFalse(RecoveryResolver.isStale(sessionEnd: end, readyAt: shortReady, now: end.addingTimeInterval(4 * 86_400)))
        XCTAssertTrue(RecoveryResolver.isStale(sessionEnd: end, readyAt: shortReady, now: end.addingTimeInterval(4 * 86_400 + 1)))
    }

    // bf02fab4: the snapshot every glance surface reads follows the same rule at
    // midnight, and its ring is empty the second it goes stale.
    func testSnapshotPhaseAndRingAtTheStaleBoundary() {
        let end = at(2026, 10, 30, 23, 59, 59)
        let readyAt = end.addingTimeInterval(96 * 3_600)
        let snap = snapshot(readyAt: readyAt, sessionEnd: end, hours: 96)
        XCTAssertEqual(snap.phase(at: readyAt), .ready)
        XCTAssertEqual(snap.phase(at: readyAt.addingTimeInterval(86_400)), .ready)
        XCTAssertEqual(snap.phase(at: readyAt.addingTimeInterval(86_401)), .noRecentWorkout)
        XCTAssertEqual(snap.progress(at: readyAt.addingTimeInterval(86_401)), 0)
        XCTAssertEqual(snap.progress(at: readyAt), 1, accuracy: 1e-9)
    }

    // 12b2f71d: of overlapping windows the latest ready time is shown, and a
    // window ending this very second is no longer active.
    func testResolverShowsTheLatestWindowAndDropsOneThatEndsNow() {
        let early = estimate(run("early", endingAt: at(2026, 7, 21, 20)))
        let late = estimate(run("late", endingAt: at(2026, 7, 21, 23, 30), minutes: 90, hr: 176))
        let both = [early, late]
        XCTAssertEqual(RecoveryResolver.active(in: both, now: at(2026, 7, 22, 0, 0, 1))?.sessionID, late.readyAt > early.readyAt ? "late" : "early")
        let end = max(early.readyAt, late.readyAt)
        XCTAssertNil(RecoveryResolver.active(in: both, now: end))
        XCTAssertNotNil(RecoveryResolver.active(in: both, now: end.addingTimeInterval(-1)))
    }

    // a5bdb0c / first-launch backfill: onboarding imports months of history whose
    // countdowns are all already over. None is asked about before setup finished,
    // one that ends the second setup completes is, and the question expires after
    // two days to the second.
    func testBackfilledHistoryIsNotAskedAboutButAFreshReadyIs() {
        let setupDone = at(2026, 7, 22, 0, 0, 5)
        let backfill = (1...120).map { day in
            estimate(run("old-\(day)", endingAt: setupDone.addingTimeInterval(-Double(day) * 86_400 - 3 * 3_600)))
        }
        XCTAssertNil(RecoveryResolver.awaitingFeedback(in: backfill, answered: [], eligibleFrom: setupDone, now: setupDone))

        let fresh = estimate(run("fresh", endingAt: setupDone.addingTimeInterval(-3 * 3_600)))
        let ready = fresh.readyAt
        XCTAssertEqual(RecoveryResolver.awaitingFeedback(in: [fresh], answered: [], eligibleFrom: ready, now: ready)?.sessionID, "fresh")
        XCTAssertNil(RecoveryResolver.awaitingFeedback(in: [fresh], answered: [], eligibleFrom: ready.addingTimeInterval(1), now: ready.addingTimeInterval(5)))
        XCTAssertNotNil(RecoveryResolver.awaitingFeedback(in: [fresh], answered: [], now: ready.addingTimeInterval(2 * 86_400 - 1)))
        XCTAssertNil(RecoveryResolver.awaitingFeedback(in: [fresh], answered: [], now: ready.addingTimeInterval(2 * 86_400)))
    }

    // df4ab6c: a failed read stays quiet for six hours to the second,
    // across midnight, and a first-ever failure counts at once.
    func testStaleHealthDataAppearsExactlySixHoursAfterTheLastGoodRead() {
        let lastGood = at(2026, 7, 21, 20)
        let sixHours = lastGood.addingTimeInterval(6 * 3_600)
        XCTAssertEqual(HealthDataState.resolve(lastImportFailed: true, lastSuccessfulImport: lastGood, now: sixHours), .current)
        XCTAssertEqual(HealthDataState.resolve(lastImportFailed: true, lastSuccessfulImport: lastGood, now: sixHours.addingTimeInterval(1)), .stale)
        XCTAssertEqual(HealthDataState.resolve(lastImportFailed: false, lastSuccessfulImport: lastGood, now: sixHours.addingTimeInterval(86_400)), .current)
        XCTAssertEqual(HealthDataState.resolve(lastImportFailed: true, lastSuccessfulImport: nil, now: sixHours), .stale)
    }

    // MARK: - The widget timeline

    private func hourly(_ dates: [Date], from now: Date, readyAt: Date) -> [Date] {
        dates.filter { $0 > now && $0 < readyAt.addingTimeInterval(-2 * 3_600) }
    }

    // 6da1bf8 (the next-hour helper and its 80 minute hole): the hourly entries sit on whole local hours and are never
    // earlier than the build instant, including the second 01:00 hour of the night
    // the clocks go back. A timeline entry before `now` renders a stale countdown.
    func testTimelineNeverStartsBeforeNowOnTheSecondHourOfFallBack() {
        let now = at(2026, 11, 1, 1, 30).addingTimeInterval(3_600) // 01:30 PST, the second 01:00 hour
        XCTAssertEqual(la.component(.hour, from: now), 1)
        XCTAssertEqual(la.timeZone.daylightSavingTimeOffset(for: now), 0)
        let readyAt = now.addingTimeInterval(12 * 3_600)
        let dates = CountdownTimeline.entryDates(for: snapshot(readyAt: readyAt, sessionEnd: now), now: now, calendar: la)
        XCTAssertEqual(dates.first, now)
        XCTAssertTrue(dates.allSatisfy { $0 >= now })
        let first = hourly(dates, from: now, readyAt: readyAt).first
        XCTAssertEqual(first, now.addingTimeInterval(1_800))
        XCTAssertEqual(first.map { la.component(.hour, from: $0) }, 2)
    }

    func testTimelineHourlyEntriesAreWholeLocalHoursAcrossMidnightAndBothDSTChanges() {
        for start in [at(2026, 7, 21, 23, 40), at(2026, 11, 1, 0, 40), at(2027, 3, 14, 1, 20)] {
            let readyAt = start.addingTimeInterval(30 * 3_600)
            let dates = CountdownTimeline.entryDates(for: snapshot(readyAt: readyAt, sessionEnd: start, hours: 30), now: start, calendar: la)
            XCTAssertEqual(dates, dates.sorted())
            XCTAssertEqual(Set(dates).count, dates.count)
            XCTAssertLessThanOrEqual(dates.count, CountdownTimeline.maximumEntries)
            XCTAssertTrue(dates.contains(readyAt))
            XCTAssertTrue(dates.contains(readyAt.addingTimeInterval(60)))
            let hours = hourly(dates, from: start, readyAt: readyAt)
            XCTAssertFalse(hours.isEmpty)
            for entry in hours {
                XCTAssertEqual(la.component(.minute, from: entry), 0, "\(entry)")
                XCTAssertEqual(la.component(.second, from: entry), 0)
            }
            // No hole wider than an hour before the final stretch.
            for (earlier, later) in zip(hours, hours.dropFirst()) {
                XCTAssertEqual(later.timeIntervalSince(earlier), 3_600, accuracy: 0.001)
            }
        }
    }

    // MARK: - Day buckets

    // 8a8af365 (baseline on one curve): two sessions on one local day are one
    // training day even when UTC splits them; one either side of local midnight
    // are two.
    func testBaselineBucketsTrainingDaysByTheLocalMidnight() {
        func history(_ times: [Date]) -> [(profile: WorkoutProfile, load: Double, date: Date)] {
            times.map { (profile: .endurance, load: 100, date: $0) }
        }
        let now = at(2026, 7, 30, 12)
        let sameLocalDay = RecoveryBaseline.build(
            from: history([at(2026, 7, 20, 16, 59), at(2026, 7, 20, 17, 1)]),
            for: .endurance, now: now, calendar: la
        )
        XCTAssertEqual(sameLocalDay.dayCount, 1)
        let acrossMidnight = RecoveryBaseline.build(
            from: history([at(2026, 7, 20, 23, 59, 59), at(2026, 7, 21, 0, 0, 0)]),
            for: .endurance, now: now, calendar: la
        )
        XCTAssertEqual(acrossMidnight.dayCount, 2)
    }

    // The baseline window is 42 days of real time: a session exactly on the edge
    // is in, one second older is out, over the fall-back night.
    func testBaselineWindowEdgeIsExactAcrossFallBack() {
        let now = at(2026, 11, 20, 12)
        let edge = now.addingTimeInterval(-Double(RecoveryBaseline.historyDays) * 86_400)
        let inside = RecoveryBaseline.build(
            from: [(profile: .endurance, load: 100, date: edge)], for: .endurance, now: now, calendar: la
        )
        XCTAssertEqual(inside.dayCount, 1)
        let outside = RecoveryBaseline.build(
            from: [(profile: .endurance, load: 100, date: edge.addingTimeInterval(-1))], for: .endurance, now: now, calendar: la
        )
        XCTAssertEqual(outside.dayCount, 0)
    }

    // The load view buckets sessions by local day: the last second of a day and
    // the first of the next never share a bar, including on the 25 hour day.
    func testDailyLoadsSplitAtLocalMidnightAndSpanTheFallBackDay() {
        let entries: [LoadSeries.Entry] = [
            (end: at(2026, 10, 31, 23, 59, 59), load: 40),
            (end: at(2026, 11, 1, 0, 0, 0), load: 50),
            (end: at(2026, 11, 1, 23, 59, 59), load: 60),
            (end: at(2026, 11, 2, 0, 0, 0), load: 70),
        ]
        let series = LoadSeries.daily(entries, days: 4, now: at(2026, 11, 2, 9), calendar: la)
        XCTAssertEqual(series.map(\.date), [at(2026, 10, 30), at(2026, 10, 31), at(2026, 11, 1), at(2026, 11, 2)])
        XCTAssertEqual(series.map(\.load), [0, 40, 110, 70])
        // Just before midnight the next day's bar is still empty.
        let early = LoadSeries.daily(entries, days: 2, now: at(2026, 11, 1, 23, 59, 59), calendar: la)
        XCTAssertEqual(early.map(\.load), [40, 110])
    }

    // The acute and chronic windows are 7 and 28 days of real seconds.
    func testLoadBalanceWindowEdgesAreExact() {
        let now = at(2026, 11, 8, 12)
        let weekAgo = now.addingTimeInterval(-7 * 86_400)
        let monthAgo = now.addingTimeInterval(-28 * 86_400)
        let entries: [LoadSeries.Entry] = [
            (end: weekAgo, load: 10), (end: weekAgo.addingTimeInterval(-1), load: 20),
            (end: monthAgo, load: 40), (end: monthAgo.addingTimeInterval(-1), load: 80),
        ]
        let balance = LoadSeries.balance(entries, now: now)
        XCTAssertEqual(balance.acute, 10, accuracy: 1e-9)
        XCTAssertEqual(balance.chronic, (10 + 20 + 40) / 4, accuracy: 1e-9)
    }
}
