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
    /// 1.1: the standard/personalized split.
    ///
    /// 1.2: the app measures more, and the screens got out of the way. This one
    /// has to fire for the same reason 1.1 did — the number an existing user
    /// sees changes, because the heart-rate ceiling every session is scored
    /// against is now their own observed maximum rather than a formula — and an
    /// unexplained change to the central figure in the app is how trust in it
    /// goes. It also has to fire because the whole shell moved: Settings is no
    /// longer a tab, and somebody who cannot find it will assume it is gone.
    public static let currentVersion = "1.2"

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
            symbol: "heart.fill",
            title: "Scored against your real maximum",
            detail: "Recharge now measures the highest heart rate your own sessions have reached and uses that as the ceiling, instead of predicting one from your age. Your countdowns may move."
        ),
        Item(
            symbol: "list.bullet.rectangle",
            title: "Every session has a number",
            detail: "A walk or an easy spin used to show \"None\" in History. They cost something, so now they say what, and they still never start or extend a countdown."
        ),
        Item(
            symbol: "gearshape",
            title: "One number, one screen",
            detail: "Today is the countdown and nothing else. Tap it for the full explanation, and find Settings behind the gear button in the corner."
        )
    ]
}
