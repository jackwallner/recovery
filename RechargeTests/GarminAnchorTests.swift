import XCTest
@testable import Recharge

/// What the standard tier is anchored *to*.
///
/// Recharge's free tier answers the same question Garmin answers before it has
/// measured anything about you, so it should land in the same place. Two things
/// make that testable rather than a matter of taste:
///
/// 1. **The structure is documented.** Firstbeat's Training Effect — which
///    recovery time is derived from — is EPOC scaled by the individual's
///    activity class, a 0-to-10 scale where 0-2 is a beginner, 3-5 is someone
///    already training, 6-7 is highly fit, and 7.5-10 is an athlete. Garmin's
///    default sits in the middle band, so `standardTypicalLoad` has to describe
///    a person who already trains, not a sedentary one.
/// 2. **The output range is documented.** 6 hours to 4 days (Edge 840 and
///    fēnix 7 owner's manuals), and the bands below are the values Garmin is
///    consistently observed to produce inside it.
///
/// The hours mapping itself was never published, so this is a fit against
/// *observed behaviour*, not a reimplementation of a formula. That is why the
/// assertions are bands rather than values: the claim is "a tempo hour is a
/// 24-to-48-hour session", not "a tempo hour is 30.9 hours".
///
/// This is the guard the last two tuning passes did not have. The standard
/// reference has now been 85, then 52, and is 70; the first ran short from a
/// steady 45 minutes upward and the second let an ordinary hard hour pin the
/// 72-hour ceiling, and nothing in the suite objected to either, because every
/// other test asserts *relationships* (monotonicity, tier separation, "more
/// information never shortens a strength window") and relationships are
/// invariant to the level. Only an external anchor can catch the level.
final class GarminAnchorTests: XCTestCase {

    private let now = RecoveryFixtures.now

    /// One canonical session and the band Garmin puts it in.
    private struct Anchor {
        let name: String
        let minutes: Double
        /// Fraction of heart-rate reserve sustained.
        let reserve: Double
        let low: Double
        let high: Double
    }

    /// Easy 0-12h, moderate 12-24h, hard 24-48h, very hard 48-72h. The bands are
    /// widened by a couple of hours at the edges where a session genuinely sits
    /// on a boundary (a 60-minute easy run is the top of "easy" or the bottom of
    /// "moderate" depending on who you ask), and never widened enough to make an
    /// assertion vacuous.
    private let anchors: [Anchor] = [
        // Low bound 0, not 6: this one sits under `absoluteCountdownFloor` and
        // starts no countdown at all, which is the bottom of Garmin's easy band
        // rather than a disagreement with it. The upper bound is still the
        // assertion that matters — it must not read as a training session.
        Anchor(name: "20m recovery jog",    minutes: 20,  reserve: 0.45, low: 0,  high: 12),
        Anchor(name: "30m easy Z2 run",     minutes: 30,  reserve: 0.55, low: 6,  high: 12),
        Anchor(name: "45m easy Z2 run",     minutes: 45,  reserve: 0.55, low: 6,  high: 14),
        Anchor(name: "60m easy Z2 run",     minutes: 60,  reserve: 0.55, low: 10, high: 18),
        Anchor(name: "45m steady run",      minutes: 45,  reserve: 0.65, low: 12, high: 24),
        Anchor(name: "60m steady run",      minutes: 60,  reserve: 0.68, low: 12, high: 26),
        Anchor(name: "45m tempo",           minutes: 45,  reserve: 0.78, low: 18, high: 40),
        Anchor(name: "60m threshold",       minutes: 60,  reserve: 0.78, low: 24, high: 48),
        Anchor(name: "60m hard intervals",  minutes: 60,  reserve: 0.85, low: 30, high: 48),
        Anchor(name: "75m hard intervals",  minutes: 75,  reserve: 0.85, low: 40, high: 62),
        Anchor(name: "90m long steady",     minutes: 90,  reserve: 0.62, low: 24, high: 44),
        Anchor(name: "120m long run",       minutes: 120, reserve: 0.62, low: 36, high: 66),
        Anchor(name: "150m very long ride", minutes: 150, reserve: 0.60, low: 44, high: 72)
    ]

