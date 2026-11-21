import SwiftData
import XCTest

/// Regression tests for the bug catalog of 2026-11-20
/// (`project-docs/audits/2026-11-20-bug-ux.html`). Each was run against the
/// unfixed code first.
final class AuditFixRegressionTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func session(
        _ id: String,
        profile: WorkoutProfile,
        endingHoursAgo: Double,
        minutes: Double,
        reserve: Double,
        label: String
    ) -> SessionInput {
        let resting = 55.0, max = 185.0
        let end = now.addingTimeInterval(-endingHoursAgo * 3600)
        return SessionInput(
            id: id,
            profile: profile,
            startDate: end.addingTimeInterval(-minutes * 60),
            endDate: end,
            durationMinutes: minutes,
            averageHeartRate: resting + reserve * (max - resting),
            restingHeartRate: resting,
            maxHeartRate: max,
            heartRateCoverage: 1,
            activityLabel: label
        )
    }

    private func estimate(_ session: SessionInput, after previous: RecoveryEstimate? = nil) -> RecoveryEstimate {
        let carried = RecoveryCalculator.carriedHours(into: session, from: previous?.readyAt)
        return RecoveryCalculator.estimate(
            for: session, baseline: .standard(for: session.profile), carriedHours: carried, now: now
        )
    }

    // MARK: - B6: the Ready moment behind an easy session

    /// A hard run, then an easy walk four hours later that starts no countdown.
    /// When the run's countdown runs out, that is a Ready moment the user had,
    /// and the walk being the newest session must not hide it.
    func testReadyMomentCountsARunWhoseCountdownOutlivedALaterEasyWalk() {
        let hours = estimate(session("run", profile: .endurance, endingHoursAgo: 0, minutes: 90, reserve: 0.8, label: "run")).totalHours
        // The run ended so that its countdown ran out an hour ago.
        let runEndedHoursAgo = hours + 1
        let run = estimate(session("run", profile: .endurance, endingHoursAgo: runEndedHoursAgo, minutes: 90, reserve: 0.8, label: "run"))
        let walk = estimate(
            session("walk", profile: .easy, endingHoursAgo: runEndedHoursAgo - 4, minutes: 30, reserve: 0.3, label: "walk"),
            after: run
        )
        XCTAssertTrue(run.producesCountdown)
        XCTAssertFalse(walk.producesCountdown, "the walk must start no countdown")
        XCTAssertLessThanOrEqual(run.readyAt, now, "the run's countdown must have run out")
        XCTAssertGreaterThan(walk.sessionEnd, run.sessionEnd, "the walk must be the newest session")

        let setup = run.sessionEnd.addingTimeInterval(-86_400)
        XCTAssertEqual(
            RecoveryResolver.readyMoment(in: [run, walk], eligibleFrom: setup, now: now)?.sessionID,
            "run",
            "the run's Ready moment was hidden by the walk after it"
        )
    }

    /// The guard that must survive the fix: while a later countdown is still
    /// running, an earlier one running out underneath it is not a Ready moment.
    func testReadyMomentWaitsWhileAStackedCountdownIsStillRunning() {
        let firstHours = estimate(session("A", profile: .endurance, endingHoursAgo: 0, minutes: 60, reserve: 0.78, label: "run")).hours
        let first = estimate(session("A", profile: .endurance, endingHoursAgo: firstHours + 1, minutes: 60, reserve: 0.78, label: "run"))
        let second = estimate(session("B", profile: .endurance, endingHoursAgo: 3, minutes: 60, reserve: 0.78, label: "run"), after: first)
        XCTAssertLessThanOrEqual(first.readyAt, now)
        XCTAssertGreaterThan(second.readyAt, now)

        let setup = first.sessionEnd.addingTimeInterval(-86_400)
        XCTAssertNil(RecoveryResolver.readyMoment(in: [first, second], eligibleFrom: setup, now: now))
        XCTAssertEqual(
            RecoveryResolver.readyMoment(in: [first, second], eligibleFrom: setup, now: second.readyAt.addingTimeInterval(60))?.sessionID,
            "B"
        )
    }
}

// MARK: - B2: the Watch effort question names the session it saves to

final class PendingEffortRequestTests: XCTestCase {

    private var defaults: UserDefaults!
    private let suite = "PendingEffortRequestTests"

