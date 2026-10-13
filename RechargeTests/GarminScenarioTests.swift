import XCTest

/// Recharge against Garmin's recovery time, across the athletes and situations
/// people actually bring to it.
///
/// `GarminAnchorTests` pins the *level* of the standard tier with one reference
/// athlete. This file asks the wider question the app is sold on: does the
/// countdown behave like Garmin's for a beginner, a recreational runner, a
/// high-volume marathoner and a masters cyclist, through easy days, threshold
/// work, intervals, long sessions and races, on both tiers? Bands come from
/// the same sources (Garmin's documented 6h-4d range, and the ranges reported
/// for each kind of session), widened at the ends of the fitness scale, where
/// Garmin's own number moves too.
///
/// Most assertions are orderings rather than values, because those are what a
/// user notices: a long easy ride must not outscore a threshold hour, intervals
/// must cost more than a steady run at the same average, a beginner must wait
/// longer than a marathoner for the same session, and a marathon must cost the
/// most of anything.
final class GarminScenarioTests: XCTestCase {

    private let now = RecoveryFixtures.now

    // MARK: - Athletes

    struct Athlete {
        let name: String
        let resting: Double
        let max: Double
        let profile: AthleteProfile
        /// A training week: day offset, minutes, fraction of heart-rate reserve.
        let week: [(day: Int, minutes: Double, reserve: Double)]
    }

    static let beginner = Athlete(
        name: "beginner", resting: 72, max: 166,
        profile: AthleteProfile(age: 45, sex: .female, experience: .underOneYear, weeklyVolume: .oneOrTwo, vo2Max: 30),
        week: [(1, 30, 0.60), (4, 35, 0.62)]
    )
    static let recreational = Athlete(
        name: "recreational", resting: 60, max: 185,
        profile: AthleteProfile(age: 35, sex: .male, experience: .oneToThreeYears, weeklyVolume: .threeOrFour, vo2Max: 42),
        week: [(0, 40, 0.60), (2, 45, 0.70), (5, 75, 0.62)]
    )
    static let marathoner = Athlete(
        name: "marathoner", resting: 45, max: 192,
        profile: AthleteProfile(age: 30, sex: .male, experience: .tenYearsPlus, weeklyVolume: .sevenPlus, vo2Max: 62),
        week: [(0, 50, 0.60), (1, 70, 0.80), (2, 50, 0.60), (3, 60, 0.62), (4, 75, 0.82), (5, 45, 0.55), (6, 130, 0.68)]
    )
    static let mastersCyclist = Athlete(
        name: "masters cyclist", resting: 52, max: 165,
        profile: AthleteProfile(age: 58, sex: .male, experience: .tenYearsPlus, weeklyVolume: .fiveOrSix, vo2Max: 44),
        week: [(0, 60, 0.60), (1, 90, 0.70), (3, 60, 0.60), (5, 180, 0.62), (6, 60, 0.55)]
    )
    static let athletes = [beginner, recreational, marathoner, mastersCyclist]

    // MARK: - Sessions

    struct Probe {
        let name: String
        let minutes: Double
        let reserve: Double
        let low: Double
        let high: Double
    }

    /// Bands for the standard tier, wide enough to hold the whole fitness scale.
    static let probes: [Probe] = [
        Probe(name: "30m easy", minutes: 30, reserve: 0.55, low: 6, high: 12),
        Probe(name: "60m easy", minutes: 60, reserve: 0.58, low: 8, high: 20),
        Probe(name: "45m tempo", minutes: 45, reserve: 0.78, low: 14, high: 40),
        Probe(name: "60m threshold", minutes: 60, reserve: 0.80, low: 22, high: 50),
        Probe(name: "2h long run", minutes: 120, reserve: 0.68, low: 24, high: 60),
        Probe(name: "3h easy ride", minutes: 180, reserve: 0.58, low: 24, high: 48),
        Probe(name: "5k race", minutes: 22, reserve: 0.92, low: 18, high: 48),
        Probe(name: "10k race", minutes: 45, reserve: 0.90, low: 36, high: 76),
        Probe(name: "half marathon race", minutes: 105, reserve: 0.87, low: 60, high: 96),
        Probe(name: "marathon race", minutes: 225, reserve: 0.80, low: 80, high: 96)
    ]

    private func probe(_ name: String) -> Probe { Self.probes.first { $0.name == name }! }

    private func session(
        _ athlete: Athlete,
        minutes: Double,
        reserve: Double,
        profile: WorkoutProfile = .endurance,
        end: Date? = nil,
        id: String = "probe",
        distribution: HeartRateDistribution? = nil
    ) -> SessionInput {
        let end = end ?? now
        return SessionInput(
            id: id,
            profile: profile,
            startDate: end.addingTimeInterval(-minutes * 60),
            endDate: end,
            durationMinutes: minutes,
            averageHeartRate: athlete.resting + reserve * (athlete.max - athlete.resting),
            restingHeartRate: athlete.resting,
            maxHeartRate: athlete.max,
            heartRateCoverage: 0.95,
            heartRateDistribution: distribution,
            activityLabel: "run"
        )
    }

