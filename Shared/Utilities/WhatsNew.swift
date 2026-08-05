import Foundation

/// Gates the one-time "What's New" announcement after an update.
///
/// It tracks the *announcement content*, not the marketing version, so an
/// unrelated build bump does not re-trigger the sheet. Fresh installs are seeded
/// past it in `RechargeSettings.init` so they get onboarding instead of a "what
/// changed" pitch for an app they have never used.
public enum WhatsNew {
    /// Bump when there is a new announcement to surface.
    public static let currentVersion = "1.0"

    public static func shouldShow(lastShown: String?) -> Bool {
        lastShown != currentVersion
    }

    public struct Item: Identifiable, Sendable {
        public let id = UUID()
        public let symbol: String
        public let title: String
        public let detail: String
    }

    public static let items: [Item] = [
        Item(
            symbol: "hourglass",
            title: "Recovery time on your wrist",
            detail: "A countdown after every qualifying workout, and a clear Ready mark when it runs out."
        ),
        Item(
            symbol: "square.grid.2x2",
            title: "Four complication families",
            detail: "Circular, rectangular, inline, and corner — in the style you pick."
        ),
        Item(
            symbol: "figure.mixed.cardio",
            title: "Built for hybrid training",
            detail: "Separate curves for endurance, lifting, and mixed sessions, not one universal number."
        )
    ]
}
