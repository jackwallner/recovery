import Foundation

/// The countdown timeline, shared by the Watch complication and the iOS widget.
///
/// This is the genuinely new piece. Every other complication in this fleet
/// renders a cumulative daily number that only ever grows, and a single entry
/// with an hourly refresh is enough. A countdown decays toward a fixed future
/// timestamp, so the provider has to pre-compute the whole descent: an entry per
/// hour down to `readyAt`, a tighter cadence in the last two hours where the
/// "Ready soon" state matters, an entry exactly at `readyAt`, and one after it
/// so the face flips to Ready even if the system never gets round to refreshing.
///
/// WidgetKit budgets refreshes, so the timeline must remain correct without any:
/// each entry carries the instant it represents and the view renders from that,
/// never from `Date.now`.
public enum CountdownTimeline {

    /// Widest timeline we will build. Beyond this WidgetKit will have refreshed
    /// several times over anyway, and a 72-hour countdown at hourly granularity
    /// is already 70-odd entries.
    public static let maximumEntries = 80
    private static let reservedFinalEntries = 2

    /// Instants the timeline should carry for a given snapshot.
    ///
    /// - Parameters:
    ///   - snapshot: the cached estimate.
    ///   - now: the moment the timeline is being built.
    public static func entryDates(for snapshot: RecoverySnapshot, now: Date) -> [Date] {
        guard let readyAt = snapshot.readyAt, readyAt > now else {
            // Nothing running: one entry now, and the caller sets a far-out
            // refresh policy. The phone reloads timelines on every new estimate,
            // so an idle face does not need to poll.
            return [now]
        }

        var dates: [Date] = [now]
        let remaining = readyAt.timeIntervalSince(now)

        // Hourly down to the last two hours.
        if remaining > 2 * 3600 {
            var cursor = nextHourBoundary(after: now)
            while cursor < readyAt.addingTimeInterval(-2 * 3600),
                  dates.count < maximumEntries - reservedFinalEntries {
                dates.append(cursor)
                cursor = cursor.addingTimeInterval(3600)
            }
        }

        // Every fifteen minutes through the final two hours, so "1h 20m" and the
        // Ready-soon colour are actually right on the wrist.
        var cursor = max(now, readyAt.addingTimeInterval(-2 * 3600))
        while cursor < readyAt, dates.count < maximumEntries - reservedFinalEntries {
            if cursor > now { dates.append(cursor) }
            cursor = cursor.addingTimeInterval(15 * 60)
        }

        // The flip itself, plus one entry just after so a delayed refresh still
        // lands on Ready rather than on a stale "1m".
        dates.append(readyAt)
        dates.append(readyAt.addingTimeInterval(60))

        return Array(Set(dates)).sorted()
    }

    /// When WidgetKit should come back for a fresh timeline.
    ///
    /// While a countdown is running the last entry already covers it, so the
    /// policy only needs to catch the case where the phone never republishes.
    public static func refreshDate(for snapshot: RecoverySnapshot, now: Date) -> Date {
        guard let readyAt = snapshot.readyAt, readyAt > now else {
            // Idle. Check back in six hours; a new workout reloads us directly.
            return now.addingTimeInterval(6 * 3600)
        }
        // Shortly after the flip, so the Ready state is re-derived against a
        // freshly loaded snapshot rather than the one we cached hours ago.
        return min(readyAt.addingTimeInterval(120), now.addingTimeInterval(4 * 3600))
    }

    /// Next whole hour after `date`, so entries land on times a user recognises
    /// rather than at arbitrary offsets from when the timeline happened to build.
    ///
    /// Built by truncating to the current hour and adding one, not with
    /// `date(bySetting:)` — that searches *forward* for the next matching
    /// component, which from 09:40 lands on 11:00 and leaves an 80-minute hole
    /// the countdown would visibly jump across.
    static func nextHourBoundary(after date: Date, calendar: Calendar = .current) -> Date {
        let components = calendar.dateComponents([.year, .month, .day, .hour], from: date)
        guard let hourStart = calendar.date(from: components),
              let next = calendar.date(byAdding: .hour, value: 1, to: hourStart)
        else { return date.addingTimeInterval(3600) }
        return next
    }
}
