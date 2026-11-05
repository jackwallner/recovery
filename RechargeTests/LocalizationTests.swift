import Foundation
import XCTest

/// The string catalog compiles into the test bundle, and the plural rules
/// survive the trip. A key that fell back to its own text would still read as
/// English, so these look the catalog up directly and use the sentences whose
/// wording depends on a count.
final class LocalizationTests: XCTestCase {
    /// Languages that must ship. Only English until the translation runs land;
    /// extend it with `Tools/Localization/check.py`'s `LANGS`.
    static let languages = ["en"]

    func testEveryLanguageShips() {
        for language in Self.languages {
            XCTAssertNotNil(
                Bundle.recharge.path(forResource: language, ofType: "lproj"),
                "\(language).lproj is missing, so the catalog was not compiled into this bundle"
            )
        }
    }

    func testTheCatalogIsCompiledIntoTheBundle() {
        let missing = "<missing>"
        for key in ["Ready", "Recovering", "Lifetime", "Continue with Recharge+"] {
            XCTAssertNotEqual(
                Bundle.recharge.localizedString(forKey: key, value: missing, table: nil),
                missing,
                "\"\(key)\" has no catalog entry"
            )
        }
    }

    func testOneCountSelectsTheSingularForm() {
        var readings = HealthIngestSummary.Readings()
        XCTAssertEqual(
            HealthIngestSummary.receiptLine(readings: readings, rowCount: 1),
            "Read from Apple Health: 1 reading."
        )
        XCTAssertEqual(
            HealthIngestSummary.receiptLine(readings: readings, rowCount: 3),
            "Read from Apple Health: 3 readings."
        )
        readings.workoutCount = 1
        readings.daysCovered = 1
        XCTAssertEqual(
            HealthIngestSummary.receiptLine(readings: readings, rowCount: 2),
            "Read from Apple Health: 1 workout over 1 day, plus 1 other signal."
        )
    }

    func testEachCountInOneSentenceTakesItsOwnForm() {
        var readings = HealthIngestSummary.Readings()
        readings.workoutCount = 214
        readings.daysCovered = 120
        XCTAssertEqual(
            HealthIngestSummary.receiptLine(readings: readings, rowCount: 5),
            "Read from Apple Health: 214 workouts over 120 days, plus 4 other signals."
        )
        readings.workoutCount = 1
        XCTAssertEqual(
            HealthIngestSummary.receiptLine(readings: readings, rowCount: 1),
            "Read from Apple Health: 1 workout over 120 days."
        )
    }

    func testCountdownShapesKeepTheirUnits() {
        XCTAssertEqual(CountdownFormat.remaining(3 * 86_400 + 4 * 3_600), "3d 4h")
        XCTAssertEqual(CountdownFormat.remaining(80 * 60), "1h 20m")
        XCTAssertEqual(CountdownFormat.window(low: 18, high: 28), "18 to 28h")
    }

    func testAStoredActivityLabelIsShownThroughTheCatalog() {
        XCTAssertEqual(WorkoutClassifier.displayLabel("run"), "run")
        XCTAssertEqual(WorkoutClassifier.displayTitle("lifting session"), "Lifting Session")
        XCTAssertEqual(WorkoutClassifier.displayTitle("HIIT session"), "HIIT Session")
        // A label written by a later version is shown as stored, not hidden.
        XCTAssertEqual(WorkoutClassifier.displayLabel("kite session"), "kite session")
    }

    func testTheStoredLabelsThemselvesDoNotChange() {
        // These are written to the store and the snapshot and matched by the
        // symbol lookup, so translating them in place would break both.
        XCTAssertEqual(WorkoutClassifier.label(activityCode: 37), "run")
        XCTAssertEqual(WorkoutClassifier.label(activityCode: 13), "ride")
    }

    func testPremiumBrandingIsRechargePlusInEverySentence() {
        XCTAssertEqual(RechargeConversionCopy.shortCTALabel(eligibleForTrial: true), "Continue with Recharge+")
        XCTAssertTrue(RechargeConversionCopy.comparisonCaption(hasPurchased: true).contains("Recharge+"))
    }

    // MARK: - Activity labels inside sentences

    /// Every label `label(activityCode:)` can store, which is the set each
    /// sentence slot in `ActivityPhrases.swift` has to carry a form for.
    private var storedLabels: [String] {
        var labels = Set(WorkoutClassifier.ActivityCode.allCases.map { WorkoutClassifier.label(activityCode: $0.rawValue) })
        labels.insert(WorkoutClassifier.label(activityCode: 9_999))
        return labels.sorted()
    }

    func testEveryStoredLabelHasAFormInEverySentenceSlot() {
        let missing = "<missing>"
        let bundle = Bundle.recharge
        func present(_ text: String, _ slot: String, _ label: String) {
            XCTAssertNotEqual(
                bundle.localizedString(forKey: text, value: missing, table: nil), missing,
                "\(slot) has no catalog key for \"\(label)\""
            )
        }
        XCTAssertGreaterThan(storedLabels.count, 20)
        for label in storedLabels {
            present("Your last \(label)", "lastSessionTitle", label)
            present("For your last \(label). %@", "lastSessionDetail", label)
            present("How hard was your \(label)?", "effortQuestion", label)
            present("How hard was that \(label)?", "watchEffortQuestion", label)
            present("Your countdown from that \(label) has finished.", "readyBody", label)
            present("your \(label)", "sourceObject", label)
            present("Your \(label)", "sourceSubject", label)
            present("Your estimate after that \(label) ran out.", "estimateAfter", label)
            present(label, "displayLabel", label)
        }
    }

