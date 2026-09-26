import XCTest

final class DuplicateWorkoutsTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func workout(
        _ id: String,
        startMinutesAgo: Double,
        minutes: Double,
        coverage: Double = 0
    ) -> DuplicateWorkouts.Candidate {
        let start = now.addingTimeInterval(-startMinutesAgo * 60)
        return DuplicateWorkouts.Candidate(
            id: id,
            start: start,
            end: start.addingTimeInterval(minutes * 60),
            heartRateCoverage: coverage
        )
    }

    /// The case this exists for: the Watch records the run, Strava writes its
    /// own copy a minute shorter and with no heart rate.
    func testAThirdPartyCopyOfAWatchRunIsDropped() {
        let watch = workout("watch", startMinutesAgo: 120, minutes: 60, coverage: 0.95)
        let strava = workout("strava", startMinutesAgo: 119, minutes: 58)
        XCTAssertEqual(DuplicateWorkouts.duplicateIDs(in: [strava, watch]), ["strava"])
    }

    func testTheCopyWithBetterHeartRateSurvivesWhicheverComesFirst() {
        let sparse = workout("sparse", startMinutesAgo: 90, minutes: 45, coverage: 0.2)
        let full = workout("full", startMinutesAgo: 90, minutes: 45, coverage: 0.9)
        XCTAssertEqual(DuplicateWorkouts.duplicateIDs(in: [sparse, full]), ["sparse"])
        XCTAssertEqual(DuplicateWorkouts.duplicateIDs(in: [full, sparse]), ["sparse"])
    }

    /// A ten-minute warm-up logged inside a ninety-minute match is its own
    /// session, not a copy of the match.
    func testAShortSessionInsideALongOneIsKept() {
        let match = workout("match", startMinutesAgo: 120, minutes: 90, coverage: 0.9)
        let warmUp = workout("warmup", startMinutesAgo: 120, minutes: 10, coverage: 0.9)
        XCTAssertTrue(DuplicateWorkouts.duplicateIDs(in: [match, warmUp]).isEmpty)
    }

    func testBackToBackSessionsAreKept() {
        let bike = workout("bike", startMinutesAgo: 180, minutes: 90)
        let run = workout("run", startMinutesAgo: 90, minutes: 30)
        XCTAssertTrue(DuplicateWorkouts.duplicateIDs(in: [bike, run]).isEmpty)
    }

    /// Three apps writing the same session leave exactly one.
    func testThreeCopiesLeaveOne() {
        let copies = [
            workout("a", startMinutesAgo: 60, minutes: 40, coverage: 0.5),
            workout("b", startMinutesAgo: 61, minutes: 42, coverage: 0.8),
            workout("c", startMinutesAgo: 59, minutes: 39),
        ]
        XCTAssertEqual(DuplicateWorkouts.duplicateIDs(in: copies), ["a", "c"])
    }

    func testZeroLengthEntriesNeverMatch() {
        let empty = workout("empty", startMinutesAgo: 30, minutes: 0)
        let real = workout("real", startMinutesAgo: 30, minutes: 30)
        XCTAssertEqual(DuplicateWorkouts.duplicateIDs(in: [empty, real]), [])
    }
}
