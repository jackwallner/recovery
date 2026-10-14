import Foundation
#if DEBUG
import os
#endif

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
    /// Today after Apple Health reads have been failing for eight hours: the
    /// countdown stays, and the line under the date says what went wrong.
    /// Not an App Store frame; it is how the stale state gets looked at.
    case stale
}

public enum ScreenshotConfig {
#if DEBUG
    private static let logger = Logger(subsystem: "com.jackwallner.recovery", category: "screenshot")

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

#if DEBUG
    /// Signals that the requested capture surface has mounted. The capture
    /// script waits for this event instead of guessing how long SwiftUI and
    /// StoreKit need on the current simulator.
    public static func markReady() {
        guard let scene else { return }
        logger.notice("screenshot-ready:\(scene.rawValue, privacy: .public)")
    }
#endif

    public static var wantsPremiumActive: Bool { scene == .premiumActive }
    /// Scenes captured as a subscriber. `StoreService` and the fixtures both
    /// read this, so the tier the shell shows and the tier the estimates were
    /// scored on cannot disagree: `ready` had the Recharge+ tab and an
    /// unblurred card above estimates labelled Standard.
    public static var wantsSubscriber: Bool { wantsPremiumActive || wantsReady }
    public static var wantsOnboarding: Bool { scene == .onboarding }
    public static var wantsHistory: Bool { scene == .history }
    public static var wantsPaywall: Bool { scene == .paywall }
    public static var wantsSettings: Bool { scene == .settings }
    public static var wantsReady: Bool { scene == .ready || scene == .watchReady }
    public static var wantsEffortPrompt: Bool { scene == .watchEffort }
    public static var wantsStale: Bool { scene == .stale }
}

#if DEBUG
/// Deterministic snapshots for the capture run. Real enough to look like a
/// training week, fixed so two captures never disagree.
public enum ScreenshotFixtures {
    /// The lead row of `history`, so the Watch, the widgets and Today all show
    /// the same session with the same tier's reasons. It was a separate
    /// hand-written value whose free version said "Hard for you" and "Extended
    /// slightly: short sleep", which the free tier never says.
    public static func snapshot(now: Date = .now) -> RecoverySnapshot {
        RecoverySnapshot(
            estimate: history(now: now)[0],
            isPro: ScreenshotConfig.wantsSubscriber,
            healthDataState: ScreenshotConfig.wantsStale ? .stale : .current
        )
    }

