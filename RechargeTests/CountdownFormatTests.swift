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
        XCTAssertEqual(CountdownFormat.compactRemaining(52 * 3600), "2d")
        XCTAssertEqual(CountdownFormat.compactRemaining(0), "Ready")
    }

    func testEveryCompactStringIsShortEnoughForAnInlineSlot() {
        for seconds in stride(from: 0.0, through: 72 * 3600, by: 137) {
            let text = CountdownFormat.compactRemaining(seconds)
            XCTAssertLessThanOrEqual(text.count, 6, "\"\(text)\" is too wide for a corner slot")
        }
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
