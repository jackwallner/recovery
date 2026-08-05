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
