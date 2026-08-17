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

    /// Whether the extension has ever been handed a model to render.
    ///
    /// This is not the same question as "is there a recent workout", and
    /// collapsing the two is what made a freshly added complication look broken.
    /// The Watch's App Group is a *separate container* from the phone's: the only
    /// thing that ever writes a snapshot into it is `PhoneWatchSession` running
    /// inside the Watch **app**, and a widget extension cannot hold a
    /// `WCSession` of its own. So between installing the app and opening it on
    /// the wrist for the first time, the extension reads `RecoverySnapshot.empty`
    /// and has genuinely never been told anything.
    ///
    /// That state used to render as the `noRecentWorkout` phase, whose primary
    /// string is `"--"`. Someone who adds the complication before opening the
    /// Watch app sees a dash on their face and no way to find out why — it reads
    /// as null, because it is. It gets its own copy now, and the copy is an
    /// instruction.
    public enum DataState: Sendable, CaseIterable {
        /// A snapshot has arrived from the phone at some point.
        case synced
        /// Nothing has ever been received. Distinct from "no workout".
        case neverSynced
    }

    /// The big value in the middle of a circular or corner slot.
    public static func primary(
        phase: RecoveryPhase,
        style: ComplicationStyle,
        remaining: TimeInterval,
        readyAt: Date?,
        dataState: DataState = .synced
    ) -> String {
        guard dataState == .synced else { return "Open" }
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
        activityLabel: String,
        dataState: DataState = .synced
    ) -> String {
        // Deliberately device-neutral: the extension and the app that has to be
        // opened always live on the same device, whether that is the wrist or
        // the phone, so naming one would be wrong on the other.
        guard dataState == .synced else { return "Open Recharge to set up" }
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
        readyAt: Date?,
        dataState: DataState = .synced
    ) -> String {
        guard dataState == .synced else { return "Open Recharge" }
        switch phase {
        case .noRecentWorkout: return "No workout"
        // The inline slot has room for one word, and "Ready" is the token every
        // other surface already uses for an expired estimate.
        case .ready: return "Ready"
        case .readySoon, .recovering:
            switch style {
            case .countdown: return "\(CountdownFormat.compactRemaining(remaining)) to ready"
            case .readyClock: return readyAt.map { "Ready \(CountdownFormat.clock($0))" } ?? "Recovering"
            case .state: return phase == .readySoon ? "Ready soon" : "Recovering"
            }
        }
    }

    public static func rectangularTitle(
        phase: RecoveryPhase,
        style: ComplicationStyle,
        remaining: TimeInterval,
        readyAt: Date?,
        dataState: DataState = .synced
    ) -> String {
        guard dataState == .synced else { return "Recharge" }
        switch phase {
        case .noRecentWorkout: return "Recharge"
        case .ready: return "Ready"
        case .readySoon, .recovering:
            switch style {
            case .countdown: return "Recover \(CountdownFormat.compactRemaining(remaining))"
            case .readyClock: return readyAt.map { "Ready \(CountdownFormat.clock($0))" } ?? "Recovering"
            case .state: return phase == .readySoon ? "READY SOON" : "RECOVERING"
            }
        }
    }
}
