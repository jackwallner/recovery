import Foundation

/// Stages 3 to 5 of the model: turn a session load and a personal baseline into
/// a bounded recovery window, adjust it for context, and clamp it.
///
/// Pure and `Sendable` by construction — no HealthKit, no SwiftData, no clock of
/// its own. Everything it needs arrives as an argument, which is what makes the
/// fixture table in `RechargeTests` meaningful.
///
/// The output is a **cardiovascular training estimate**. It is not a statement
/// about tissue repair, injury risk, or fitness to train.
public enum RecoveryCalculator {

    // MARK: - Bounds

    /// No session shorter or easier than this starts a countdown, whatever the
    /// user's percentiles say. Roughly a 20-minute walk.
    public static let absoluteCountdownFloor: Double = 18

    /// Hard ceiling on any single estimate. Garmin caps around four days; we are
    /// more conservative because we have less signal.
    public static let maximumHours: Double = 72

    /// How far the displayed window spreads either side of the point estimate.
    static let windowSpread = 0.15

    /// Bounds on the total context adjustment, so one poor night or one noisy
    /// HRV reading can move the estimate but never dominate it.
    static let minimumContextAdjustment = -0.15
    static let maximumContextAdjustment = 0.20

    /// Anchors of the relative-load to hours curve, on the endurance baseline.
    /// Linear interpolation between them, flat above the last anchor. Kept as a
    /// continuous monotone function rather than discrete category buckets so
    /// "harder never returns a shorter window" holds by construction instead of
    /// by test.
    static let curve: [(relativeLoad: Double, hours: Double)] = [
        (0.00, 0),
        (0.60, 8),
        (1.25, 18),
        (2.00, 36),
        (3.50, 72)
    ]

    /// Category boundaries on relative load. Same breakpoints as the curve, so
    /// the label and the number can never disagree.
    static let easyCeiling = 0.60
    static let typicalCeiling = 1.25
    static let hardCeiling = 2.00

    // MARK: - Entry point

    /// Scores one finished session.
    ///
    /// - Parameters:
    ///   - session: the finished workout.
    ///   - baseline: the person's own recent loads for this profile.
    ///   - context: sleep / HRV / RHR. Pass `.empty` for free users or when
    ///     nothing is known; the estimate still resolves, at lower confidence.
    ///   - calibration: the running personal factor from expired-countdown
    ///     feedback. `RecoveryCalibration.neutral` when there is none.
    ///   - personalization: the Recharge+ multiplier from
    ///     `PersonalRecoveryModel`. `.standard` for the free tier, which is the
    ///     same table for everyone.
    ///   - now: the calculation instant. Injected so tests are deterministic.
    public static func estimate(
        for session: SessionInput,
        baseline: RecoveryBaseline,
        context: RecoveryContext = .empty,
        calibration: Double = RecoveryCalibration.neutral,
        personalization: RecoveryPersonalization = .standard,
        standardHours: Double? = nil,
        now: Date = .now
    ) -> RecoveryEstimate {
        let load = SessionLoadCalculator.profiledLoad(for: session)
        let relative = relativeLoad(load.value, baseline: baseline)
        let category = category(forRelativeLoad: relative)

        // Easy/active-recovery sessions and anything under the person's quiet
        // threshold produce no countdown at all. `RecoveryResolver` is what
        // guarantees they cannot shorten one that is already running.
        let qualifies = session.profile != .easy && load.value >= baseline.quietThreshold

        var hours = 0.0
        var adjustment = 0.0
        if qualifies {
            let base = baseHours(forRelativeLoad: relative) * session.profile.windowMultiplier
            adjustment = contextAdjustment(context)
            let personal = min(max(personalization.factor, PersonalRecoveryModel.minimumFactor), PersonalRecoveryModel.maximumFactor)
            hours = min(
                max(base * (1 + adjustment) * clampCalibration(calibration) * personal, 0),
                maximumHours
            )
        }

        let confidence = confidence(
            load: load,
            baseline: baseline,
            context: context,
            profile: session.profile,
            tier: personalization.tier
        )

        return RecoveryEstimate(
            sessionID: session.id,
            profile: session.profile,
            activityLabel: session.activityLabel,
            calculatedAt: now,
            sessionEnd: session.endDate,
            readyAt: session.endDate.addingTimeInterval(hours * 3600),
            hours: hours,
            windowLowHours: hours * (1 - windowSpread),
            windowHighHours: hours * (1 + windowSpread),
            load: load,
            relativeLoad: relative,
            category: category,
            confidence: confidence,
            reasons: reasons(
                session: session,
                load: load,
                category: category,
                context: context,
                adjustment: adjustment,
                qualifies: qualifies,
                baseline: baseline,
                personalization: personalization
            ),
            tier: personalization.tier,
            personalFactor: qualifies ? personalization.factor : 1,
            standardHours: standardHours
        )
    }

