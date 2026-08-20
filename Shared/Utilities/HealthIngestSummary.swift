import Foundation

/// Exactly what Recharge read out of Apple Health, in the user's words.
///
/// The app asks for eleven types in one permission sheet, which is a lot to
/// consent to on the strength of a sentence. This is the receipt: every row is
/// something that was actually found, phrased as the reading rather than as the
/// feature, and every type in `HealthKitService.readTypes` can appear here.
///
/// It is deliberately not a settings screen and not a chart. Three surfaces show
/// it and all three are making the same argument — onboarding, where it is the
/// evidence that the estimate on the next page was computed rather than
/// invented; the Recharge+ tab, where it is what the subscription is built on;
/// and Settings, where it answers "is this thing actually reading my data".
///
/// **A row only exists when there is a real value behind it.** Nothing here says
/// "not available" or "—": a receipt for something that was not read is not
/// evidence of anything, and a list of blanks in front of somebody deciding
/// whether to trust the app argues the opposite of what it is there for.
///
/// Pure and `Sendable`, so it can be built in a test without a Health store.
public struct HealthIngestSummary: Sendable, Equatable {

    /// One reading. `value` is the headline, `detail` says what it is for —
    /// which is the half that turns a permission grant into an explanation.
    public struct Row: Sendable, Equatable, Identifiable {
        public let id: String
        public let symbol: String
        public let value: String
        public let title: String
        public let detail: String

        public init(id: String, symbol: String, value: String, title: String, detail: String) {
            self.id = id
            self.symbol = symbol
            self.value = value
            self.title = title
            self.detail = detail
        }
    }

    public var rows: [Row]

    public var isEmpty: Bool { rows.isEmpty }

    public init(rows: [Row] = []) {
        self.rows = rows
    }

    // MARK: - Inputs

    /// The raw figures, before any of them have been turned into a sentence.
    /// Held as its own type so `RecoveryEngine` can publish measurements and
    /// this file can own every word the user reads.
    public struct Readings: Sendable, Equatable {
        public var workoutCount: Int = 0
        public var daysCovered: Int = 0
        public var activityTypes: Int = 0
        public var sessionsWithHeartRate: Int = 0
        public var observedMaxHeartRate: Double?
        public var restingHeartRate: Double?
        public var heartRateVariability: Double?
        public var averageSleepHours: Double?
        public var respiratoryRate: Double?
        public var heartRateRecovery: Double?
        public var vo2Max: Double?
        public var bodyMassKilograms: Double?
        public var age: Int?

        public init() {}
    }

    // MARK: - Building

    public init(readings: Readings, usesObservedMaxHeartRate: Bool) {
        var rows: [Row] = []

        if readings.workoutCount > 0 {
            let types = readings.activityTypes
            let detail = types > 1
                ? "Across \(types) activity types, over the last \(readings.daysCovered) days."
                : "Over the last \(readings.daysCovered) days."
            rows.append(Row(
                id: "workouts",
                symbol: "figure.run",
                value: "\(readings.workoutCount)",
                title: "Workouts scored",
                detail: detail
            ))
        }

        if let max = readings.observedMaxHeartRate {
            rows.append(Row(
                id: "maxHeartRate",
                symbol: "heart.fill",
                value: "\(Int(max.rounded())) bpm",
                title: usesObservedMaxHeartRate ? "Your highest heart rate" : "Heart-rate ceiling",
                // The distinction matters enough to spend a line on. A measured
                // ceiling is the difference between scoring somebody's intensity
                // and guessing at it, and a user who has never gone truly
                // maximal is being scored against a formula whatever this
                // number says.
                detail: usesObservedMaxHeartRate
                    ? "Measured from \(readings.sessionsWithHeartRate) sessions. Every intensity reading is scored against it."
                    : "Seen in your sessions, below what your age predicts, so the higher figure is used."
            ))
        } else if let age = readings.age {
            rows.append(Row(
                id: "age",
                symbol: "heart.fill",
                value: "\(age)",
                title: "Age, from your Health profile",
                detail: "Sets the heart-rate ceiling until your workouts show a higher one."
            ))
        }

        if let vo2 = readings.vo2Max {
            rows.append(Row(
                id: "vo2Max",
                symbol: "lungs.fill",
                value: String(format: "%.0f", vo2),
                title: "Cardio fitness (VO₂ max)",
                detail: "Sets the training level your sessions are compared against."
            ))
        }

        if let resting = readings.restingHeartRate {
            rows.append(Row(
                id: "restingHeartRate",
                symbol: "bed.double.fill",
                value: "\(Int(resting.rounded())) bpm",
                title: "Resting heart rate",
                detail: "Watched night to night for signs the last session is still with you."
            ))
        }

        if let hrv = readings.heartRateVariability {
            rows.append(Row(
                id: "hrv",
                symbol: "waveform.path.ecg",
                value: "\(Int(hrv.rounded())) ms",
                title: "Heart rate variability",
                detail: "The same, from the other direction."
            ))
        }

        if let recovery = readings.heartRateRecovery {
            rows.append(Row(
                id: "heartRateRecovery",
                symbol: "arrow.down.heart.fill",
                value: "−\(Int(recovery.rounded())) bpm",
                title: "One-minute recovery",
                detail: "How far your heart rate falls in the minute after a session ends."
            ))
        }

        if let sleep = readings.averageSleepHours {
            rows.append(Row(
                id: "sleep",
                symbol: "moon.stars.fill",
                value: String(format: "%.1fh", sleep),
                title: "Average sleep",
                detail: "A short night lengthens the estimate a little; a long one shortens it."
            ))
        }

        if let rate = readings.respiratoryRate {
            rows.append(Row(
                id: "respiratoryRate",
                symbol: "wind",
                value: String(format: "%.0f/min", rate),
                title: "Overnight breathing rate",
                detail: "Rises before you feel it when a session has not been absorbed."
            ))
        }

        if let mass = readings.bodyMassKilograms {
            rows.append(Row(
                id: "bodyMass",
                symbol: "scalemass.fill",
                value: MassFormatting.label(kilograms: mass),
                title: "Body weight",
                detail: "Corrects the calories-to-intensity estimate, which scales with weight."
            ))
        }

        self.rows = rows
    }
}

/// Kilograms or pounds, following the device's own measurement system.
///
/// `Measurement` formatting rather than a hardcoded unit, because the figure is
/// shown to the user as evidence that the app read *their* data, and a US user
/// shown "86 kg" is being shown a number they do not recognise as their weight.
enum MassFormatting {
    static func label(kilograms: Double) -> String {
        let measurement = Measurement(value: kilograms, unit: UnitMass.kilograms)
        return measurement.formatted(
            .measurement(
                width: .abbreviated,
                usage: .personWeight,
                numberFormatStyle: .number.precision(.fractionLength(0))
            )
        )
    }
}
