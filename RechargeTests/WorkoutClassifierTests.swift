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

    /// The whole raw-value table, pinned against HealthKit's own numbering.
    ///
    /// This exists because the original table omitted `australianFootball` (3)
    /// and shifted everything from `badminton` (4) through `crossTraining` (11)
    /// up by one slot. Boxing arrived as an unmapped code and was scored as
    /// endurance; a climb was read as boxing; basketball was read as the name
    /// below it and fell through to the default branch. Nothing in the suite
    /// could see it, because every test asked the classifier about a code it had
    /// looked up in the same wrong table.
    ///
    /// Verified against `HKWorkout.h` in the iOS 26.5 SDK. Note that 81 is a
    /// genuine gap in Apple's enum: `swimBikeRun` carries an explicit `= 82`.
    func testTheRawValuesMatchHealthKit() {
        let healthKit: [UInt: WorkoutClassifier.ActivityCode] = [
            1: .americanFootball, 2: .archery, 3: .australianFootball, 4: .badminton,
            5: .baseball, 6: .basketball, 7: .bowling, 8: .boxing, 9: .climbing,
            10: .cricket, 11: .crossTraining, 12: .curling, 13: .cycling, 14: .dance,
            15: .danceInspiredTraining, 16: .elliptical, 17: .equestrianSports,
            18: .fencing, 19: .fishing, 20: .functionalStrengthTraining, 21: .golf,
            22: .gymnastics, 23: .handball, 24: .hiking, 25: .hockey, 26: .hunting,
            27: .lacrosse, 28: .martialArts, 29: .mindAndBody,
            30: .mixedMetabolicCardioTraining, 31: .paddleSports, 32: .play,
            33: .preparationAndRecovery, 34: .racquetball, 35: .rowing, 36: .rugby,
            37: .running, 38: .sailing, 39: .skatingSports, 40: .snowSports,
            41: .soccer, 42: .softball, 43: .squash, 44: .stairClimbing,
            45: .surfingSports, 46: .swimming, 47: .tableTennis, 48: .tennis,
            49: .trackAndField, 50: .traditionalStrengthTraining, 51: .volleyball,
            52: .walking, 53: .waterFitness, 54: .waterPolo, 55: .waterSports,
            56: .wrestling, 57: .yoga, 58: .barre, 59: .coreTraining,
            60: .crossCountrySkiing, 61: .downhillSkiing, 62: .flexibility,
            63: .highIntensityIntervalTraining, 64: .jumpRope, 65: .kickboxing,
            66: .pilates, 67: .snowboarding, 68: .stairs, 69: .stepTraining,
            70: .wheelchairWalkPace, 71: .wheelchairRunPace, 72: .taiChi,
            73: .mixedCardio, 74: .handCycling, 75: .discSports, 76: .fitnessGaming,
            77: .cardioDance, 78: .socialDance, 79: .pickleball, 80: .cooldown,
            82: .swimBikeRun, 83: .transition, 84: .underwaterDiving, 3000: .other
        ]
        for (raw, expected) in healthKit {
            XCTAssertEqual(
                WorkoutClassifier.ActivityCode(rawValue: raw), expected,
                "raw value \(raw) does not name \(expected)"
            )
        }
        XCTAssertNil(WorkoutClassifier.ActivityCode(rawValue: 81), "81 is a gap in HealthKit's enum")
    }

    /// The four activities the shift actually broke, named so a regression is
    /// legible rather than a number moving.
    func testTheActivitiesTheOffByOneBrokeAreClassifiedAgain() {
        XCTAssertEqual(WorkoutClassifier.profile(activityCode: 8), .mixed, "boxing")
        XCTAssertEqual(WorkoutClassifier.profile(activityCode: 6), .mixed, "basketball")
        XCTAssertEqual(WorkoutClassifier.profile(activityCode: 9), .strength, "climbing")
        XCTAssertEqual(WorkoutClassifier.profile(activityCode: 11), .mixed, "cross-training")
        XCTAssertEqual(WorkoutClassifier.profile(activityCode: 4), .mixed, "badminton")
        XCTAssertEqual(WorkoutClassifier.profile(activityCode: 7), .easy, "bowling")
    }

    /// `String.capitalized` lowercases the rest of every word, so the one label
    /// with an acronym in it rendered in History and on the detail sheet as
    /// "Hiit Session". Nothing in the suite could see it, because every fixture
    /// and every other label is ordinary words; a seeded Health store with a
    /// real HIIT session in it is what surfaced it.
    func testAnAcronymSurvivesBeingTitleCased() {
        XCTAssertEqual(WorkoutClassifier.title(activityCode: 63), "HIIT Session")
        XCTAssertEqual("HIIT session".capitalized, "Hiit Session", "the behaviour being avoided")
    }

    /// Every label has to survive the same treatment: a title is the label with
    /// word-initial capitals and nothing else changed.
    func testTitleCasingOnlyEverRaisesTheFirstLetterOfAWord() {
        for raw in (UInt(1)...UInt(84)) where raw != 81 {
            let label = WorkoutClassifier.label(activityCode: raw)
            let title = WorkoutClassifier.title(activityCode: raw)
            XCTAssertEqual(title.count, label.count, "\(label) changed length")
            XCTAssertEqual(title.lowercased(), label.lowercased(), "\(label) changed letters")
            XCTAssertEqual(title.first, label.first?.uppercased().first, "\(label) is not capitalised")
        }
    }

    /// No real HealthKit code may fall through to the unknown-code fallback.
    func testEveryHealthKitCodeHasAHome() {
        for raw in (UInt(1)...UInt(84)) where raw != 81 {
            XCTAssertNotNil(
                WorkoutClassifier.ActivityCode(rawValue: raw),
                "raw value \(raw) is not pinned, so it falls back to endurance"
            )
        }
    }
}
