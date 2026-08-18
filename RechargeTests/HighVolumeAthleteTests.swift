import XCTest

/// The user who trains several times a day, reported from a real Health store.
///
/// The app told him his last ride was a **6 hour** standard window and a **15
/// hour** personal one, and by the time the reported history was reconstructed
/// it was **72 hours** against a **20 hour** standard. Somebody who trains this
/// much should get a *shorter* window than the population table, not one three
/// times longer.
///
/// It took two fixes, and the second only became visible once the first was in.
///
/// 1. The personal baseline was the median of his own *sessions*, and when most
///    sessions are short easy spins the median **is** a short easy spin, so a
///    real session read as a huge multiple of "normal" when it was a Tuesday.
///    `dailyLoads` fixed that: three spins are one day of training.
/// 2. Totalling per day still left the median vulnerable to a *polarised* week.
///    His volume is concentrated into two hard days, so the middle day is still
///    small — 57.5 against a population reference day of 70, for a rider whose
///    weekly load is three times the reference. `typicalLoad` is a geometric
///    mean now, which is the median for an evenly spread history and notices the
///    skew when there is one.
///
/// These tests state properties about *ordering*, not about specific hours, so
/// tuning may move every figure but may not put the frequent trainer above the
/// population table. What the table itself is anchored to is a separate question
/// and lives in `GarminAnchorTests`.
final class HighVolumeAthleteTests: XCTestCase {

    private let now = RecoveryFixtures.now

    // MARK: - The reported history

    /// Roughly what his Health store looks like: a couple of real rides a week,
    /// a lot of short easy spins, and walks all day long.
    ///
    /// Walks are excluded by the baseline builder already, so they are not what
    /// is dragging the median down. The short easy *rides* are, because they are
    /// endurance sessions and they outnumber the real ones four to one.
    private func highVolumeHistory() -> [(profile: WorkoutProfile, load: Double, date: Date)] {
        var history: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        for day in 1...28 {
            let date = now.addingTimeInterval(-Double(day) * 86_400)
            // Two or three short easy rides most days.
            history.append((.endurance, 22, date))
            history.append((.endurance, 26, date.addingTimeInterval(3600)))
            if day % 2 == 0 { history.append((.endurance, 19, date.addingTimeInterval(7200))) }
            // A genuinely hard session twice a week.
            if day % 4 == 0 { history.append((.endurance, 140, date.addingTimeInterval(10_800))) }
        }
        return history
    }

    /// The session he was looking at: an ordinary hard ride.
    private func hardRide() -> SessionInput {
        RecoveryFixtures.session(
            id: "ride",
            profile: .endurance,
            minutes: 60,
            averageHR: 152,
            restingHR: 48,
            maxHR: 190,
            coverage: 0.95,
            label: "ride"
        )
    }

    private func standardHours(for session: SessionInput) -> Double {
        RecoveryCalculator.estimate(
            for: session,
            baseline: .standard(for: session.profile),
            now: now
        ).hours
    }

    private func personalHours(
        for session: SessionInput,
        history: [(profile: WorkoutProfile, load: Double, date: Date)],
        factor: Double = 1
    ) -> Double {
        RecoveryCalculator.estimate(
            for: session,
            baseline: .build(from: history, for: session.profile, now: now),
            personalization: .personalized(factor: factor),
            now: now
        ).hours
    }

    // MARK: - The two properties

    /// The headline claim, and the one the reported bug violates.
    func testSomeoneTrainingSeveralTimesADayGetsAShorterWindowThanTheStandardTable() {
        let session = hardRide()
        let standard = standardHours(for: session)
        let personal = personalHours(for: session, history: highVolumeHistory())

        XCTAssertLessThan(
            personal, standard,
            "a user training 3x a day was given \(personal)h against a standard of \(standard)h. "
                + "More training must never buy a longer window."
        )
    }

    /// And it must hold across the range of sessions he actually does, not only
    /// at the one that was reported.
    func testTheOrderingHoldsAcrossEveryIntensityHeTrainsAt() {
        let history = highVolumeHistory()
        for heartRate in stride(from: 120.0, through: 180.0, by: 10) {
            for minutes in [30.0, 60.0, 90.0] {
                let session = RecoveryFixtures.session(
                    id: "ride-\(heartRate)-\(minutes)",
                    profile: .endurance,
                    minutes: minutes,
                    averageHR: heartRate,
                    restingHR: 48,
                    maxHR: 190,
                    coverage: 0.95,
                    label: "ride"
                )
                let standard = standardHours(for: session)
                let personal = personalHours(for: session, history: history)
                guard standard > 0 || personal > 0 else { continue }
                XCTAssertLessThanOrEqual(
                    personal, standard + 0.001,
                    "\(Int(minutes))min at \(Int(heartRate))bpm: personal \(personal)h vs standard \(standard)h"
                )
            }
        }
    }

