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
    /// 1.4: Garmin parity (model version 16). The standard countdown is the
    /// model again rather than the user's usual gap, races reach four days,
    /// intervals and long easy sessions are costed the way Garmin costs them,
    /// and Recharge+ moves a running countdown with the nights after the
    /// session. Almost every figure an existing user has seen moves, so it fires.
    /// Model version 17 shipped in the same release, so its stacking rule (the
    /// larger overlapping countdown in full plus half the smaller) is announced
    /// here rather than in a 1.5 nobody would see separately.
    public static let currentVersion = "1.4"

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
            symbol: "gauge.with.needle",
            title: "Standard is a recovery time again",
            detail: "The free countdown scores each session at your training level, like a Garmin does, instead of repeating your usual gap between sessions. That gap is still shown beside it."
        ),
        Item(
            symbol: "flag.checkered",
            title: "Up to four days after a race",
            detail: "Countdowns now reach four days, so a half marathon or a marathon reads longer than a long run."
        ),
        Item(
            symbol: "waveform.path.ecg",
            title: "Intervals count for what they were",
            detail: "Recharge reads the time you spent at each heart rate, so hard repeats cost more than a steady run at the same average, and a long easy ride no longer outweighs a hard hour."
        ),
        Item(
            symbol: "square.stack.3d.up.fill",
            title: "Sessions close together add up",
            detail: "Train again before a countdown ends and the two combine: the longer one counts in full, plus half of the shorter. Training twice a day still reaches Ready."
        ),
        Item(
            symbol: "moon.zzz.fill",
            title: "Updated by the nights after",
            detail: "Recharge+ adjusts a running countdown after each night's sleep, HRV, and resting heart rate, not only the night before the session."
        )
    ]
}
