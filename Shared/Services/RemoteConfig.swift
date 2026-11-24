import Foundation

/// Everything RevenueCat can change without a release, read from the current
/// offering's metadata (so a running Experiment's variant is read too). Every
/// variant ships in the binary; a missing, non-string or unknown value is the
/// control, which is what the last release shipped. Keys that a switch reads
/// must be set the same on every offering, or an Experiment arm would flip
/// them as a side effect. Wording tests go through the `trial_cta` key.
///
/// DEBUG builds can pin any key for captures: `-recharge.rc.<key> <value>`.
///
/// This file imports nothing from RevenueCat: the store hands over
/// `offering.metadata`, so the reader is testable without the SDK.

/// The primary button on the onboarding trial page, the trial sheet and the
/// paywall.
///
/// Only the control ships. The shipped button is "Continue with Recharge+" on
/// purpose: it carries no trial or price words, because Apple 3.1.2(c) weighs
/// pricing elements against each other and the billed amount has to stay the
/// largest one (`onboarding-and-pitch.md`). A "Start my free trial" arm names
/// the trial on the button, so it waits on that decision rather than riding in
/// as a dormant case.
public enum TrialCTA: String, CaseIterable, Sendable {
    public static let metadataKey = "trial_cta"

    /// Control: the 7-day trial's button, as shipped.
    case control = "seven_day"

    public static func from(metadata: [String: Any]?) -> TrialCTA {
        RemoteConfig.value(metadataKey, in: metadata, default: .control)
    }

    /// The button text. An Apple Account that already used its free week gets
    /// the same words today; the parameter keeps the 3.1.2 rule on the type
    /// that owns the copy, for the day an arm names the trial.
    public func title(trialEligible: Bool) -> String {
        switch self {
        case .control: String(localized: "Continue with Recharge+", bundle: .recharge)
        }
    }
}

/// Remote off switches, for what is worth pausing without a release. On
/// unless the metadata says "off".
public enum RemoteSwitch: String, CaseIterable, Sendable {
    /// Apple's rating prompt at a good moment. "off" pauses the automatic ask.
    /// The Rate row in Settings is unaffected.
    case ratingPrompt = "rating_prompt"
}

public enum RemoteConfig {
    /// The value for `key`, or `fallback` when it is missing, not a string, or
    /// not one of the shipped variants.
    public static func value<T: RawRepresentable>(
        _ key: String,
        in metadata: [String: Any]?,
        default fallback: T
    ) -> T where T.RawValue == String {
        #if DEBUG
        if let pinned = launchOverride(key).flatMap(T.init(rawValue:)) { return pinned }
        #endif
        guard let raw = metadata?[key] as? String else { return fallback }
        return T(rawValue: raw) ?? fallback
    }

    public static func isOn(_ remoteSwitch: RemoteSwitch, in metadata: [String: Any]?) -> Bool {
        #if DEBUG
        if let pinned = launchOverride(remoteSwitch.rawValue) { return pinned != "off" }
        #endif
        return (metadata?[remoteSwitch.rawValue] as? String) != "off"
    }

    #if DEBUG
    private static func launchOverride(_ key: String) -> String? {
        let args = ProcessInfo.processInfo.arguments
        guard let index = args.firstIndex(of: "-recharge.rc.\(key)"), index + 1 < args.count else { return nil }
        return args[index + 1]
    }
    #endif
}
