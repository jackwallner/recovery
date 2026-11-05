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
}
