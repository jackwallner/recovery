import SwiftUI

/// One palette across iPhone, Watch, and both widget extensions.
///
/// The colour carries the state: amber while a countdown is running, green at
/// Ready. That pairing is the whole visual language of the app, so it is defined
/// once here and never re-derived at a call site.
public enum Theme {
    // MARK: - Adaptive surfaces

    #if os(watchOS)
    public static let background = Color.black
    public static let cardSurface = Color(white: 0.12)
    public static let cardSurfaceLight = Color(white: 0.18)
    public static let ringTrack = Color(white: 0.2)
    public static let textPrimary = Color.white
    public static let textSecondary = Color(white: 0.7)
    public static let textTertiary = Color(white: 0.5)
    #else
    public static let background = Color(.systemBackground)
    public static let cardSurface = Color(.secondarySystemBackground)
    public static let cardSurfaceLight = Color(.tertiarySystemBackground)
    public static let ringTrack = Color(.systemFill)
    public static let textPrimary = Color(.label)
    public static let textSecondary = Color(.secondaryLabel)
    public static let textTertiary = Color(.tertiaryLabel)
    #endif

    // MARK: - State palette

    /// Recovering. Warm amber: something is still running down.
    public static let recovering = Color(red: 1.0, green: 0.62, blue: 0.20)
    public static let recoveringSecondary = Color(red: 1.0, green: 0.45, blue: 0.28)

    /// Ready soon. Between the two, so the transition reads as progress.
    public static let readySoon = Color(red: 0.78, green: 0.76, blue: 0.24)

    /// Ready. The payoff colour.
    public static let ready = Color(red: 0.24, green: 0.78, blue: 0.44)
    public static let readySecondary = Color(red: 0.16, green: 0.70, blue: 0.58)

    /// Nothing to score yet.
    public static let idle = Color(red: 0.48, green: 0.52, blue: 0.60)

    /// Pro accent, used only on paywall and locked surfaces.
    public static let pro = Color(red: 0.36, green: 0.44, blue: 0.92)

    public static func color(for phase: RecoveryPhase) -> Color {
        switch phase {
        case .recovering: recovering
        case .readySoon: readySoon
        case .ready: ready
        case .noRecentWorkout: idle
        }
    }

    public static func gradient(for phase: RecoveryPhase) -> LinearGradient {
        let colors: [Color]
        switch phase {
        case .recovering: colors = [recovering, recoveringSecondary]
        case .readySoon: colors = [readySoon, recovering]
        case .ready: colors = [ready, readySecondary]
        case .noRecentWorkout: colors = [idle, idle.opacity(0.6)]
        }
        return LinearGradient(colors: colors, startPoint: .topLeading, endPoint: .bottomTrailing)
    }

    /// SF Symbol for a phase. Kept beside the colours so a state can never be
    /// drawn with a mismatched glyph.
    public static func symbol(for phase: RecoveryPhase) -> String {
        switch phase {
        case .recovering: "hourglass"
        case .readySoon: "hourglass.bottomhalf.filled"
        case .ready: "checkmark.circle.fill"
        case .noRecentWorkout: "figure.run.circle"
        }
    }

    public static func symbol(for profile: WorkoutProfile) -> String {
        switch profile {
        case .endurance: "figure.run"
        case .strength: "dumbbell.fill"
        case .mixed: "figure.highintensity.intervaltraining"
        case .easy: "figure.walk"
        }
    }

    /// Prefers the activity over the profile where one is recognisable — a ride
    /// showing a running figure is the kind of small wrongness this audience
    /// notices immediately. Falls back to the profile symbol.
    public static func symbol(forActivityLabel label: String, profile: WorkoutProfile) -> String {
        switch label {
        case "ride": "figure.outdoor.cycle"
        case "swim": "figure.pool.swim"
        case "row": "figure.rower"
        case "walk": "figure.walk"
        case "hike": "figure.hiking"
        case "run": "figure.run"
        case "yoga session": "figure.yoga"
        case "elliptical session": "figure.elliptical"
        case "stair session": "figure.stair.stepper"
        case "climb": "figure.climbing"
        case "lifting session": "dumbbell.fill"
        case "core session": "figure.core.training"
        default: symbol(for: profile)
        }
    }

    // MARK: - Constants

    public static let cardRadius: CGFloat = 20
    public static let cardPadding: CGFloat = 20

    // MARK: - Typography

    public static func bigNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}
