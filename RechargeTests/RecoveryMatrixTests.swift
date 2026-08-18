import XCTest

/// The audit the model has to survive before a number goes in front of a
/// stranger.
///
/// The rest of the suite tests the model on the sessions it was designed from.
/// This tests it on the ones it was not: every activity type HealthKit defines,
/// at three durations and three intensities, for seven people who recover at
/// different rates, under seven combinations of working sensors. That is around
/// thirty thousand scored sessions per tier, and none of them was chosen because
/// the model looked good on it.
///
/// The assertions here are deliberately **properties**, not values. A tuning
/// change is allowed to move every number in the table; it is not allowed to
/// make a longer session return a shorter window, to make answering a question
/// cost the user something, or to produce a countdown that is not a number.
final class RecoveryMatrixTests: XCTestCase {

    // MARK: - Structural

    /// Every cell, both tiers: finite, bounded, ordered, and consistent with the
    /// timestamp it publishes.
    ///
    /// The countdown is rendered from `readyAt` on four surfaces that cannot ask
    /// a question, so a NaN here is a widget that shows nothing forever.
    func testEveryCellProducesABoundedFiniteWindow() {
        var checked = 0
        for cell in AthleteMatrix.sweep() {
            for estimate in [cell.standard, cell.personalized] {
                checked += 1
                XCTAssertTrue(estimate.hours.isFinite, "non-finite hours: \(cell.label)")
                XCTAssertGreaterThanOrEqual(estimate.hours, 0, cell.label)
                XCTAssertLessThanOrEqual(estimate.hours, RecoveryCalculator.maximumHours, cell.label)
                XCTAssertLessThanOrEqual(estimate.windowLowHours, estimate.hours, cell.label)
                XCTAssertGreaterThanOrEqual(estimate.windowHighHours, estimate.hours, cell.label)
                XCTAssertGreaterThanOrEqual(estimate.readyAt, estimate.sessionEnd, cell.label)
                XCTAssertTrue(estimate.relativeLoad.isFinite, "non-finite relative load: \(cell.label)")
                XCTAssertTrue(estimate.load.value.isFinite, "non-finite load: \(cell.label)")
                XCTAssertGreaterThanOrEqual(estimate.load.value, 0, cell.label)
            }
        }
        XCTAssertGreaterThan(checked, 10_000, "the sweep collapsed — the matrix is not being built")
    }

    /// A qualifying session clears the documented floor, whoever did it and
    /// whatever the sensors managed to record.
    func testTheSixHourFloorHoldsEverywhere() {
        for cell in AthleteMatrix.sweep() {
            for estimate in [cell.standard, cell.personalized] where estimate.producesCountdown {
                XCTAssertGreaterThanOrEqual(
                    estimate.hours, RecoveryCalculator.minimumCountdownHours,
                    "below the floor: \(cell.label)"
                )
            }
        }
    }

    /// Active recovery never starts a countdown — not at two hours, not at the
    /// top intensity, not for the athlete whose baseline is nearly empty.
    func testActiveRecoveryNeverStartsACountdown() {
        for cell in AthleteMatrix.sweep() where cell.session.profile == .easy {
            XCTAssertEqual(cell.standard.hours, 0, "easy session started a countdown: \(cell.label)")
            XCTAssertEqual(cell.personalized.hours, 0, "easy session started a countdown: \(cell.label)")
        }
    }

    /// Every code HealthKit defines lands on a profile, a label, and a number.
    /// The off-by-one in the activity table was invisible for the app's whole
    /// life because every test asked the classifier about a code it had looked
    /// up in the same wrong table; sweeping the raw values is what makes a
    /// future shift visible.
    func testEveryActivityCodeIsScorable() {
        let codes = Set(AthleteMatrix.sweep().map(\.code))
        XCTAssertEqual(
            codes.count, AthleteMatrix.activityCodes.count,
            "the sweep dropped activity codes"
        )
        for code in AthleteMatrix.activityCodes {
            let label = WorkoutClassifier.label(activityCode: code)
            XCTAssertFalse(label.isEmpty, "code \(code) has no label")
            XCTAssertFalse(label.contains("HK"), "code \(code) leaks a HealthKit name")
        }
    }

    // MARK: - Monotonicity

