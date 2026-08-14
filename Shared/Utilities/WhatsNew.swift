import Foundation

/// Gates the one-time "What's New" announcement after an update.
///
/// It tracks the *announcement content*, not the marketing version, so an
/// unrelated build bump does not re-trigger the sheet. Fresh installs are seeded
/// past it in `RechargeSettings.init` so they get onboarding instead of a "what
/// changed" pitch for an app they have never used.
public enum WhatsNew {
    /// Bump when there is a new announcement to surface.
    ///
    /// 1.1: the standard/personalized split. This one has to fire — the number
    /// an existing user sees changes, and an unexplained change to the central
    /// figure in the app is how trust in it goes.
    public static let currentVersion = "1.1"

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
            title: "A standard recharge time, free",
            detail: "Session type, length, and intensity in, hours out — the same clear countdown for everyone, with no history required."
        ),
        Item(
            symbol: "person.crop.circle.badge.clock",
            title: "Or one built from your own history",
            detail: "Recharge+ scores each session against your own baseline, then reads the last \(PersonalRecoveryModel.windowDays) days to set how fast your countdowns run."
        ),
        Item(
            symbol: "heart.text.square",
            title: "Fewer questions, better numbers",
            detail: "Recharge now reads your age from Apple Health to set the heart-rate range every session is measured against, and only asks for what Health can't answer."
        )
    ]
}