    override func setUp() {
        defaults = UserDefaults(suiteName: suite)
        defaults.removePersistentDomain(forName: suite)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suite)
    }

    /// A morning lift wants an effort answer and an evening run owns the
    /// countdown, so the snapshot says "run". What the Watch reads for the
    /// question has to be the lift, both its ID and its activity.
    func testTheWatchReadsTheLabelOfTheSessionTheAnswerIsSavedTo() {
        let snapshot = RecoverySnapshot(
            readyAt: RecoveryFixtures.now.addingTimeInterval(20 * 3600),
            sessionEnd: RecoveryFixtures.now.addingTimeInterval(-3600),
            hours: 21,
            windowLowHours: 18,
            windowHighHours: 24,
            profile: .endurance,
            activityLabel: "run",
            calculatedAt: RecoveryFixtures.now
        )
        RecoverySnapshotStore.save(snapshot, defaults: defaults)
        PendingEffortRequest.save(
            PendingEffortRequest(sessionID: "lift", activityLabel: "lifting session"),
            defaults: defaults
        )

        let pending = PendingEffortRequest.load(defaults: defaults)
        XCTAssertEqual(pending?.sessionID, "lift")
        XCTAssertEqual(pending?.activityLabel, "lifting session")
        XCTAssertNotEqual(pending?.activityLabel, RecoverySnapshotStore.load(defaults: defaults).activityLabel)
    }

    /// Clearing the request clears its label too, so a later request from an
    /// older phone build (ID only) cannot inherit a stale activity.
    func testClearingTheRequestClearsItsLabel() {
        PendingEffortRequest.save(PendingEffortRequest(sessionID: "lift", activityLabel: "lifting session"), defaults: defaults)
        PendingEffortRequest.save(nil, defaults: defaults)
        XCTAssertNil(PendingEffortRequest.load(defaults: defaults))

        defaults.set("older", forKey: PendingEffortRequest.sessionIDKey)
        XCTAssertEqual(PendingEffortRequest.load(defaults: defaults)?.activityLabel, "")
    }
}

// MARK: - B3: a quarantined store and the Health anchor

/// When the SwiftData store cannot be opened, `DataService` moves it aside and
/// starts empty. The saved HealthKit workout anchor still points past every
/// workout the old store held, and an anchored query only returns what is newer
/// than its anchor, so the empty store would stay empty. The anchor has to go
/// with the store.
@MainActor
final class StoreQuarantineTests: XCTestCase {

    /// `DataService.containerURL`, resolved the same way.
    private var storeURL: URL {
        let base = FileManager.default.containerURL(forSecurityApplicationGroupIdentifier: rechargeAppGroupID)
            ?? FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.temporaryDirectory
        return base.appendingPathComponent("Recharge.store")
    }

    func testAQuarantinedStoreForgetsTheHealthAnchorSoHistoryReimports() throws {
        let defaults = try XCTUnwrap(UserDefaults(suiteName: rechargeAppGroupID))
        let url = storeURL
        try FileManager.default.createDirectory(
            at: url.deletingLastPathComponent(),
            withIntermediateDirectories: true
        )
        for suffix in ["", "-wal", "-shm"] {
            try? FileManager.default.removeItem(atPath: url.path + suffix)
        }
        try Data("not a database".utf8).write(to: url)
        defaults.set(Data([1, 2, 3]), forKey: "healthKitWorkoutAnchor")

        // First touch in this process: the open fails, the store is
        // quarantined, and an empty one replaces it.
        _ = DataService.sharedModelContainer

        XCTAssertTrue(
            try FileManager.default.contentsOfDirectory(atPath: url.deletingLastPathComponent().path)
                .contains { $0.hasPrefix("Recharge.store.corrupt-") },
            "the unreadable store was not quarantined"
        )
        XCTAssertNil(
            defaults.data(forKey: "healthKitWorkoutAnchor"),
            "the empty store kept the old Health anchor, so past workouts would never re-import"
        )
    }
}

// MARK: - B10: the max heart rate field in local digits

final class TypedNumberTests: XCTestCase {

    /// What the field used to parse with. Kept as the record of the bug: both
    /// spellings of 185 read as nothing, so the field rejected them.
    func testDoubleReadsOnlyASCIIDigits() {
        XCTAssertNil(Double("\u{0661}\u{0668}\u{0665}"))
        XCTAssertNil(Double("\u{06F1}\u{06F8}\u{06F5}"))
    }

    func testAMaxHeartRateTypedInArabicIndicOrPersianDigitsReadsAsItsValue() {
        XCTAssertEqual(TypedNumber.value(of: "\u{0661}\u{0668}\u{0665}"), 185)
        XCTAssertEqual(TypedNumber.value(of: "\u{06F1}\u{06F8}\u{06F5}"), 185)
        XCTAssertEqual(TypedNumber.value(of: "\u{0967}\u{096E}\u{096B}"), 185)
    }

    func testASCIIInputReadsExactlyAsBefore() {
        for text in ["185", "185.5", "0", "", "abc", "18a", "-5"] {
            XCTAssertEqual(TypedNumber.value(of: text), Double(text), "\(text)")
        }
    }

    func testAnythingThatIsNotAWholeNumberIsRejected() {
        XCTAssertNil(TypedNumber.value(of: "\u{0661}\u{0668}x"))
        XCTAssertNil(TypedNumber.value(of: "\u{0661}\u{0668}\u{0665}\u{0661}\u{0668}\u{0665}\u{0661}"))
    }
}