    /// Longer is never shorter, holding everything else fixed.
    ///
    /// `RecoveryCalculator.curve` gives this by construction, but the load stage
    /// is where it can break: a source that saturates, or a maximum taken across
    /// sources that do not all scale with duration, would break it without
    /// touching the curve.
    func testALongerSessionIsNeverShorter() {
        for code in AthleteMatrix.activityCodes {
            for intensity in AthleteMatrix.intensities {
                for persona in AthleteMatrix.personas {
                    for sensors in AthleteMatrix.sensorScenarios {
                        var previous = -1.0
                        var previousPersonalized = -1.0
                        for minutes in AthleteMatrix.durations.sorted() {
                            let shape = AthleteMatrix.Shape(
                                minutes: minutes,
                                reserveFraction: intensity.reserve,
                                reportedEffort: intensity.effort,
                                kilocaloriesPerMinute: intensity.kilocaloriesPerMinute
                            )
                            let session = AthleteMatrix.session(
                                code: code, shape: shape, persona: persona, sensors: sensors
                            )
                            let standard = AthleteMatrix.standard(session, persona: persona).hours
                            let personalized = AthleteMatrix.personalized(session, persona: persona).hours
                            XCTAssertGreaterThanOrEqual(
                                standard, previous,
                                "standard window shrank as the session got longer: "
                                    + "\(session.id) at \(Int(minutes)) minutes"
                            )
                            XCTAssertGreaterThanOrEqual(
                                personalized, previousPersonalized,
                                "personalized window shrank as the session got longer: "
                                    + "\(session.id) at \(Int(minutes)) minutes"
                            )
                            previous = standard
                            previousPersonalized = personalized
                        }
                    }
                }
            }
        }
    }

    /// Harder is never shorter, holding everything else fixed. Every term of the
    /// intensity ladder rises together, so this holds whichever source the
    /// profile's rule ends up reading.
    func testAHarderSessionIsNeverShorter() {
        for code in AthleteMatrix.activityCodes {
            for minutes in AthleteMatrix.durations {
                for persona in AthleteMatrix.personas {
                    for sensors in AthleteMatrix.sensorScenarios {
                        var previous = -1.0
                        var previousPersonalized = -1.0
                        for intensity in AthleteMatrix.intensities {
                            let shape = AthleteMatrix.Shape(
                                minutes: minutes,
                                reserveFraction: intensity.reserve,
                                reportedEffort: intensity.effort,
                                kilocaloriesPerMinute: intensity.kilocaloriesPerMinute
                            )
                            let session = AthleteMatrix.session(
                                code: code, shape: shape, persona: persona, sensors: sensors
                            )
                            let standard = AthleteMatrix.standard(session, persona: persona).hours
                            let personalized = AthleteMatrix.personalized(session, persona: persona).hours
                            XCTAssertGreaterThanOrEqual(
                                standard, previous,
                                "standard window shrank as the session got harder: \(session.id)"
                            )
                            XCTAssertGreaterThanOrEqual(
                                personalized, previousPersonalized,
                                "personalized window shrank as the session got harder: \(session.id)"
                            )
                            previous = standard
                            previousPersonalized = personalized
                        }
                    }
                }
            }
        }
    }

    // MARK: - Answering a question must never cost the user

    /// The bug class this whole matrix exists for.
    ///
    /// A user who answers the effort prompt with a number at or above what the
    /// app would have assumed for the session type must never get a *shorter*
    /// window for having answered. The inverse is legitimate and deliberately
    /// not asserted: reporting RPE 4 on a session the app assumed was RPE 5 is
    /// the user saying it was easy, and shortening the window is the correct
    /// response to that.
    func testAnHonestHardEffortAnswerNeverShortensTheWindow() {
        let withEffort = AthleteMatrix.sensorScenarios.filter(\.hasEffort)
        for code in AthleteMatrix.activityCodes {
            for shape in AthleteMatrix.shapes {
                for persona in AthleteMatrix.personas {
                    for sensors in withEffort {
                        let profile = WorkoutClassifier.profile(activityCode: code)
                        guard shape.reportedEffort >= profile.assumedEffort else { continue }

                        let silent = AthleteMatrix.Sensors(
                            name: sensors.name + "-unanswered",
                            heartRateCoverage: sensors.heartRateCoverage,
                            hasEnergy: sensors.hasEnergy,
                            hasEffort: false
                        )
                        let answered = AthleteMatrix.session(
                            code: code, shape: shape, persona: persona, sensors: sensors
                        )
                        let unanswered = AthleteMatrix.session(
                            code: code, shape: shape, persona: persona, sensors: silent
                        )
                        XCTAssertGreaterThanOrEqual(
                            AthleteMatrix.standard(answered, persona: persona).hours,
                            AthleteMatrix.standard(unanswered, persona: persona).hours,
                            "answering the effort question shortened the standard window: \(answered.id)"
                        )
                        XCTAssertGreaterThanOrEqual(
                            AthleteMatrix.personalized(answered, persona: persona).hours,
                            AthleteMatrix.personalized(unanswered, persona: persona).hours,
                            "answering the effort question shortened the personalized window: \(answered.id)"
                        )
                    }
                }
            }
        }
    }

