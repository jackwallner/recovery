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
    /// 1.3: the user gets to correct the model, and the two figures stopped
    /// contradicting each other. It fires for the same reason 1.1 and 1.2 did —
    /// the Ready alert is on for everyone now and it needs permission, the two
    /// comparison columns are named differently everywhere they appear, and a
    /// session's countdown can be changed by hand for the first time.
    public static let currentVersion = "1.3"

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
            symbol: "bell.badge.fill",
            title: "Told when the countdown ends",
            detail: "The completion alert is on for everyone now, not just Recharge+. Recharge keeps counting down in the background, so you never have to open it to find out."
        ),
        Item(
            symbol: "slider.horizontal.3",
            title: "Tell it how hard it really was",
            detail: "Open any session and mark it light, moderate, or hard. The countdown is recalculated from your answer, including for a walk the sensors read as nothing."
        ),
        Item(
            symbol: "pin.fill",
            title: "Or pin your own hours",
            detail: "Recharge+ can hold a fixed recharge time for light, moderate, and hard sessions, for anyone following a programme of their own."
        ),
        Item(
            symbol: "arrow.left.arrow.right",
            title: "Standard and Recharge+, named",
            detail: "The two figures Recharge compares now say which is which, and tapping a session explains exactly what separates them."
        )
    ]
}