    func testEnglishReadsExactlyAsItDidBeforeTheSlots() {
        for label in storedLabels {
            XCTAssertEqual(WorkoutClassifier.lastSessionTitle(label), "Your last \(label)")
            XCTAssertEqual(WorkoutClassifier.lastSessionDetail(label, caption: "Caption."), "For your last \(label). Caption.")
            XCTAssertEqual(WorkoutClassifier.effortQuestion(label), "How hard was your \(label)?")
            XCTAssertEqual(WorkoutClassifier.watchEffortQuestion(label), "How hard was that \(label)?")
            XCTAssertEqual(WorkoutClassifier.readyBody(label), "Your countdown from that \(label) has finished.")
            XCTAssertEqual(WorkoutClassifier.sourceObject(label), "your \(label)")
            XCTAssertEqual(WorkoutClassifier.sourceSubject(label), "Your \(label)")
            XCTAssertEqual(WorkoutClassifier.estimateAfter(label), "Your estimate after that \(label) ran out.")
            XCTAssertEqual(WorkoutClassifier.minuteSession(45, label), "45-minute \(label)")
            XCTAssertEqual(WorkoutClassifier.indefiniteMinuteSession(8, label), "a 8-minute \(label)")
            XCTAssertEqual(WorkoutClassifier.yourMinuteSession(60, label), "Your 60-minute \(label)")
        }
    }

    func testALabelFromALaterVersionReadsAsAWorkoutInsideASentence() {
        XCTAssertEqual(WorkoutClassifier.effortQuestion("kite session"), "How hard was your workout?")
        XCTAssertEqual(WorkoutClassifier.minuteSession(30, "kite session"), "30-minute workout")
    }

    func testTheReasonsKeepTheirMinuteCount() {
        XCTAssertEqual(
            RecoveryCalculator.belowThresholdReason(
                tier: .standard,
                category: .easy,
                activity: WorkoutClassifier.indefiniteMinuteSession(1, "run")
            ),
            "light session: a 1-minute run below the level that starts a countdown."
        )
        XCTAssertEqual(
            RecoveryCalculator.belowThresholdReason(
                tier: .personalized,
                category: .unusuallyHard,
                activity: WorkoutClassifier.indefiniteMinuteSession(12, "swim")
            ),
            "very hard for you: a 12-minute swim below your usual session load."
        )
    }

    // MARK: - The trial in a sentence

    func testEachTrialSentenceTakesTheLengthAsANumber() {
        XCTAssertEqual(
            RechargeConversionCopy.billedNote(trial: .days(7), eligibleForTrial: true),
            "7-day free trial included \u{B7} Cancel anytime"
        )
        XCTAssertEqual(
            RechargeConversionCopy.billedNote(trial: .days(1), eligibleForTrial: true),
            "1-day free trial included \u{B7} Cancel anytime"
        )
        XCTAssertEqual(
            RechargeConversionCopy.billedNote(trial: .months(1), eligibleForTrial: true),
            "1-month free trial included \u{B7} Cancel anytime"
        )
        XCTAssertEqual(
            RechargeConversionCopy.billedNote(trial: .days(7), eligibleForTrial: false),
            "Billed automatically \u{B7} Cancel anytime"
        )
        XCTAssertEqual(
            RechargeConversionCopy.billedNote(trial: .days(7), eligibleForTrial: true, isRecurring: false),
            "One-time purchase \u{B7} No subscription"
        )
    }

    func testTheDisclosuresNameTheTrialLength() {
        let full = RechargeConversionCopy.disclosure(trial: .days(7), priceLabel: "$29.99", eligibleForTrial: true)
        XCTAssertTrue(full.hasPrefix("$29.99 after the 7-day free trial. Auto-renews unless cancelled"), full)
        let months = RechargeConversionCopy.disclosure(trial: .months(1), priceLabel: "$29.99", eligibleForTrial: true)
        XCTAssertTrue(months.hasPrefix("$29.99 after the 1-month free trial. "), months)
        XCTAssertEqual(
            RechargeConversionCopy.sheetDisclosure(trial: .days(14), priceLabel: "$29.99", eligibleForTrial: true),
            "$29.99 after the 14-day free trial. Auto-renews unless cancelled at least 24 hours before the trial ends."
        )
        XCTAssertTrue(
            RechargeConversionCopy.disclosure(trial: .days(7), priceLabel: "$29.99", eligibleForTrial: false)
                .hasPrefix("$29.99. Auto-renews")
        )
    }

    func testTheTrialBadgeKeepsItsNumber() {
        XCTAssertEqual(IntroTrialLength.days(7).badge, "7-day free \u{B7} Nothing charged today")
        XCTAssertEqual(IntroTrialLength.months(1).badge, "1-month free \u{B7} Nothing charged today")
    }

    // MARK: - One word, two meanings

    func testAppearanceLightAndTrainingLightAreSeparateKeys() {
        let missing = "<missing>"
        XCTAssertEqual(Bundle.recharge.localizedString(forKey: "appearance.light", value: missing, table: nil), "Light")
        XCTAssertEqual(Bundle.recharge.localizedString(forKey: "Light", value: missing, table: nil), "Light")
        XCTAssertEqual(Bundle.recharge.localizedString(forKey: "sessionProfile.easy", value: missing, table: nil), "Easy")
        XCTAssertEqual(SessionIntensity.light.label, "Light")
    }
}