    /// The same session, with and without a working heart-rate trace, must not
    /// produce wildly different windows. This is the reproducible form of the
    /// sensor-spread claim in the project guide: it prints the distribution and
    /// fails if the worst case drifts past what the load rules are supposed to
    /// guarantee.
    ///
    /// Spread is measured only over scenarios that produce a countdown at all,
    /// and `testQualificationRarelyDependsOnTheSensors` covers the other half.
    func testSensorAvailabilityDoesNotMoveTheWindowMuch() {
        var spreadsByProfile: [WorkoutProfile: [Double]] = [:]

        for code in AthleteMatrix.activityCodes {
            for shape in AthleteMatrix.shapes {
                for persona in AthleteMatrix.personas {
                    let profile = WorkoutClassifier.profile(activityCode: code)
                    guard profile != .easy else { continue }
                    let hours = AthleteMatrix.reachableScenarios(for: profile).map { sensors in
                        AthleteMatrix.personalized(
                            AthleteMatrix.session(
                                code: code, shape: shape, persona: persona, sensors: sensors
                            ),
                            persona: persona
                        ).hours
                    }.filter { $0 > 0 }

                    guard let low = hours.min(), let high = hours.max(), low > 0 else { continue }
                    spreadsByProfile[profile, default: []].append(high / low)
                }
            }
        }

        var lines = ["", "── sensor-availability spread, personalized tier ".padding(toLength: 72, withPad: "─", startingAt: 0)]
        lines.append("profile      cells    mean     p95      worst")
        for profile in [WorkoutProfile.endurance, .strength, .mixed] {
            guard let spreads = spreadsByProfile[profile], !spreads.isEmpty else { continue }
            let sorted = spreads.sorted()
            let mean = spreads.reduce(0, +) / Double(spreads.count)
            let p95 = sorted[min(Int(Double(sorted.count) * 0.95), sorted.count - 1)]
            lines.append(
                profile.rawValue.padding(toLength: 13, withPad: " ", startingAt: 0)
                    + String(format: "%-9d%-9.2f%-9.2f%.2f", spreads.count, mean, p95, sorted.last ?? 0)
            )

            XCTAssertLessThanOrEqual(
                mean, Self.meanSpreadCeiling[profile] ?? 2.0,
                "mean sensor spread for \(profile.rawValue) regressed"
            )
            XCTAssertLessThanOrEqual(
                sorted.last ?? 0, Self.worstSpreadCeiling[profile] ?? 4.0,
                "worst-case sensor spread for \(profile.rawValue) regressed"
            )
        }
        print(lines.joined(separator: "\n"))
    }

    /// Ceilings, not targets, set about 15% above what the model currently
    /// produces so an ordinary tuning change passes and a structural
    /// regression — a source dropping out of a maximum, a floor removed, a
    /// fallback recalibrated onto a different curve — fails.
    ///
    /// Measured at model version 4: endurance 1.63 mean / 2.97 worst, strength
    /// 1.36 / 2.33, mixed 1.87 / 3.53. What remains is almost entirely the
    /// blind fallback: a session with no heart rate, no energy, and no effort
    /// answer is scored at what its type usually costs, and no such guess can
    /// know that this particular hour was an easy one. Those estimates report
    /// low confidence, which is the honest thing available.
    private static let meanSpreadCeiling: [WorkoutProfile: Double] = [
        .endurance: 1.80, .strength: 1.50, .mixed: 2.10
    ]
    private static let worstSpreadCeiling: [WorkoutProfile: Double] = [
        .endurance: 3.40, .strength: 2.70, .mixed: 4.00
    ]

