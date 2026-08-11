import Foundation

/// Scenes the App Store capture run can request. Set via the environment so a
/// screenshot pass never has to fake data by hand in the UI layer.
public enum ScreenshotScene: String, Sendable {
    case recovering
    case ready
    case history
    case paywall
    case premiumActive
    case settings
    case onboarding
    case watchRecovering
    case watchReady
    case watchEffort
}

public enum ScreenshotConfig {
#if DEBUG
    public static let isEnabled = ProcessInfo.processInfo.environment["RECHARGE_SCREENSHOT_MODE"] == "1"
    public static let scene = isEnabled
        ? ScreenshotScene(rawValue: ProcessInfo.processInfo.environment["RECHARGE_SCREENSHOT_SCENE"] ?? "")
        : nil
    /// Force intro-offer ineligible so used-trial copy can be verified across
    /// onboarding, the trial sheet, and the paywall.
    public static let forceIntroIneligible =
        ProcessInfo.processInfo.environment["RECHARGE_FORCE_INTRO_INELIGIBLE"] == "1"
#else
    public static let isEnabled = false
    public static let scene: ScreenshotScene? = nil
    public static let forceIntroIneligible = false
#endif

    public static var wantsPremiumActive: Bool { scene == .premiumActive }
    public static var wantsOnboarding: Bool { scene == .onboarding }
    public static var wantsHistory: Bool { scene == .history }
    public static var wantsPaywall: Bool { scene == .paywall }
    public static var wantsSettings: Bool { scene == .settings }
    public static var wantsReady: Bool { scene == .ready || scene == .watchReady }
    public static var wantsEffortPrompt: Bool { scene == .watchEffort }
}

#if DEBUG
/// Deterministic snapshots for the capture run. Real enough to look like a
/// training week, fixed so two captures never disagree.
public enum ScreenshotFixtures {
    public static func snapshot(now: Date = .now) -> RecoverySnapshot {
        if ScreenshotConfig.wantsReady {
            return RecoverySnapshot(
                readyAt: nil,
                sessionEnd: now.addingTimeInterval(-26 * 3600),
                hours: 22,
                windowLowHours: 18.7,
                windowHighHours: 25.3,
                profile: .endurance,
                activityLabel: "run",
                category: .hard,
                confidence: .high,
                reasons: [
                    "Hard for you: 62-minute run.",
                    "Load estimated from heart rate."
                ],
                calculatedAt: now.addingTimeInterval(-26 * 3600),
                isPro: true
            )
        }
        return RecoverySnapshot(
            readyAt: now.addingTimeInterval(18 * 3600 + 40 * 60),
            sessionEnd: now.addingTimeInterval(-3 * 3600),
            hours: 21.7,
            windowLowHours: 18.4,
            windowHighHours: 24.9,
            profile: .endurance,
            activityLabel: "run",
            category: .hard,
            confidence: .high,
            reasons: [
                "Hard for you: 52-minute run.",
                "Load estimated from heart rate.",
                "Extended slightly: short sleep (5.4h)."
            ],
            calculatedAt: now.addingTimeInterval(-3 * 3600),
            isPro: ScreenshotConfig.wantsPremiumActive
        )
    }

    /// A settled Recharge Pro analysis, so the onboarding comparison card and
    /// the Settings rows render the real shape rather than their empty states.
    ///
    /// Curated rather than derived: the fixture history carries estimates, not
    /// the overnight day points the rebound signal reads, and inventing those
    /// just to run the analysis over them would be a longer way to the same
    /// hand-picked numbers.
    public static func personalAnalysis() -> PersonalRecoveryModel.Analysis {
        PersonalRecoveryModel.Analysis(
            factor: 0.86,
            prior: 0.97,
            reboundFactor: 0.88,
            reboundSamples: 6,
            toleranceFactor: 0.91,
            toleranceSamples: 4,
            densityFactor: 0.95,
            weeklyLoad: 268,
            sessionsPerWeek: 4.7,
            qualifyingSessions: 20,
            evidenceWeight: 0.62
        )
    }

    /// What Health would have supplied for the screenshot user. Experience and
    /// bounce-back are deliberately left out: they are the two questions Health
    /// can never answer, so leaving them open is what makes the onboarding
    /// capture show the question pages.
    public static func athleteProfile() -> AthleteProfile {
        AthleteProfile(
            age: 34,
            sex: .male,
            weeklyVolume: .fiveOrSix,
            primaryProfile: .endurance,
            healthDerivedFields: [
                AthleteProfile.ageField,
                AthleteProfile.sexField,
                AthleteProfile.weeklyVolumeField,
                AthleteProfile.primaryProfileField
            ]
        )
    }

    /// Two weeks of finished estimates for the history screen. The leading
    /// session's age flips with the scene, so `ready` shows an expired countdown
    /// and `recovering` shows a live one from the same fixture set.
    public static func history(now: Date = .now) -> [RecoveryEstimate] {
        let leadHoursAgo: Double = ScreenshotConfig.wantsReady ? 26 : 3
        let pattern: [(hoursAgo: Double, hours: Double, profile: WorkoutProfile, label: String, category: LoadCategory)] = [
            (leadHoursAgo, 21.7, .endurance, "run", .hard),
            (27, 9.4, .endurance, "ride", .typical),
            (52, 0, .easy, "walk", .easy),
            (74, 31.2, .mixed, "functional session", .unusuallyHard),
            (98, 14.8, .strength, "lifting session", .typical),
            (122, 18.1, .endurance, "run", .hard),
            (170, 7.6, .endurance, "run", .typical),
            (196, 26.4, .mixed, "functional session", .hard)
        ]
        return pattern.enumerated().map { index, item in
            let end = now.addingTimeInterval(-item.hoursAgo * 3600)
            var reasons = ["\(item.category.label): \(item.label)."]
            if index == 0 {
                reasons = [
                    "\(item.category.label): 52-minute \(item.label).",
                    "Load estimated from heart rate.",
                    "Extended slightly: short sleep (5.4h) and HRV below your usual range."
                ]
            }
            return RecoveryEstimate(
                sessionID: "screenshot-\(index)",
                profile: item.profile,
                activityLabel: item.label,
                calculatedAt: end,
                sessionEnd: end,
                readyAt: end.addingTimeInterval(item.hours * 3600),
                hours: item.hours,
                windowLowHours: item.hours * 0.85,
                windowHighHours: item.hours * 1.15,
                load: SessionLoad(value: 40 + Double(index) * 12, source: .heartRate, heartRateCoverage: 0.95),
                relativeLoad: 0.5 + Double(index) * 0.22,
                category: item.category,
                confidence: index % 3 == 0 ? .high : .medium,
                reasons: reasons
            )
        }
    }
}
#endif
