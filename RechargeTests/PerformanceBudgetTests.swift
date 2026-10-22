import XCTest

/// Worst-case open paths against three years of dense training: two sessions a
/// day, every day, with a duplicate copy of every fifth one and an overnight
/// reading for every day. Each budget is about 5x the best of three runs on the
/// simulator, with the measurement beside it, so a normal machine passes with
/// wide margin and a quadratic regression does not.
final class PerformanceBudgetTests: XCTestCase {
    private let la: Calendar = {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "America/Los_Angeles")!
        return calendar
    }()

    private let dayCount = 3 * 365
    private var now: Date { la.date(from: DateComponents(year: 2027, month: 8, day: 20, hour: 12))! }

    private func sessions() -> [SessionInput] {
        let today = la.startOfDay(for: now)
        var result: [SessionInput] = []
        for back in stride(from: dayCount, through: 1, by: -1) {
            let day = la.date(byAdding: .day, value: -back, to: today)!
            for slot in 0..<2 {
                let end = day.addingTimeInterval(TimeInterval(slot == 0 ? 8 : 18) * 3_600 + Double(back % 7) * 60)
                let minutes = 35.0 + Double((back * 13 + slot * 7) % 70)
                let profile: WorkoutProfile = (back + slot) % 4 == 0 ? .strength : .endurance
                result.append(SessionInput(
                    id: "s-\(back)-\(slot)", profile: profile,
                    startDate: end.addingTimeInterval(-minutes * 60), endDate: end,
                    averageHeartRate: 130 + Double((back * 3 + slot) % 45), restingHeartRate: 52, maxHeartRate: 188,
                    heartRateCoverage: 0.95, activeEnergyKilocalories: 300 + Double(back % 400), activityLabel: "run"
                ))
            }
        }
        return result
    }

    private func best(_ label: String, budget: Double, _ body: () throws -> Void) rethrows {
        var fastest = Double.infinity
        for _ in 0..<3 {
            let start = ContinuousClock.now
            try body()
            let elapsed = start.duration(to: .now)
            fastest = min(fastest, Double(elapsed.components.seconds) + Double(elapsed.components.attoseconds) / 1e18)
        }
        print("PERF \(label): \(String(format: "%.1f", fastest * 1_000)) ms (budget \(Int(budget * 1_000)) ms)")
        XCTAssertLessThan(fastest, budget, "\(label) took \(fastest) s")
    }

    func testFixtureBuildsInUnderTwoSeconds() {
        let start = ContinuousClock.now
        let all = sessions()
        let elapsed = start.duration(to: .now)
        XCTAssertEqual(all.count, dayCount * 2)
        XCTAssertLessThan(elapsed, .seconds(2))
    }

    // 8a8af365 / 4701553b: the rescore chain walks every session in order, building
    // each one's baseline from the history before it, as `RecoveryEngine.rescore`
    // does on every import.
    func testRescoreChainOverThreeYears() {
        let inputs = sessions()
        best("rescore chain", budget: 5.0) {
            var history: [(profile: WorkoutProfile, load: Double, date: Date)] = []
            var readyAt: Date?
            var last: RecoveryEstimate?
            for session in inputs {
                let baseline = RecoveryBaseline.build(from: history, for: session.profile, now: session.endDate)
                let item = RecoveryCalculator.estimate(
                    for: session, baseline: baseline,
                    carriedHours: RecoveryCalculator.carriedHours(into: session, from: readyAt), now: now
                )
                if item.producesCountdown { readyAt = item.readyAt }
                history.append((profile: session.profile, load: item.load.value, date: session.endDate))
                last = item
            }
            XCTAssertNotNil(last)
        }
    }

    // 471dcca2: the duplicate scan over a store with the same session written twice.
    func testDuplicateScanOverThreeYears() {
        let inputs = sessions()
        var candidates = inputs.map {
            DuplicateWorkouts.Candidate(id: $0.id, start: $0.startDate, end: $0.endDate, heartRateCoverage: 0.95)
        }
        for (index, session) in inputs.enumerated() where index % 5 == 0 {
            candidates.append(DuplicateWorkouts.Candidate(
                id: session.id + "-copy", start: session.startDate.addingTimeInterval(60),
                end: session.endDate.addingTimeInterval(60), heartRateCoverage: 0.4
            ))
        }
        best("duplicate scan", budget: 5.0) {
            XCTAssertEqual(DuplicateWorkouts.duplicateIDs(in: candidates).count, inputs.count / 5 + (inputs.count % 5 == 0 ? 0 : 1))
        }
    }

    // 2de1c28c / 8a8af365: the 30 day analysis, the observed habit and the
    // overnight context read a store that holds years of rows.
    func testAnalysisPassesOverThreeYears() {
        let inputs = sessions()
        let history = inputs.map { session in
            PersonalRecoveryModel.HistorySession(
                id: session.id, profile: session.profile, startDate: session.startDate, endDate: session.endDate,
                load: 80 + Double(session.id.count), intensityFraction: 0.7, standardHours: 20
            )
        }
        let days = (0..<dayCount).map { back in
            PersonalRecoveryModel.DayPoint(
                date: la.date(byAdding: .day, value: -back, to: la.startOfDay(for: now))!,
                restingHeartRate: 50 + Double(back % 6), heartRateVariability: 55 + Double(back % 20), heartRateRecovery: 30
            )
        }
        best("personal analysis", budget: 1.0) {
            _ = PersonalRecoveryModel.analyse(profile: .empty, sessions: history, days: days, now: now)
        }
        let observed = inputs.map {
            ObservedRecoveryPattern.Session(profile: $0.profile, startDate: $0.startDate, endDate: $0.endDate, load: 90, id: $0.id)
        }
        best("observed pattern", budget: 1.0) {
            _ = ObservedRecoveryPattern.analyse(sessions: observed, now: now)
        }
    }

    // 12b2f71d / bf02fab4: Today resolves its estimate, phase and readiness
    // question from the whole scored history, and the load view reads 14 days.
    func testTodayAndLoadViewOverThreeYears() {
        let inputs = sessions()
        let estimates = inputs.map { session in
            RecoveryCalculator.estimate(for: session, baseline: .standard(for: session.profile), now: session.endDate)
        }
        best("resolver", budget: 1.0) {
            _ = RecoveryResolver.current(in: estimates, now: now)
            _ = RecoveryResolver.phase(in: estimates, now: now)
            _ = RecoveryResolver.awaitingFeedback(in: estimates, answered: [], now: now)
        }
        let entries = inputs.map { (end: $0.endDate, load: 100.0) }
        best("daily loads", budget: 1.0) {
            XCTAssertEqual(LoadSeries.daily(entries, days: 14, now: now, calendar: la).count, 14)
            _ = LoadSeries.balance(entries, now: now)
        }
        let snapshot = RecoverySnapshot(
            readyAt: now.addingTimeInterval(95 * 3_600), sessionEnd: now, hours: 95, windowLowHours: 80, windowHighHours: 96,
            profile: .endurance, activityLabel: "run", category: .hard, confidence: .high, reasons: [], calculatedAt: now
        )
        best("timeline", budget: 0.5) {
            XCTAssertLessThanOrEqual(CountdownTimeline.entryDates(for: snapshot, now: now, calendar: la).count, CountdownTimeline.maximumEntries)
        }
    }
}
