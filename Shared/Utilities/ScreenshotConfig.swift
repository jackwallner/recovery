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
            densityFactor: 0.95,
            weeklyLoad: 268,
            sessionsPerWeek: 4.7,
            qualifyingSessions: 20,
            evidenceWeight: 0.62
        )
    }

    /// The conversion card's two figures, fixed so the capture is reproducible.
    public static func personalizedPreview() -> PersonalizedPreview {
        PersonalizedPreview(
            label: "Your last run",
            standardHours: 21,
            personalizedHours: 16,
            isExample: false
        )
    }

    /// The receipt the app prints back to the user, fixed so the onboarding
    /// readout, the trial page's proof block, the Settings section and the
    /// Recharge+ tab all render the same rows on every capture.
    ///
    /// Every field is filled in, which is the one way this fixture is *not*
    /// typical: plenty of real users have no VO2 max and no weight. That is
    /// deliberate for a capture — a screenshot of the receipt has to show what
    /// the receipt is — and it is why the empty and partial cases are covered by
    /// `HealthIngestSummary` building no row at all for a missing reading rather
    /// than by a second fixture.
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
        readings.bodyMassKilograms = 78
        readings.age = 34
        return HealthIngestSummary(readings: readings, usesObservedMaxHeartRate: true)
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
    ///
    /// `standard` is the same session on the standard table and is **not** the
    /// same figure as `hours`. It used to be left off, which defaulted it to
    /// `hours` — so every surface that compares the two tiers rendered the same
    /// number twice, and the rest-pattern card's whole third column had nothing
    /// to show. The spread here is what the fixture user's own analysis implies:
    /// a 0.86 multiplier *and* a personal baseline above the population
    /// reference, which is the compounding the model actually does.
    public static func history(now: Date = .now) -> [RecoveryEstimate] {
        let leadHoursAgo: Double = ScreenshotConfig.wantsReady ? 26 : 3
        // `carried` is the recovery still outstanding when the session landed,
        // and one row has a real one: the lifting session at 98h went on top of
        // the run at 122h, whose 18.1-hour window still had 5.9 hours to go.
        // Recovery time is cumulative, so a capture where nothing ever stacks
        // would show a model quietly simpler than the one that ships — the same
        // trap `standardHours` fell into when it defaulted to `hours`.
        // `cost` is what the session cost and `hours` is the countdown it set.
        // They are the same figure for a qualifying session and they diverge for
        // the two rows that used to render as the word "None" — the walk, and
        // the short evening spin that fell under the quiet threshold. A capture
        // without both of those in it would show a History tab that cannot
        // happen.
        let pattern: [(hoursAgo: Double, hours: Double, cost: Double, standard: Double, carried: Double, profile: WorkoutProfile, label: String, category: LoadCategory)] = [
            (leadHoursAgo, 21.7, 21.7, 28.0, 0, .endurance, "run", .hard),
            (27, 9.4, 9.4, 13.0, 0, .endurance, "ride", .typical),
            (34, 0, 1.9, 2.4, 0, .easy, "walk", .easy),
            (52, 0, 3.1, 4.0, 0, .endurance, "ride", .easy),
            (74, 31.2, 31.2, 39.0, 0, .mixed, "functional session", .unusuallyHard),
            (98, 14.8, 14.8, 19.0, 5.9, .strength, "lifting session", .typical),
            (122, 18.1, 18.1, 24.0, 0, .endurance, "run", .hard),
            (146, 0, 2.2, 2.8, 0, .easy, "walk", .easy),
            (170, 7.6, 7.6, 11.0, 0, .endurance, "run", .typical),
            (196, 26.4, 26.4, 34.0, 0, .mixed, "functional session", .hard)
        ]
        return pattern.enumerated().map { index, item in
            let end = now.addingTimeInterval(-item.hoursAgo * 3600)
            var reasons = ["\(item.category.label): \(item.label)."]
            if item.hours == 0 {
                reasons = item.profile == .easy
                    ? [
                        "38-minute \(item.label) counts as active recovery.",
                        "Light enough to leave the countdown where it is."
                      ]
                    : [
                        "Light session: a 24-minute \(item.label) below the level that starts a countdown.",
                        "Counted toward your training load, but no countdown started."
                      ]
            }
            if index == 0 {
                reasons = [
                    "\(item.category.label): 52-minute \(item.label).",
                    "Load estimated from heart rate.",
                    "Extended slightly: short sleep (5.4h) and HRV below your usual range."
                ]
            }
            // The countdown this session actually set, which is what `readyAt`
            // and the displayed range have to agree with.
            let total = item.hours > 0 ? item.hours + item.carried : 0
            return RecoveryEstimate(
                sessionID: "screenshot-\(index)",
                profile: item.profile,
                activityLabel: item.label,
                calculatedAt: end,
                sessionEnd: end,
                readyAt: end.addingTimeInterval(total * 3600),
                hours: item.hours,
                windowLowHours: total * 0.85,
                windowHighHours: total * 1.15,
                load: SessionLoad(value: 40 + Double(index) * 12, source: .heartRate, heartRateCoverage: 0.95),
                relativeLoad: 0.5 + Double(index) * 0.22,
                category: item.category,
                confidence: index % 3 == 0 ? .high : .medium,
                reasons: reasons,
                standardHours: item.standard,
                carriedHours: item.carried,
                recoveryCostHours: item.cost
            )
        }
    }
}
#endif