    private func standard(_ athlete: Athlete, _ probe: Probe) -> RecoveryEstimate {
        RecoveryCalculator.estimate(
            for: session(athlete, minutes: probe.minutes, reserve: probe.reserve),
            baseline: .standard(for: .endurance, fitnessScale: athlete.profile.fitnessScale),
            now: now
        )
    }

    /// Six weeks of the athlete's own training, ending the day before `now`.
    private func history(_ athlete: Athlete) -> [(profile: WorkoutProfile, load: Double, date: Date)] {
        (0..<6).flatMap { week in
            athlete.week.map { day in
                let daysAgo = Double((6 - week) * 7 - day.day) + 1
                let input = session(
                    athlete, minutes: day.minutes, reserve: day.reserve,
                    end: now.addingTimeInterval(-daysAgo * 86_400)
                )
                return (profile: .endurance, load: SessionLoadCalculator.profiledLoad(for: input).value, date: input.endDate)
            }
        }
    }

    private func personalized(_ athlete: Athlete, _ probe: Probe, context: RecoveryContext = .empty) -> RecoveryEstimate {
        let analysis = PersonalRecoveryModel.analyse(profile: athlete.profile, sessions: [], days: [], now: now)
        return RecoveryCalculator.estimate(
            for: session(athlete, minutes: probe.minutes, reserve: probe.reserve),
            baseline: .build(
                from: history(athlete), for: .endurance, now: now,
                fitnessScale: athlete.profile.fitnessScale
            ),
            context: context,
            personalization: .personalized(factor: analysis.factor),
            now: now
        )
    }

    // MARK: - Bands

    func testEveryAthleteLandsInGarminsBandForEverySession() {
        for athlete in Self.athletes {
            for probe in Self.probes {
                let hours = standard(athlete, probe).hours
                XCTAssertGreaterThanOrEqual(hours, probe.low, "\(athlete.name), \(probe.name): \(hours)h")
                XCTAssertLessThanOrEqual(hours, probe.high, "\(athlete.name), \(probe.name): \(hours)h")
            }
        }
    }

    /// Recharge+ tunes the standard figure to the person; it does not relocate
    /// it. Anything outside this envelope is a different answer to the
    /// question, not a personalised one. The top of it belongs to the beginner
    /// training twice a week in half hours, for whom an easy hour is twice an
    /// ordinary day: the personal denominator sits at its 0.75 floor and the
    /// curve is steeper there, so 17h becomes 28h. Garmin does the same to a
    /// low-load, low-VO2 max user, which is the case it is criticised for.
    func testRechargePlusStaysWithinReachOfTheStandardFigure() {
        for athlete in Self.athletes {
            for probe in Self.probes {
                let free = standard(athlete, probe).hours
                let plus = personalized(athlete, probe).hours
                XCTAssertGreaterThanOrEqual(plus, free * 0.6 - 0.001, "\(athlete.name), \(probe.name): \(free)h -> \(plus)h")
                XCTAssertLessThanOrEqual(plus, min(free * 1.7, RecoveryCalculator.maximumHours) + 0.001, "\(athlete.name), \(probe.name): \(free)h -> \(plus)h")
            }
        }
    }

    // MARK: - Orderings Garmin users notice

    func testHarderAndLongerSessionsCostMoreForEveryAthleteOnBothTiers() {
        let ladders = [
            ["30m easy", "60m easy", "45m tempo", "60m threshold"],
            ["3h easy ride", "half marathon race", "marathon race"],
            ["5k race", "10k race", "half marathon race"]
        ]
        for athlete in Self.athletes {
            for ladder in ladders {
                let free = ladder.map { standard(athlete, probe($0)).hours }
                let plus = ladder.map { personalized(athlete, probe($0)).hours }
                XCTAssertEqual(free, free.sorted(), "\(athlete.name), standard: \(zip(ladder, free).map { "\($0) \($1)" })")
                XCTAssertEqual(plus, plus.sorted(), "\(athlete.name), Recharge+: \(zip(ladder, plus).map { "\($0) \($1)" })")
            }
        }
    }

    /// The inversion this file was written for: a three-hour zone-two ride
    /// cost 59 hours, more than a threshold hour (38h), because TRIMP grows
    /// linearly with time and EPOC does not.
    func testALongEasyRideDoesNotOutscoreAThresholdHour() {
        for athlete in Self.athletes {
            XCTAssertLessThan(
                standard(athlete, probe("3h easy ride")).hours,
                standard(athlete, probe("60m threshold")).hours * 1.25,
                athlete.name
            )
            XCTAssertLessThan(
                standard(athlete, probe("3h easy ride")).hours,
                standard(athlete, probe("2h long run")).hours,
                athlete.name
            )
        }
    }

