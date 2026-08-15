import XCTest

final class RecoveryBaselineTests: XCTestCase {

    private let now = RecoveryFixtures.now

    func testEmptyBaselineFallsBackToTheProfileBootstrap() {
        for profile in WorkoutProfile.allCases {
            let baseline = RecoveryBaseline(loads: [], profile: profile)
            XCTAssertEqual(baseline.typicalLoad, profile.standardTypicalLoad)
            XCTAssertFalse(baseline.hasEnoughSamples)
        }
    }

    func testMedianIsTheTypicalLoadOnceTheSampleIsBigEnough() {
        let baseline = RecoveryBaseline(
            loads: [10, 20, 30, 40, 50, 60, 70, 80, 90], profile: .endurance
        )
        XCTAssertTrue(baseline.hasEnoughSamples)
        XCTAssertEqual(baseline.typicalLoad, 50, accuracy: 0.0001)
    }

    /// A thin history is shrunk toward the population reference rather than
    /// taken at face value. Three sessions is a description of three sessions,
    /// and dividing every future session by their median is how a 60-minute
    /// lift became a 72-hour countdown for someone three days into the app.
    func testAThinHistoryIsPulledTowardTheStandardReference() {
        let thin = RecoveryBaseline(loads: [30, 44, 52], profile: .strength)
        let median = thin.percentile(0.5)
        XCTAssertGreaterThan(thin.typicalLoad, median)
        XCTAssertLessThan(thin.typicalLoad, WorkoutProfile.strength.standardTypicalLoad)

        // More evidence moves it toward the person, monotonically.
        var previous = RecoveryBaseline(loads: [44], profile: .strength).typicalLoad
        for count in 2...RecoveryBaseline.minimumSamples {
            let baseline = RecoveryBaseline(
                loads: Array(repeating: 44.0, count: count), profile: .strength
            )
            XCTAssertLessThanOrEqual(baseline.typicalLoad, previous)
            previous = baseline.typicalLoad
        }
        XCTAssertEqual(previous, 44, accuracy: 0.0001, "eight sessions must be fully personal")
    }

    func testPercentileInterpolatesRatherThanSnapping() {
        let baseline = RecoveryBaseline(loads: [10, 110], profile: .endurance)
        XCTAssertEqual(baseline.percentile(0.25), 35, accuracy: 0.0001)
        XCTAssertEqual(baseline.percentile(0.5), 60, accuracy: 0.0001)
    }

    func testUnsortedInputIsHandled() {
        let baseline = RecoveryBaseline(
            loads: [50, 10, 90, 40, 20, 80, 30, 70, 60], profile: .endurance
        )
        XCTAssertEqual(baseline.typicalLoad, 50, accuracy: 0.0001)
    }

    func testNonPositiveLoadsAreDiscarded() {
        let baseline = RecoveryBaseline(loads: [0, -5, 20, 40], profile: .endurance)
        XCTAssertEqual(baseline.sampleCount, 2)
    }

    func testQuietThresholdNeverDropsBelowTheAbsoluteFloor() {
        // A user whose entire history is gentle: the 25th percentile is tiny,
        // but the floor must still stop a stroll from starting a countdown.
        let baseline = RecoveryBaseline(
            loads: Array(repeating: 4.0, count: 12), profile: .endurance
        )
        XCTAssertEqual(baseline.quietThreshold, RecoveryCalculator.absoluteCountdownFloor)
    }

    func testQuietThresholdUsesTheUsersOwn25thPercentileOnceItIsMeaningful() {
        let baseline = RecoveryBaseline(
            loads: [40, 45, 50, 60, 70, 80, 90, 100, 120, 150], profile: .endurance
        )
        XCTAssertGreaterThan(baseline.quietThreshold, RecoveryCalculator.absoluteCountdownFloor)
        XCTAssertEqual(baseline.quietThreshold, baseline.percentile(0.25), accuracy: 0.0001)
    }

    // MARK: - Building from history

    private func history(
        profile: WorkoutProfile,
        count: Int,
        load: Double,
        daysAgoStart: Int = 1
    ) -> [(profile: WorkoutProfile, load: Double, date: Date)] {
        (0..<count).map { index in
            (
                profile: profile,
                load: load + Double(index),
                date: now.addingTimeInterval(-Double(daysAgoStart + index) * 86_400)
            )
        }
    }

    func testSameProfileHistoryIsPreferredWhenItIsRichEnough() {
        var entries = history(profile: .strength, count: 10, load: 80)
        entries += history(profile: .endurance, count: 20, load: 40)
        let baseline = RecoveryBaseline.build(from: entries, for: .strength, now: now)
        XCTAssertEqual(baseline.sampleCount, 10)
        XCTAssertGreaterThan(baseline.typicalLoad, 60)
    }

    func testSparseProfileHistoryPoolsAcrossProfilesRatherThanUsingTheBootstrap() {
        var entries = history(profile: .mixed, count: 2, load: 100)
        entries += history(profile: .endurance, count: 15, load: 50)
        let baseline = RecoveryBaseline.build(from: entries, for: .mixed, now: now)
        XCTAssertEqual(baseline.sampleCount, 17)
        XCTAssertTrue(baseline.hasEnoughSamples)
    }

    func testEasySessionsAreExcludedFromTheBaseline() {
        var entries = history(profile: .endurance, count: 10, load: 60)
        entries += history(profile: .easy, count: 40, load: 5)
        let baseline = RecoveryBaseline.build(from: entries, for: .endurance, now: now)
        XCTAssertEqual(baseline.sampleCount, 10, "walks must not drag the median down")
    }

    func testSessionsOutsideTheWindowAreExcluded() {
        var entries = history(profile: .endurance, count: 10, load: 60)
        entries += history(profile: .endurance, count: 10, load: 200, daysAgoStart: 200)
        let baseline = RecoveryBaseline.build(from: entries, for: .endurance, now: now)
        XCTAssertEqual(baseline.sampleCount, 10)
        XCTAssertLessThan(baseline.typicalLoad, 100)
    }

    func testAUserWithNoHistoryAtAllStillProducesAUsableBaseline() {
        let baseline = RecoveryBaseline.build(from: [], for: .endurance, now: now)
        XCTAssertEqual(baseline.sampleCount, 0)
        XCTAssertEqual(baseline.typicalLoad, WorkoutProfile.endurance.standardTypicalLoad)
        XCTAssertFalse(baseline.hasEnoughSamples)
    }
}
