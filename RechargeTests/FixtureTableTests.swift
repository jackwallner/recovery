import XCTest

/// Not an assertion suite so much as a readout. Running this prints the whole
/// fixture set with the window each one produces, which is the artefact the
/// build plan asks for before any UI exists:
///
///     xcodebuild test -project Recharge.xcodeproj -scheme Recharge \
///       -destination "id=$UDID" -only-testing:RechargeTests/FixtureTableTests
///
/// It still asserts the one thing that must hold across the table — the ordering
/// a human would expect when reading it — so a bad tuning change fails CI rather
/// than quietly printing nonsense.
final class FixtureTableTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private struct Row {
        let name: String
        let estimate: RecoveryEstimate
    }

    private func rows(context: RecoveryContext) -> [Row] {
        let endurance = RecoveryFixtures.settledEnduranceBaseline()
        let strength = RecoveryFixtures.settledStrengthBaseline()
        let mixed = RecoveryFixtures.settledMixedBaseline()

        let cases: [(String, SessionInput, RecoveryBaseline)] = [
            ("30-min easy walk", RecoveryFixtures.easyWalk30, endurance),
            ("45-min easy run", RecoveryFixtures.easyRun45, endurance),
            ("60-min threshold run", RecoveryFixtures.thresholdRun60, endurance),
            ("90-min long run", RecoveryFixtures.longRun90, endurance),
            ("45-min ride", RecoveryFixtures.ride45, endurance),
            ("60-min lift, no HR", RecoveryFixtures.strengthNoHeartRate, strength),
            ("60-min lift, RPE 8", RecoveryFixtures.strengthWithEffort, strength),
            ("70-min HYROX", RecoveryFixtures.mixedHyrox, mixed),
            ("50-min run (dupe A)", RecoveryFixtures.duplicateA, endurance),
            ("50-min run (dupe B)", RecoveryFixtures.duplicateB, endurance),
            ("new user, 45-min run", RecoveryFixtures.easyRun45, RecoveryFixtures.emptyBaseline()),
            ("thin baseline, threshold run", RecoveryFixtures.thresholdRun60, RecoveryFixtures.thinBaseline())
        ]

        return cases.map { name, session, baseline in
            Row(
                name: name,
                estimate: RecoveryCalculator.estimate(
                    for: session, baseline: baseline, context: context, now: now
                )
            )
        }
    }

    private func print(_ title: String, _ rows: [Row]) {
        var lines: [String] = ["", "── \(title) ".padding(toLength: 92, withPad: "─", startingAt: 0)]
        lines.append(
            "fixture".padding(toLength: 30, withPad: " ", startingAt: 0)
            + "profile".padding(toLength: 11, withPad: " ", startingAt: 0)
            + "load".padding(toLength: 9, withPad: " ", startingAt: 0)
            + "source".padding(toLength: 15, withPad: " ", startingAt: 0)
            + "rel".padding(toLength: 7, withPad: " ", startingAt: 0)
            + "category".padding(toLength: 16, withPad: " ", startingAt: 0)
            + "window"
        )
        for row in rows {
            let e = row.estimate
            let window = e.producesCountdown
                ? CountdownFormat.window(low: e.windowLowHours, high: e.windowHighHours)
                : "— no countdown"
            lines.append(
                row.name.padding(toLength: 30, withPad: " ", startingAt: 0)
                + e.profile.rawValue.padding(toLength: 11, withPad: " ", startingAt: 0)
                + String(format: "%-9.1f", e.load.value)
                + e.load.source.rawValue.padding(toLength: 15, withPad: " ", startingAt: 0)
                + String(format: "%-7.2f", e.relativeLoad)
                + e.category.shortLabel.padding(toLength: 16, withPad: " ", startingAt: 0)
                + window
            )
        }
        Swift.print(lines.joined(separator: "\n"))
    }

    func testPrintFixtureTable() {
        print("no context (free tier)", rows(context: .empty))
        print("good context (slept well, HRV up)", rows(context: RecoveryFixtures.goodContext))
        print("poor context (short sleep, HRV down)", rows(context: RecoveryFixtures.poorContext))
    }

    // MARK: - Cross-table sanity

    func testTheTableReadsInTheOrderAHumanWouldExpect() {
        let table = Dictionary(uniqueKeysWithValues: rows(context: .empty).map { ($0.name, $0.estimate.hours) })

        func hours(_ name: String) -> Double {
            guard let value = table[name] else {
                XCTFail("missing row \(name)")
                return 0
            }
            return value
        }

        // Only same-profile rows are comparable. Each profile is scored against
        // that person's own history for *that* profile, so a HYROX session at
        // 1.4x their usual HYROX load can legitimately produce a shorter window
        // than a run at 2.6x their usual run. `testMixedProducesTheLongest…`
        // covers the profile ordering at equal relative load.
        XCTAssertEqual(hours("30-min easy walk"), 0, "a walk must not start a countdown")
        XCTAssertGreaterThan(hours("45-min easy run"), 0)
        XCTAssertGreaterThan(hours("60-min threshold run"), hours("45-min easy run"))
        XCTAssertGreaterThan(hours("90-min long run"), hours("45-min ride"))
        XCTAssertGreaterThan(hours("70-min HYROX"), 0)
        XCTAssertGreaterThan(
            hours("60-min lift, RPE 8"), hours("60-min lift, no HR"),
            "answering the effort question must matter"
        )
        XCTAssertEqual(hours("50-min run (dupe A)"), hours("50-min run (dupe B)"))
    }

    func testContextMovesEveryQualifyingRowInTheSameDirection() {
        let neutral = rows(context: .empty)
        let good = rows(context: RecoveryFixtures.goodContext)
        let poor = rows(context: RecoveryFixtures.poorContext)

        for index in neutral.indices where neutral[index].estimate.producesCountdown {
            XCTAssertLessThanOrEqual(
                good[index].estimate.hours, neutral[index].estimate.hours,
                "\(neutral[index].name) got longer on good context"
            )
            XCTAssertGreaterThanOrEqual(
                poor[index].estimate.hours, neutral[index].estimate.hours,
                "\(neutral[index].name) got shorter on poor context"
            )
        }
    }
}
