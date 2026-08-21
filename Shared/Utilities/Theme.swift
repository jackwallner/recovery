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

    /// The inset a card puts around its own content. Radius, spacing and every
    /// other geometry constant live in the token layer at the bottom of this
    /// file.
    public static let cardPadding: CGFloat = Space.lg

    /// Apple's minimum comfortable touch target. A control smaller than this
    /// does not read as small, it reads as unreliable: the taps that miss get
    /// blamed on the app being buggy rather than on the target being 37pt.
    public static let minimumTapTarget: CGFloat = 44

    // MARK: - Typography

    public static func bigNumber(_ size: CGFloat) -> Font {
        .system(size: size, weight: .bold, design: .rounded)
    }
}

// MARK: - The token layer

/// Spacing, radius, stroke and elevation as named constants.
///
/// The reason these exist is drift. Every number below was already in the app,
/// typed at a call site: seventeen radii across four values, and paddings at 3,
/// 7, 10, 14, 15, 18 and 22 that no rule produced. Nobody chose any of that, and
/// nobody could see it either. Inconsistent spacing is read as cheapness
/// without ever being noticed as spacing.
///
/// The rule is a 4pt grid and three radii, and the way it is enforced is that a
/// call site has a name to reach for. A raw number in a view is now a
/// deliberate exception rather than the default path.
public extension Theme {
    /// 4pt grid. Nothing in the app should sit between two of these.
    enum Space {
        public static let hair: CGFloat = 2
        public static let xxs: CGFloat = 4
        public static let xs: CGFloat = 8
        public static let sm: CGFloat = 12
        public static let md: CGFloat = 16
        public static let lg: CGFloat = 20
        public static let xl: CGFloat = 24
        public static let xxl: CGFloat = 32

        /// `n` steps on the grid, for the handful of gaps that have no name.
        /// The point of the scale is the grid, not the vocabulary: a value that
        /// needs seven steps should say so rather than being typed as 28.
        public static func step(_ n: Int) -> CGFloat { CGFloat(n) * xxs }
    }

    /// Three, not one.
    ///
    /// The single-radius rule is right about the failure it prevents (sharp and
    /// round on one screen) and wrong about iOS, where a 20pt button inside a
    /// 20pt card reads as a mistake: nested corners have to shrink or the inner
    /// one looks like it has burst its container. So the scale is a card, a
    /// control, and a chip, and every one of them is `.continuous`.
    enum Radius {
        /// Cards, sheets, anything that holds other content.
        public static let card: CGFloat = 20
        /// Buttons, inputs, plan cards, tappable rows.
        public static let control: CGFloat = 16
        /// Badges, pills, small inline surfaces.
        public static let chip: CGFloat = 10
    }

    /// One shadow scale. Elevation is information, not decoration: a card at
    /// rest, and a thing that floats over content.
    enum Elevation {
        public static let card = (radius: CGFloat(8), y: CGFloat(2), opacity: 0.06)
        public static let floating = (radius: CGFloat(18), y: CGFloat(6), opacity: 0.14)
    }

    /// Selection strokes. Two weights so a selected plan card and a focus ring
    /// cannot disagree.
    enum Stroke {
        public static let hairline: CGFloat = 1
        public static let selected: CGFloat = 2
    }
}

public extension View {
    /// The card shape, so no call site has to name a radius or a curve style.
    func cardShape(_ fill: Color = Theme.cardSurface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.card, style: .continuous))
    }

    /// The control shape: buttons, plan cards, tappable rows.
    func controlShape(_ fill: Color = Theme.cardSurface) -> some View {
        background(fill, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
    }

    /// A countdown figure: the rounded face and tabular digits together.
    ///
    /// Together on purpose. Every number in this app counts down, and a
    /// proportional font re-lays the digits out as they change, so a hero that
    /// reads "12h" jitters sideways on its way to "9h" and the ring behind it
    /// looks like it is being redrawn. Two call sites had the font without the
    /// digits before this modifier existed, which is exactly the drift a pair of
    /// modifiers you have to remember to type together will always produce.
    func countdownNumber(_ size: CGFloat) -> some View {
        font(Theme.bigNumber(size)).monospacedDigit()
    }

    func cardShadow() -> some View {
        shadow(
            color: .black.opacity(Theme.Elevation.card.opacity),
            radius: Theme.Elevation.card.radius,
            y: Theme.Elevation.card.y
        )
    }
}
