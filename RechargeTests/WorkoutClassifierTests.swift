import XCTest

final class WorkoutClassifierTests: XCTestCase {

    private func profile(_ code: WorkoutClassifier.ActivityCode) -> WorkoutProfile {
        WorkoutClassifier.profile(activityCode: code.rawValue)
    }

    func testObviousEnduranceTypes() {
        for code in [WorkoutClassifier.ActivityCode.running, .cycling, .swimming, .rowing, .elliptical] {
            XCTAssertEqual(profile(code), .endurance, "\(code) should be endurance")
        }
    }

    func testObviousStrengthTypes() {
        XCTAssertEqual(profile(.traditionalStrengthTraining), .strength)
        XCTAssertEqual(profile(.coreTraining), .strength)
    }

    func testActiveRecoveryTypesNeverStartACountdown() {
        for code in [WorkoutClassifier.ActivityCode.walking, .yoga, .pilates, .flexibility, .taiChi, .cooldown] {
            XCTAssertEqual(profile(code), .easy, "\(code) should be easy")
        }
    }

    // MARK: - The HYROX / CrossFit ambiguity

    func testAmbiguousTypesDefaultToMixed() {
        XCTAssertEqual(profile(.functionalStrengthTraining), WorkoutClassifier.ambiguousDefault)
        XCTAssertEqual(profile(.highIntensityIntervalTraining), WorkoutClassifier.ambiguousDefault)
        XCTAssertEqual(WorkoutClassifier.ambiguousDefault, .mixed)
    }

    func testTheUserSettingRedirectsBothAmbiguousTypes() {
        for code in WorkoutClassifier.ambiguousCodes {
            XCTAssertEqual(
                WorkoutClassifier.profile(activityCode: code, ambiguousProfile: .strength),
                .strength
            )
        }
    }

    func testTheUserSettingDoesNotLeakOntoUnambiguousTypes() {
        XCTAssertEqual(
            WorkoutClassifier.profile(
                activityCode: WorkoutClassifier.ActivityCode.running.rawValue,
                ambiguousProfile: .strength
            ),
            .endurance,
            "a run must stay a run whatever the HYROX default is set to"
        )
    }

    func testPerSessionOverrideBeatsEverything() {
        XCTAssertEqual(
            WorkoutClassifier.profile(
                activityCode: WorkoutClassifier.ActivityCode.running.rawValue,
                ambiguousProfile: .mixed,
                override: .easy
            ),
            .easy
        )
    }

    // MARK: - Unknown codes

    func testUnknownActivityCodesFallBackToEnduranceRatherThanCrashing() {
        XCTAssertEqual(WorkoutClassifier.profile(activityCode: 9_999), .endurance)
        XCTAssertEqual(WorkoutClassifier.label(activityCode: 9_999), "workout")
    }

    // MARK: - Labels

    func testLabelsReadAsPlainEnglish() {
        XCTAssertEqual(WorkoutClassifier.label(activityCode: WorkoutClassifier.ActivityCode.running.rawValue), "run")
        XCTAssertEqual(WorkoutClassifier.label(activityCode: WorkoutClassifier.ActivityCode.cycling.rawValue), "ride")
        XCTAssertEqual(
            WorkoutClassifier.label(activityCode: WorkoutClassifier.ActivityCode.traditionalStrengthTraining.rawValue),
            "lifting session"
        )
    }

    func testEveryKnownCodeProducesANonEmptyLabelAndAProfile() {
        for code in 1...100 {
            let label = WorkoutClassifier.label(activityCode: UInt(code))
            XCTAssertFalse(label.isEmpty)
            XCTAssertFalse(label.contains("HK"), "raw HealthKit names must never reach the user")
        }
    }

    // MARK: - Effort prompt

    func testOnlyStrengthAndMixedAskForEffort() {
        XCTAssertTrue(WorkoutProfile.strength.wantsEffortInput)
        XCTAssertTrue(WorkoutProfile.mixed.wantsEffortInput)
        XCTAssertFalse(WorkoutProfile.endurance.wantsEffortInput)
        XCTAssertFalse(WorkoutProfile.easy.wantsEffortInput)
    }
}
