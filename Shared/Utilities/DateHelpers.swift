import Foundation

/// Calendar arithmetic shared across targets. All of it goes through the current
/// calendar so travel across time zones behaves the way the user expects.
public enum DateHelpers {
    public static func startOfDay(_ date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.startOfDay(for: date)
    }

    public static func daysAgo(_ days: Int, from date: Date = .now, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: -days, to: startOfDay(date, calendar: calendar))
            ?? date.addingTimeInterval(-Double(days) * 86_400)
    }

    /// End bound for a HealthKit query that should include all of `date`.
    public static func healthQueryEnd(including date: Date, calendar: Calendar = .current) -> Date {
        calendar.date(byAdding: .day, value: 1, to: startOfDay(date, calendar: calendar))
            ?? date.addingTimeInterval(86_400)
    }

    /// Stable `yyyy-MM-dd` key, computed without a `DateFormatter` so it is
    /// locale-proof and cheap enough to call in a loop.
    public static func dayKey(for date: Date, calendar: Calendar = .current) -> String {
        let parts = calendar.dateComponents([.year, .month, .day], from: date)
        return String(format: "%04d-%02d-%02d", parts.year ?? 0, parts.month ?? 0, parts.day ?? 0)
    }
}

/// The weekly-load figures behind the Recharge+ load view, pure so they can be
/// driven with a fixed clock and calendar.
public enum LoadSeries {
    public typealias Entry = (end: Date, load: Double)

    /// Daily load totals for the last `days` local days, oldest first, today last.
    public static func daily(
        _ entries: [Entry],
        days: Int,
        now: Date,
        calendar: Calendar = .current
    ) -> [(date: Date, load: Double)] {
        var totals: [String: Double] = [:]
        for entry in entries {
            totals[DateHelpers.dayKey(for: entry.end, calendar: calendar), default: 0] += entry.load
        }
        return (0..<days).reversed().compactMap { offset in
            let date = DateHelpers.daysAgo(offset, from: now, calendar: calendar)
            return (date: date, load: totals[DateHelpers.dayKey(for: date, calendar: calendar)] ?? 0)
        }
    }

    /// Acute (7-day) and chronic (28-day, as a weekly average) load.
    public static func balance(_ entries: [Entry], now: Date) -> (acute: Double, chronic: Double) {
        let acuteCutoff = now.addingTimeInterval(-7 * 86_400)
        let chronicCutoff = now.addingTimeInterval(-28 * 86_400)
        let acute = entries.filter { $0.end >= acuteCutoff }.reduce(0) { $0 + $1.load }
        let chronicTotal = entries.filter { $0.end >= chronicCutoff }.reduce(0) { $0 + $1.load }
        return (acute, chronicTotal / 4)
    }
}
