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

    /// The geometric mean of the day totals, once there are enough of them for
    /// the shrinkage to have let go. It sits below the median on a right-skewed
    /// sample, which is the whole reason it replaced it: a week whose middle day
    /// is small does not mean the person trains small.
    func testTheGeometricMeanIsTheTypicalLoadOnceTheSampleIsBigEnough() {
        // Inside the band the person's own figure is used exactly. A sample
        // further from the reference than `maximumPersonalRatio` allows is the
        // subject of `testThePersonalDenominatorCannotLeaveTheReferenceBand`.
        let loads: [Double] = [55, 60, 62, 66, 70, 74, 78, 84, 90]
        let baseline = RecoveryBaseline(loads: loads, profile: .endurance)
        XCTAssertTrue(baseline.hasEnoughSamples)
        XCTAssertEqual(
            baseline.typicalLoad, RecoveryBaseline.geometricMean(of: loads), accuracy: 0.0001
        )
    }

    /// The denominator of every relative load may be tuned by the person's own
    /// history and may not be relocated by it.
    ///
    /// Unbounded, it was: somebody training seven days a week in 25-minute
    /// sessions had a typical training day of about 26 against a reference day
    /// of 115, so the paid tier scored their ordinary session at twice normal
    /// and their weekly long run at 36 hours while the free tier said 13. The
    /// band is what stops the two tiers from being able to disagree by a
    /// multiple.
    func testThePersonalDenominatorCannotLeaveTheReferenceBand() {
        let reference = WorkoutProfile.endurance.standardTypicalLoad

        let tiny = RecoveryBaseline(loads: Array(repeating: 12.0, count: 20), profile: .endurance)
        XCTAssertEqual(
            tiny.typicalLoad, reference * RecoveryBaseline.minimumPersonalRatio, accuracy: 0.0001
        )

        let huge = RecoveryBaseline(loads: Array(repeating: 400.0, count: 20), profile: .endurance)
        XCTAssertEqual(
            huge.typicalLoad, reference * RecoveryBaseline.maximumPersonalRatio, accuracy: 0.0001
        )

        // Still monotone in the person's own training, which is what the
        // "training more never lengthens the window" guarantee rests on.
        var previous = 0.0
        for load in stride(from: 10.0, through: 400.0, by: 10.0) {
            let baseline = RecoveryBaseline(
                loads: Array(repeating: load, count: 20), profile: .endurance
            )
            XCTAssertGreaterThanOrEqual(baseline.typicalLoad, previous)
            previous = baseline.typicalLoad
        }
    }

    /// On a symmetric sample the two statistics agree, which is the guarantee
    /// that switching to the geometric mean did not quietly retune every
    /// ordinary user's window. They separate only where the sample is skewed.
    func testTheGeometricMeanMatchesTheMedianOnAnEvenlySpreadHistory() {
        let even: [Double] = [40, 44, 48, 52, 56, 60, 64, 68]
        let baseline = RecoveryBaseline(loads: even, profile: .endurance)
        XCTAssertEqual(baseline.typicalLoad, baseline.percentile(0.5), accuracy: baseline.percentile(0.5) * 0.04)
    }

    /// And it is not an arithmetic mean: one enormous session must not redefine
    /// what a normal day costs for this person.
    func testOneOutlierDoesNotRedefineATypicalDay() {
        var loads: [Double] = Array(repeating: 50, count: 11)
        loads.append(600)
        let baseline = RecoveryBaseline(loads: loads, profile: .endurance)
        let arithmetic = loads.reduce(0, +) / Double(loads.count)
        XCTAssertLessThan(baseline.typicalLoad, arithmetic * 0.75)
        XCTAssertLessThan(baseline.typicalLoad, 70)
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

        // More evidence moves it toward the person, monotonically. The sample
        // sits inside the reference band, so the endpoint is the person's own
        // figure exactly rather than the bound.
        var previous = RecoveryBaseline(loads: [70], profile: .strength).typicalLoad
        for count in 2...RecoveryBaseline.minimumSamples {
            let baseline = RecoveryBaseline(
                loads: Array(repeating: 70.0, count: count), profile: .strength
            )
            XCTAssertLessThanOrEqual(baseline.typicalLoad, previous)
            previous = baseline.typicalLoad
        }
        XCTAssertEqual(previous, 70, accuracy: 0.0001, "eight sessions must be fully personal")
    }

    func testPercentileInterpolatesRatherThanSnapping() {
        let baseline = RecoveryBaseline(loads: [10, 110], profile: .endurance)
        XCTAssertEqual(baseline.percentile(0.25), 35, accuracy: 0.0001)
        XCTAssertEqual(baseline.percentile(0.5), 60, accuracy: 0.0001)
    }

    func testUnsortedInputIsHandled() {
        let loads: [Double] = [70, 55, 90, 66, 60, 84, 62, 78, 74]
        let baseline = RecoveryBaseline(loads: loads, profile: .endurance)
        XCTAssertEqual(
            baseline.typicalLoad, RecoveryBaseline.geometricMean(of: loads), accuracy: 0.0001
        )
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
        XCTAssertFalse(baseline.hasEstablishedBaseline)
    }

    // MARK: - Confidence counts the same thing the shrinkage does

    /// The disagreement, in one case. Someone training three times a day clears
    /// eight *sessions* on day three, and `typicalLoad` is still shrunk
    /// three-eighths of the way toward the population reference, so a
    /// confidence rating built on the session count announced a measured
    /// baseline while the denominator underneath was mostly a guess. It
    /// announced it soonest for the heaviest trainers, who are the users most
    /// likely to go looking.
    func testAThickSessionCountOnThreeDaysIsNotAnEstablishedBaseline() {
        let baseline = RecoveryBaseline(
            loads: Array(repeating: 40, count: 9),
            profile: .endurance,
            dailyLoads: [120, 120, 120]
        )
        XCTAssertTrue(baseline.hasEnoughSamples, "nine sessions is a usable per-session percentile")
        XCTAssertFalse(
            baseline.hasEstablishedBaseline,
            "three training days is still mostly the population reference"
        )
    }

    /// The claim the split is for: `hasEstablishedBaseline` is true exactly when
    /// `typicalLoad` has stopped blending in the reference. Asserted as an
    /// equivalence over a range rather than at one point, because the two are
    /// only worth separating if they agree everywhere.
    func testAnEstablishedBaselineIsExactlyWhenTheShrinkageHasLetGo() {
        for days in 1...16 {
            let baseline = RecoveryBaseline(
                loads: Array(repeating: 40, count: 40),
                profile: .endurance,
                dailyLoads: Array(repeating: 90, count: days)
            )
            let isPurelyPersonal = abs(baseline.typicalLoad - 90) < 0.0001
            XCTAssertEqual(
                baseline.hasEstablishedBaseline, isPurelyPersonal,
                "day \(days): confidence and shrinkage disagree about the sample"
            )
        }
    }

    /// And the per-session statistic keeps its per-session gate, because whether
    /// one workout was substantial enough to earn a countdown is a question
    /// about that workout.
    func testTheQuietThresholdStillCountsSessions() {
        let baseline = RecoveryBaseline(
            loads: Array(repeating: 40, count: 9),
            profile: .endurance,
            dailyLoads: [120, 120, 120]
        )
        XCTAssertGreaterThan(baseline.quietThreshold, RecoveryCalculator.absoluteCountdownFloor)
    }
}
