import Foundation

/// The population and the session catalogue the model is audited against.
///
/// `RecoveryFixtures` holds the dozen shapes the model was designed from, and
/// they are the right thing to reason about while tuning. They are the wrong
/// thing to ship on: they are a handful of sessions from one imagined athlete,
/// and every one of them was chosen by the same person who chose the constants.
///
/// This is the other half. Every activity type HealthKit can hand us, at every
/// duration and intensity a real training week contains, for six people who
/// recover at different rates, under every combination of sensors that actually
/// turns up in a Health store. `RecoveryMatrixTests` sweeps the product of all
/// four and asserts the properties that have to hold everywhere, rather than the
/// specific numbers that happen to hold on the fixtures.
///
/// Nothing here is a claim about sport-specific physiology. The sessions are
/// built from duration, heart-rate reserve, perceived effort, and burn rate,
/// which are exactly the four things the model reads; the sport only enters
/// through `WorkoutClassifier`, which is the point.
enum AthleteMatrix {

    /// Fixed clock, so every row of the audit is reproducible.
    static let now = Date(timeIntervalSince1970: 1_770_000_000)

    // MARK: - People

    /// One person, as the model sees them: an age and sex (which set the
    /// heart-rate ceiling on both tiers), a questionnaire prior, a resting heart
    /// rate, and the recent history their personalized baseline is built from.
    struct Persona: Sendable {
        let name: String
        let profile: AthleteProfile
        let restingHeartRate: Double
        /// Recent session loads per profile — what `RecoveryBaseline` is built
        /// from for a Recharge+ user.
        let loads: [WorkoutProfile: [Double]]

        /// Age-predicted, exactly as the app does it. A persona with no age
        /// falls back to the blunt default, which is itself worth sweeping.
        var maxHeartRate: Double {
            profile.predictedMaxHeartRate ?? SessionLoadCalculator.defaultMaxHeartRate
        }

        func baseline(for workoutProfile: WorkoutProfile) -> RecoveryBaseline {
            RecoveryBaseline(loads: loads[workoutProfile] ?? [], profile: workoutProfile)
        }

        /// The personal multiplier available on day one: the questionnaire prior,
        /// clamped. The three observed signals need weeks of days and sessions,
        /// and `PersonalRecoveryModelTests` covers them; what this matrix is for
        /// is the interaction between the prior, the baseline, and the session.
        var personalization: RecoveryPersonalization {
            .personalized(factor: profile.prior ?? 1)
        }
    }

    static let personas: [Persona] = [
        // Day one of the app for the person it is hardest to be right about:
        // almost no history, so the baseline is thin and the prior is doing the
        // work.
        Persona(
            name: "newcomer-24F",
            profile: AthleteProfile(
                age: 24, sex: .female,
                experience: .underOneYear,
                bounceBack: .threeOrMoreDays,
                weeklyVolume: .oneOrTwo
            ),
            restingHeartRate: 68,
            loads: [.endurance: [22, 31, 38, 45], .strength: [30, 44, 52]]
        ),
        // The modal user: trains a few times a week, a settled baseline in the
        // three profiles that matter.
        Persona(
            name: "recreational-35M",
            profile: AthleteProfile(
                age: 35, sex: .male,
                experience: .oneToThreeYears,
                bounceBack: .aboutTwoDays,
                weeklyVolume: .threeOrFour
            ),
            restingHeartRate: 58,
            loads: [
                .endurance: [34, 41, 48, 55, 60, 66, 72, 80, 95, 110],
                .strength: [55, 68, 74, 82, 90, 98, 106, 118],
                .mixed: [60, 72, 85, 96, 104, 118, 130]
            ]
        ),
        // High volume and a low resting heart rate at an age where the predicted
        // ceiling is well under the 185 default. The persona the flat-max bug
        // would have been worst for.
        Persona(
            name: "masters-endurance-58M",
            profile: AthleteProfile(
                age: 58, sex: .male,
                experience: .tenYearsPlus,
                bounceBack: .nextDay,
                weeklyVolume: .fiveOrSix
            ),
            restingHeartRate: 46,
            loads: [
                .endurance: [55, 68, 74, 82, 90, 98, 110, 124, 140, 158, 176, 205],
                .strength: [40, 52, 60, 68, 75, 84, 92, 101],
                .mixed: [70, 84, 96, 108, 120]
            ]
        ),
        // Trains almost entirely in the profile whose sensors lie: the load
        // ladder's worst case, with a baseline high enough that an under-read
        // reads as an easy day.
        Persona(
            name: "strength-27M",
            profile: AthleteProfile(
                age: 27, sex: .male,
                experience: .threeToTenYears,
                bounceBack: .aboutTwoDays,
                weeklyVolume: .fiveOrSix
            ),
            restingHeartRate: 54,
            loads: [
                .strength: [95, 110, 124, 138, 150, 162, 178, 190, 205, 225],
                .endurance: [30, 38, 45, 52, 58, 66, 74, 85],
                .mixed: [80, 95, 110, 125, 140, 158]
            ]
        ),
        // Seven sessions a week across all three profiles, which is where the
        // density signal and the mixed curve meet.
        Persona(
            name: "hybrid-41F",
            profile: AthleteProfile(
                age: 41, sex: .female,
                experience: .threeToTenYears,
                bounceBack: .nextDay,
                weeklyVolume: .sevenPlus
            ),
            restingHeartRate: 50,
            loads: [
                .mixed: [110, 124, 138, 152, 166, 180, 195, 212, 230, 255],
                .endurance: [60, 72, 84, 96, 108, 120, 135, 150],
                .strength: [80, 92, 105, 118, 130, 142, 155, 170]
            ]
        ),
        // The oldest predicted ceiling in the set, the highest resting heart
        // rate, and the least history. Every bound in the model is closest to
        // binding here.
        Persona(
            name: "returning-66F",
            profile: AthleteProfile(
                age: 66, sex: .female,
                experience: .underOneYear,
                bounceBack: .threeOrMoreDays,
                weeklyVolume: .oneOrTwo
            ),
            restingHeartRate: 72,
            loads: [.endurance: [18, 24, 30, 36, 42], .strength: [25, 32, 40]]
        ),
        // Nothing answered and nothing derived: no age, so the default ceiling,
        // and `prior` is nil. This is a real state — a user who declines Health
        // and skips the questions — and it must still produce a sane number.
        Persona(
            name: "unknown-athlete",
            profile: AthleteProfile(),
            restingHeartRate: SessionLoadCalculator.defaultRestingHeartRate,
            loads: [:]
        )
    ]

