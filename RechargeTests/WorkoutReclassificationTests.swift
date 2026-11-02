import SwiftData
import XCTest

/// "Functional and hybrid training" in Settings has to reach the sessions that
/// are already on the phone.
///
/// `RecoveryEngine.importWorkouts` classifies a session once, with whatever the
/// setting said that day, and Health's workout query is anchored, so the same
/// session is never handed over again. Until `WorkoutRecord.reclassify` the
/// picker only ever moved sessions recorded after the change, and the countdown
/// on screen kept the curve the user had just told the app was wrong.
final class WorkoutReclassificationTests: XCTestCase {

    private let functional = WorkoutClassifier.ActivityCode.functionalStrengthTraining
    private let running = WorkoutClassifier.ActivityCode.running

    private func container() throws -> ModelContainer {
        try ModelContainer(
            for: WorkoutRecord.self,
            configurations: ModelConfiguration(isStoredInMemoryOnly: true)
        )
    }

    /// A session as the importer stores it: classified once, under the setting
    /// of the day it arrived.
    private func imported(
        _ code: WorkoutClassifier.ActivityCode,
        id: String = UUID().uuidString,
        whileTheSettingWas setting: WorkoutProfile = WorkoutClassifier.ambiguousDefault
    ) -> WorkoutRecord {
        let end = RecoveryFixtures.now.addingTimeInterval(-3600)
        return WorkoutRecord(
            healthKitUUID: id,
            activityCode: Int(code.rawValue),
            startDate: end.addingTimeInterval(-3600),
            endDate: end,
            durationMinutes: 60,
            activeEnergy: 380,
            profile: WorkoutClassifier.profile(activityCode: code.rawValue, ambiguousProfile: setting),
            activityLabel: WorkoutClassifier.label(activityCode: code.rawValue)
        )
    }

    /// What the model says about one stored session, scored the way the engine
    /// scores it: the record's profile, a patchy heart-rate trace, and the
    /// energy the watch reported.
    private func hours(for record: WorkoutRecord) -> Double {
        let session = SessionInput(
            id: record.healthKitUUID,
            profile: record.effectiveProfile,
            startDate: record.startDate,
            endDate: record.endDate,
            durationMinutes: record.durationMinutes,
            averageHeartRate: 120,
            restingHeartRate: 55,
            maxHeartRate: 188,
            heartRateCoverage: 0.2,
            activeEnergyKilocalories: record.activeEnergy,
            activityLabel: record.activityLabel
        )
        return RecoveryCalculator.estimate(
            for: session,
            baseline: RecoveryBaseline.standard(for: session.profile),
            now: RecoveryFixtures.now
        ).hours
    }

    // MARK: - The setting reaches what is already stored

    func testASessionImportedUnderTheDefaultFollowsTheSettingOnceItChanges() {
        let record = imported(functional)
        XCTAssertEqual(record.effectiveProfile, .mixed)

        XCTAssertTrue(record.reclassify(ambiguousProfile: .strength))

        XCTAssertEqual(record.effectiveProfile, .strength)
        XCTAssertEqual(record.profileRaw, WorkoutProfile.strength.rawValue)
    }

    func testBothAmbiguousTypesFollowEveryChoiceThePickerOffers() {
        for code in WorkoutClassifier.ActivityCode.allCases
        where WorkoutClassifier.ambiguousCodes.contains(code.rawValue) {
            for choice in [WorkoutProfile.mixed, .strength, .endurance] {
                let record = imported(code, whileTheSettingWas: .mixed)
                record.reclassify(ambiguousProfile: choice)
                XCTAssertEqual(
                    record.effectiveProfile, choice,
                    "\(code) stored under mixed should read \(choice) once the setting says so"
                )
            }
        }
    }

    func testTheSettingGoesBackAsEasilyAsItWentForward() {
        let record = imported(functional, whileTheSettingWas: .strength)
        XCTAssertEqual(record.effectiveProfile, .strength)

        XCTAssertTrue(record.reclassify(ambiguousProfile: .mixed))

        XCTAssertEqual(record.effectiveProfile, .mixed)
    }

    func testTheCountdownMovesWhenTheSettingDoes() {
        let record = imported(functional)
        let underTheDefault = hours(for: record)

        record.reclassify(ambiguousProfile: .strength)
        let afterTheChange = hours(for: record)

        XCTAssertNotEqual(
            afterTheChange, underTheDefault, accuracy: 0.5,
            "the same session must be scored on the curve the user picked"
        )
        let scoredAsStrengthFromTheStart = hours(for: imported(functional, whileTheSettingWas: .strength))
        XCTAssertEqual(afterTheChange, scoredAsStrengthFromTheStart, accuracy: 0.0001)
    }

    // MARK: - What it must leave alone

    func testASessionThatIsNotAmbiguousIsLeftAlone() {
        let record = imported(running)
        XCTAssertFalse(record.reclassify(ambiguousProfile: .strength))
        XCTAssertEqual(record.effectiveProfile, .endurance)
    }

    func testReclassifyingUnderTheSameSettingChangesNothing() {
        let record = imported(functional)
        XCTAssertFalse(record.reclassify(ambiguousProfile: WorkoutClassifier.ambiguousDefault))
        XCTAssertEqual(record.effectiveProfile, .mixed)
    }

    func testAPerSessionOverrideStillBeatsTheSetting() {
        let record = imported(functional)
        record.profileOverride = .endurance

        record.reclassify(ambiguousProfile: .strength)

        XCTAssertEqual(record.effectiveProfile, .endurance)
        XCTAssertEqual(record.profileOverride, .endurance)
    }

    func testTheUsersIntensityAnswerSurvivesReclassification() {
        let record = imported(functional)
        record.intensityOverride = .hard

        record.reclassify(ambiguousProfile: .strength)

        XCTAssertEqual(record.intensityOverride, .hard)
        XCTAssertEqual(record.effectiveProfile, .strength)
    }

    func testACorruptActivityCodeIsIgnoredRatherThanTrapping() {
        let record = imported(functional)
        record.activityCode = -1

        XCTAssertFalse(record.reclassify(ambiguousProfile: .strength))
        XCTAssertEqual(record.effectiveProfile, .mixed)
    }

    // MARK: - It is the stored record that changes

    func testTheNewClassificationIsWhatComesBackAfterASaveAndReload() throws {
        let container = try container()
        let context = ModelContext(container)
        let record = imported(functional, id: "stored-functional")
        context.insert(record)
        try context.save()

        record.reclassify(ambiguousProfile: .strength)
        try context.save()

        let reloaded = try ModelContext(container).fetch(FetchDescriptor<WorkoutRecord>())
        XCTAssertEqual(reloaded.count, 1)
        XCTAssertEqual(try XCTUnwrap(reloaded.first).effectiveProfile, .strength)
    }
}
