import Foundation

/// Every string that renders a recovery countdown, in one place.
///
/// Garmin's surface is hours, so the hero is hours: `18h`, dropping to
/// `1h 20m` and then `18m` as it runs out. Complications get shorter variants
/// because an inline slot is a handful of characters wide.
///
/// Compliance note: nothing in here may say "recovered", "safe to train",
/// "injury", or "your body". The output is a cardiovascular training estimate.
public enum CountdownFormat {

    // MARK: - Durations

    /// Full countdown: `2d 4h`, `18h 40m`, `1h 20m`, `18m`, `Ready`.
    public static func remaining(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Ready" }
        let totalMinutes = Int((seconds / 60).rounded(.up))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return hours > 0 ? "\(days)d \(hours)h" : "\(days)d" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    /// Complication-width countdown: `2d`, `18h`, `1h 20m`, `18m`.
    /// Whole hours drop the minutes so a circular slot never truncates.
    public static func compactRemaining(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return "Ready" }
        let totalMinutes = Int((seconds / 60).rounded(.up))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return "\(days)d" }
        if hours >= 2 { return "\(hours)h" }
        if hours > 0 { return minutes > 0 ? "\(hours)h \(minutes)m" : "\(hours)h" }
        return "\(minutes)m"
    }

    /// Hours-only, the way Garmin prints it at the end of an activity: `32h`.
    public static func hours(_ hours: Double) -> String {
        guard hours > 0 else { return "0h" }
        return "\(Int(hours.rounded()))h"
    }

    /// The bounded window, e.g. `18 to 28h`. Collapses to a single figure when
    /// rounding makes the two ends equal.
    public static func window(low: Double, high: Double) -> String {
        let lowRounded = Int(low.rounded())
        let highRounded = Int(high.rounded())
        if lowRounded == highRounded { return "\(highRounded)h" }
        return "\(lowRounded) to \(highRounded)h"
    }

    // MARK: - Ready time

    /// `today at 7:30 PM`, `tomorrow at 7:30 AM`, `Thu at 7:30 AM`.
    public static func readyAt(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = timeFormatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return "today at \(time)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow at \(time)"
        }
        return "\(weekdayFormatter.string(from: date)) at \(time)"
    }

    /// Complication-width ready time: `7:30 AM`.
    public static func clock(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Coarse ready time for low-confidence estimates, where a minute-precise
    /// clock reading would overstate what the model knows.
    public static func readySoftly(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let partOfDay: String
        switch hour {
        case 0..<5: partOfDay = "overnight"
        case 5..<12: partOfDay = "morning"
        case 12..<17: partOfDay = "afternoon"
        case 17..<21: partOfDay = "evening"
        default: partOfDay = "late evening"
        }
        if calendar.isDate(date, inSameDayAs: now) { return "this \(partOfDay)" }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return "tomorrow \(partOfDay)"
        }
        return "\(weekdayFormatter.string(from: date)) \(partOfDay)"
    }

    // MARK: - Phase copy

    /// The one line under the countdown. Never a claim about the body.
    public static func phaseHeadline(_ phase: RecoveryPhase) -> String {
        switch phase {
        case .noRecentWorkout: "No recent workout"
        case .ready: "Ready"
        case .readySoon: "Ready soon"
        case .recovering: "Recovering"
        }
    }

    public static func phaseDetail(_ phase: RecoveryPhase) -> String {
        switch phase {
        case .noRecentWorkout:
            "Finish a workout and Recharge will estimate your next hard session."
        case .ready:
            "Ready for another hard session based on your recent workout load estimate."
        case .readySoon:
            "Less than two hours left on your current estimate."
        case .recovering:
            "Time left before another hard session is likely to be reasonable."
        }
    }

    // MARK: - Formatters

    private static let timeFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.dateStyle = .none
        formatter.timeStyle = .short
        return formatter
    }()

    private static let weekdayFormatter: DateFormatter = {
        let formatter = DateFormatter()
        formatter.setLocalizedDateFormatFromTemplate("EEE")
        return formatter
    }()
}
