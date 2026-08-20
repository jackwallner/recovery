import XCTest

/// Model version 10: the things Recharge stopped guessing at.
///
/// Each of these replaced an assumption with a reading, and every one of them
/// moves the central number in the app, so each gets a property pinned rather
/// than a value: the direction of the effect, the bound on it, and the case
/// where the reading must be ignored.
final class MeasuredInputsTests: XCTestCase {

    // MARK: - Every session carries a cost

    /// The whole of the "None" fix, stated as an invariant. A walk costs
    /// something and starts nothing, and both halves have to be true at once —
    /// the first is what History renders, the second is the guarantee the `easy`
    /// profile exists to make.
    func testAnEasySessionCostsSomethingAndStartsNothing() {
        let walk = SessionInput(
            id: "walk",
            profile: .easy,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 45 * 60),
            averageHeartRate: 95,
            restingHeartRate: 55,
            maxHeartRate: 185,
            heartRateCoverage: 0.9,
            activityLabel: "walk"
        )
        let estimate = RecoveryCalculator.estimate(for: walk, baseline: .standard(for: .easy))

        XCTAssertFalse(estimate.producesCountdown, "an easy session started a countdown")
        XCTAssertEqual(estimate.hours, 0)
        XCTAssertEqual(estimate.totalHours, 0)
        XCTAssertGreaterThan(
            estimate.recoveryCostHours, 0,
            "an easy session still reports no cost, which is what History rendered as 'None'"
        )
    }

    /// A session under the quiet threshold is the *other* row that used to read
    /// "None", and it is a different case: not active recovery, just small.
    func testAQuietSessionCostsSomethingAndStartsNothing() {
        let spin = SessionInput(
            id: "spin",
            profile: .endurance,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 12 * 60),
            averageHeartRate: 105,
            restingHeartRate: 55,
            maxHeartRate: 185,
            heartRateCoverage: 0.9,
            activityLabel: "ride"
        )
        let estimate = RecoveryCalculator.estimate(for: spin, baseline: .standard(for: .endurance))

        XCTAssertLessThan(estimate.load.value, RecoveryCalculator.absoluteCountdownFloor)
        XCTAssertFalse(estimate.producesCountdown)
        XCTAssertGreaterThan(estimate.recoveryCostHours, 0)
    }

    /// The cost skips the six-hour countdown floor, which exists so a *countdown*
    /// is not over before bedtime and has nothing to say about what a short
    /// session cost. Without this the two numbers would collapse back together
    /// for everything small, which is exactly the range they exist to separate.
    func testTheCostIsNotSubjectToTheCountdownFloor() {
        let walk = SessionInput(
            id: "walk",
            profile: .easy,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 25 * 60),
            averageHeartRate: 92,
            restingHeartRate: 55,
            maxHeartRate: 185,
            heartRateCoverage: 0.9
        )
        let estimate = RecoveryCalculator.estimate(for: walk, baseline: .standard(for: .easy))
        XCTAssertLessThan(estimate.recoveryCostHours, RecoveryCalculator.minimumCountdownHours)
    }

    /// For a qualifying session the two agree, so nothing in History disagrees
    /// with the countdown the user watched run.
    func testCostAndCountdownAgreeForAQualifyingSession() {
        let run = SessionInput(
            id: "run",
            profile: .endurance,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 60 * 60),
            averageHeartRate: 158,
            restingHeartRate: 52,
            maxHeartRate: 187,
            heartRateCoverage: 0.95
        )
        let estimate = RecoveryCalculator.estimate(for: run, baseline: .standard(for: .endurance))
        XCTAssertTrue(estimate.producesCountdown)
        XCTAssertEqual(estimate.recoveryCostHours, estimate.hours, accuracy: 0.001)
    }

    /// It has to survive the round trip, for the reason `carriedHours` did not
    /// the first time: computed, published and rendered without ever reaching
    /// the record, so History rehydrates disagreeing with the app that wrote it.
    func testTheCostSurvivesPersistence() throws {
        let walk = SessionInput(
            id: "walk",
            profile: .easy,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 45 * 60),
            averageHeartRate: 95,
            restingHeartRate: 55,
            maxHeartRate: 185,
            heartRateCoverage: 0.9
        )
        let estimate = RecoveryCalculator.estimate(for: walk, baseline: .standard(for: .easy))
        let record = RecoveryStateRecord(estimate: estimate)

        XCTAssertEqual(record.estimate.recoveryCostHours, estimate.recoveryCostHours, accuracy: 0.001)

        let data = try JSONEncoder().encode(estimate)
        let decoded = try JSONDecoder().decode(RecoveryEstimate.self, from: data)
        XCTAssertEqual(decoded.recoveryCostHours, estimate.recoveryCostHours, accuracy: 0.001)
    }

    /// A record written before the field existed decodes to `hours`, which is
    /// the truthful legacy value both ways round: a qualifying session's cost
    /// *was* its hours, and a quiet session's recorded cost genuinely was zero.
    func testALegacyRecordDecodesItsCostAsItsHours() throws {
        let json = """
        {
          "sessionID": "legacy", "profile": "endurance", "activityLabel": "run",
          "calculatedAt": 0, "sessionEnd": 0, "readyAt": 3600,
          "hours": 18, "windowLowHours": 15.3, "windowHighHours": 20.7,
          "load": {"value": 90, "source": "heartRate", "heartRateCoverage": 0.9},
          "relativeLoad": 1.3, "category": "hard", "confidence": "medium",
          "reasons": [], "modelVersion": 8
        }
        """
        let decoded = try JSONDecoder().decode(RecoveryEstimate.self, from: Data(json.utf8))
        XCTAssertEqual(decoded.recoveryCostHours, 18, accuracy: 0.001)
    }

    // MARK: - The heart-rate ceiling

    /// The observed maximum wins when it is higher, which is the ordinary case
    /// for anybody who has ever raced.
    func testAnObservedMaximumBeatsThePrediction() {
        var profile = AthleteProfile(age: 40, sex: .male)
        let predicted = try? XCTUnwrap(profile.predictedMaxHeartRate)
        XCTAssertNotNil(predicted)

        profile.observedMaxHeartRate = 195
        XCTAssertEqual(profile.effectiveMaxHeartRate, 195)
        XCTAssertTrue(profile.usesObservedMaxHeartRate)
    }

    /// And loses when it is lower. A real maximum is elicited by a maximal
    /// effort, so somebody who has never gone that hard shows a peak well below
    /// their true ceiling — and taking it literally would inflate the intensity
    /// of every session they have ever recorded.
    func testAnObservedPeakBelowThePredictionIsIgnored() {
        var profile = AthleteProfile(age: 40, sex: .male)
        let predicted = profile.predictedMaxHeartRate ?? 0
        profile.observedMaxHeartRate = predicted - 20

        XCTAssertEqual(profile.effectiveMaxHeartRate, predicted)
        XCTAssertFalse(profile.usesObservedMaxHeartRate)
    }

    /// With no age and no history there is nothing to say, and the caller falls
    /// back to `SessionLoadCalculator.defaultMaxHeartRate`.
    func testNoAgeAndNoHistoryLeavesTheCeilingUnset() {
        XCTAssertNil(AthleteProfile.empty.effectiveMaxHeartRate)
    }

    /// A higher ceiling makes the same session read as *less* intense, and
    /// therefore never lengthens its window. The direction matters more than the
    /// magnitude: this is the input the whole heart-rate path divides by.
    func testARaisedCeilingNeverLengthensTheWindow() {
        func hours(maxHeartRate: Double) -> Double {
            let run = SessionInput(
                id: "run",
                profile: .endurance,
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 60 * 60),
                averageHeartRate: 158,
                restingHeartRate: 52,
                maxHeartRate: maxHeartRate,
                heartRateCoverage: 0.95
            )
            return RecoveryCalculator.estimate(for: run, baseline: .standard(for: .endurance)).hours
        }

        var previous = Double.greatestFiniteMagnitude
        for ceiling in stride(from: 170.0, through: 205.0, by: 5) {
            let value = hours(maxHeartRate: ceiling)
            XCTAssertLessThanOrEqual(value, previous + 0.001, "raising the ceiling to \(ceiling) lengthened the window")
            previous = value
        }
    }

    // MARK: - Body mass on the energy path

    /// The residual the energy path was always known to carry. HealthKit's
    /// active energy already includes body mass, so at the same reserve fraction
    /// a heavier person burns more — and before this correction that read as
    /// their having worked harder.
    func testBodyMassRemovesTheEnergyPathsWeightBias() {
        /// Kilocalories a person of `mass` burns in an hour at the same fraction
        /// of heart-rate reserve, on the model's own reference relationship.
        func energy(forMass mass: Double, reserve: Double) -> Double {
            60 * reserve * SessionLoadCalculator.referenceEnergyAtFullReserve
                * (mass / SessionLoadCalculator.referenceBodyMassKilograms)
        }

        func load(mass: Double) -> Double {
            let session = SessionInput(
                id: "ride",
                profile: .endurance,
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 60 * 60),
                activeEnergyKilocalories: energy(forMass: mass, reserve: 0.65),
                bodyMassKilograms: mass
            )
            return SessionLoadCalculator.profiledLoad(for: session).value
        }

        // Same session, three body masses. Without the correction the 95 kg
        // figure is about a quarter above the 60 kg one for identical work.
        let light = load(mass: 60)
        let reference = load(mass: 75)
        let heavy = load(mass: 95)
        XCTAssertEqual(light, reference, accuracy: 0.5)
        XCTAssertEqual(heavy, reference, accuracy: 0.5)
    }

    /// No weight in Health means the reference adult, which is exactly what this
    /// path did before body mass was read at all.
    func testAMissingBodyMassKeepsTheOldBehaviour() {
        XCTAssertEqual(
            SessionLoadCalculator.referenceEnergy(forBodyMass: nil),
            SessionLoadCalculator.referenceEnergyAtFullReserve
        )
    }

    /// One implausible sample from a kitchen scale must not halve or double
    /// somebody's whole history.
    func testAnAbsurdBodyMassIsBounded() {
        let ratios = [1.0, 300.0, 0.0, -20.0].map {
            SessionLoadCalculator.referenceEnergy(forBodyMass: $0)
                / SessionLoadCalculator.referenceEnergyAtFullReserve
        }
        for ratio in ratios {
            XCTAssertGreaterThanOrEqual(ratio, 0.6)
            XCTAssertLessThanOrEqual(ratio, 1.7)
        }
        // A value the initialiser rejects outright never reaches the calculator.
        let session = SessionInput(
            id: "x",
            profile: .endurance,
            startDate: Date(timeIntervalSince1970: 0),
            endDate: Date(timeIntervalSince1970: 3600),
            bodyMassKilograms: 4
        )
        XCTAssertNil(session.bodyMassKilograms)
    }

    // MARK: - VO2 max in the fitness scale

    /// It moves the standard denominator in the right direction and stays inside
    /// the range the two questionnaire terms already spanned, so a third
    /// measured term cannot widen the envelope `GarminAnchorTests` was fitted at.
    func testVO2MaxMovesTheFitnessScaleWithinTheExistingBounds() {
        var lower = AthleteProfile.empty
        lower.vo2Max = 28
        var upper = AthleteProfile.empty
        upper.vo2Max = 68

        XCTAssertLessThan(lower.fitnessScale, 1)
        XCTAssertGreaterThan(upper.fitnessScale, 1)
        for profile in [lower, upper] {
            XCTAssertGreaterThanOrEqual(profile.fitnessScale, 0.78)
            XCTAssertLessThanOrEqual(profile.fitnessScale, 1.40)
        }
    }

    /// A fitter reading means a bigger ordinary training day, which means the
    /// same session is a smaller multiple of it — so it can only ever shorten.
    /// The same claim `testAddingTrainingVolumeOnlyEverShortensTheWindow` makes
    /// about the questionnaire.
    func testMoreCardioFitnessOnlyEverShortensTheStandardWindow() {
        func hours(vo2Max: Double?) -> Double {
            var profile = AthleteProfile.empty
            profile.vo2Max = vo2Max
            let run = SessionInput(
                id: "run",
                profile: .endurance,
                startDate: Date(timeIntervalSince1970: 0),
                endDate: Date(timeIntervalSince1970: 60 * 60),
                averageHeartRate: 158,
                restingHeartRate: 52,
                maxHeartRate: 187,
                heartRateCoverage: 0.95
            )
            return RecoveryCalculator.estimate(
                for: run,
                baseline: .standard(for: .endurance, fitnessScale: profile.fitnessScale)
            ).hours
        }

        // Monotone *across the sweep*, not against the no-reading case: an
        // absent VO2 max leaves the scale at 1, which sits in the middle of the
        // range, so a low reading legitimately produces a longer window than no
        // reading at all. That is the feature — the standard tier's job is to
        // answer for the person it has been told about.
        var previous = Double.greatestFiniteMagnitude
        for value in stride(from: 25.0, through: 70.0, by: 5) {
            let current = hours(vo2Max: value)
            XCTAssertLessThanOrEqual(current, previous + 0.001, "VO2 max \(value) lengthened the window")
            previous = current
        }

        // And a reading either side of the anchor straddles the unmeasured case,
        // which is what "45 is the reference adult" has to mean.
        let unmeasured = hours(vo2Max: nil)
        XCTAssertGreaterThan(hours(vo2Max: 30), unmeasured)
        XCTAssertLessThan(hours(vo2Max: 60), unmeasured)
    }

    /// A reading outside the plausible human range says nothing.
    func testAnImplausibleVO2MaxIsIgnored() {
        for value in [0.0, 5.0, 120.0] {
            var profile = AthleteProfile.empty
            profile.vo2Max = value
            XCTAssertEqual(profile.fitnessScale, 1, "VO2 max \(value) reached the fitness scale")
        }
    }

    // MARK: - Heart-rate recovery

    /// A faster fall shortens, a slower one lengthens, and neither runs away:
    /// the signal is used for its direction and rough size, because Health does
    /// not say which workout each sample belongs to.
    func testFasterHeartRateRecoveryShortensAndIsBounded() {
        func factor(_ recovery: Double) -> Double? {
            let days = (0..<5).map {
                PersonalRecoveryModel.DayPoint(
                    date: Date(timeIntervalSince1970: Double($0) * 86_400),
                    heartRateRecovery: recovery
                )
            }
            return PersonalRecoveryModel.kineticsEvidence(days: days).factor
        }

        let fast = try? XCTUnwrap(factor(42))
        let slow = try? XCTUnwrap(factor(14))
        XCTAssertNotNil(fast)
        XCTAssertNotNil(slow)
        XCTAssertLessThan(fast ?? 1, 1)
        XCTAssertGreaterThan(slow ?? 1, 1)
        for value in [fast, slow].compactMap({ $0 }) {
            XCTAssertGreaterThanOrEqual(value, 0.85)
            XCTAssertLessThanOrEqual(value, 1.18)
        }
    }

    /// An average responder gets no adjustment at all, which is what a
    /// multiplier on a population table should do.
    func testAnAverageHeartRateRecoverySaysNothing() {
        let days = (0..<5).map {
            PersonalRecoveryModel.DayPoint(
                date: Date(timeIntervalSince1970: Double($0) * 86_400),
                heartRateRecovery: PersonalRecoveryModel.referenceHeartRateRecovery
            )
        }
        XCTAssertEqual(PersonalRecoveryModel.kineticsEvidence(days: days).factor ?? 0, 1, accuracy: 0.001)
    }

    /// Two readings is not "how this person recovers".
    func testTooFewRecoverySamplesProduceNoFactor() {
        let days = (0..<2).map {
            PersonalRecoveryModel.DayPoint(
                date: Date(timeIntervalSince1970: Double($0) * 86_400),
                heartRateRecovery: 45
            )
        }
        XCTAssertNil(PersonalRecoveryModel.kineticsEvidence(days: days).factor)
    }

    // MARK: - Overnight respiratory rate

    /// It moves the estimate in the same direction an elevated resting heart
    /// rate does, and by less — and adding it cannot widen the total range,
    /// because the clamp on the whole adjustment is unchanged.
    func testRespiratoryRateLengthensButCannotDominate() {
        let elevated = RecoveryContext(respiratoryRate: 17, respiratoryRateBaseline: 14)
        let settled = RecoveryContext(respiratoryRate: 12.5, respiratoryRateBaseline: 14)

        XCTAssertGreaterThan(RecoveryCalculator.contextAdjustment(elevated), 0)
        XCTAssertLessThan(RecoveryCalculator.contextAdjustment(settled), 0)

        let everythingBad = RecoveryContext(
            sleepHours: 4.2,
            heartRateVariability: 30,
            heartRateVariabilityBaseline: 60,
            restingHeartRate: 62,
            restingHeartRateBaseline: 52,
            respiratoryRate: 18,
            respiratoryRateBaseline: 14
        )
        XCTAssertLessThanOrEqual(
            RecoveryCalculator.contextAdjustment(everythingBad),
            RecoveryCalculator.maximumContextAdjustment + 0.0001
        )
    }

    /// A reading with nothing to compare it against says nothing.
    func testRespiratoryRateWithNoBaselineSaysNothing() {
        let context = RecoveryContext(respiratoryRate: 19)
        XCTAssertEqual(RecoveryCalculator.contextAdjustment(context), 0, accuracy: 0.0001)
    }

    // MARK: - The receipt

    /// A row only exists when there is a real value behind it. A receipt for
    /// something that was not read is not evidence of anything, and a list of
    /// blanks in front of somebody deciding whether to trust the app argues the
    /// opposite of what it is there for.
    func testTheIngestSummaryHasNoRowsForMissingReadings() {
        XCTAssertTrue(HealthIngestSummary(readings: .init(), usesObservedMaxHeartRate: false).isEmpty)

        var readings = HealthIngestSummary.Readings()
        readings.workoutCount = 40
        readings.daysCovered = 90
        readings.activityTypes = 3
        let summary = HealthIngestSummary(readings: readings, usesObservedMaxHeartRate: false)

        XCTAssertEqual(summary.rows.count, 1)
        XCTAssertEqual(summary.rows.first?.id, "workouts")
        for row in summary.rows {
            XCTAssertFalse(row.value.isEmpty)
            XCTAssertFalse(row.value.contains("—"))
        }
    }

    /// The heart-rate row says which kind of figure it is, because a measured
    /// ceiling and a predicted one are different claims.
    func testTheIngestSummaryDistinguishesAMeasuredCeilingFromAPredictedOne() {
        var readings = HealthIngestSummary.Readings()
        readings.observedMaxHeartRate = 187
        readings.sessionsWithHeartRate = 88

        let measured = HealthIngestSummary(readings: readings, usesObservedMaxHeartRate: true)
        let predicted = HealthIngestSummary(readings: readings, usesObservedMaxHeartRate: false)

        XCTAssertNotEqual(
            measured.rows.first?.title,
            predicted.rows.first?.title,
            "the receipt claims a measured ceiling and a formula are the same thing"
        )
    }
}