    /// For a strength session, more information may only ever lengthen the
    /// window — never shorten it.
    ///
    /// This is the guarantee `strengthLoad` exists to provide, and it is
    /// stronger than any spread number: every signal under-reads a lift in its
    /// own way, so the rule takes the maximum across all four, and a maximum
    /// over a superset cannot be smaller. It is asserted rather than measured
    /// because it is the property the 5.3h/7.2h/24h inversion violated.
    func testForAStrengthSessionMoreInformationNeverShortensTheWindow() {
        let full = AthleteMatrix.sensorScenarios[0]
        let bare = AthleteMatrix.sensorScenarios[AthleteMatrix.sensorScenarios.count - 1]

        for code in AthleteMatrix.activityCodes {
            guard WorkoutClassifier.profile(activityCode: code) == .strength else { continue }
            for shape in AthleteMatrix.shapes {
                for persona in AthleteMatrix.personas {
                    func hours(_ sensors: AthleteMatrix.Sensors) -> Double {
                        AthleteMatrix.personalized(
                            AthleteMatrix.session(
                                code: code, shape: shape, persona: persona, sensors: sensors
                            ),
                            persona: persona
                        ).hours
                    }
                    let everything = hours(full)
                    let nothing = hours(bare)
                    for sensors in AthleteMatrix.sensorScenarios {
                        let partial = hours(sensors)
                        XCTAssertGreaterThanOrEqual(
                            everything, partial,
                            "a lift scored higher on \(sensors.name) than on every signal at once"
                        )
                        XCTAssertLessThanOrEqual(
                            nothing, partial,
                            "a lift with no data at all outscored \(sensors.name)"
                        )
                    }
                }
            }
        }
    }

    /// The inferred path and the measured path have to agree about the same
    /// session.
    ///
    /// `energyLoad` estimates the fraction of aerobic reserve a session
    /// sustained from its burn rate and costs it on the same curve
    /// `heartRateLoad` uses, so for an athlete whose burn rate follows the
    /// reference relation the two land on the same number. They did not before:
    /// the old inference mapped kilocalories onto a perceived effort with a
    /// different shape, matched heart rate at the hard end, and roughly doubled
    /// it at the easy end — which is how a 60-minute easy run scored no
    /// countdown from a watch and eighteen hours from a phone.
    ///
    /// The fixtures' kilocalorie figures come from %HRR ≈ %VO2R for a 75 kg
    /// adult at 45 ml/kg/min, which is where `referenceEnergyAtFullReserve`
    /// comes from too, so this pins the two constants together rather than
    /// asserting a coincidence.
    func testTheEnergyPathAgreesWithTheHeartRatePathForTheReferenceAthlete() {
        let persona = AthleteMatrix.personas[1]
        for shape in AthleteMatrix.shapes {
            let code = WorkoutClassifier.ActivityCode.running.rawValue
            let measured = SessionLoadCalculator.load(for: AthleteMatrix.session(
                code: code, shape: shape, persona: persona,
                sensors: AthleteMatrix.Sensors(
                    name: "hr", heartRateCoverage: 0.95, hasEnergy: false, hasEffort: false
                )
            ))
            let inferred = SessionLoadCalculator.load(for: AthleteMatrix.session(
                code: code, shape: shape, persona: persona,
                sensors: AthleteMatrix.Sensors(
                    name: "kcal", heartRateCoverage: nil, hasEnergy: true, hasEffort: false
                )
            ))
            XCTAssertEqual(measured.source, .heartRate)
            XCTAssertEqual(inferred.source, .energy)
            XCTAssertEqual(
                inferred.value / measured.value, 1, accuracy: 0.10,
                "the energy inference drifted off the heart-rate scale at \(shape.name)"
            )
        }
    }