    private func session(_ anchor: Anchor) -> SessionInput {
        // Reserve fraction expressed as a real average heart rate, so the test
        // exercises the same TRIMP path a recorded workout takes rather than
        // reaching into the load calculator.
        let resting = 55.0
        let max = 185.0
        return SessionInput(
            id: anchor.name,
            profile: .endurance,
            startDate: now.addingTimeInterval(-anchor.minutes * 60),
            endDate: now,
            durationMinutes: anchor.minutes,
            averageHeartRate: resting + anchor.reserve * (max - resting),
            restingHeartRate: resting,
            maxHeartRate: max,
            heartRateCoverage: 1,
            activityLabel: anchor.name
        )
    }

    private func standardHours(_ anchor: Anchor) -> Double {
        RecoveryCalculator.estimate(
            for: session(anchor),
            baseline: .standard(for: .endurance),
            now: now
        ).hours
    }

    // MARK: - The anchor

    /// Every canonical session lands in the band Garmin puts it in.
    func testTheStandardTierLandsInGarminsBands() {
        for anchor in anchors {
            let hours = standardHours(anchor)
            XCTAssertGreaterThanOrEqual(
                hours, anchor.low,
                "\(anchor.name): \(String(format: "%.1f", hours))h is short of the \(Int(anchor.low))-\(Int(anchor.high))h band"
            )
            XCTAssertLessThanOrEqual(
                hours, anchor.high,
                "\(anchor.name): \(String(format: "%.1f", hours))h is past the \(Int(anchor.low))-\(Int(anchor.high))h band"
            )
        }
    }

    /// The ceiling is a bound, not a working value. A session an ordinary
    /// recreational runner does on a Saturday must not return the longest window
    /// the app can express — if it does, everything above it is indistinguishable
    /// and the scale has run out before the training has.
    func testAnOrdinaryHardSessionDoesNotPinTheCeiling() {
        for anchor in anchors {
            XCTAssertLessThan(
                standardHours(anchor), RecoveryCalculator.maximumHours,
                "\(anchor.name) pins the \(Int(RecoveryCalculator.maximumHours))h ceiling on the free tier"
            )
        }
    }

    /// The reference has to describe someone who already trains. Firstbeat's own
    /// scale is the argument: activity class 3-5 is "already engaged in
    /// training", and that is the default, so the population denominator sits
    /// well above what a beginner's training day costs.
    func testTheStandardReferenceDescribesSomeoneWhoAlreadyTrains() {
        // A 45-minute session at 65% of reserve — the reference training day in
        // the documentation on `standardTypicalLoad`.
        let referenceDay = 45 * SessionLoadCalculator.trimpPerMinute(atReserve: 0.65)
        XCTAssertEqual(
            WorkoutProfile.endurance.standardTypicalLoad, referenceDay,
            accuracy: referenceDay * 0.10,
            "the endurance reference no longer matches the training day it is documented as"
        )
    }

    /// Ratios between the profiles are a separate decision from the level, and
    /// re-anchoring the level must not quietly retune them.
    func testReanchoringTheLevelLeftTheProfileRatiosAlone() {
        let endurance = WorkoutProfile.endurance.standardTypicalLoad
        XCTAssertEqual(WorkoutProfile.strength.standardTypicalLoad / endurance, 105.0 / 85.0, accuracy: 0.02)
        XCTAssertEqual(WorkoutProfile.mixed.standardTypicalLoad / endurance, 115.0 / 85.0, accuracy: 0.02)
    }

    // MARK: - The table, for reading

    /// Prints the standard tier beside the bands it is fitted to. Not an
    /// assertion; run it when the model is next opened.
    func testPrintTheGarminAnchorTable() {
        var lines = ["", "standard tier vs observed Garmin bands (endurance, model v\(recoveryModelVersion))", ""]
        lines.append("  session                   load    Recharge    Garmin")
        for anchor in anchors {
            let load = SessionLoadCalculator.profiledLoad(for: session(anchor)).value
            let hours = standardHours(anchor)
            let fits = hours >= anchor.low && hours <= anchor.high
            lines.append(String(
                format: "  %-22@  %6.1f   %6.1fh   %2d-%2dh %@",
                anchor.name as NSString, load, hours,
                Int(anchor.low), Int(anchor.high),
                (fits ? "" : "  <- outside") as NSString
            ))
        }
        print(lines.joined(separator: "\n"))
    }
}