    // MARK: - Sessions

    /// One session's difficulty, expressed in the four terms the model reads.
    /// The sport is applied separately, so the same shape can be swept across
    /// every activity type.
    struct Shape: Sendable {
        let minutes: Double
        /// Fraction of heart-rate reserve sustained. Converted to an absolute
        /// average heart rate per persona, which is what makes the age-predicted
        /// ceiling observable in the output.
        let reserveFraction: Double
        /// Session RPE the user would report if asked. Independent of the
        /// sensors by construction: it is what the person felt, not what the
        /// watch saw.
        let reportedEffort: Double
        /// Burn rate for endurance work of this difficulty, scaled per profile
        /// by `energyScale`.
        let kilocaloriesPerMinute: Double

        var name: String { "\(Int(minutes))min@\(Int(reserveFraction * 100))%" }
    }

    static let durations: [Double] = [30, 60, 120]

    /// Ordered easiest to hardest. Every term rises together, because that is
    /// what "harder" means to each of the three load sources at once, and the
    /// monotonicity assertions depend on the ordering being total.
    static let intensities: [(reserve: Double, effort: Double, kilocaloriesPerMinute: Double)] = [
        (0.45, 4, 7.0),
        (0.62, 6, 9.5),
        (0.80, 9, 12.5)
    ]

    static let shapes: [Shape] = durations.flatMap { minutes in
        intensities.map { intensity in
            Shape(
                minutes: minutes,
                reserveFraction: intensity.reserve,
                reportedEffort: intensity.effort,
                kilocaloriesPerMinute: intensity.kilocaloriesPerMinute
            )
        }
    }

    /// How the burn rate of a session relates to the reserve fraction it
    /// sustained, per profile.
    ///
    /// Energy expenditure tracks oxygen uptake, and oxygen uptake does not care
    /// which sport produced it: a basketball game held at 62% of heart-rate
    /// reserve burns what a run held at 62% burns, so mixed work carries no
    /// discount here. Resistance work does, and heavily — much of what a hard
    /// set costs is not aerobic, so the kilocalorie figure reads a fraction of
    /// the session's real cost. That gap is the whole reason `strengthLoad`
    /// takes a maximum rather than the first available source, and baking it
    /// into the fixtures is what makes the sensor-spread numbers mean anything.
    ///
    /// An earlier version of this file discounted mixed work by 15% as well,
    /// which had no justification behind it and showed up as a mixed-specific
    /// sensor spread that was an artefact of the fixture rather than a property
    /// of the model.
    static func energyScale(for profile: WorkoutProfile) -> Double {
        switch profile {
        case .endurance, .mixed: 1.0
        case .strength: 0.55
        case .easy: 0.85
        }
    }

    // MARK: - Sensors

    /// What the Health store actually contains for this session.
    ///
    /// These are not hypotheticals. A lift with the strap on and the effort
    /// question answered, the same lift with the optical signal lost at the bar,
    /// a phone-logged session with no heart rate at all, and a manually entered
    /// workout with nothing but a duration are all ordinary imports.
    struct Sensors: Sendable {
        let name: String
        /// `nil` when the session carries no usable heart-rate samples at all.
        let heartRateCoverage: Double?
        let hasEnergy: Bool
        let hasEffort: Bool
    }

