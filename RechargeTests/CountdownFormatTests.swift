import XCTest

final class CountdownFormatTests: XCTestCase {

    func testRemainingReadsTheWayGarminPrintsIt() {
        XCTAssertEqual(CountdownFormat.remaining(0), "Ready")
        XCTAssertEqual(CountdownFormat.remaining(-500), "Ready")
        XCTAssertEqual(CountdownFormat.remaining(18 * 3600), "18h")
        XCTAssertEqual(CountdownFormat.remaining(18 * 3600 + 40 * 60), "18h 40m")
        XCTAssertEqual(CountdownFormat.remaining(80 * 60), "1h 20m")
        XCTAssertEqual(CountdownFormat.remaining(18 * 60), "18m")
        XCTAssertEqual(CountdownFormat.remaining(52 * 3600), "2d 4h")
        XCTAssertEqual(CountdownFormat.remaining(48 * 3600), "2d")
    }

    func testCompactRemainingFitsAComplicationSlot() {
        // Truncates rather than rounds: a countdown that says "19h" with 18h40m
        // left is claiming more time than the model gave you.
        XCTAssertEqual(CountdownFormat.compactRemaining(18 * 3600 + 40 * 60), "18h")
        XCTAssertEqual(CountdownFormat.compactRemaining(80 * 60), "1h 20m")
        XCTAssertEqual(CountdownFormat.compactRemaining(18 * 60), "18m")
        XCTAssertEqual(CountdownFormat.compactRemaining(52 * 3600), "2d 4h")
        XCTAssertEqual(CountdownFormat.compactRemaining(48 * 3600), "2d")
        XCTAssertEqual(CountdownFormat.compactRemaining(0), "Ready")
    }

    func testEveryCompactStringIsShortEnoughForAnInlineSlot() {
        for seconds in stride(from: 0.0, through: 72 * 3600, by: 137) {
            let text = CountdownFormat.compactRemaining(seconds)
            XCTAssertLessThanOrEqual(text.count, 6, "\"\(text)\" is too wide for a corner slot")
        }
    }

    /// The property that makes a countdown a countdown, asserted across the whole
    /// range the model can produce rather than at a handful of sample points.
    ///
    /// This is the check that was missing when `compactRemaining` returned a bare
    /// `"\(days)d"` above 24 hours. Every existing test passed: the string was
    /// short enough, it read correctly at the sampled values, and the timeline
    /// dutifully carried an entry for every hour. None of them asked the only
    /// question that mattered on the wrist — whether two entries an hour apart
    /// render differently — so a 72-hour window sat on `3d` for a full day, then
    /// `2d` for a full day, and looked broken because it was indistinguishable
    /// from broken.
    func testTheCompactCountdownChangesAtLeastOnceAnHourAcrossTheWholeRange() {
        // Every minute from the maximum window down to a minute left. The
        // comparison is against the same instant an hour later, which is the
        // coarsest cadence `CountdownTimeline` ever schedules an entry at.
        for minute in stride(from: 60, through: Int(RecoveryCalculator.maximumHours) * 60, by: 1) {
            let now = TimeInterval(minute * 60)
            let anHourLater = TimeInterval((minute - 60) * 60)
            XCTAssertNotEqual(
                CountdownFormat.compactRemaining(now),
                CountdownFormat.compactRemaining(anHourLater),
                "the complication reads \"\(CountdownFormat.compactRemaining(now))\" for at least an hour "
                    + "at \(minute) minutes remaining"
            )
        }
    }

    /// A countdown that goes up is worse than one that stands still.
    ///
    /// The strings are not ordered by anything the compiler can check — `"2d 4h"`
    /// sorts before `"18h"` — so the claim is made on the parsed value: whatever
    /// unit the reading lands in, it has to describe a shorter time than the
    /// reading a minute before it.
    func testTheCompactCountdownNeverReadsLongerAsTimeRunsOut() {
        var previousMinutes = Int.max
        for minute in stride(from: Int(RecoveryCalculator.maximumHours) * 60, through: 1, by: -1) {
            let parsed = Self.minutes(fromCompact: CountdownFormat.compactRemaining(TimeInterval(minute * 60)))
            XCTAssertLessThanOrEqual(
                parsed, previousMinutes,
                "the complication went up: \(previousMinutes)m then \(parsed)m at \(minute) minutes left"
            )
            previousMinutes = parsed
        }
    }