    /// Whether a session starts a countdown at all should be a fact about the
    /// session, not about which sensor happened to work. Reported rather than
    /// asserted per cell: a session sitting exactly on the quiet threshold can
    /// legitimately fall either side of it. What is asserted is that it stays
    /// rare, because "the watch decides whether your workout counted" is the
    /// complaint this model cannot survive.
    func testQualificationRarelyDependsOnTheSensors() {
        var total = 0
        var inconsistent = 0
        var examples: [String] = []

        for code in AthleteMatrix.activityCodes {
            for shape in AthleteMatrix.shapes {
                for persona in AthleteMatrix.personas {
                    let profile = WorkoutClassifier.profile(activityCode: code)
                    guard profile != .easy else { continue }
                    let qualifies = AthleteMatrix.reachableScenarios(for: profile).map { sensors in
                        AthleteMatrix.personalized(
                            AthleteMatrix.session(
                                code: code, shape: shape, persona: persona, sensors: sensors
                            ),
                            persona: persona
                        ).producesCountdown
                    }
                    total += 1
                    if Set(qualifies).count > 1 {
                        inconsistent += 1
                        if examples.count < 5 {
                            examples.append("\(WorkoutClassifier.label(activityCode: code)) \(shape.name) \(persona.name)")
                        }
                    }
                }
            }
        }

        let rate = Double(inconsistent) / Double(max(total, 1))
        print(String(
            format: "\nsensor-dependent qualification: %d of %d cells (%.1f%%)%@",
            inconsistent, total, rate * 100,
            examples.isEmpty ? "" : "\n  e.g. " + examples.joined(separator: "\n  e.g. ")
        ))
        // 8.2% at model version 4, and every one of them is a session sitting
        // near the person's quiet threshold where the blind fallback lands on
        // the other side of it.
        XCTAssertLessThanOrEqual(rate, 0.10, "which sensor worked is deciding whether a workout counted")
    }

    // MARK: - Across athletes

    /// The free tier is the same table for everyone.
    ///
    /// Everyone, here, means everyone with the same measured heart-rate range:
    /// the age-predicted ceiling and the resting rate are measurement inputs and
    /// apply on both tiers, by design. Nothing else about the person may reach a
    /// standard estimate — not their history, not their questionnaire answers,
    /// not their training volume.
    func testTheStandardTierDependsOnTheSessionAndTheHeartRateRangeOnly() {
        var byKey: [String: (hours: Double, label: String)] = [:]
        for cell in AthleteMatrix.sweep() {
            let key = [
                String(cell.code),
                cell.shape.name,
                cell.sensors.name,
                String(cell.persona.maxHeartRate),
                String(cell.persona.restingHeartRate),
                // The stated fitness level is part of the standard tier now, so
                // it belongs in the key. What must still never appear here is
                // anything the person has *done*: history, context, calibration,
                // the thirty-day analysis. Two personas who answered the same
                // two questions the same way get the same free-tier number
                // however differently they train.
                String(format: "%.6f", cell.persona.profile.fitnessScale)
            ].joined(separator: "|")

            if let existing = byKey[key] {
                XCTAssertEqual(
                    cell.standard.hours, existing.hours, accuracy: 1e-9,
                    "the standard estimate saw something personal: "
                        + "\(cell.label) vs \(existing.label)"
                )
            } else {
                byKey[key] = (cell.standard.hours, cell.label)
            }
        }
    }

    /// Age lowers the predicted ceiling, which raises the reserve fraction the
    /// same absolute heart rate represents, which lengthens the window.
    ///
    /// Asserted on the **standard** tier, because that is the claim that gets
    /// argued with: an age-predicted maximum is part of measuring the session,
    /// not part of personalising it, and a free 58-year-old scored against a
    /// flat 185 is not getting a standard estimate, they are getting a wrong one.
    func testTheSameHeartRateCostsAnOlderAthleteMore() {
        let restingHeartRate = 60.0
        let averageHeartRate = 150.0

        var previousHours = 0.0
        var previousAge = 0
        for age in [25, 40, 55, 70] {
            let profile = AthleteProfile(age: age, sex: .male)
            guard let max = profile.predictedMaxHeartRate else {
                return XCTFail("no predicted maximum at age \(age)")
            }
            let session = SessionInput(
                id: "age-\(age)",
                profile: .endurance,
                startDate: AthleteMatrix.now.addingTimeInterval(-3_600),
                endDate: AthleteMatrix.now,
                durationMinutes: 60,
                averageHeartRate: averageHeartRate,
                restingHeartRate: restingHeartRate,
                maxHeartRate: max,
                heartRateCoverage: 0.95,
                activityLabel: "run"
            )
            let hours = AthleteMatrix.standard(session, persona: AthleteMatrix.unanswered).hours
            XCTAssertGreaterThanOrEqual(
                hours, previousHours,
                "the same 150 bpm hour got cheaper between \(previousAge) and \(age)"
            )
            previousHours = hours
            previousAge = age
        }
        XCTAssertGreaterThan(previousHours, 0, "the sweep produced no countdown at all")
    }