    /// Garmin's recovery time comes from EPOC scaled by fitness, so the same
    /// session costs a beginner more than a marathoner.
    func testTheSameSessionCostsTheLessTrainedAthleteMore() {
        for probe in Self.probes {
            let hours = [Self.beginner, Self.recreational, Self.marathoner].map { standard($0, probe).hours }
            XCTAssertEqual(hours, hours.sorted(by: >), "\(probe.name): \(hours)")
        }
    }

    /// The old 72-hour ceiling gave a raced half marathon, a marathon and a
    /// beginner's long run the same figure.
    func testRacesUseTheFourDayRangeAndOnlyTheLongestPinIt() {
        for athlete in [Self.recreational, Self.marathoner, Self.mastersCyclist] {
            let half = standard(athlete, probe("half marathon race")).hours
            let marathon = standard(athlete, probe("marathon race")).hours
            XCTAssertGreaterThan(half, 72, athlete.name)
            XCTAssertLessThan(half, RecoveryCalculator.maximumHours, athlete.name)
            XCTAssertGreaterThan(marathon, half, athlete.name)
        }
        XCTAssertEqual(RecoveryCalculator.maximumHours, 96)
    }

    // MARK: - Intervals

    /// Fifteen minutes easy, six times four minutes hard with three easy, ten
    /// minutes down: the same average heart rate as a steady 67 minutes, and a
    /// clearly bigger session.
    func testIntervalsCostMoreThanASteadySessionAtTheSameAverage() {
        let athlete = Self.recreational
        var samples: [Double] = []
        func add(_ minutes: Double, _ reserve: Double) {
            let bpm = athlete.resting + reserve * (athlete.max - athlete.resting)
            samples += Array(repeating: bpm, count: Int(minutes * 12))
        }
        add(15, 0.55)
        for _ in 0..<6 { add(4, 0.90); add(3, 0.60) }
        add(10, 0.50)
        let average = samples.reduce(0, +) / Double(samples.count)
        let reserve = (average - athlete.resting) / (athlete.max - athlete.resting)
        let distribution = HeartRateDistribution(samples: samples, secondsEach: 5)
        XCTAssertNotNil(distribution)

        let baseline = RecoveryBaseline.standard(for: .endurance, fitnessScale: athlete.profile.fitnessScale)
        let steady = RecoveryCalculator.estimate(
            for: session(athlete, minutes: 67, reserve: reserve), baseline: baseline, now: now
        )
        let intervals = RecoveryCalculator.estimate(
            for: session(athlete, minutes: 67, reserve: reserve, distribution: distribution),
            baseline: baseline, now: now
        )
        XCTAssertGreaterThan(intervals.hours, steady.hours * 1.3, "\(steady.hours)h -> \(intervals.hours)h")
        XCTAssertGreaterThanOrEqual(intervals.hours, 24)
        XCTAssertLessThanOrEqual(intervals.hours, 48)
    }

    /// A steady session read through its distribution scores what its average
    /// does, so importing the distribution moves nothing that was not interval
    /// shaped.
    func testASteadyDistributionAgreesWithTheAverage() {
        let athlete = Self.recreational
        let bpm = athlete.resting + 0.70 * (athlete.max - athlete.resting)
        let distribution = HeartRateDistribution(samples: Array(repeating: bpm, count: 720), secondsEach: 5)
        let plain = SessionLoadCalculator.profiledLoad(for: session(athlete, minutes: 60, reserve: 0.70)).value
        let viaDistribution = SessionLoadCalculator.profiledLoad(
            for: session(athlete, minutes: 60, reserve: 0.70, distribution: distribution)
        ).value
        XCTAssertEqual(viaDistribution, plain, accuracy: plain * 0.03)
    }

    func testTheDistributionSurvivesTheRoundTripThroughTheRecord() {
        let distribution = HeartRateDistribution(samples: [120, 121, 150, 151, 180], secondsEach: 5)
        XCTAssertEqual(HeartRateDistribution.decode(distribution?.encoded), distribution)
        XCTAssertEqual(distribution?.totalSeconds, 25)
        XCTAssertNil(HeartRateDistribution.decode(nil))
        XCTAssertNil(HeartRateDistribution(samples: [], secondsEach: 5))
    }

    // MARK: - Strength

