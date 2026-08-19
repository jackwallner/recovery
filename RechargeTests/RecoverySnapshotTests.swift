import XCTest

final class RecoverySnapshotTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func estimate(hours: Double, endedHoursAgo: Double = 1) -> RecoveryEstimate {
        RecoveryEstimate(
            sessionID: "s",
            profile: .endurance,
            activityLabel: "run",
            calculatedAt: now,
            sessionEnd: now.addingTimeInterval(-endedHoursAgo * 3600),
            readyAt: now.addingTimeInterval((hours - endedHoursAgo) * 3600),
            hours: hours,
            windowLowHours: hours * 0.85,
            windowHighHours: hours * 1.15,
            load: SessionLoad(value: 120, source: .heartRate, heartRateCoverage: 0.95),
            relativeLoad: 1.5,
            category: .hard,
            confidence: .high,
            reasons: ["Hard for you: 60-minute run."]
        )
    }

    func testRoundTripsThroughUserDefaults() {
        let defaults = UserDefaults(suiteName: "RecoverySnapshotTests")!
        defaults.removePersistentDomain(forName: "RecoverySnapshotTests")

        let snapshot = RecoverySnapshot(estimate: estimate(hours: 20), isPro: true)
        RecoverySnapshotStore.save(snapshot, defaults: defaults)
        XCTAssertEqual(RecoverySnapshotStore.load(defaults: defaults), snapshot)
    }

    func testAnEmptyStoreLoadsTheEmptySnapshotRatherThanFailing() {
        let defaults = UserDefaults(suiteName: "RecoverySnapshotTestsEmpty")!
        defaults.removePersistentDomain(forName: "RecoverySnapshotTestsEmpty")
        let loaded = RecoverySnapshotStore.load(defaults: defaults)
        XCTAssertEqual(loaded, .empty)
        XCTAssertFalse(loaded.hasSession)
        XCTAssertEqual(loaded.phase(at: now), .noRecentWorkout)
    }

    func testAZeroHourEstimateStoresNoReadyTime() {
        let snapshot = RecoverySnapshot(estimate: estimate(hours: 0), isPro: false)
        XCTAssertNil(snapshot.readyAt)
        XCTAssertEqual(snapshot.phase(at: now), .ready)
        XCTAssertEqual(snapshot.remainingSeconds(at: now), 0)
    }

    func testProgressRunsFromZeroToOneAcrossTheWindow() {
        let snapshot = RecoverySnapshot(estimate: estimate(hours: 20, endedHoursAgo: 0), isPro: false)
        XCTAssertEqual(snapshot.progress(at: now), 0, accuracy: 0.001)
        XCTAssertEqual(snapshot.progress(at: now.addingTimeInterval(10 * 3600)), 0.5, accuracy: 0.001)
        XCTAssertEqual(snapshot.progress(at: now.addingTimeInterval(20 * 3600)), 1, accuracy: 0.001)
        XCTAssertEqual(snapshot.progress(at: now.addingTimeInterval(40 * 3600)), 1, accuracy: 0.001)
    }

    func testProgressIsEmptyWhenThereIsNoSession() {
        XCTAssertEqual(RecoverySnapshot.empty.progress(at: now), 0)
    }

    func testProgressIsFullWhenACompletedSessionHasNoWindow() {
        XCTAssertEqual(
            RecoverySnapshot(estimate: estimate(hours: 0), isPro: false).progress(at: now),
            1
        )
    }

    func testMissingAdditiveFieldsDecodeWithTheirCurrentDefaults() throws {
        let snapshot = RecoverySnapshot(estimate: estimate(hours: 20), isPro: true)
        var object = try XCTUnwrap(
            JSONSerialization.jsonObject(with: JSONEncoder().encode(snapshot)) as? [String: Any]
        )
        object.removeValue(forKey: "windowLowHours")
        object.removeValue(forKey: "windowHighHours")
        object.removeValue(forKey: "modelVersion")
        object.removeValue(forKey: "isPro")

        let legacyData = try JSONSerialization.data(withJSONObject: object)
        let decoded = try JSONDecoder().decode(RecoverySnapshot.self, from: legacyData)

        XCTAssertEqual(decoded.hours, 20)
        XCTAssertEqual(decoded.windowLowHours, 0)
        XCTAssertEqual(decoded.windowHighHours, 0)
        XCTAssertEqual(decoded.modelVersion, recoveryModelVersion)
        XCTAssertFalse(decoded.isPro)
    }

    func testAStaleSnapshotReadsAsNoRecentWorkout() {
        let snapshot = RecoverySnapshot(estimate: estimate(hours: 20, endedHoursAgo: 24 * 9), isPro: false)
        XCTAssertEqual(snapshot.phase(at: now), .noRecentWorkout)
    }

    func testDecodingSurvivesAnUnknownFutureModelVersion() throws {
        // Forward-compatibility: a snapshot written by a newer build must not
        // crash an older extension, it should just render what it understands.
        var snapshot = RecoverySnapshot(estimate: estimate(hours: 20), isPro: false)
        snapshot.modelVersion = 99
        let data = try JSONEncoder().encode(snapshot)
        let decoded = try JSONDecoder().decode(RecoverySnapshot.self, from: data)
        XCTAssertEqual(decoded.modelVersion, 99)
        XCTAssertEqual(decoded.hours, 20)
    }

    // MARK: - Phone → Watch transport

    /// The Watch and the iPhone have separate App Group containers, so the
    /// snapshot reaches the wrist only by being encoded into a WatchConnectivity
    /// application context and decoded on the other side. That is a plain
    /// property-list `Data` value, and everything the Watch renders has to
    /// survive the trip — including the optionals that distinguish a live
    /// countdown from a finished one.
    func testTheSnapshotSurvivesTheWatchConnectivityPayload() throws {
        for snapshot in [
            RecoverySnapshot(estimate: estimate(hours: 20), isPro: true),
            RecoverySnapshot(estimate: estimate(hours: 0), isPro: false),
            RecoverySnapshot.empty
        ] {
            let payload: [String: Any] = ["snapshot": try JSONEncoder().encode(snapshot)]
            let data = try XCTUnwrap(payload["snapshot"] as? Data)
            XCTAssertEqual(try JSONDecoder().decode(RecoverySnapshot.self, from: data), snapshot)
        }
    }

    /// A never-synced Watch and a Watch told "you have no workouts" both hold
    /// the empty snapshot, and its zero `remainingSeconds` formats as the word
    /// "Ready". Any surface that renders a countdown string has to branch on the
    /// phase first — the medium iOS widget did not, and printed Ready inside an
    /// empty ring for a user who had never finished a workout.
    func testTheEmptySnapshotMustNotBeRenderedThroughTheCountdownFormatter() {
        let empty = RecoverySnapshot.empty
        XCTAssertEqual(empty.phase(at: now), .noRecentWorkout)
        XCTAssertEqual(empty.remainingSeconds(at: now), 0)
        XCTAssertEqual(CountdownFormat.compactRemaining(empty.remainingSeconds(at: now)), "Ready")
        XCTAssertEqual(CountdownFormat.phaseHeadline(empty.phase(at: now)), "No recent workout")
    }
}