    /// Where the population table sits on the scale.
    ///
    /// It is anchored to Firstbeat's activity class 3-5, "already engaged in
    /// training", because that is where Garmin's default sits and the standard
    /// tier is answering the same question: what do we say before we have
    /// measured anything about you. So it is a *middle* of the scale, and the
    /// testable consequence is that it brackets — a lightly active person's own
    /// window lands above it, and the high-volume rider's lands below.
    ///
    /// This replaces an assertion that the table should describe a mostly
    /// sedentary person, which was the previous anchor and is the reason the
    /// free tier gave an ordinary threshold hour a fifty-hour window.
    func testThePopulationTableSitsBetweenALightUserAndAFrequentOne() {
        let session = hardRide()
        let standard = standardHours(for: session)

        // Someone doing two easy-ish sessions a week and nothing else.
        var light: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        for week in 0..<6 {
            let base = now.addingTimeInterval(-Double(week) * 7 * 86_400)
            light.append((.endurance, 40, base))
            light.append((.endurance, 48, base.addingTimeInterval(-3 * 86_400)))
        }

        let lightHours = personalHours(for: session, history: light)
        let frequentHours = personalHours(for: session, history: highVolumeHistory())

        XCTAssertGreaterThan(
            lightHours, standard,
            "a lightly active person (\(lightHours)h) should need longer than the population "
                + "table (\(standard)h), which describes someone who already trains"
        )
        XCTAssertLessThan(
            frequentHours, standard,
            "a rider training three times a day (\(frequentHours)h) should need less than the "
                + "population table (\(standard)h)"
        )
    }

    /// Monotone in volume, stated directly: adding training can only ever shorten
    /// the window for the same session.
    ///
    /// Measured from the point the baseline is real. The first week is the
    /// shrinkage ramp, where `typicalLoad` is still mostly the population
    /// reference, and a user who turns out to train *less* than that reference
    /// will correctly see their window lengthen as the app learns it — that is
    /// a prior giving way to a measurement, not volume buying a longer window.
    /// Past `minimumSamples` there is no prior left and the claim is strict.
    func testAddingTrainingVolumeOnlyEverShortensTheWindow() {
        let session = hardRide()
        var history: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        var previous = Double.greatestFiniteMagnitude

        for week in 0..<6 {
            let base = now.addingTimeInterval(-Double(week) * 7 * 86_400)
            for index in 0..<4 {
                history.append((.endurance, 30 + Double(index) * 25, base.addingTimeInterval(-Double(index) * 86_400)))
            }
            let baseline = RecoveryBaseline.build(from: history, for: .endurance, now: now)
            let hours = personalHours(for: session, history: history)
            guard baseline.dayCount >= RecoveryBaseline.minimumSamples else { continue }
            XCTAssertLessThanOrEqual(
                hours, previous + 0.001,
                "week \(week): the window grew to \(hours)h from \(previous)h as training was added"
            )
            previous = hours
        }
        XCTAssertLessThan(previous, Double.greatestFiniteMagnitude, "the walk never reached a real baseline")
    }

    /// The bootstrap exception above, stated as its own claim so it cannot be
    /// used to excuse an inversion it does not cover.
    ///
    /// While the shrinkage is ramping, `typicalLoad` may move either way, but it
    /// is always a blend of two things the app can name: the person's own figure
    /// so far and the population reference. It may never land outside them. That
    /// is what makes the ramp a prior giving way to a measurement rather than a
    /// number of its own, and it is what a sign error or a weight above 1 would
    /// break.
    func testTheShrinkageRampAlwaysSitsBetweenThePersonAndTheReference() {
        var history: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        for week in 0..<6 {
            let base = now.addingTimeInterval(-Double(week) * 7 * 86_400)
            for index in 0..<4 {
                history.append((.endurance, 30 + Double(index) * 25, base.addingTimeInterval(-Double(index) * 86_400)))
            }
        }
        let reference = WorkoutProfile.endurance.standardTypicalLoad

        var partial: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        var sawShrinkage = false
        for (index, entry) in history.enumerated() {
            partial.append(entry)
            let baseline = RecoveryBaseline.build(from: partial, for: .endurance, now: now)
            let own = RecoveryBaseline.geometricMean(of: baseline.dailyLoads)
            XCTAssertGreaterThanOrEqual(baseline.typicalLoad, min(own, reference) - 0.001, "day \(index)")
            XCTAssertLessThanOrEqual(baseline.typicalLoad, max(own, reference) + 0.001, "day \(index)")
            if baseline.dayCount < RecoveryBaseline.minimumSamples { sawShrinkage = true }
            if baseline.dayCount >= RecoveryBaseline.minimumSamples {
                XCTAssertEqual(baseline.typicalLoad, own, accuracy: 0.001, "day \(index): the prior should be gone")
            }
        }
        XCTAssertTrue(sawShrinkage, "the walk never exercised the ramp")
    }

    // MARK: - Diagnostics

    /// Prints the reported case so a tuning change can be read rather than
    /// inferred. Not an assertion.
    func testPrintTheHighVolumeCase() {
        let session = hardRide()
        let history = highVolumeHistory()
        let baseline = RecoveryBaseline.build(from: history, for: .endurance, now: now)
        let load = SessionLoadCalculator.profiledLoad(for: session)

        print("""

        === The user who trains several times a day ===
        sessions in baseline      \(baseline.sampleCount)
        typical load (own)        \(String(format: "%.1f", baseline.typicalLoad))
        standard reference        \(String(format: "%.1f", WorkoutProfile.endurance.standardTypicalLoad))
        quiet threshold           \(String(format: "%.1f", baseline.quietThreshold))
        this session's load       \(String(format: "%.1f", load.value)) (\(load.source.rawValue))
        relative, personal        \(String(format: "%.2f", load.value / baseline.typicalLoad))
        relative, standard        \(String(format: "%.2f", load.value / WorkoutProfile.endurance.standardTypicalLoad))
        --
        standard window           \(String(format: "%.1f", standardHours(for: session)))h
        personal window           \(String(format: "%.1f", personalHours(for: session, history: history)))h

        """)
    }
}