    // MARK: - Stage 3: relative load to hours

    static func relativeLoad(_ load: Double, baseline: RecoveryBaseline) -> Double {
        let typical = baseline.typicalLoad
        guard typical > 0 else { return 0 }
        return load / typical
    }

    static func category(forRelativeLoad relative: Double) -> LoadCategory {
        if relative < easyCeiling { return .easy }
        if relative < typicalCeiling { return .typical }
        if relative < hardCeiling { return .hard }
        return .unusuallyHard
    }

    /// The standard window for a canonical hard endurance session, straight off
    /// the real curve.
    ///
    /// Conversion surfaces have to be able to show what personalisation does
    /// before the user has any history to do it to, and an invented number on a
    /// paywall is a number someone will hold the app to.
    public static var referenceHardSessionHours: Double {
        baseHours(forRelativeLoad: 1.6) * WorkoutProfile.endurance.windowMultiplier
    }

    /// Piecewise-linear, monotone non-decreasing, flat above the last anchor.
    static func baseHours(forRelativeLoad relative: Double) -> Double {
        let r = max(relative, 0)
        guard let last = curve.last else { return 0 }
        if r >= last.relativeLoad { return last.hours }

        for (lower, upper) in zip(curve, curve.dropFirst()) where r < upper.relativeLoad {
            let span = upper.relativeLoad - lower.relativeLoad
            guard span > 0 else { return lower.hours }
            let t = (r - lower.relativeLoad) / span
            return lower.hours + (upper.hours - lower.hours) * t
        }
        return last.hours
    }

    // MARK: - Stage 4: context

    /// Total fractional adjustment from sleep, HRV, and resting heart rate,
    /// clamped so the estimate moves modestly within a bounded range rather than
    /// swinging on one reading.
    static func contextAdjustment(_ context: RecoveryContext) -> Double {
        var delta = 0.0

        if let sleep = context.sleepHours {
            if sleep < 5 {
                delta += 0.12
            } else if sleep < 6 {
                delta += 0.08
            } else if sleep >= 7.5 {
                delta -= 0.05
            }
        }

        if let hrv = context.heartRateVariability,
           let baseline = context.heartRateVariabilityBaseline,
           baseline > 0 {
            let ratio = hrv / baseline
            if ratio < 0.85 {
                delta += 0.08
            } else if ratio > 1.15 {
                delta -= 0.05
            }
        }

        if let rhr = context.restingHeartRate,
           let baseline = context.restingHeartRateBaseline,
           baseline > 0 {
            if rhr >= baseline + 5 {
                delta += 0.08
            } else if rhr <= baseline - 2 {
                delta -= 0.04
            }
        }

        return min(max(delta, minimumContextAdjustment), maximumContextAdjustment)
    }

    static func clampCalibration(_ factor: Double) -> Double {
        min(max(factor, RecoveryCalibration.minimum), RecoveryCalibration.maximum)
    }

    // MARK: - Confidence

    static func confidence(
        load: SessionLoad,
        baseline: RecoveryBaseline,
        context: RecoveryContext,
        profile: WorkoutProfile,
        tier: RecoveryTier = .personalized
    ) -> RecoveryConfidence {
        // "Building baseline" is a statement about a personal baseline that is
        // still filling up. The standard tier is not building one — it is not
        // using one — so reporting that forever would be a permanent excuse for
        // a number that is exactly as good as it is ever going to get. It is
        // capped at medium instead: the standard table cannot reach high, since
        // high is what knowing the person buys.
        if tier == .standard {
            switch load.source {
            case .duration: return .low
            case .energy: return profile == .easy ? .medium : .low
            case .reportedEffort: return .medium
            case .heartRate: return load.heartRateCoverage < 0.75 ? .low : .medium
            }
        }

        guard baseline.hasEnoughSamples else { return .buildingBaseline }

        switch load.source {
        case .duration:
            return .low
        case .energy:
            // Energy alone is a guess about intensity. Acceptable for a walk,
            // not for the sessions that actually set a long window.
            return profile == .easy ? .medium : .low
        case .reportedEffort:
            return context.isEmpty ? .medium : .high
        case .heartRate:
            if load.heartRateCoverage < 0.75 { return .medium }
            return context.isEmpty ? .medium : .high
        }
    }

