import SwiftData
import XCTest

/// The half of stacking that lives on disk.
///
/// `StackedRecoveryTests` covers the arithmetic; this covers what survives a
/// relaunch. They are separate files because they fail for different reasons:
/// one means the model is wrong, the other means the model is right and the
/// record forgot half of it.
final class StackedRecoveryPersistenceTests: XCTestCase {

    private let now = RecoveryFixtures.now

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: RecoveryStateRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    private func stacked(
        sessionHours: Double = 12,
        carried: Double = 6,
        id: String = "stacked"
    ) -> RecoveryEstimate {
        let end = now.addingTimeInterval(-3600)
        return RecoveryEstimate(
            sessionID: id,
            profile: .endurance,
            activityLabel: "run",
            calculatedAt: now,
            sessionEnd: end,
            readyAt: end.addingTimeInterval((sessionHours + carried) * 3600),
            hours: sessionHours,
            windowLowHours: (sessionHours + carried) * 0.85,
            windowHighHours: (sessionHours + carried) * 1.15,
            load: SessionLoad(value: 120, source: .heartRate, heartRateCoverage: 0.95),
            relativeLoad: 1.5,
            category: .hard,
            confidence: .high,
            reasons: [],
            carriedHours: carried
        )
    }

    /// The one the audit was about. Everything the model works out about a
    /// stacked session has to come back after the process dies, because the
    /// countdown outlives the launch that produced it.
    func testAStackedEstimateSurvivesASaveAndReload() throws {
        let container = try container()
        let context = ModelContext(container)
        let original = stacked()

        context.insert(RecoveryStateRecord(estimate: original))
        try context.save()

        let reloaded = try ModelContext(container)
            .fetch(FetchDescriptor<RecoveryStateRecord>())
        XCTAssertEqual(reloaded.count, 1)
        let restored = try XCTUnwrap(reloaded.first).estimate

        XCTAssertEqual(restored.carriedHours, original.carriedHours, accuracy: 0.0001)
        XCTAssertEqual(restored.totalHours, original.totalHours, accuracy: 0.0001)
        XCTAssertEqual(restored.hours, original.hours, accuracy: 0.0001)
        XCTAssertTrue(restored.isStacked)
    }

    /// `readyAt` is stored and `hours` is the session's own cost, so a record
    /// that drops the carried amount rehydrates self-contradictory: the
    /// countdown ends where an 18-hour window ends while every figure derived
    /// from `totalHours` says 12. This asserts the two agree.
    func testTheRestoredCountdownEndsWhereTheRestoredTotalSaysItShould() throws {
        let container = try container()
        let context = ModelContext(container)
        let original = stacked(sessionHours: 12, carried: 6)
        context.insert(RecoveryStateRecord(estimate: original))
        try context.save()

        let restored = try XCTUnwrap(
            try context.fetch(FetchDescriptor<RecoveryStateRecord>()).first
        ).estimate

        let impliedHours = restored.readyAt.timeIntervalSince(restored.sessionEnd) / 3600
        XCTAssertEqual(impliedHours, restored.totalHours, accuracy: 0.0001)
        XCTAssertEqual(restored.totalHours, 18, accuracy: 0.0001)
    }

    /// `update(from:)` is the path a rescore takes, and it has its own list of
    /// fields to copy. Adding a property to the initialiser and forgetting this
    /// one leaves a record that is correct until the first refresh.
    func testRescoringARecordCarriesTheNewResidual() throws {
        let container = try container()
        let context = ModelContext(container)
        let record = RecoveryStateRecord(estimate: stacked(sessionHours: 12, carried: 0))
        context.insert(record)
        try context.save()
        XCTAssertFalse(record.estimate.isStacked)

        record.update(from: stacked(sessionHours: 12, carried: 6))
        try context.save()

        let restored = try XCTUnwrap(
            try context.fetch(FetchDescriptor<RecoveryStateRecord>()).first
        ).estimate
        XCTAssertEqual(restored.carriedHours, 6, accuracy: 0.0001)
        XCTAssertTrue(restored.isStacked)
    }

    /// A record written before stacking existed has nil here, and nil has to
    /// mean zero rather than crash or guess. Those estimates genuinely were not
    /// stacked, so reporting them as unstacked is not a fallback, it is the
    /// truth.
    func testALegacyRecordWithNoResidualDecodesAsUnstacked() throws {
        let container = try container()
        let context = ModelContext(container)
        let record = RecoveryStateRecord(estimate: stacked(sessionHours: 12, carried: 6))
        context.insert(record)
        // Exactly what SwiftData hands back for a row written before the
        // property existed.
        record.carriedHours = nil
        try context.save()

        let restored = try XCTUnwrap(
            try context.fetch(FetchDescriptor<RecoveryStateRecord>()).first
        ).estimate
        XCTAssertEqual(restored.carriedHours, 0)
        XCTAssertFalse(restored.isStacked)
        XCTAssertEqual(restored.totalHours, restored.hours, accuracy: 0.0001)
    }

    /// Stacking changes published numbers, so it has to change the version too,
    /// or `RecoveryEngine.rescore` leaves every existing record frozen under
    /// pre-stacking semantics and the user has no way to reach the new ones.
    func testTheStackingBehaviourCarriesItsOwnModelVersion() {
        XCTAssertGreaterThanOrEqual(
            recoveryModelVersion, 8,
            "stacking changed the numbers; bump recoveryModelVersion so old records thaw"
        )
        XCTAssertEqual(stacked().modelVersion, recoveryModelVersion)
    }
}
