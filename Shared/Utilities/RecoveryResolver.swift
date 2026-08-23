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

    /// A session older than this tells the user nothing useful about today.
    public static let stalenessCutoff: TimeInterval = 4 * 86_400

    /// Phase for a whole set of estimates.
    public static func phase(in estimates: [RecoveryEstimate], now: Date = .now) -> RecoveryPhase {
        guard let current = current(in: estimates, now: now) else { return .noRecentWorkout }
        // Past the cutoff it reads as "no recent workout" rather than a stale Ready.
        if now.timeIntervalSince(current.sessionEnd) > stalenessCutoff { return .noRecentWorkout }
        return current.phase(at: now)
    }

    /// The estimate a screen is allowed to *explain*: its window, confidence,
    /// reasons, and the session that set it.
    ///
    /// `current` deliberately keeps returning a stale estimate so history and
    /// the snapshot have something to carry. A screen that shows the phase must
    /// not also narrate it: past the cutoff the hero says there is no recent
    /// workout, and a window plus reasons beside it hands the user two
    /// different answers to the same question.
    public static func explanation(in estimates: [RecoveryEstimate], now: Date = .now) -> RecoveryEstimate? {
        guard phase(in: estimates, now: now) != .noRecentWorkout else { return nil }
        return current(in: estimates, now: now)
    }

    /// Estimates whose countdown has expired since they were last acknowledged.
    /// These are the ones eligible for the one-tap readiness question.
    ///
    /// - Parameter eligibleFrom: the earliest `readyAt` worth asking about — in
    ///   practice the moment setup finished. Onboarding imports a hundred and
    ///   twenty days of history at once, so every countdown in it has already
    ///   expired by the time the user reaches Today, and without this bound the
    ///   first thing a new user was asked is how a session they did before
    ///   installing the app felt when a countdown they never saw ran out. Nil
    ///   means unbounded, which is the behaviour every test written before this
    ///   existed assumes.
    public static func awaitingFeedback(
        in estimates: [RecoveryEstimate],
        answered: Set<String>,
        eligibleFrom: Date? = nil,
        now: Date = .now
    ) -> RecoveryEstimate? {
        estimates
            .filter { $0.producesCountdown && $0.readyAt <= now && !answered.contains($0.sessionID) }
            // Only ask about something recent enough to remember.
            .filter { now.timeIntervalSince($0.readyAt) < 2 * 86_400 }
            .filter { estimate in
                guard let eligibleFrom else { return true }
                return estimate.readyAt >= eligibleFrom
            }
            .max { $0.readyAt < $1.readyAt }
    }
}
