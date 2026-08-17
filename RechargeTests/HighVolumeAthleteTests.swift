import XCTest

/// The user who trains several times a day, reported from a real Health store.
///
/// The app told him his last ride was a **6 hour** standard window and a **15
/// hour** personal one. Both halves of that are wrong, and they are wrong for
/// two different reasons:
///
/// 1. Somebody who trains this much should get a *shorter* window than the
///    standard table, not one two and a half times longer. The personal
///    baseline is the median of his own sessions, and when most sessions are
///    short easy rides the median *is* a short easy ride, so a real session
///    reads as a huge multiple of "normal" when it was a Tuesday. This is the
///    open tuning question the dossier has carried since before 1.0, and it
///    turns out to bite hardest for exactly the user the app is best for.
/// 2. The standard table itself was anchored to a moderately trained adult, so
///    it under-reads the population it is supposed to describe. The free tier is
///    the number a first-time user sees, and it should be the number a mostly
///    sedentary person needs.
///
/// These tests state the two properties. They are deliberately about *ordering*
/// and not about specific hours, so tuning may move every figure but may not put
/// the frequent trainer above the couch.
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

    /// The other half: the standard table is what a first-time user sees, and it
    /// should describe someone who barely trains rather than someone who trains
    /// well. A lightly active person's own baseline should land near it.
    func testTheStandardTableDescribesALightlyActivePersonRatherThanATrainedOne() {
        let session = hardRide()

        // Someone doing two easy-ish sessions a week and nothing else.
        var light: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        for week in 0..<6 {
            let base = now.addingTimeInterval(-Double(week) * 7 * 86_400)
            light.append((.endurance, 40, base))
            light.append((.endurance, 48, base.addingTimeInterval(-3 * 86_400)))
        }

        let standard = standardHours(for: session)
        let personal = personalHours(for: session, history: light)
        XCTAssertEqual(
            personal, standard, accuracy: max(standard * 0.35, 4),
            "a lightly active person's own window (\(personal)h) should land near the standard table "
                + "(\(standard)h); the standard is supposed to describe them"
        )
    }

    /// Monotone in volume, stated directly: adding training can only ever shorten
    /// the window for the same session.
    func testAddingTrainingVolumeOnlyEverShortensTheWindow() {
        let session = hardRide()
        var history: [(profile: WorkoutProfile, load: Double, date: Date)] = []
        var previous = Double.greatestFiniteMagnitude

        for week in 0..<6 {
            let base = now.addingTimeInterval(-Double(week) * 7 * 86_400)
            for index in 0..<4 {
                history.append((.endurance, 30 + Double(index) * 25, base.addingTimeInterval(-Double(index) * 86_400)))
            }
            let hours = personalHours(for: session, history: history)
            XCTAssertLessThanOrEqual(
                hours, previous + 0.001,
                "week \(week): the window grew to \(hours)h from \(previous)h as training was added"
            )
            previous = hours
        }
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