    static let sensorScenarios: [Sensors] = [
        Sensors(name: "full", heartRateCoverage: 0.95, hasEnergy: true, hasEffort: true),
        Sensors(name: "watch", heartRateCoverage: 0.95, hasEnergy: true, hasEffort: false),
        Sensors(name: "lost-signal", heartRateCoverage: 0.28, hasEnergy: true, hasEffort: false),
        Sensors(name: "lost-signal+RPE", heartRateCoverage: 0.28, hasEnergy: true, hasEffort: true),
        Sensors(name: "energy-only", heartRateCoverage: nil, hasEnergy: true, hasEffort: false),
        Sensors(name: "effort-only", heartRateCoverage: nil, hasEnergy: false, hasEffort: true),
        Sensors(name: "bare", heartRateCoverage: nil, hasEnergy: false, hasEffort: false)
    ]

    /// The scenarios that can actually reach a given profile.
    ///
    /// Recharge only offers the effort prompt on the profiles that raise it, so
    /// an endurance session carrying an RPE is reachable only through a profile
    /// override applied after the answer. Those cells stay in the structural
    /// sweep, where they still have to behave, and stay out of the spread and
    /// qualification statistics, which are meant to describe what users see
    /// rather than what the type system permits.
    static func reachableScenarios(for profile: WorkoutProfile) -> [Sensors] {
        profile.wantsEffortInput ? sensorScenarios : sensorScenarios.filter { !$0.hasEffort }
    }

    /// Every activity type HealthKit defines, plus a code it does not, so the
    /// unknown-code fallback is swept alongside the rest.
    static let activityCodes: [UInt] =
        WorkoutClassifier.ActivityCode.allCases.map(\.rawValue) + [9_999]

    // MARK: - Building one session

    static func session(
        code: UInt,
        shape: Shape,
        persona: Persona,
        sensors: Sensors,
        ambiguousProfile: WorkoutProfile = WorkoutClassifier.ambiguousDefault,
        endedMinutesAgo: Double = 0
    ) -> SessionInput {
        let profile = WorkoutClassifier.profile(activityCode: code, ambiguousProfile: ambiguousProfile)
        let reserve = persona.maxHeartRate - persona.restingHeartRate
        let averageHeartRate = persona.restingHeartRate + shape.reserveFraction * reserve
        let end = now.addingTimeInterval(-endedMinutesAgo * 60)

        return SessionInput(
            id: "\(code)-\(shape.name)-\(persona.name)-\(sensors.name)",
            profile: profile,
            startDate: end.addingTimeInterval(-shape.minutes * 60),
            endDate: end,
            durationMinutes: shape.minutes,
            averageHeartRate: sensors.heartRateCoverage == nil ? nil : averageHeartRate,
            restingHeartRate: persona.restingHeartRate,
            maxHeartRate: persona.maxHeartRate,
            heartRateCoverage: sensors.heartRateCoverage ?? 0,
            activeEnergyKilocalories: sensors.hasEnergy
                ? shape.minutes * shape.kilocaloriesPerMinute * energyScale(for: profile)
                : nil,
            reportedEffort: sensors.hasEffort ? shape.reportedEffort : nil,
            activityLabel: WorkoutClassifier.label(activityCode: code)
        )
    }

    // MARK: - Scoring

    /// The free tier: the population reference, no context, no calibration, no
    /// personal multiplier.
    static func standard(_ session: SessionInput) -> RecoveryEstimate {
        RecoveryCalculator.estimate(
            for: session,
            baseline: .standard(for: session.profile),
            now: now
        )
    }

    /// Recharge+: the person's own baseline and their personal multiplier.
    static func personalized(
        _ session: SessionInput,
        persona: Persona,
        context: RecoveryContext = .empty
    ) -> RecoveryEstimate {
        RecoveryCalculator.estimate(
            for: session,
            baseline: persona.baseline(for: session.profile),
            context: context,
            personalization: persona.personalization,
            now: now
        )
    }

    // MARK: - Sweeping

    /// One scored cell of the matrix.
    struct Cell: Sendable {
        let code: UInt
        let shape: Shape
        let persona: Persona
        let sensors: Sensors
        let session: SessionInput
        let standard: RecoveryEstimate
        let personalized: RecoveryEstimate

        var label: String {
            "\(WorkoutClassifier.label(activityCode: code)) (\(code)) "
                + "\(shape.name) \(persona.name) \(sensors.name)"
        }
    }

    /// The whole product: every activity code, shape, persona, and sensor
    /// scenario, scored on both tiers.
    ///
    /// Built once per test rather than stored, because it is cheap arithmetic
    /// and a stored copy is a copy that can drift from the code it audits.
    static func sweep() -> [Cell] {
        var cells: [Cell] = []
        cells.reserveCapacity(activityCodes.count * shapes.count * personas.count * sensorScenarios.count)
        for code in activityCodes {
            for shape in shapes {
                for persona in personas {
                    for sensors in sensorScenarios {
                        let input = session(code: code, shape: shape, persona: persona, sensors: sensors)
                        cells.append(
                            Cell(
                                code: code,
                                shape: shape,
                                persona: persona,
                                sensors: sensors,
                                session: input,
                                standard: standard(input),
                                personalized: personalized(input, persona: persona)
                            )
                        )
                    }
                }
            }
        }
        return cells
    }
}
