import Foundation

/// Exactly what Recharge read out of Apple Health, in the user's words.
///
/// The app asks for twelve types in one permission sheet, which is a lot to
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

    /// The whole receipt as one sentence, for a surface with room for a line
    /// rather than a table.
    ///
    /// The purchase page is the only caller and the reason is layout: the
    /// itemised list is nine rows, five of them fitted only by truncating the
    /// list and adding an "…and 4 more" footnote, and the whole block sat
    /// between the two numbers being compared and the price. The full receipt is
    /// two pages earlier in onboarding, on the readout, and in Settings and the
    /// Recharge+ tab afterwards; here it only has to establish that the figure
    /// above came from the user's own data.
    ///
    /// Nil when nothing was read, for the same reason a row with no value is
    /// never drawn: a receipt for nothing argues against the thing it is on.
    public private(set) var oneLineReceipt: String?

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

    /// The receipt as one concrete sentence: what was counted, then how many
    /// other signals were found. Concrete on purpose — "9 readings" is a claim
    /// and "214 workouts over 120 days" is evidence.
    static func receiptLine(readings: Readings, rowCount: Int) -> String? {
        guard rowCount > 0 else { return nil }
        guard readings.workoutCount > 0 else {
            return String(localized: "Read from Apple Health: \(rowCount) readings.", bundle: .recharge)
        }
        let workouts = readings.workoutCount
        let days = readings.daysCovered
        let others = rowCount - 1
        switch (days > 0, others > 0) {
        case (false, false):
            return String(localized: "Read from Apple Health: \(workouts) workouts.", bundle: .recharge)
        case (true, false):
            return String(localized: "Read from Apple Health: \(workouts) workouts over \(days) days.", bundle: .recharge)
        case (false, true):
            return String(localized: "Read from Apple Health: \(workouts) workouts, plus \(others) other signals.", bundle: .recharge)
        case (true, true):
            return String(localized: "Read from Apple Health: \(workouts) workouts over \(days) days, plus \(others) other signals.", bundle: .recharge)
        }
    }

    // MARK: - Building

    public init(readings: Readings, usesObservedMaxHeartRate: Bool) {
        var rows: [Row] = []

        if readings.workoutCount > 0 {
            let types = readings.activityTypes
            let detail = types > 1
                ? String(localized: "Across \(types) activity types, over the last \(readings.daysCovered) days.", bundle: .recharge)
                : String(localized: "Over the last \(readings.daysCovered) days.", bundle: .recharge)
            rows.append(Row(
                id: "workouts",
                symbol: "figure.run",
                value: "\(readings.workoutCount)",
                title: String(localized: "Workouts scored", bundle: .recharge),
                detail: detail
            ))
        }

        if let max = readings.observedMaxHeartRate {
            rows.append(Row(
                id: "maxHeartRate",
                symbol: "heart.fill",
                value: String(localized: "\(Int(max.rounded())) bpm", bundle: .recharge),
                title: usesObservedMaxHeartRate ? String(localized: "Your highest heart rate", bundle: .recharge) : String(localized: "Heart-rate ceiling", bundle: .recharge),
                // The distinction matters enough to spend a line on. A measured
                // ceiling is the difference between scoring somebody's intensity
                // and guessing at it, and a user who has never gone truly
                // maximal is being scored against a formula whatever this
                // number says.
                detail: usesObservedMaxHeartRate
                    ? String(localized: "Measured from \(readings.sessionsWithHeartRate) sessions. Every intensity reading is scored against it.", bundle: .recharge)
                    : String(localized: "Seen in your sessions, below what your age predicts, so the higher figure is used.", bundle: .recharge)
            ))
        } else if let age = readings.age {
            rows.append(Row(
                id: "age",
                symbol: "heart.fill",
                value: "\(age)",
                title: String(localized: "Age, from your Health profile", bundle: .recharge),
                detail: String(localized: "Sets the heart-rate ceiling until your workouts show a higher one.", bundle: .recharge)
            ))
        }

        if let vo2 = readings.vo2Max {
            rows.append(Row(
                id: "vo2Max",
                symbol: "lungs.fill",
                value: vo2.formatted(.number.precision(.fractionLength(0))),
                title: String(localized: "Cardio fitness (VO₂ max)", bundle: .recharge),
                detail: String(localized: "Sets the training level your sessions are compared against.", bundle: .recharge)
            ))
        }

        if let resting = readings.restingHeartRate {
            rows.append(Row(
                id: "restingHeartRate",
                symbol: "bed.double.fill",
                value: String(localized: "\(Int(resting.rounded())) bpm", bundle: .recharge),
                title: String(localized: "Resting heart rate", bundle: .recharge),
                detail: String(localized: "Watched night to night for signs the last session is still with you.", bundle: .recharge)
            ))
        }

        if let hrv = readings.heartRateVariability {
            rows.append(Row(
                id: "hrv",
                symbol: "waveform.path.ecg",
                value: String(localized: "\(Int(hrv.rounded())) ms", bundle: .recharge),
                title: String(localized: "Heart rate variability", bundle: .recharge),
                detail: String(localized: "The same, from the other direction.", bundle: .recharge)
            ))
        }

        if let recovery = readings.heartRateRecovery {
            rows.append(Row(
                id: "heartRateRecovery",
                symbol: "arrow.down.heart.fill",
                value: String(localized: "−\(Int(recovery.rounded())) bpm", bundle: .recharge),
                title: String(localized: "One-minute recovery", bundle: .recharge),
                detail: String(localized: "How far your heart rate falls in the minute after a session ends.", bundle: .recharge)
            ))
        }

        if let sleep = readings.averageSleepHours {
            rows.append(Row(
                id: "sleep",
                symbol: "moon.stars.fill",
                value: String(localized: "\(sleep.formatted(.number.precision(.fractionLength(1))))h", bundle: .recharge),
                title: String(localized: "Average sleep", bundle: .recharge),
                detail: String(localized: "A short night lengthens the estimate a little; a long one shortens it.", bundle: .recharge)
            ))
        }

        if let rate = readings.respiratoryRate {
            rows.append(Row(
                id: "respiratoryRate",
                symbol: "wind",
                value: String(localized: "\(rate.formatted(.number.precision(.fractionLength(0))))/min", bundle: .recharge),
                title: String(localized: "Overnight breathing rate", bundle: .recharge),
                detail: String(localized: "Adds another overnight signal to the estimate alongside sleep, HRV, and resting heart rate.", bundle: .recharge)
            ))
        }

        if let mass = readings.bodyMassKilograms {
            rows.append(Row(
                id: "bodyMass",
                symbol: "scalemass.fill",
                value: MassFormatting.label(kilograms: mass),
                title: String(localized: "Body weight", bundle: .recharge),
                detail: String(localized: "Corrects the calories-to-intensity estimate, which scales with weight.", bundle: .recharge)
            ))
        }

        self.rows = rows
        self.oneLineReceipt = Self.receiptLine(readings: readings, rowCount: rows.count)
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
