import XCTest

final class SessionLoadCalculatorTests: XCTestCase {

    // MARK: - Source selection ladder

    func testGoodHeartRateCoverageWinsOverEverythingElse() {
        let session = RecoveryFixtures.session(
            id: "s", profile: .endurance, minutes: 60, averageHR: 160,
            coverage: 0.9, energy: 600, effort: 3
        )
        XCTAssertEqual(SessionLoadCalculator.load(for: session).source, .heartRate)
    }

    func testPoorCoverageFallsThroughToReportedEffort() {
        let session = RecoveryFixtures.session(
            id: "s", profile: .strength, minutes: 60, averageHR: 110,
            coverage: 0.2, energy: 300, effort: 8
        )
        let load = SessionLoadCalculator.load(for: session)
        XCTAssertEqual(load.source, .reportedEffort)
        XCTAssertEqual(load.value, 60 * 8 * SessionLoadCalculator.effortToTrimpScale, accuracy: 0.001)
    }

    func testNoEffortFallsThroughToEnergy() {
        let session = RecoveryFixtures.session(
            id: "s", profile: .strength, minutes: 60, coverage: 0.1, energy: 360
        )
        XCTAssertEqual(SessionLoadCalculator.load(for: session).source, .energy)
    }

    func testNothingAtAllFallsThroughToDuration() {
        let session = RecoveryFixtures.session(id: "s", profile: .mixed, minutes: 45, coverage: 0)
        let load = SessionLoadCalculator.load(for: session)
        XCTAssertEqual(load.source, .duration)
        XCTAssertEqual(
            load.value,
            45 * WorkoutProfile.mixed.assumedEffort * SessionLoadCalculator.effortToTrimpScale,
            accuracy: 0.001
        )
    }

    func testCoverageExactlyAtTheThresholdStillUsesHeartRate() {
        let session = RecoveryFixtures.session(
            id: "s", profile: .endurance, minutes: 60, averageHR: 150,
            coverage: SessionLoadCalculator.minimumHeartRateCoverage
        )
        XCTAssertEqual(SessionLoadCalculator.load(for: session).source, .heartRate)
    }

    // MARK: - TRIMP shape

    func testTrimpRisesWithBothDurationAndIntensity() {
        func load(minutes: Double, hr: Double) -> Double {
            SessionLoadCalculator.load(for: RecoveryFixtures.session(
                id: "s", profile: .endurance, minutes: minutes, averageHR: hr, coverage: 0.95
            )).value
        }
        XCTAssertGreaterThan(load(minutes: 60, hr: 150), load(minutes: 30, hr: 150))
        XCTAssertGreaterThan(load(minutes: 60, hr: 170), load(minutes: 60, hr: 150))
    }

    func testAnHourOfHardWorkOutranksAnHourOfEasyWorkByMoreThanLinearly() {
        func load(hr: Double) -> Double {
            SessionLoadCalculator.load(for: RecoveryFixtures.session(
                id: "s", profile: .endurance, minutes: 60, averageHR: hr, restingHR: 50, maxHR: 190,
                coverage: 0.95
            )).value
        }
        // Reserve doubles from 0.35 to 0.70; the exponential weighting must make
        // the load more than double.
        let easy = load(hr: 99)     // reserve 0.35
        let hard = load(hr: 148)    // reserve 0.70
        XCTAssertGreaterThan(hard / easy, 2.0)
    }

    func testHeartRateBelowRestingClampsToZeroRatherThanGoingNegative() {
        let session = RecoveryFixtures.session(
            id: "s", profile: .endurance, minutes: 30, averageHR: 45,
            restingHR: 52, maxHR: 188, coverage: 0.9
        )
        XCTAssertGreaterThanOrEqual(SessionLoadCalculator.load(for: session).value, 0)
    }

    func testMissingRestingAndMaxFallBackToDefaultsRatherThanFailing() {
        let session = SessionInput(
            id: "s",
            profile: .endurance,
            startDate: RecoveryFixtures.now.addingTimeInterval(-3600),
            endDate: RecoveryFixtures.now,
            averageHeartRate: 150,
            restingHeartRate: nil,
            maxHeartRate: nil,
            heartRateCoverage: 0.9
        )
        let load = SessionLoadCalculator.load(for: session)
        XCTAssertEqual(load.source, .heartRate)
        XCTAssertGreaterThan(load.value, 0)
    }

    // MARK: - Mixed profile

    func testMixedTakesTheHigherOfHeartRateAndEffort() {
        // High effort, modest heart rate: effort should win.
        let effortDominant = RecoveryFixtures.session(
            id: "s", profile: .mixed, minutes: 60, averageHR: 120, coverage: 0.9, effort: 10
        )
        XCTAssertEqual(SessionLoadCalculator.mixedLoad(for: effortDominant).source, .reportedEffort)

        // High heart rate, low effort claim: heart rate should win.
        let hrDominant = RecoveryFixtures.session(
            id: "s", profile: .mixed, minutes: 60, averageHR: 178, coverage: 0.9, effort: 2
        )
        XCTAssertEqual(SessionLoadCalculator.mixedLoad(for: hrDominant).source, .heartRate)
    }

