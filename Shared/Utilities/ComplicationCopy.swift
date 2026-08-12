import Foundation

/// Every string a complication renders, for all four families and all three
/// styles.
///
/// Lives in `Shared` rather than beside the widget bundle so the test target can
/// compile it. That is not a tidiness argument: the complication is the
/// glanciest surface in the app and the one with the least room for a
/// qualifier, so it is exactly where a medical claim would do the most damage
/// and, until this moved, the only place `testNoPhaseCopyMakesAMedicalClaim`
/// could not reach.
///
/// Pure and parameter-driven, taking the phase and the two numbers a countdown
/// needs rather than a `TimelineEntry`, because `TimelineEntry` drags WidgetKit
/// in and the copy does not need it.
public enum ComplicationCopy {

    /// The big value in the middle of a circular or corner slot.
    public static func primary(
        phase: RecoveryPhase,
        style: ComplicationStyle,
        remaining: TimeInterval,
        readyAt: Date?
    ) -> String {
        switch phase {
        case .noRecentWorkout:
            return "--"
        case .ready:
            return style == .state ? "READY" : "Ready"
        case .readySoon, .recovering:
            switch style {
            case .countdown:
                return CountdownFormat.compactRemaining(remaining)
            case .readyClock:
                return readyAt.map(CountdownFormat.clock) ?? "--"
            case .state:
                return phase == .readySoon ? "SOON" : "REC"
            }
        }
    }

    /// The line under it on rectangular, and the widget label on corner/inline.
    public static func secondary(
        phase: RecoveryPhase,
        style: ComplicationStyle,
        remaining: TimeInterval,
        readyAt: Date?,
        activityLabel: String
    ) -> String {
        switch phase {
        case .noRecentWorkout:
            return "No workout"
        case .ready:
            // Not "Ready to train": on a glance surface with no room for the
            // qualifier, that reads as clearance to train rather than as an
            // estimate about training load, which is the only thing the model
            // knows. Every other surface says "hard session"; so does this one.
            return activityLabel.isEmpty
                ? "Ready for a hard session"
                : "After your \(activityLabel)"
        case .readySoon, .recovering:
            switch style {
            case .countdown:
                return readyAt.map { "Ready \(CountdownFormat.clock($0))" } ?? "Recovering"
            case .readyClock:
                return CountdownFormat.compactRemaining(remaining) + " left"
            case .state:
                return CountdownFormat.compactRemaining(remaining) + " left"
            }
        }
    }

    /// Inline slots are a handful of characters wide and get no ring, so they
    /// carry the shortest complete sentence available.
    public static func inline(
        phase: RecoveryPhase,
        style: ComplicationStyle,
        remaining: TimeInterval,
        readyAt: Date?
    ) -> String {
        switch phase {
        case .noRecentWorkout: "No workout"
        // The inline slot has room for one word, and "Ready" is the token every
        // other surface already uses for an expired estimate.
        case .ready: "Ready"
        case .readySoon, .recovering:
            switch style {
            case .countdown: "\(CountdownFormat.compactRemaining(remaining)) to ready"
            case .readyClock: readyAt.map { "Ready \(CountdownFormat.clock($0))" } ?? "Recovering"
            case .state: phase == .readySoon ? "Ready soon" : "Recovering"
            }
        }
    }

    public static func rectangularTitle(
        phase: RecoveryPhase,
        style: ComplicationStyle,
        remaining: TimeInterval,
        readyAt: Date?
    ) -> String {
        switch phase {
        case .noRecentWorkout: "Recharge"
        case .ready: "Ready"
        case .readySoon, .recovering:
            switch style {
            case .countdown: "Recover \(CountdownFormat.compactRemaining(remaining))"
            case .readyClock: readyAt.map { "Ready \(CountdownFormat.clock($0))" } ?? "Recovering"
            case .state: phase == .readySoon ? "READY SOON" : "RECOVERING"
            }
        }
    }
}