    // MARK: - Explanation

    /// The "why" line, in the order a user would read it. Copy here is
    /// compliance-sensitive: no "recovered", no "safe to train", no "your body".
    static func reasons(
        session: SessionInput,
        load: SessionLoad,
        category: LoadCategory,
        context: RecoveryContext,
        adjustment: Double,
        qualifies: Bool,
        baseline: RecoveryBaseline,
        personalization: RecoveryPersonalization = .standard
    ) -> [String] {
        var reasons: [String] = []
        let tier = personalization.tier
        let categoryLabel = category.label(for: tier)

        let minutes = Int(session.durationMinutes.rounded())
        if session.profile == .easy {
            reasons.append("\(minutes)-minute \(session.activityLabel) counts as active recovery, so it does not start a countdown.")
            return reasons
        }

        if !qualifies {
            let comparison = tier == .standard ? "below the level that starts a countdown" : "below your usual session load"
            reasons.append("\(categoryLabel.lowercased()): a \(minutes)-minute \(session.activityLabel) \(comparison).")
            reasons.append("No countdown started.")
            return reasons
        }

        reasons.append("\(categoryLabel): \(minutes)-minute \(session.activityLabel).")
        reasons.append("Load estimated from \(load.source.label).")

        switch tier {
        case .standard:
            reasons.append("Standard estimate: the same table for everyone, from session type, length, and intensity.")
        case .personalized:
            if !baseline.hasEnoughSamples {
                reasons.append("Still building your baseline from \(baseline.sampleCount) recent \(baseline.sampleCount == 1 ? "session" : "sessions").")
            }
            let percent = Int(((personalization.factor - 1) * 100).rounded())
            if percent <= -3 {
                reasons.append("Your own \(PersonalRecoveryModel.windowDays)-day pattern shortens this by about \(abs(percent))%.")
            } else if percent >= 3 {
                reasons.append("Your own \(PersonalRecoveryModel.windowDays)-day pattern lengthens this by about \(percent)%.")
            }
        }

        if adjustment > 0.02 {
            reasons.append(contextSummary(context, lengthened: true))
        } else if adjustment < -0.02 {
            reasons.append(contextSummary(context, lengthened: false))
        }

        return reasons.filter { !$0.isEmpty }
    }

    private static func contextSummary(_ context: RecoveryContext, lengthened: Bool) -> String {
        var signals: [String] = []
        if let sleep = context.sleepHours {
            if lengthened, sleep < 6 {
                signals.append("short sleep (\(String(format: "%.1f", sleep))h)")
            } else if !lengthened, sleep >= 7.5 {
                signals.append("good sleep (\(String(format: "%.1f", sleep))h)")
            }
        }
        if let hrv = context.heartRateVariability,
           let base = context.heartRateVariabilityBaseline, base > 0 {
            let ratio = hrv / base
            if lengthened, ratio < 0.85 {
                signals.append("HRV below your usual range")
            } else if !lengthened, ratio > 1.15 {
                signals.append("HRV above your usual range")
            }
        }
        if let rhr = context.restingHeartRate,
           let base = context.restingHeartRateBaseline, base > 0 {
            if lengthened, rhr >= base + 5 {
                signals.append("resting heart rate up \(Int((rhr - base).rounded())) bpm")
            } else if !lengthened, rhr <= base - 2 {
                signals.append("resting heart rate below your usual range")
            }
        }
        guard !signals.isEmpty else { return "" }
        let joined = ListFormatterShim.join(signals)
        return lengthened ? "Extended slightly: \(joined)." : "Shortened slightly: \(joined)."
    }
}

/// `ListFormatter` is unavailable on watchOS in the shape we want and drags a
/// locale dependency into a pure type, so joining is done by hand.
enum ListFormatterShim {
    static func join(_ items: [String]) -> String {
        switch items.count {
        case 0: return ""
        case 1: return items[0]
        case 2: return "\(items[0]) and \(items[1])"
        default:
            return items.dropLast().joined(separator: ", ") + ", and " + (items.last ?? "")
        }
    }
}