    /// A bigger training history never produces a longer window for the same
    /// session. This is the whole promise of the personalized tier: the same
    /// hour costs the person who does it every week less than the person who
    /// does not.
    func testAFitterHistoryNeverLengthensTheWindow() {
        for code in AthleteMatrix.activityCodes {
            let profile = WorkoutClassifier.profile(activityCode: code)
            guard profile != .easy else { continue }
            for shape in AthleteMatrix.shapes {
                for sensors in AthleteMatrix.sensorScenarios {
                    let persona = AthleteMatrix.personas[1]
                    let session = AthleteMatrix.session(
                        code: code, shape: shape, persona: persona, sensors: sensors
                    )
                    let base = persona.loads[profile] ?? [40, 50, 60, 70, 80, 90, 100, 110]
                    var previous = Double.greatestFiniteMagnitude

                    for scale in [1.0, 1.5, 2.5, 4.0] {
                        let hours = RecoveryCalculator.estimate(
                            for: session,
                            baseline: RecoveryBaseline(loads: base.map { $0 * scale }, profile: profile),
                            personalization: persona.personalization,
                            now: AthleteMatrix.now
                        ).hours
                        XCTAssertLessThanOrEqual(
                            hours, previous,
                            "a bigger baseline lengthened the window: \(session.id) at \(scale)x"
                        )
                        previous = hours
                    }
                }
            }
        }
    }

    /// The personal multiplier stays inside its documented bounds for every
    /// persona, including the one who answered nothing.
    func testThePersonalFactorStaysWithinItsBounds() {
        for persona in AthleteMatrix.personas {
            let factor = persona.personalization.factor
            XCTAssertGreaterThanOrEqual(factor, PersonalRecoveryModel.minimumFactor, persona.name)
            XCTAssertLessThanOrEqual(factor, PersonalRecoveryModel.maximumFactor, persona.name)
            XCTAssertEqual(persona.personalization.tier, .personalized, persona.name)
        }
    }

    // MARK: - Compliance, everywhere

    /// The banned-phrase check, run over the whole matrix rather than the five
    /// fixtures. The reason strings are assembled from the session label, the
    /// category, the load source, and the context summary, so the combinations
    /// that could produce a claim are exactly the ones a fixture list does not
    /// enumerate.
    func testNoCellEverMakesAMedicalClaim() {
        let banned = ["recovered", "safe to train", "injury", "your body", "cure", "diagnos", "heal"]
        for cell in AthleteMatrix.sweep() {
            for estimate in [cell.standard, cell.personalized] {
                XCTAssertFalse(estimate.reasons.isEmpty, "no explanation: \(cell.label)")
                let text = estimate.reasons.joined(separator: " ").lowercased()
                for phrase in banned {
                    XCTAssertFalse(
                        text.contains(phrase),
                        "\"\(phrase)\" appeared in: \(text) — \(cell.label)"
                    )
                }
            }
        }
    }

    /// Context moves every qualifying cell in one direction, whatever the sport
    /// or the athlete. A poor night can only lengthen; a good one can only
    /// shorten.
    func testContextMovesEveryCellInOneDirection() {
        for code in AthleteMatrix.activityCodes {
            guard WorkoutClassifier.profile(activityCode: code) != .easy else { continue }
            for shape in AthleteMatrix.shapes {
                for persona in AthleteMatrix.personas {
                    let session = AthleteMatrix.session(
                        code: code, shape: shape, persona: persona,
                        sensors: AthleteMatrix.sensorScenarios[0]
                    )
                    let neutral = AthleteMatrix.personalized(session, persona: persona).hours
                    guard neutral > 0 else { continue }
                    let good = AthleteMatrix.personalized(
                        session, persona: persona, context: RecoveryFixtures.goodContext
                    ).hours
                    let poor = AthleteMatrix.personalized(
                        session, persona: persona, context: RecoveryFixtures.poorContext
                    ).hours
                    XCTAssertLessThanOrEqual(good, neutral, "good context lengthened \(session.id)")
                    XCTAssertGreaterThanOrEqual(poor, neutral, "poor context shortened \(session.id)")
                }
            }
        }
    }

    // MARK: - The readout

