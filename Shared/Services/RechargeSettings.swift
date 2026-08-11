import Combine
import Foundation
import SwiftUI
import WidgetKit

public enum AppAppearance: Int, CaseIterable, Sendable {
    case system = 0
    case light = 1
    case dark = 2

    public var label: String {
        switch self {
        case .system: "System"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    public var colorScheme: ColorScheme? {
        switch self {
        case .system: nil
        case .light: .light
        case .dark: .dark
        }
    }
}

/// Keys the widget and complication extensions read directly. They cannot see
/// this `@MainActor` class, so the names live in one place both sides agree on.
public enum SettingsKeys {
    public static let complicationStyle = "complicationStyle"
    public static let ambiguousProfile = "ambiguousProfile"
    public static let maxHeartRate = "maxHeartRate"
    public static let isProCached = "isProCached"
}

/// Every user preference, in App Group `UserDefaults` so the Watch app and both
/// widget extensions see the same values the phone wrote.
@MainActor
public final class RechargeSettings: ObservableObject {
    public static let shared = RechargeSettings()

    private let defaults: UserDefaults

    // MARK: - Onboarding / lifecycle

    @Published public var hasCompletedSetup: Bool {
        didSet { defaults.set(hasCompletedSetup, forKey: "hasCompletedSetup") }
    }

    /// The user explicitly skipped Health access during onboarding. Persisting
    /// this prevents the app from asking again on the next launch and gives the
    /// main UI a stable state from which to offer reconnection.
    @Published public var hasDeferredHealthAccess: Bool {
        didSet { defaults.set(hasDeferredHealthAccess, forKey: "hasDeferredHealthAccess") }
    }

    @Published public var lastWhatsNewVersionShown: String? {
        didSet {
            if let version = lastWhatsNewVersionShown {
                defaults.set(version, forKey: "lastWhatsNewVersionShown")
            } else {
                defaults.removeObject(forKey: "lastWhatsNewVersionShown")
            }
        }
    }

    @Published public var appearance: AppAppearance {
        didSet { defaults.set(appearance.rawValue, forKey: "appearance") }
    }

    // MARK: - Model behaviour

    /// How the countdown renders on every complication family. A setting rather
    /// than a hardcode: this audience left Garmin and fiddles with exactly this.
    @Published public var complicationStyle: ComplicationStyle {
        didSet {
            defaults.set(complicationStyle.rawValue, forKey: SettingsKeys.complicationStyle)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    /// "These are usually my…" for `.functionalStrengthTraining` and
    /// `.highIntensityIntervalTraining`, which HYROX and CrossFit both arrive as.
    @Published public var ambiguousProfile: WorkoutProfile {
        didSet { defaults.set(ambiguousProfile.rawValue, forKey: SettingsKeys.ambiguousProfile) }
    }

    /// User-set maximum heart rate. Zero means "use the model default", which
    /// the confidence rating already accounts for.
    @Published public var maxHeartRate: Double {
        didSet { defaults.set(maxHeartRate, forKey: SettingsKeys.maxHeartRate) }
    }

    /// Running calibration factor from expired-countdown feedback.
    @Published public var calibrationFactor: Double {
        didSet { defaults.set(calibrationFactor, forKey: "calibrationFactor") }
    }

    /// Session IDs whose readiness question has been answered or dismissed, so
    /// the prompt never reappears for the same session.
    @Published public var answeredFeedbackSessions: Set<String> {
        didSet { defaults.set(Array(answeredFeedbackSessions), forKey: "answeredFeedbackSessions") }
    }

    /// Sessions the user declined to rate, from either device.
    ///
    /// `Not now` on the Watch and `Skip` on the phone used to leave the request
    /// pending, so the same question came back on every launch until the workout
    /// aged out two days later. A decline is an answer.
    @Published public var declinedEffortSessions: Set<String> {
        didSet { defaults.set(Array(declinedEffortSessions), forKey: "declinedEffortSessions") }
    }

    // MARK: - Pro features

    /// What Recharge knows about the person: whatever Health supplied, plus the
    /// gap questions from onboarding.
    ///
    /// Stored on the free tier too. Age sets the heart-rate ceiling every
    /// session is measured against, which is a measurement input rather than a
    /// personalisation, and the answers have to survive until the user upgrades
    /// or nobody would ever see them used.
    @Published public var athleteProfile: AthleteProfile {
        didSet { persistAthleteProfile() }
    }

    /// The user has been through the profile questions, so onboarding must not
    /// ask again after an upgrade.
    @Published public var hasAnsweredProfileQuestions: Bool {
        didSet { defaults.set(hasAnsweredProfileQuestions, forKey: "hasAnsweredProfileQuestions") }
    }

    /// Pro: fold sleep, HRV, and resting heart rate into the estimate.
    @Published public var useContextSignals: Bool {
        didSet { defaults.set(useContextSignals, forKey: "useContextSignals") }
    }

    /// Pro: a local notification the moment an estimate expires.
    @Published public var notifyOnReady: Bool {
        didSet { defaults.set(notifyOnReady, forKey: "notifyOnReady") }
    }

    // MARK: - Conversion surfaces

    @Published public var lastTrialOfferShownDate: Date? {
        didSet {
            if let date = lastTrialOfferShownDate {
                defaults.set(date, forKey: "lastTrialOfferShownDate")
            } else {
                defaults.removeObject(forKey: "lastTrialOfferShownDate")
            }
        }
    }

    public static let trialOfferCooldownDays = 14

    /// True when a passive trial surface may fire: never shown, or the last show
    /// is older than the cooldown. Intent-driven taps bypass this entirely.
    public func passiveTrialOfferAllowed(now: Date = .now) -> Bool {
        guard let last = lastTrialOfferShownDate else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(Self.trialOfferCooldownDays) * 86_400
    }

    // MARK: - Init

    private init() {
        let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard
        self.defaults = defaults

        self.hasCompletedSetup = defaults.bool(forKey: "hasCompletedSetup")
        self.hasDeferredHealthAccess = defaults.bool(forKey: "hasDeferredHealthAccess")
        self.lastWhatsNewVersionShown = defaults.string(forKey: "lastWhatsNewVersionShown")
        self.appearance = AppAppearance(rawValue: defaults.integer(forKey: "appearance")) ?? .system

        self.complicationStyle = ComplicationStyle(
            rawValue: defaults.integer(forKey: SettingsKeys.complicationStyle)
        ) ?? .countdown

        self.ambiguousProfile = defaults.string(forKey: SettingsKeys.ambiguousProfile)
            .flatMap(WorkoutProfile.init(rawValue:)) ?? WorkoutClassifier.ambiguousDefault

        let storedMax = defaults.double(forKey: SettingsKeys.maxHeartRate)
        self.maxHeartRate = (120...230).contains(storedMax) ? storedMax : 0

        let storedCalibration = defaults.double(forKey: "calibrationFactor")
        self.calibrationFactor = (RecoveryCalibration.minimum...RecoveryCalibration.maximum)
            .contains(storedCalibration) ? storedCalibration : RecoveryCalibration.neutral

        self.athleteProfile = defaults.data(forKey: "athleteProfile")
            .flatMap { try? JSONDecoder().decode(AthleteProfile.self, from: $0) } ?? .empty
        self.hasAnsweredProfileQuestions = defaults.bool(forKey: "hasAnsweredProfileQuestions")
        self.answeredFeedbackSessions = Set(defaults.stringArray(forKey: "answeredFeedbackSessions") ?? [])
        self.declinedEffortSessions = Set(defaults.stringArray(forKey: "declinedEffortSessions") ?? [])
        self.useContextSignals = defaults.object(forKey: "useContextSignals") as? Bool ?? true
        self.notifyOnReady = defaults.object(forKey: "notifyOnReady") as? Bool ?? false
        self.lastTrialOfferShownDate = defaults.object(forKey: "lastTrialOfferShownDate") as? Date

        // Fresh installs get onboarding, not a "what changed" pitch for an app
        // they have never used. `didSet` does not run during init, so persist by
        // hand.
        if self.lastWhatsNewVersionShown == nil && !self.hasCompletedSetup {
            self.lastWhatsNewVersionShown = WhatsNew.currentVersion
            defaults.set(WhatsNew.currentVersion, forKey: "lastWhatsNewVersionShown")
        }

        applyScreenshotOverridesIfNeeded()
    }

    /// The max heart rate the calculator should use, or `nil` to let it apply
    /// its own default.
    ///
    /// A value the user typed in Settings always wins. Failing that, the
    /// age-predicted figure is far better than the blunt 185 bpm constant, and
    /// it applies on both tiers: measuring a 58-year-old's session against a
    /// 30-year-old's ceiling is not "standard", it is wrong.
    public var effectiveMaxHeartRate: Double? {
        if maxHeartRate > 0 { return maxHeartRate }
        return athleteProfile.predictedMaxHeartRate
    }

    private func persistAthleteProfile() {
        guard let data = try? JSONEncoder().encode(athleteProfile) else { return }
        defaults.set(data, forKey: "athleteProfile")
    }

    /// Merges what Health just reported without overwriting anything the user
    /// answered by hand. Health is the source of truth for the fields it owns,
    /// and silent about the rest.
    public func mergeHealthDerivedProfile(
        age: Int?,
        sex: AthleteSex?,
        weeklyVolume: WeeklyVolume?,
        primaryProfile: WorkoutProfile?
    ) {
        var profile = athleteProfile
        if let age {
            profile.age = age
            profile.healthDerivedFields.insert(AthleteProfile.ageField)
        }
        if let sex, sex != .unspecified {
            profile.sex = sex
            profile.healthDerivedFields.insert(AthleteProfile.sexField)
        }
        // Only fills a gap. Someone who told us they train five times a week
        // during a deload should not be relabelled by a quiet fortnight.
        if let weeklyVolume, profile.weeklyVolume == nil
            || profile.healthDerivedFields.contains(AthleteProfile.weeklyVolumeField) {
            profile.weeklyVolume = weeklyVolume
            profile.healthDerivedFields.insert(AthleteProfile.weeklyVolumeField)
        }
        if let primaryProfile {
            profile.primaryProfile = primaryProfile
            profile.healthDerivedFields.insert(AthleteProfile.primaryProfileField)
        }
        guard profile != athleteProfile else { return }
        athleteProfile = profile
    }

    public func recordFeedbackAnswered(_ sessionID: String) {
        answeredFeedbackSessions.insert(sessionID)
    }

    public func applyFeedback(_ feedback: ReadinessFeedback) {
        calibrationFactor = RecoveryCalibration.apply(feedback, to: calibrationFactor)
    }

    private func applyScreenshotOverridesIfNeeded() {
        guard ScreenshotConfig.isEnabled else { return }
        appearance = .system
        complicationStyle = .countdown
        hasCompletedSetup = !ScreenshotConfig.wantsOnboarding
        hasDeferredHealthAccess = false
        useContextSignals = true
        athleteProfile = ScreenshotFixtures.athleteProfile()
    }
}