    func testMixedFallsBackToTheOrdinaryLadderWhenOnlyOneSourceExists() {
        let hrOnly = RecoveryFixtures.session(
            id: "s", profile: .mixed, minutes: 60, averageHR: 160, coverage: 0.9
        )
        XCTAssertEqual(SessionLoadCalculator.mixedLoad(for: hrOnly).source, .heartRate)

        let effortOnly = RecoveryFixtures.session(
            id: "s", profile: .mixed, minutes: 60, coverage: 0.1, effort: 7
        )
        XCTAssertEqual(SessionLoadCalculator.mixedLoad(for: effortOnly).source, .reportedEffort)
    }

    // MARK: - Cross-source scale

    func testTheThreeSourcesLandOnAComparableScale() {
        // A 60-minute threshold run (TRIMP) and a 60-minute RPE-8 session should
        // be within a factor of two of each other. If they drift apart, the
        // fallbacks stop being interchangeable and the profile curves lie.
        let trimp = SessionLoadCalculator.load(for: RecoveryFixtures.thresholdRun60).value
        let rpe = SessionLoadCalculator.load(for: RecoveryFixtures.strengthWithEffort).value
        XCTAssertGreaterThan(trimp / rpe, 0.5)
        XCTAssertLessThan(trimp / rpe, 2.0)
    }

    func testEnergyFallbackReadsAWalkAsEasyAndARunAsHarder() {
        let walk = RecoveryFixtures.session(
            id: "w", profile: .easy, minutes: 30, coverage: 0, energy: 105
        )
        let run = RecoveryFixtures.session(
            id: "r", profile: .endurance, minutes: 30, coverage: 0, energy: 360
        )
        XCTAssertLessThan(
            SessionLoadCalculator.load(for: walk).value,
            SessionLoadCalculator.load(for: run).value
        )
    }

    func testZeroDurationProducesZeroLoadRatherThanNaN() {
        let session = SessionInput(
            id: "s",
            profile: .endurance,
            startDate: RecoveryFixtures.now,
            endDate: RecoveryFixtures.now,
            averageHeartRate: 150,
            heartRateCoverage: 1.0
        )
        let load = SessionLoadCalculator.load(for: session)
        XCTAssertTrue(load.value.isFinite)
        XCTAssertEqual(load.value, 0, accuracy: 0.0001)
    }

    /// The bug this whole family of tests was missing: for a lifting session the
    /// answer depended on which sensor happened to work, not on the session.
    ///
    /// The same 60-minute lift scored 5.3 hours with a clean heart-rate trace,
    /// 7.2 hours from energy alone, and 24 hours once the effort prompt was
    /// answered. More information made the number smaller, and answering the
    /// question the app itself asked was punished with a shorter window.
    func testAStrengthSessionScoresTheSameWhicheverSensorWorked() {
        func lift(hr: Bool, energy: Bool) -> Double {
            SessionLoadCalculator.profiledLoad(for: RecoveryFixtures.session(
                id: "lift", profile: .strength, minutes: 60,
                averageHR: hr ? 118 : nil,
                coverage: hr ? 0.9 : 0.1,
                energy: energy ? 255 : nil
            )).value
        }
        let everything = lift(hr: true, energy: true)
        for (name, value) in [
            ("optical signal lost", lift(hr: false, energy: true)),
            ("no energy recorded", lift(hr: true, energy: false)),
            ("nothing but a duration", lift(hr: false, energy: false))
        ] {
            XCTAssertEqual(
                value, everything, accuracy: everything * 0.15,
                "a lift scored differently when \(name)"
            )
        }
    }

    /// Answering the effort prompt must only ever be able to raise the estimate.
    /// It is the one signal the user supplies by hand, and a shorter window in
    /// return for saying "that was hard" teaches them not to answer.
    func testAnsweringTheEffortPromptNeverShortensAStrengthSession() {
        for rpe in stride(from: 1.0, through: 10.0, by: 1.0) {
            let silent = SessionLoadCalculator.profiledLoad(for: RecoveryFixtures.session(
                id: "l", profile: .strength, minutes: 60, averageHR: 118, coverage: 0.9, energy: 255
            )).value
            let answered = SessionLoadCalculator.profiledLoad(for: RecoveryFixtures.session(
                id: "l", profile: .strength, minutes: 60, averageHR: 118, coverage: 0.9,
                energy: 255, effort: rpe
            )).value
            XCTAssertGreaterThanOrEqual(answered, silent, "RPE \(rpe) shortened the window")
        }
    }

    /// Court and combat sports hold the optical signal, so heart rate is a real
    /// measurement there rather than the systematic under-read it is at a
    /// barbell. Letting the coarse energy inference outbid it turned a
    /// 90-minute social tennis match into a 36-hour window.
    func testEnergyDoesNotOutbidHeartRateOnAMixedSession() {
        let tennis = RecoveryFixtures.session(
            id: "tennis", profile: .mixed, minutes: 90, averageHR: 133,
            coverage: 0.88, energy: 612
        )
        let load = SessionLoadCalculator.profiledLoad(for: tennis)
        XCTAssertEqual(load.source, .heartRate)
    }
}