    /// Not an assertion so much as the artefact: the window a real session
    /// produces for each persona, on both tiers, for the sports people actually
    /// log. Run it whenever the model changes and read the table:
    ///
    ///     xcodebuild test -project Recharge.xcodeproj -scheme Recharge \
    ///       -destination "id=$UDID" \
    ///       -only-testing:RechargeTests/RecoveryMatrixTests/testPrintTheAthleteMatrix
    func testPrintTheAthleteMatrix() {
        let sports: [(String, WorkoutClassifier.ActivityCode)] = [
            ("run", .running),
            ("ride", .cycling),
            ("swim", .swimming),
            ("lift", .traditionalStrengthTraining),
            ("climb", .climbing),
            ("HYROX/CrossFit", .functionalStrengthTraining),
            ("HIIT", .highIntensityIntervalTraining),
            ("tennis", .tennis),
            ("basketball", .basketball),
            ("boxing", .boxing),
            ("yoga", .yoga),
            ("walk", .walking)
        ]
        let shape = AthleteMatrix.Shape(
            minutes: 60, reserveFraction: 0.62, reportedEffort: 6, kilocaloriesPerMinute: 9.5
        )
        let sensors = AthleteMatrix.sensorScenarios[0]

        var lines: [String] = []
        for persona in AthleteMatrix.personas {
            lines.append("")
            lines.append(
                "── \(persona.name)  max \(Int(persona.maxHeartRate)) bpm, "
                    + "resting \(Int(persona.restingHeartRate)) bpm, "
                    + String(format: "prior %.2f ", persona.personalization.factor)
                    .padding(toLength: 14, withPad: " ", startingAt: 0)
            )
            lines.append(
                "sport".padding(toLength: 17, withPad: " ", startingAt: 0)
                    + "profile".padding(toLength: 11, withPad: " ", startingAt: 0)
                    + "load".padding(toLength: 8, withPad: " ", startingAt: 0)
                    + "source".padding(toLength: 15, withPad: " ", startingAt: 0)
                    + "standard".padding(toLength: 11, withPad: " ", startingAt: 0)
                    + "personalized"
            )
            for (name, code) in sports {
                let session = AthleteMatrix.session(
                    code: code.rawValue, shape: shape, persona: persona, sensors: sensors
                )
                let standard = AthleteMatrix.standard(session, persona: persona)
                let personalized = AthleteMatrix.personalized(session, persona: persona)
                func window(_ estimate: RecoveryEstimate) -> String {
                    estimate.producesCountdown
                        ? String(format: "%.1fh", estimate.hours)
                        : "—"
                }
                lines.append(
                    name.padding(toLength: 17, withPad: " ", startingAt: 0)
                        + session.profile.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)
                        + String(format: "%-8.1f", standard.load.value)
                        + standard.load.source.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)
                        + window(standard).padding(toLength: 11, withPad: " ", startingAt: 0)
                        + window(personalized)
                )
            }
        }
        print(lines.joined(separator: "\n"))
    }

    /// The same 60-minute lifting session under every sensor scenario, printed
    /// side by side. This is the table the load-ladder bug was found in, and the
    /// one to read first when someone asks why the number changed.
    func testPrintTheSensorLadderForALift() {
        var lines = ["", "── 60-minute lift at RPE 9, by what the watch recorded ".padding(toLength: 78, withPad: "─", startingAt: 0)]
        lines.append(
            "persona".padding(toLength: 24, withPad: " ", startingAt: 0)
                + AthleteMatrix.sensorScenarios
                    .map { $0.name.padding(toLength: 17, withPad: " ", startingAt: 0) }
                    .joined()
        )
        let shape = AthleteMatrix.Shape(
            minutes: 60, reserveFraction: 0.45, reportedEffort: 9, kilocaloriesPerMinute: 7.0
        )
        for persona in AthleteMatrix.personas {
            var row = persona.name.padding(toLength: 24, withPad: " ", startingAt: 0)
            for sensors in AthleteMatrix.sensorScenarios {
                let session = AthleteMatrix.session(
                    code: WorkoutClassifier.ActivityCode.traditionalStrengthTraining.rawValue,
                    shape: shape, persona: persona, sensors: sensors
                )
                let estimate = AthleteMatrix.personalized(session, persona: persona)
                row += String(format: "%.1fh", estimate.hours)
                    .padding(toLength: 17, withPad: " ", startingAt: 0)
            }
            lines.append(row)
        }
        print(lines.joined(separator: "\n"))
    }
}
