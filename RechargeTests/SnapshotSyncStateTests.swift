import XCTest

/// "Nothing has ever arrived" and "the phone says you have not trained lately"
/// are different sentences, and the wrist had only one of them.
final class SnapshotSyncStateTests: XCTestCase {

    private var defaults: UserDefaults!
    private var suiteName: String!

    override func setUpWithError() throws {
        suiteName = "SnapshotSyncStateTests.\(UUID().uuidString)"
        defaults = try XCTUnwrap(UserDefaults(suiteName: suiteName))
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        super.tearDown()
    }

    func testAnUntouchedContainerReportsNothingRatherThanAnEmptySnapshot() {
        XCTAssertNil(RecoverySnapshotStore.loadIfPresent(defaults: defaults))
        XCTAssertFalse(RecoverySnapshotStore.hasEverSynced(defaults: defaults))
        // `load` keeps its old forgiving behaviour for every caller that only
        // wants something to draw.
        XCTAssertEqual(RecoverySnapshotStore.load(defaults: defaults), .empty)
    }

    /// The bug. A phone with no qualifying workout publishes
    /// `RecoverySnapshot.empty`, which is equal to the value a missing key
    /// decodes to, so the two were indistinguishable and the complication chose
    /// the wrong one: it told a fully synced user to open Recharge and set it
    /// up, with nothing to set up and no way to dismiss it.
    func testASuccessfullyPublishedEmptySnapshotIsNotMistakenForNeverSynced() {
        RecoverySnapshotStore.save(.empty, defaults: defaults)

        XCTAssertTrue(RecoverySnapshotStore.hasEverSynced(defaults: defaults))
        XCTAssertNotNil(RecoverySnapshotStore.loadIfPresent(defaults: defaults))
        // The snapshot itself is still empty. That is what `noRecentWorkout` is
        // for, and it is a different answer from "open Recharge".
        XCTAssertFalse(RecoverySnapshotStore.load(defaults: defaults).hasSession)
    }

    func testARealSnapshotRoundTripsAndReportsSynced() {
        let snapshot = RecoverySnapshot(
            readyAt: RecoveryFixtures.now.addingTimeInterval(6 * 3600),
            sessionEnd: RecoveryFixtures.now.addingTimeInterval(-3600),
            hours: 18,
            windowLowHours: 15,
            windowHighHours: 21,
            profile: .endurance,
            activityLabel: "run",
            category: .hard,
            confidence: .high,
            calculatedAt: RecoveryFixtures.now
        )
        RecoverySnapshotStore.save(snapshot, defaults: defaults)

        XCTAssertTrue(RecoverySnapshotStore.hasEverSynced(defaults: defaults))
        XCTAssertEqual(RecoverySnapshotStore.loadIfPresent(defaults: defaults), snapshot)
    }

    /// The background-wake path re-applies whatever the system replayed into
    /// `receivedApplicationContext`, which on a wrist that has heard nothing new
    /// is the *same* payload it already holds. `applyInboundSnapshot` skips the
    /// `reloadAllTimelines` in that case, and the comparison it makes that
    /// decision on is `loadIfPresent(...) == snapshot`. So round-trip equality
    /// is not a nicety here: one field that fails to survive `Codable` makes
    /// every wake look like new data and spends WidgetKit's refresh budget on
    /// nothing, which on watchOS is the budget the countdown itself needs.
    ///
    /// Fractional seconds are in the fixture on purpose — `Date` goes through
    /// JSON as a `Double`, and a lossy encoding would show up here first.
    func testAReplayedSnapshotComparesEqualSoTheWakeCanSkipTheReload() {
        let shapes: [RecoverySnapshot] = [
            .empty,
            RecoverySnapshot(
                readyAt: RecoveryFixtures.now.addingTimeInterval(18 * 3600 + 0.375),
                sessionEnd: RecoveryFixtures.now.addingTimeInterval(-3600.25),
                hours: 21.7,
                windowLowHours: 18.4,
                windowHighHours: 24.9,
                profile: .strength,
                activityLabel: "lifting session",
                category: .unusuallyHard,
                confidence: .medium,
                reasons: ["Hard for you: 60-minute lifting session."],
                calculatedAt: RecoveryFixtures.now.addingTimeInterval(-0.125),
                isPro: true
            ),
            // Expired: `readyAt` in the past is the state the wrist sits in for
            // most of a week, so it is the payload replayed most often.
            RecoverySnapshot(
                readyAt: RecoveryFixtures.now.addingTimeInterval(-2 * 3600),
                sessionEnd: RecoveryFixtures.now.addingTimeInterval(-26 * 3600),
                hours: 22,
                windowLowHours: 18.7,
                windowHighHours: 25.3,
                profile: .endurance,
                activityLabel: "run",
                category: .hard,
                confidence: .high,
                calculatedAt: RecoveryFixtures.now.addingTimeInterval(-26 * 3600)
            )
        ]

        for snapshot in shapes {
            RecoverySnapshotStore.save(snapshot, defaults: defaults)
            XCTAssertEqual(
                RecoverySnapshotStore.loadIfPresent(defaults: defaults), snapshot,
                "a replayed \(snapshot.activityLabel.isEmpty ? "empty" : snapshot.activityLabel) snapshot must read back equal"
            )
        }
    }

    /// The copy this all exists to select between. `neverSynced` is an
    /// instruction the user can act on; `noRecentWorkout` is a statement about
    /// their training. Showing the instruction to somebody with nothing to do
    /// is the failure, so the two must not render the same.
    func testTheNeverSyncedCopyDiffersFromTheNoWorkoutCopy() {
        let neverSynced = ComplicationCopy.primary(
            phase: .noRecentWorkout, style: .countdown, remaining: 0, readyAt: nil,
            dataState: .neverSynced
        )
        let noWorkout = ComplicationCopy.primary(
            phase: .noRecentWorkout, style: .countdown, remaining: 0, readyAt: nil,
            dataState: .synced
        )
        XCTAssertNotEqual(neverSynced, noWorkout)
    }
}