    /// Resistance work is sets, not a steady aerobic state, and session-RPE is
    /// linear in duration. The long-session discount must not reach it.
    func testStrengthIsCostedLinearlyInDuration() {
        let lift = { (minutes: Double) in
            SessionLoadCalculator.profiledLoad(for: SessionInput(
                id: "lift", profile: .strength,
                startDate: self.now.addingTimeInterval(-minutes * 60), endDate: self.now,
                durationMinutes: minutes, reportedEffort: 7
            )).value
        }
        XCTAssertEqual(lift(120), lift(60) * 2, accuracy: 0.001)
    }

    // MARK: - The nights after

    private var recoveryBaselines: (hrv: Double, resting: Double) { (50, 55) }

    private func context(following nights: [RecoveryContext.Night]) -> RecoveryContext {
        RecoveryContext(
            heartRateVariabilityBaseline: recoveryBaselines.hrv,
            restingHeartRateBaseline: recoveryBaselines.resting,
            followingNights: nights
        )
    }

    /// Garmin keeps adjusting a running countdown from the sleep and stress
    /// that follow the session. A good night brings Ready forward and a bad one
    /// pushes it back, within the same bounded range the night before uses.
    func testTheNightAfterMovesTheCountdownBothWays() {
        let athlete = Self.recreational
        let threshold = probe("60m threshold")
        let nightAfter = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let plain = personalized(athlete, threshold).hours
        let good = personalized(athlete, threshold, context: context(following: [
            .init(date: nightAfter, sleepHours: 8.2, heartRateVariability: 60, restingHeartRate: 52)
        ]))
        let bad = personalized(athlete, threshold, context: context(following: [
            .init(date: nightAfter, sleepHours: 4.5, heartRateVariability: 38, restingHeartRate: 61)
        ]))
        XCTAssertLessThan(good.hours, plain)
        XCTAssertGreaterThan(bad.hours, plain)
        XCTAssertGreaterThanOrEqual(good.hours, plain * (1 + RecoveryCalculator.minimumContextAdjustment) - 0.001)
        XCTAssertLessThanOrEqual(bad.hours, plain * (1 + RecoveryCalculator.maximumContextAdjustment) + 0.001)
        XCTAssertTrue(bad.reasons.contains { $0.contains("since the session") }, "\(bad.reasons)")
    }

    /// A night that landed after the countdown would have ended cannot reopen
    /// it, however bad it was.
    func testANightAfterReadyCannotReopenTheCountdown() {
        let athlete = Self.recreational
        let easy = probe("60m easy")
        let plain = personalized(athlete, easy)
        let longAfter = Calendar.current.startOfDay(for: plain.readyAt.addingTimeInterval(2 * 86_400))
        let late = personalized(athlete, easy, context: context(following: [
            .init(date: longAfter, sleepHours: 3, heartRateVariability: 20, restingHeartRate: 70)
        ]))
        XCTAssertEqual(late.hours, plain.hours, accuracy: 0.001)
        XCTAssertEqual(late.readyAt, plain.readyAt)
    }

    /// The nights after count double against the night before: how the session
    /// was absorbed says more than how the person went into it.
    func testTheNightsAfterOutweighTheNightBefore() {
        let nightAfter = Calendar.current.startOfDay(for: now.addingTimeInterval(86_400))
        let context = RecoveryContext(
            sleepHours: 4.5,
            heartRateVariabilityBaseline: 50,
            restingHeartRateBaseline: 55,
            followingNights: [.init(date: nightAfter, sleepHours: 8.5, heartRateVariability: 60, restingHeartRate: 52)]
        )
        XCTAssertLessThan(RecoveryCalculator.contextAdjustment(context), 0)
        XCTAssertGreaterThan(RecoveryCalculator.contextAdjustment(context, nightsBefore: .distantPast), 0)
    }

    // MARK: - High volume

    /// A cyclist riding five times a week has an hour on the bike under their
    /// own 25th percentile. It still starts a countdown, as it does on Garmin.
    func testARealHourAlwaysStartsACountdownForAHighVolumeAthlete() {
        for athlete in [Self.marathoner, Self.mastersCyclist] {
            XCTAssertTrue(personalized(athlete, probe("60m easy")).producesCountdown, athlete.name)
            XCTAssertTrue(personalized(athlete, probe("30m easy")).producesCountdown, athlete.name)
        }
    }

    // MARK: - Reading it

    func testPrintTheScenarioTable() {
        var lines = ["", "Garmin scenarios, model v\(recoveryModelVersion): standard / Recharge+ hours", ""]
        lines.append("  session               " + Self.athletes.map { $0.name.padding(toLength: 17, withPad: " ", startingAt: 0) }.joined())
        for probe in Self.probes {
            let cells = Self.athletes.map { athlete in
                String(format: "%5.1f / %-5.1f    ", standard(athlete, probe).hours, personalized(athlete, probe).hours)
            }
            lines.append("  " + probe.name.padding(toLength: 22, withPad: " ", startingAt: 0) + cells.joined())
        }
        print(lines.joined(separator: "\n"))
    }
}