    /// A settled Recharge+ analysis, so the onboarding comparison card and
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
            weeklyLoad: 268,
            sessionsPerWeek: 4.7,
            qualifyingSessions: 20,
            evidenceWeight: 0.62
        )
    }

    /// The conversion card's two figures, fixed so the capture is reproducible.
    ///
    /// They are the lead run's two figures from `history`, because the card
    /// sits under that run's countdown: the Standard figure is the free hero
    /// and the Recharge+ figure is the subscriber's hero. They used to be
    /// 21 and 16 under a 22-hour ring on both tiers, which read as a card
    /// describing some other session.
    public static func personalizedPreview() -> PersonalizedPreview {
        PersonalizedPreview(
            label: "Your last run",
            standardHours: leadRun.standard,
            personalizedHours: leadRun.personal,
            isExample: false
        )
    }

    /// The lead run's standard and Recharge+ hours, shared by the history row
    /// and the conversion card so they cannot drift apart.
    static let leadRun = (standard: 21.7, personal: 18.0)

    /// The receipt the app prints back to the user, fixed so the onboarding
    /// readout, the trial page's proof block, the Settings section and the
    /// Recharge+ tab all render the same rows on every capture.
    ///
    /// The measured fields are filled in except body mass, which is commonly
    /// absent and lets the receipt demonstrate that optional readings disappear
    /// cleanly rather than leaving a blank row. The energy path's body-mass
    /// correction is covered by the seeded HealthKit walkthrough and unit suite.
    public static func healthIngest() -> HealthIngestSummary {
        var readings = HealthIngestSummary.Readings()
        readings.workoutCount = 96
        readings.daysCovered = 120
        readings.activityTypes = 5
        readings.sessionsWithHeartRate = 88
        readings.observedMaxHeartRate = 187
        readings.restingHeartRate = 52
        readings.heartRateVariability = 58
        readings.averageSleepHours = 7.1
        readings.respiratoryRate = 14
        readings.heartRateRecovery = 36
        readings.vo2Max = 51
        readings.age = 34
        return HealthIngestSummary(readings: readings, usesObservedMaxHeartRate: true)
    }

    /// What Health would have supplied for the screenshot user. Experience and
    /// bounce-back are deliberately left out: they are the two questions Health
    /// can never answer, so leaving them open is what makes the onboarding
    /// capture show the question pages.
    ///
    /// The measured maximum and VO2 max match `healthIngest`. Without them
    /// Settings said "Auto is 184 bpm, predicted from your age" a few rows
    /// below a receipt reading "Your highest heart rate 187 bpm, measured".
    public static func athleteProfile() -> AthleteProfile {
        AthleteProfile(
            age: 34,
            sex: .male,
            weeklyVolume: .fiveOrSix,
            primaryProfile: .endurance,
            vo2Max: 51,
            observedMaxHeartRate: 187,
            healthDerivedFields: [
                AthleteProfile.ageField,
                AthleteProfile.sexField,
                AthleteProfile.weeklyVolumeField,
                AthleteProfile.primaryProfileField,
                AthleteProfile.vo2MaxField,
                AthleteProfile.observedMaxHeartRateField
            ]
        )
    }

    /// A compact training week of finished estimates for the history screen. The leading
    /// session's age flips with the scene, so `ready` shows an expired countdown
    /// and `recovering` shows a live one from the same fixture set.
    ///
    /// **Tier-aware, because the two tiers now print different things.** The
    /// free scenes are the model at the user's training level: the countdown is
    /// the standard figure, the labels drop "for you", there is no overnight
    /// line, and the habit is a sentence. The subscriber scene is the Recharge+
    /// estimate with its own lower figure, a personal factor, and the nights.
    /// One shared set used to print "Hard for you" and "Extended slightly:
    /// short sleep" on a free estimate, which the free tier can never say, and
    /// labelled a subscriber's estimate "Standard".
    ///
    /// Load and relative load are per row and on the curve: the lead run is
    /// about 1.4x a typical day, which is what 21.7 standard hours means. They
    /// used to climb by index, so the hard run read "0.50x a typical session".
    public static func history(now: Date = .now) -> [RecoveryEstimate] {
        let isPro = ScreenshotConfig.wantsSubscriber
        let tier: RecoveryTier = isPro ? .personalized : .standard
        let leadHoursAgo: Double = ScreenshotConfig.wantsReady ? 26 : 3
        // `carried` is the recovery still outstanding when the session landed,
        // and one row has a real one: the lifting session carries a residual
        // from earlier in the training week, because a capture where nothing
        // ever stacks would show a model quietly simpler than the one that
        // ships. `cost` and `hours` diverge on the two rows that start no
        // countdown, the walk and the short spin under the threshold. The
        // capture ends after the stacked lifting session so the floating tab
        // bar never covers the final row in the App Store frame.
        typealias Row = (
            hoursAgo: Double, minutes: Int, profile: WorkoutProfile, label: String, category: LoadCategory,
            load: Double, standard: Double, personal: Double,
            standardRelative: Double, personalRelative: Double,
            standardCarried: Double, personalCarried: Double, qualifies: Bool
        )
        let rows: [Row] = [
            (leadHoursAgo, 52, .endurance, "run", .hard, 104, leadRun.standard, leadRun.personal, 1.40, 1.20, 0, 0, true),
            (27, 48, .endurance, "ride", .typical, 66, 13.0, 10.4, 0.90, 0.78, 0, 0, true),
            (34, 38, .easy, "walk", .easy, 20, 2.4, 1.9, 0.27, 0.23, 0, 0, false),
            (52, 18, .endurance, "ride", .easy, 15, 2.7, 2.3, 0.20, 0.17, 0, 0, false),
            (74, 46, .mixed, "functional session", .unusuallyHard, 191, 39.0, 31.2, 1.92, 1.64, 0, 0, true),
            (98, 58, .strength, "lifting session", .typical, 107, 19.0, 14.8, 1.17, 1.00, 7.0, 5.9, true)
        ]
        return rows.enumerated().map { index, row in
            let end = now.addingTimeInterval(-row.hoursAgo * 3600)
            let cost = isPro ? row.personal : row.standard
            let hours = row.qualifies ? cost : 0
            let carried = row.qualifies ? (isPro ? row.personalCarried : row.standardCarried) : 0
            let label = row.category.label(for: tier)
            var reasons = ["\(label): \(row.minutes)-minute \(row.label).", "Load estimated from heart rate."]
            if row.profile == .easy {
                reasons = [
                    "\(row.minutes)-minute \(row.label) counts as active recovery.",
                    "Light enough to leave the countdown where it is."
                ]
            } else if !row.qualifies {
                let comparison = isPro ? "below your usual session load" : "below the level that starts a countdown"
                reasons = [
                    "\(label.lowercased()): a \(row.minutes)-minute \(row.label) \(comparison).",
                    "Counted toward your training load, but no countdown started."
                ]
            } else if index == 0 {
                reasons += isPro
                    ? [
                        "Your own 30-day pattern shortens this by about 14%.",
                        "After a hard session you have usually gone again after about 30h (14 times).",
                        "Extended slightly: short sleep (5.4h) and HRV below your usual range."
                      ]
                    : [
                        "Standard estimate at your training level, scored against your heart-rate range.",
                        "After a hard session you have usually gone again after about 30h (14 times)."
                      ]
            }
            // The countdown this session actually set, which is what `readyAt`
            // and the displayed range have to agree with.
            let total = hours > 0 ? hours + carried : 0
            return RecoveryEstimate(
                sessionID: "screenshot-\(index)",
                profile: row.profile,
                activityLabel: row.label,
                calculatedAt: end,
                sessionEnd: end,
                readyAt: end.addingTimeInterval(total * 3600),
                hours: hours,
                windowLowHours: total * 0.85,
                windowHighHours: total * 1.15,
                load: SessionLoad(value: row.load, source: .heartRate, heartRateCoverage: 0.95),
                relativeLoad: isPro ? row.personalRelative : row.standardRelative,
                category: row.category,
                confidence: isPro ? (index % 3 == 0 ? .high : .medium) : .medium,
                reasons: reasons,
                tier: tier,
                personalFactor: isPro && row.qualifies ? 0.86 : 1,
                standardHours: row.qualifies ? row.standard : 0,
                carriedHours: carried,
                recoveryCostHours: cost
            )
        }
    }
}
#endif
