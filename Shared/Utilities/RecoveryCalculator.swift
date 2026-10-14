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

    /// The shortest countdown a qualifying session may produce.
    ///
    /// Garmin documents its recovery time as spanning "a minimum of 6 hours to a
    /// maximum of 4 days" (Edge 840 and fēnix 7 owner's manuals), and the floor
    /// is the half that matters here. A session either earns a countdown or it
    /// does not; one that does and then returns three hours is Ready before
    /// bedtime, which reads as the app having quietly ignored the workout. It is
    /// applied after every other adjustment so nothing — thin context, a
    /// calibration factor, a personal multiplier — can push a real session below
    /// it. Monotonicity survives: a maximum against a constant is still
    /// non-decreasing in load.
    public static let minimumCountdownHours: Double = 6

    /// Hard ceiling on any single estimate, and on a stacked countdown: four
    /// days, which is Garmin's documented maximum.
    ///
    /// It was 72 hours, on the argument that less signal should mean a more
    /// conservative ceiling. A ceiling is the opposite of conservative here: it
    /// is the one place the app tells somebody to wait *less* than the model
    /// says, and it bit on exactly the sessions that need it most. A half
    /// marathon raced hard and a marathon both read 72 hours, the same figure as
    /// an ordinary long run for a beginner, where Garmin puts races at 48-96h
    /// and a marathon at or near its four-day maximum.
    public static let maximumHours: Double = 96

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
    ///
    /// The last segment, 72h to 96h between 3.5x and 6x a typical day, is the
    /// race segment. Everything below it is unchanged from the 72-hour model, so
    /// the training sessions `GarminAnchorTests` pins did not move; only sessions
    /// that used to pin the old ceiling now spread out above it.
    static let curve: [(relativeLoad: Double, hours: Double)] = [
        (0.00, 0),
        (0.60, 8),
        (1.25, 18),
        (2.00, 36),
        (3.50, 72),
        (6.00, 96)
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
    ///     `PersonalRecoveryModel`. `.standard` for the free tier, which is one
    ///     shared table read at the person's stated training level (the
    ///     `fitnessScale` on `baseline`) rather than the same number for
    ///     everyone.
    ///   - observed: what this person **actually does** after a session this
    ///     size, read off their own history by `ObservedRecoveryPattern`. A
    ///     sentence in the reasons, on both tiers, and never the countdown.
    ///
    ///     It was the free countdown from model version 11 to 15, and that
    ///     measured training frequency rather than recovery: somebody who runs
    ///     three times a week was shown 47 hours after a 30-minute jog and 72
    ///     after everything harder, and a daily trainer 23 hours after a
    ///     marathon. A recovery time has to depend on the session, so the free
    ///     tier is the model at the person's training level again, which is
    ///     what the App Store description always said it was.
    ///   - manualHours: hours the user pinned to this session's intensity band,
    ///     when they are following a programme the model does not know about.
    ///     Recharge+ only, and it replaces the modelled window outright — a
    ///     typed number blended with a computed one is a third figure that is
    ///     neither. It never reaches the standard tier, whose whole claim is
    ///     that the figure came from the history rather than from a preference.
    ///   - now: the calculation instant. Injected so tests are deterministic.
    public static func estimate(
        for session: SessionInput,
        baseline: RecoveryBaseline,
        context: RecoveryContext = .empty,
        calibration: Double = RecoveryCalibration.neutral,
        personalization: RecoveryPersonalization = .standard,
        standardHours: Double? = nil,
        carriedHours: Double = 0,
        observed: ObservedRecoveryPattern.Window? = nil,
        manualHours: Double? = nil,
        now: Date = .now
    ) -> RecoveryEstimate {
        let load = SessionLoadCalculator.profiledLoad(for: session)
        let relative = relativeLoad(load.value, baseline: baseline)
        let category = category(forRelativeLoad: relative)

        // Easy/active-recovery sessions and anything under the person's quiet
        // threshold produce no countdown at all. `RecoveryResolver` is what
        // guarantees they cannot shorten one that is already running.
        let qualifies = session.profile != .easy && load.value >= baseline.quietThreshold

        // Recovery still outstanding when this session ended. Only a session
        // that earns a countdown of its own may inherit it: an easy walk taken
        // mid-window neither starts a countdown nor lengthens the one already
        // running, which is the same guarantee `RecoveryResolver` gives.
        let residual = qualifies && carriedHours.isFinite ? max(carriedHours, 0) : 0

        let personal = personalization.factor.isFinite
            ? min(max(personalization.factor, PersonalRecoveryModel.minimumFactor), PersonalRecoveryModel.maximumFactor)
            : 1
        let unadjusted = baseHours(forRelativeLoad: relative) * clampCalibration(calibration) * personal

        // The nights after the session only count while the countdown they
        // would adjust was still running. They are admitted one at a time, in
        // order, each against the window as the nights before it left it: a
        // good first night that brings Ready forward to the afternoon makes the
        // next night one after Ready, and a bad one there may not reopen it.
        // Judged against the night-before window alone, it was admitted. The
        // rule needs no clock, so a rescore days later reaches the same answer.
        func countdownEnd(admittingNightsBefore cutoff: Date) -> Date {
            let adjusted = unadjusted * (1 + contextAdjustment(context, nightsBefore: cutoff))
            let hours = min(max(adjusted * session.profile.windowMultiplier, minimumCountdownHours), maximumHours)
            let stacked = hours + stackedContribution(residual: residual, sessionHours: hours)
            return session.endDate.addingTimeInterval(min(stacked, maximumHours) * 3600)
        }
        var nightsCutoff = Date.distantPast
        var end = countdownEnd(admittingNightsBefore: nightsCutoff)
        for night in context.followingNights {
            guard night.date < end else { break }
            nightsCutoff = night.date.addingTimeInterval(1)
            end = countdownEnd(admittingNightsBefore: nightsCutoff)
        }
        let adjustment = contextAdjustment(context, nightsBefore: nightsCutoff)
        let scaled = unadjusted * (1 + adjustment)

        // Computed for **every** session, qualifying or not, because "what did
        // this session cost" is a different question from "how long should the
        // countdown run", and only the second one has a reason to be zero for a
        // walk. History asks the first; the ring, `readyAt` and the snapshot ask
        // the second. No `minimumCountdownHours` here: that floor exists so a
        // countdown is not over before bedtime, and it has nothing to say about
        // what forty minutes of walking cost.
        var cost = min(max(scaled * session.profile.costMultiplier, 0), maximumHours)

        var hours = 0.0
        if qualifies {
            hours = min(
                max(scaled * session.profile.windowMultiplier, minimumCountdownHours),
                maximumHours
            )
            // A pinned band is the last word. Somebody following a written
            // programme has an answer the app cannot derive, and the only useful
            // thing to do with it is use it. Recharge+ only: the standard tier
            // is the model at the user's training level, and a typed number is
            // not that.
            if personalization.tier == .personalized, let manual = manualHours, manual.isFinite, manual > 0 {
                hours = min(max(manual, minimumCountdownHours), maximumHours)
                // A pinned window is a statement about what the session cost, so
                // the description moves with it, or History prints a figure the
                // countdown contradicts.
                cost = hours
            }
        }

        // The countdown runs for this session's cost plus its share of what was
        // left over, bounded by the same ceiling a single session obeys.
        // `hours` stays the session's own cost: it is what the tier comparison
        // and the history rows are asking about. `carried` is the residual's
        // actual contribution, so "18h, incl. 6h carried" always adds up.
        //
        // Capped at the room the ceiling leaves. A marathon scored 96h on top of
        // a residual told Today "96h from your run, on top of 11h already owed"
        // above a 96-hour countdown: the residual was clamped away by the
        // ceiling but still reported as carried.
        let carried = qualifies
            ? min(stackedContribution(residual: residual, sessionHours: hours), max(maximumHours - hours, 0))
            : 0
        let total = qualifies ? min(hours + carried, maximumHours) : 0

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
            readyAt: session.endDate.addingTimeInterval(total * 3600),
            hours: hours,
            // The displayed range is the uncertainty on the countdown the user
            // is looking at, so it spreads around the stacked total rather than
            // around the session's own cost.
            windowLowHours: total * (1 - windowSpread),
            windowHighHours: min(total * (1 + windowSpread), maximumHours),
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
                personalization: personalization,
                observed: observed,
                manualHours: qualifies && personalization.tier == .personalized ? manualHours : nil,
                nightsBefore: nightsCutoff
            ),
            tier: personalization.tier,
            personalFactor: qualifies ? personalization.factor : 1,
            standardHours: standardHours,
            carriedHours: carried,
            recoveryCostHours: cost
        )
    }

    // MARK: - Stacking

    /// Recovery still outstanding when `session` ended, given where the previous
    /// countdown was due to finish. Half of the stacking rule;
    /// `stackedContribution` is the other half, and decides how much of it the
    /// new countdown inherits.
    ///
    /// Recovery time is cumulative: a session done inside a running countdown
    /// adds to it rather than starting fresh, so two hard sessions in a day
    /// cost more than one. Recharge used
    /// to take the *maximum* of overlapping windows, which is the simplest
    /// defensible rule and the wrong one — it made a same-day double read
    /// exactly like a single session, at the one moment somebody coming from a
    /// Garmin would expect the number to jump.
    ///
    /// A previous window that has already expired carries nothing, which is what
    /// the clamp at zero is for: without it a session a week after the last one
    /// would be *credited* with negative recovery.
    ///
    /// Pure and static, deliberately: the caller that walks the chain lives in
    /// `RecoveryEngine`, but the rule itself needs no store, no clock and no
    /// actor, so it is testable beside every other stage of the model.
    public static func carriedHours(into session: SessionInput, from previousReadyAt: Date?) -> Double {
        guard let previousReadyAt else { return 0 }
        return max(previousReadyAt.timeIntervalSince(session.endDate) / 3600, 0)
    }

    /// How much of the remaining countdown a new session adds on top of its own
    /// hours: the larger of the two in full, the smaller at `overlapShare`.
    ///
    /// It was the whole residual, and that has no fixed point for anybody who
    /// trains inside their own countdown every day. An athlete doing an easy
    /// morning session and a steady evening one gained about eight hours a day
    /// on the free tier and sat at the 96-hour ceiling for half of every
    /// fortnight, a countdown that could never reach Ready. Garmin's own figure
    /// visibly does not add in full either: an easy run on top of a long
    /// countdown nudges it rather than adding its whole standalone value, and
    /// the5krunner notes two moderate sessions leave more fatigue than the
    /// figure shows.
    ///
    /// The total is continuous and increasing in both inputs, so a harder
    /// session or more leftover recovery can never shorten the countdown, and a
    /// hard double is still 1.5 times a single.
    public static func stackedContribution(residual: Double, sessionHours: Double) -> Double {
        guard residual.isFinite, sessionHours.isFinite, residual > 0, sessionHours >= 0 else { return 0 }
        let total = max(residual, sessionHours) + overlapShare * min(residual, sessionHours)
        return max(total - sessionHours, 0)
    }

    /// The share of the smaller of two overlapping windows that still counts.
    public static let overlapShare = 0.5

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

    /// Total fractional adjustment from sleep, HRV, resting heart rate and
    /// breathing rate, clamped so the estimate moves modestly within a bounded
    /// range rather than swinging on one reading.
    ///
    /// The night before the session and every night after it that landed
    /// before `nightsBefore` are each scored on their own, then averaged with
    /// the nights after weighted double. How the session was absorbed matters
    /// more than how the person went into it, and it is what Garmin keeps
    /// adjusting the countdown with. With no nights after, this is exactly the
    /// night-before adjustment it always was.
    ///
    /// - Parameter nightsBefore: only nights that started before this instant
    ///   count. Nil admits every night the context carries.
    static func contextAdjustment(_ context: RecoveryContext, nightsBefore end: Date? = nil) -> Double {
        var readings: [(adjustment: Double, weight: Double)] = []
        let before = context.nightBefore
        if before.hasSignal { readings.append((nightAdjustment(before, context), 1)) }
        for night in includedNights(context, before: end) {
            readings.append((nightAdjustment(night, context), followingNightWeight))
        }
        let weight = readings.reduce(0) { $0 + $1.weight }
        guard weight > 0 else { return 0 }
        let mean = readings.reduce(0) { $0 + $1.adjustment * $1.weight } / weight
        return min(max(mean, minimumContextAdjustment), maximumContextAdjustment)
    }

    /// How much more a night after the session counts than the night before it.
    static let followingNightWeight = 2.0

    static func includedNights(_ context: RecoveryContext, before end: Date?) -> [RecoveryContext.Night] {
        guard let end else { return context.followingNights }
        return context.followingNights.filter { $0.date < end }
    }

    /// One night against the person's own baselines.
    static func nightAdjustment(_ night: RecoveryContext.Night, _ context: RecoveryContext) -> Double {
        var delta = 0.0

        if let sleep = night.sleepHours {
            if sleep < 5 {
                delta += 0.12
            } else if sleep < 6 {
                delta += 0.08
            } else if sleep >= 7.5 {
                delta -= 0.05
            }
        }

        if let hrv = night.heartRateVariability,
           let baseline = context.heartRateVariabilityBaseline,
           baseline > 0 {
            let ratio = hrv / baseline
            if ratio < 0.85 {
                delta += 0.08
            } else if ratio > 1.15 {
                delta -= 0.05
            }
        }

        if let rhr = night.restingHeartRate,
           let baseline = context.restingHeartRateBaseline,
           baseline > 0 {
            if rhr >= baseline + 5 {
                delta += 0.08
            } else if rhr <= baseline - 2 {
                delta -= 0.04
            }
        }

        // Half the weight of resting heart rate, deliberately. Overnight
        // respiratory rate is a real signal that the previous day has not been
        // absorbed, and it is also the noisiest of the four; four signals each
        // pulling as hard as one another would between them swamp the session
        // the estimate is supposed to be about.
        if let rate = night.respiratoryRate,
           let baseline = context.respiratoryRateBaseline,
           baseline > 0 {
            if rate >= baseline + 1.5 {
                delta += 0.04
            } else if rate <= baseline - 1 {
                delta -= 0.02
            }
        }

        return min(max(delta, minimumContextAdjustment), maximumContextAdjustment)
    }

    static func clampCalibration(_ factor: Double) -> Double {
        guard factor.isFinite else { return RecoveryCalibration.neutral }
        return min(max(factor, RecoveryCalibration.minimum), RecoveryCalibration.maximum)
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

        guard baseline.hasEstablishedBaseline else { return .buildingBaseline }

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
        personalization: RecoveryPersonalization = .standard,
        observed: ObservedRecoveryPattern.Window? = nil,
        manualHours: Double? = nil,
        nightsBefore: Date? = nil
    ) -> [String] {
        var reasons: [String] = []
        let tier = personalization.tier
        let categoryLabel = category.label(for: tier)

        let minutes = Int(session.durationMinutes.rounded())
        if session.profile == .easy {
            if session.intensityOverride == .light {
                reasons.append("You marked this session light, so it counts as active recovery.")
                reasons.append("Light enough to leave the countdown where it is.")
                return reasons
            }
            reasons.append("\(minutes)-minute \(session.activityLabel) counts as active recovery.")
            reasons.append("Light enough to leave the countdown where it is.")
            return reasons
        }

        if !qualifies {
            let comparison = tier == .standard ? "below the level that starts a countdown" : "below your usual session load"
            reasons.append("\(categoryLabel.lowercased()): a \(minutes)-minute \(session.activityLabel) \(comparison).")
            reasons.append("Counted toward your training load, but no countdown started.")
            return reasons
        }

        reasons.append("\(categoryLabel): \(minutes)-minute \(session.activityLabel).")
        if let override = session.intensityOverride {
            reasons.append("You marked this session \(override.label.lowercased()), so that is what it was scored as.")
        } else {
            reasons.append("Load estimated from \(load.source.label).")
        }

        // Stated before anything else that moved the number, because when a band
        // is pinned nothing else did.
        if let manualHours, manualHours.isFinite, manualHours > 0 {
            reasons.append("You pinned \(CountdownFormat.hours(manualHours)) to this intensity, so the model's own figure is not used here.")
            return reasons
        }

        switch tier {
        case .standard:
            reasons.append("Standard estimate at your training level, scored against your heart-rate range.")
        case .personalized:
            if !baseline.hasEstablishedBaseline {
                reasons.append("Still building your baseline from \(baseline.dayCount) recent training \(baseline.dayCount == 1 ? "day" : "days").")
            }
            let percent = Int(((personalization.factor - 1) * 100).rounded())
            if percent <= -3 {
                reasons.append("Your own \(PersonalRecoveryModel.windowDays)-day pattern shortens this by about \(abs(percent))%.")
            } else if percent >= 3 {
                reasons.append("Your own \(PersonalRecoveryModel.windowDays)-day pattern lengthens this by about \(percent)%.")
            }
        }

        // What the person actually does after a session this size, on both
        // tiers. A recommendation is easiest to read against a habit, and the
        // habit is the one figure here the user can check against their own
        // calendar.
        if let observed {
            let times = "\(observed.sampleCount) \(observed.sampleCount == 1 ? "time" : "times")"
            if observed.isBandSpecific {
                reasons.append("After \(observed.band.sessionPhrase) you have usually gone again after about \(CountdownFormat.hours(observed.hours)) (\(times)).")
            } else {
                reasons.append("You have usually gone again after about \(CountdownFormat.hours(observed.hours)) between sessions (\(times)).")
            }
        }

        let nights = includedNights(context, before: nightsBefore)
        let night = nights.last ?? context.nightBefore
        let prefix = nights.isEmpty ? nil : (nights.count == 1 ? "since the session" : "over the \(nights.count) nights since")
        if adjustment > 0.02 {
            reasons.append(contextSummary(night, context, lengthened: true, prefix: prefix))
        } else if adjustment < -0.02 {
            reasons.append(contextSummary(night, context, lengthened: false, prefix: prefix))
        }

        return reasons.filter { !$0.isEmpty }
    }

    private static func contextSummary(
        _ night: RecoveryContext.Night,
        _ context: RecoveryContext,
        lengthened: Bool,
        prefix: String?
    ) -> String {
        var signals: [String] = []
        if let sleep = night.sleepHours {
            if lengthened, sleep < 6 {
                signals.append("short sleep (\(String(format: "%.1f", sleep))h)")
            } else if !lengthened, sleep >= 7.5 {
                signals.append("good sleep (\(String(format: "%.1f", sleep))h)")
            }
        }
        if let hrv = night.heartRateVariability,
           let base = context.heartRateVariabilityBaseline, base > 0 {
            let ratio = hrv / base
            if lengthened, ratio < 0.85 {
                signals.append("HRV below your usual range")
            } else if !lengthened, ratio > 1.15 {
                signals.append("HRV above your usual range")
            }
        }
        if let rhr = night.restingHeartRate,
           let base = context.restingHeartRateBaseline, base > 0 {
            if lengthened, rhr >= base + 5 {
                signals.append("resting heart rate up \(Int((rhr - base).rounded())) bpm")
            } else if !lengthened, rhr <= base - 2 {
                signals.append("resting heart rate below your usual range")
            }
        }
        if let rate = night.respiratoryRate,
           let base = context.respiratoryRateBaseline, base > 0 {
            if lengthened, rate >= base + 1.5 {
                signals.append("breathing rate up overnight")
            } else if !lengthened, rate <= base - 1 {
                signals.append("breathing rate below your usual range")
            }
        }
        let verb = lengthened ? "Extended slightly" : "Shortened slightly"
        let lead = prefix.map { "\(verb) \($0)" } ?? verb
        guard !signals.isEmpty else {
            // Several nights can move the window between them without the last
            // one crossing a threshold on its own. Say so rather than nothing.
            return prefix == nil ? "" : "\(lead): overnight readings against your usual range."
        }
        return "\(lead): \(ListFormatterShim.join(signals))."
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
