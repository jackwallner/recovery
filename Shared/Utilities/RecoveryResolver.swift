import Foundation

/// Resolves several overlapping estimates into the one the countdown shows.
///
/// Two sessions on the same day, from different profiles, can each carry their
/// own window. The rule from `positioning.md` is the simplest defensible one:
/// show the **latest** `readyAt`, and name the session that set it.
public enum RecoveryResolver {

    /// The estimate the countdown should display, or `nil` when nothing is
    /// active.
    ///
    /// Estimates that produce no countdown (easy sessions, anything under the
    /// quiet threshold) are ignored entirely, which is what guarantees an
    /// active-recovery walk can never shorten a window that is already running.
    public static func active(in estimates: [RecoveryEstimate], now: Date = .now) -> RecoveryEstimate? {
        estimates
            .filter { $0.producesCountdown && $0.readyAt > now }
            .max { $0.readyAt < $1.readyAt }
    }

    /// The estimate to render, active or not: falls back to the most recently
    /// calculated one so an expired countdown still explains what it was.
    public static func current(in estimates: [RecoveryEstimate], now: Date = .now) -> RecoveryEstimate? {
        if let active = active(in: estimates, now: now) { return active }
        return estimates.max { $0.sessionEnd < $1.sessionEnd }
    }

    /// Phase for a whole set of estimates.
    public static func phase(in estimates: [RecoveryEstimate], now: Date = .now) -> RecoveryPhase {
        guard let current = current(in: estimates, now: now) else { return .noRecentWorkout }
        // A session older than four days tells the user nothing useful about
        // today, so it reads as "no recent workout" rather than a stale Ready.
        if now.timeIntervalSince(current.sessionEnd) > 4 * 86_400 { return .noRecentWorkout }
        return current.phase(at: now)
    }

    /// Estimates whose countdown has expired since they were last acknowledged.
    /// These are the ones eligible for the one-tap readiness question.
    public static func awaitingFeedback(
        in estimates: [RecoveryEstimate],
        answered: Set<String>,
        now: Date = .now
    ) -> RecoveryEstimate? {
        estimates
            .filter { $0.producesCountdown && $0.readyAt <= now && !answered.contains($0.sessionID) }
            // Only ask about something recent enough to remember.
            .filter { now.timeIntervalSince($0.readyAt) < 2 * 86_400 }
            .max { $0.readyAt < $1.readyAt }
    }
}