    /// Reads `2d 23h`, `18h`, `1h 20m`, `18m` back into whole minutes.
    private static func minutes(fromCompact text: String) -> Int {
        var total = 0
        for part in text.split(separator: " ") {
            guard let unit = part.last, let value = Int(part.dropLast()) else { continue }
            switch unit {
            case "d": total += value * 1440
            case "h": total += value * 60
            case "m": total += value
            default: break
            }
        }
        return total
    }

    func testElapsedReadsAsAFreshnessStamp() {
        let now = RecoveryFixtures.now
        XCTAssertEqual(CountdownFormat.elapsed(since: now, now: now), "just now")
        XCTAssertEqual(CountdownFormat.elapsed(since: now.addingTimeInterval(-30), now: now), "just now")
        XCTAssertEqual(CountdownFormat.elapsed(since: now.addingTimeInterval(-4 * 60), now: now), "4m ago")
        XCTAssertEqual(CountdownFormat.elapsed(since: now.addingTimeInterval(-2 * 3600), now: now), "2h ago")
        XCTAssertEqual(CountdownFormat.elapsed(since: now.addingTimeInterval(-25 * 3600), now: now), "yesterday")
        XCTAssertEqual(CountdownFormat.elapsed(since: now.addingTimeInterval(-3 * 86_400), now: now), "3d ago")
    }

    func testWindowCollapsesWhenRoundingMakesBothEndsEqual() {
        XCTAssertEqual(CountdownFormat.window(low: 17.9, high: 18.1), "18h")
        XCTAssertEqual(CountdownFormat.window(low: 18, high: 28), "18 to 28h")
    }

    func testHoursNeverPrintsANegative() {
        XCTAssertEqual(CountdownFormat.hours(-3), "0h")
        XCTAssertEqual(CountdownFormat.hours(0), "0h")
        XCTAssertEqual(CountdownFormat.hours(31.6), "32h")
    }

    func testReadyAtDistinguishesTodayTomorrowAndLater() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        let now = Date(timeIntervalSince1970: 1_770_000_000)

        let laterToday = now.addingTimeInterval(3 * 3600)
        let tomorrow = now.addingTimeInterval(26 * 3600)
        let nextWeek = now.addingTimeInterval(4 * 86_400)

        XCTAssertTrue(CountdownFormat.readyAt(laterToday, now: now, calendar: calendar).hasPrefix("today at"))
        XCTAssertTrue(CountdownFormat.readyAt(tomorrow, now: now, calendar: calendar).hasPrefix("tomorrow at"))
        let later = CountdownFormat.readyAt(nextWeek, now: now, calendar: calendar)
        XCTAssertFalse(later.hasPrefix("today"))
        XCTAssertFalse(later.hasPrefix("tomorrow"))
        XCTAssertTrue(later.contains(" at "))
    }

    func testSoftReadyTimeAvoidsAFalselyPreciseClockReading() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC") ?? .current
        // 1_770_000_000 is 2026-02-02 02:40 UTC.
        let now = Date(timeIntervalSince1970: 1_770_000_000)
        let morning = now.addingTimeInterval(6 * 3600)      // ~08:40 UTC, same day
        XCTAssertEqual(CountdownFormat.readySoftly(morning, now: now, calendar: calendar), "this morning")

        let tomorrowEvening = now.addingTimeInterval(40 * 3600)  // ~18:40 UTC next day
        XCTAssertEqual(
            CountdownFormat.readySoftly(tomorrowEvening, now: now, calendar: calendar),
            "tomorrow evening"
        )
    }

    // MARK: - Compliance

    func testNoPhaseCopyMakesAMedicalClaim() {
        let banned = ["recovered", "safe to train", "injury", "your body", "cure", "diagnos", "muscle"]
        for phase in [RecoveryPhase.noRecentWorkout, .ready, .readySoon, .recovering] {
            let text = (CountdownFormat.phaseHeadline(phase) + " " + CountdownFormat.phaseDetail(phase)).lowercased()
            for phrase in banned {
                XCTAssertFalse(text.contains(phrase), "\"\(phrase)\" appeared in \(phase) copy")
            }
        }
    }

    func testReadyCopyFramesItselfAsAnEstimate() {
        XCTAssertTrue(CountdownFormat.phaseDetail(.ready).contains("estimate"))
    }
}
