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
        guard seconds > 0 else { return String(localized: "Ready", bundle: .recharge) }
        let totalMinutes = Int((seconds / 60).rounded(.up))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return hours > 0 ? daysAndHours(days, hours) : daysOnly(days) }
        if hours > 0 { return minutes > 0 ? hoursAndMinutes(hours, minutes) : hoursOnly(hours) }
        return minutesOnly(minutes)
    }

    // The five shapes a countdown takes. Each is a whole key so a language can
    // choose its own unit letters and spacing; the compact complication format
    // depends on them staying this short.
    private static func daysAndHours(_ days: Int, _ hours: Int) -> String {
        String(localized: "\(days)d \(hours)h", bundle: .recharge)
    }

    private static func daysOnly(_ days: Int) -> String {
        String(localized: "\(days)d", bundle: .recharge)
    }

    private static func hoursAndMinutes(_ hours: Int, _ minutes: Int) -> String {
        String(localized: "\(hours)h \(minutes)m", bundle: .recharge)
    }

    private static func hoursOnly(_ hours: Int) -> String {
        String(localized: "\(hours)h", bundle: .recharge)
    }

    private static func minutesOnly(_ minutes: Int) -> String {
        String(localized: "\(minutes)m", bundle: .recharge)
    }

    /// Complication-width countdown: `2d 23h`, `18h`, `1h 20m`, `18m`.
    ///
    /// The unit steps down as the window runs out — days and hours, then hours,
    /// then hours and minutes, then minutes — and the rule that decides where to
    /// stop is **the string has to change at least once an hour, everywhere**. A
    /// complication whose value has not moved since yesterday morning is
    /// indistinguishable from one that is broken.
    ///
    /// The previous version returned a bare `"\(days)d"` above 24 hours, which is
    /// where the app's own maximum window lives: a 72-hour countdown read `3d`
    /// for a full day, then `2d` for a full day, then `1d` for a full day.
    /// Two-thirds of the longest estimate Recharge can produce rendered as a
    /// figure that never ticked, on the one surface whose whole job is to tick,
    /// while the timeline dutifully built seventy hourly entries that all carried
    /// the same three characters.
    ///
    /// Never longer than six characters, so a circular or corner slot does not
    /// truncate. `3d 23h` is the widest it gets, and only above 72 hours.
    public static func compactRemaining(_ seconds: TimeInterval) -> String {
        guard seconds > 0 else { return String(localized: "Ready", bundle: .recharge) }
        let totalMinutes = Int((seconds / 60).rounded(.up))
        let days = totalMinutes / 1440
        let hours = (totalMinutes % 1440) / 60
        let minutes = totalMinutes % 60

        if days > 0 { return hours > 0 ? daysAndHours(days, hours) : daysOnly(days) }
        if hours >= 2 { return hoursOnly(hours) }
        if hours > 0 { return minutes > 0 ? hoursAndMinutes(hours, minutes) : hoursOnly(hours) }
        return minutesOnly(minutes)
    }

    /// Hours-only, the way Garmin prints it at the end of an activity: `32h`.
    public static func hours(_ hours: Double) -> String {
        guard hours > 0 else { return hoursOnly(0) }
        return hoursOnly(Int(hours.rounded()))
    }

    /// Why a stacked countdown is longer than the session on screen.
    ///
    /// Recovery time is cumulative, so a session done inside a running
    /// countdown produces a number the session alone does not explain. Saying
    /// the two parts out loud is the difference between a model the user can
    /// follow and one that looks broken.
    ///
    /// Deliberately arithmetic and deliberately not a claim about the body: it
    /// names two figures the app has already shown and adds them.
    public static func stackedNote(sessionHours: Double, carriedHours: Double) -> String {
        String(localized: "\(hours(sessionHours)) for this session, on top of \(hours(carriedHours)) still to go", bundle: .recharge)
    }

    /// The bounded window, e.g. `18 to 28h`. Collapses to a single figure when
    /// rounding makes the two ends equal.
    public static func window(low: Double, high: Double) -> String {
        let lowRounded = Int(low.rounded())
        let highRounded = Int(high.rounded())
        if lowRounded == highRounded { return hoursOnly(highRounded) }
        return String(localized: "\(lowRounded) to \(highRounded)h", bundle: .recharge)
    }

    /// How long ago something happened: `just now`, `4m ago`, `2h 10m ago`.
    /// Anything past a day stops counting hours, because "27h ago" is a figure
    /// nobody reads as yesterday.
    public static func elapsed(since date: Date, now: Date = .now) -> String {
        let seconds = now.timeIntervalSince(date)
        guard seconds >= 60 else { return String(localized: "just now", bundle: .recharge) }
        if seconds >= 86_400 {
            let days = Int(seconds / 86_400)
            return days == 1 ? String(localized: "yesterday", bundle: .recharge) : String(localized: "\(days)d ago", bundle: .recharge)
        }
        return String(localized: "\(remaining(seconds)) ago", bundle: .recharge)
    }

    // MARK: - Ready time

    /// `today at 7:30 PM`, `tomorrow at 7:30 AM`, `Thu at 7:30 AM`.
    public static func readyAt(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let time = timeFormatter.string(from: date)
        if calendar.isDate(date, inSameDayAs: now) { return String(localized: "today at \(time)", bundle: .recharge) }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return String(localized: "tomorrow at \(time)", bundle: .recharge)
        }
        let weekday = weekdayFormatter.string(from: date)
        return String(localized: "\(weekday) at \(time)", bundle: .recharge)
    }

    /// Complication-width ready time: `7:30 AM`.
    public static func clock(_ date: Date) -> String {
        timeFormatter.string(from: date)
    }

    /// Ready time with the weekday once it is not today: `7:30 AM`, then
    /// `Thu 7:30 AM`.
    ///
    /// A countdown can run four days, and a bare clock reading on Monday
    /// evening that means Thursday morning reads as tomorrow morning. Used on
    /// the complication surfaces wide enough to carry the day; the circular
    /// slot keeps the bare clock and leaves the day to the countdown beside it.
    ///
    /// - Parameter now: the instant being rendered, which on a complication is
    ///   the timeline entry's date, never the wall clock.
    public static func clockWithDay(_ date: Date, now: Date, calendar: Calendar = .current) -> String {
        if calendar.isDate(date, inSameDayAs: now) { return clock(date) }
        let weekday = weekdayFormatter.string(from: date)
        return String(localized: "\(weekday) \(clock(date))", bundle: .recharge)
    }

    /// Coarse ready time for low-confidence estimates, where a minute-precise
    /// clock reading would overstate what the model knows.
    public static func readySoftly(_ date: Date, now: Date = .now, calendar: Calendar = .current) -> String {
        let hour = calendar.component(.hour, from: date)
        let partOfDay: PartOfDay
        switch hour {
        case 0..<5: partOfDay = .overnight
        case 5..<12: partOfDay = .morning
        case 12..<17: partOfDay = .afternoon
        case 17..<21: partOfDay = .evening
        default: partOfDay = .lateEvening
        }
        if calendar.isDate(date, inSameDayAs: now) { return partOfDay.today }
        if let tomorrow = calendar.date(byAdding: .day, value: 1, to: now),
           calendar.isDate(date, inSameDayAs: tomorrow) {
            return partOfDay.tomorrow
        }
        return partOfDay.onWeekday(weekdayFormatter.string(from: date))
    }

    /// The coarse ready time, one whole phrase per day and part of the day.
    private enum PartOfDay {
        case overnight, morning, afternoon, evening, lateEvening

        var today: String {
            switch self {
            case .overnight: String(localized: "this overnight", bundle: .recharge)
            case .morning: String(localized: "this morning", bundle: .recharge)
            case .afternoon: String(localized: "this afternoon", bundle: .recharge)
            case .evening: String(localized: "this evening", bundle: .recharge)
            case .lateEvening: String(localized: "this late evening", bundle: .recharge)
            }
        }

        var tomorrow: String {
            switch self {
            case .overnight: String(localized: "tomorrow overnight", bundle: .recharge)
            case .morning: String(localized: "tomorrow morning", bundle: .recharge)
            case .afternoon: String(localized: "tomorrow afternoon", bundle: .recharge)
            case .evening: String(localized: "tomorrow evening", bundle: .recharge)
            case .lateEvening: String(localized: "tomorrow late evening", bundle: .recharge)
            }
        }

        func onWeekday(_ weekday: String) -> String {
            switch self {
            case .overnight: String(localized: "\(weekday) overnight", bundle: .recharge)
            case .morning: String(localized: "\(weekday) morning", bundle: .recharge)
            case .afternoon: String(localized: "\(weekday) afternoon", bundle: .recharge)
            case .evening: String(localized: "\(weekday) evening", bundle: .recharge)
            case .lateEvening: String(localized: "\(weekday) late evening", bundle: .recharge)
            }
        }
    }

    // MARK: - Phase copy

    /// The one line under the countdown. Never a claim about the body.
    public static func phaseHeadline(_ phase: RecoveryPhase) -> String {
        switch phase {
        case .noRecentWorkout: String(localized: "No recent workout", bundle: .recharge)
        case .ready: String(localized: "Ready", bundle: .recharge)
        case .readySoon: String(localized: "Ready soon", bundle: .recharge)
        case .recovering: String(localized: "Recovering", bundle: .recharge)
        }
    }

    public static func phaseDetail(_ phase: RecoveryPhase) -> String {
        switch phase {
        case .noRecentWorkout:
            String(localized: "Finish a workout and Recharge will estimate a training-load window.", bundle: .recharge)
        case .ready:
            String(localized: "Recovery estimate complete. No countdown is active.", bundle: .recharge)
        case .readySoon:
            String(localized: "Less than two hours left on your current estimate.", bundle: .recharge)
        case .recovering:
            String(localized: "Time left on the current training-load estimate.", bundle: .recharge)
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
