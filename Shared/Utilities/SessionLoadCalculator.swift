import Foundation

/// Stage 1 of the model: turn one finished workout into a single load number.
///
/// Three sources feed one common scale, tried in order of how much we trust
/// them. The scale is anchored on heart-rate TRIMP, and the other two are
/// converted onto it so a 60-minute threshold run and a 60-minute RPE-8 lifting
/// session land in the same neighbourhood rather than three orders of magnitude
/// apart.
///
/// This is a load proxy, not a measurement of tissue recovery.
public enum SessionLoadCalculator {

    // MARK: - Tuning constants

    /// Banister's exponential intensity weighting. Hard work counts for more
    /// than the same duration of easy work.
    static let trimpWeightConstant = 0.64
    static let trimpExponent = 1.92

    /// Minimum fraction of the session that must carry usable heart-rate samples
    /// before TRIMP is trusted. Below this, a lifting session's dropped signal
    /// would read as an easy hour.
    static let minimumHeartRateCoverage = 0.5

    /// Converts session-RPE (minutes x effort, Foster's arbitrary units) onto the
    /// TRIMP scale. Chosen so 60 minutes at RPE 8 lands near the TRIMP of a
    /// 60-minute threshold run.
    static let effortToTrimpScale = 0.30

    /// Active kilocalories per minute a reference adult burns at full
    /// heart-rate reserve, which is what converts a burn rate into the same
    /// reserve fraction the heart-rate path measures.
    ///
    /// From %HRR ≈ %VO2R: a 75 kg adult at a VO2 max of 45 ml/kg/min has
    /// (3.375 − 0.263) L/min of oxygen uptake available above rest, and at
    /// roughly 5 kcal per litre that is about 15.6 kcal/min of *active* energy
    /// at full reserve.
    ///
    /// It is a reference for a **75 kg** adult, and that qualifier used to be
    /// the model's largest known unfixed error. HealthKit's active energy
    /// already accounts for body mass, so a 95 kg athlete burns about a quarter
    /// more than a 75 kg one at the identical fraction of heart-rate reserve,
    /// and dividing both by the same constant reads the heavier one as having
    /// worked harder. `referenceEnergy(forBodyMass:)` is the correction, and
    /// reading body mass from Health is what pays for it.
    public static let referenceEnergyAtFullReserve: Double = 15.6

    /// The body mass `referenceEnergyAtFullReserve` describes.
    public static let referenceBodyMassKilograms: Double = 75

    /// The reference burn rate at full reserve for a given body mass.
    ///
    /// Linear in mass, which is what the underlying arithmetic is: VO2 max is
    /// expressed per kilogram, so absolute oxygen uptake — and therefore the
    /// kilocalories HealthKit reports — scales with the kilograms. The ratio is
    /// bounded because the rest of the derivation (a fixed 45 ml/kg/min, a fixed
    /// 5 kcal/L) is not, and one implausible weight sample should not be able to
    /// halve or double every calorie-derived session in someone's history.
    ///
    /// Falls back to the reference adult when Health has no weight, which is
    /// exactly the behaviour this path had before body mass was read at all.
    static func referenceEnergy(forBodyMass mass: Double?) -> Double {
        guard let mass, mass.isFinite, mass > 0 else { return referenceEnergyAtFullReserve }
        let ratio = min(max(mass / referenceBodyMassKilograms, 0.6), 1.7)
        return referenceEnergyAtFullReserve * ratio
    }

    /// Fallback max heart rate when the user has not set one and Health has no
    /// estimate. Age-predicted values need an age we may not have, so this is a
    /// deliberately blunt default and the confidence rating reflects it.
    public static let defaultMaxHeartRate: Double = 185
    public static let defaultRestingHeartRate: Double = 60

    // MARK: - Entry point

    public static func load(for session: SessionInput) -> SessionLoad {
        if let trimp = heartRateLoad(for: session) {
            return trimp
        }
        if let effort = reportedEffortLoad(for: session) {
            return effort
        }
        if let energy = energyLoad(for: session) {
            return energy
        }
        return durationLoad(for: session)
    }

    /// Strength and mixed sessions take the **highest** available signal rather
    /// than the first one on the ladder.
    ///
    /// The ladder is an order of trust, and for these two profiles that order is
    /// simply wrong. Every signal under-reads a lifting session, each in its own
    /// way: optical heart rate loses the plot at the bar, and kilocalories per
    /// minute are low for work that is hard but not aerobic. Preferring heart
    /// rate because it is "best" then produced the inversion this was found by —
    /// the same 60-minute lift scored 5.3 hours with a clean heart-rate trace,
    /// 7.2 hours from energy alone, and 24 hours once the user answered the
    /// effort prompt. More information made the number smaller, and answering
    /// the question the app asked was punished.
    ///
    /// Taking the maximum makes the sources agree to within the spread of what
    /// they actually disagree about, and makes the effort answer the thing that
    /// can only ever help. `durationLoad` is included as the floor: it is the
    /// blind type-typical guess, and no sensor reading should drag a hard
    /// session below what its own category usually costs.
    public static func strengthLoad(for session: SessionInput) -> SessionLoad {
        // `durationLoad` is in the maximum rather than being the last resort.
        // For this profile it is not a guess of last resort, it is the floor:
        // sixty minutes of resistance work costs what sixty minutes of
        // resistance work costs, and a heart-rate trace reading 36 against an
        // energy-derived 90 is the sensor being wrong, not the session being
        // easy. Leaving it out let a lift with heart rate but no energy fall
        // back to a third of what the same lift scored a day earlier.
        let candidates = [
            heartRateLoad(for: session),
            reportedEffortLoad(for: session),
            energyLoad(for: session),
            durationLoad(for: session)
        ].compactMap { $0 }
        return candidates.max { $0.value < $1.value } ?? durationLoad(for: session)
    }

    /// Mixed sessions tax both systems, and either signal alone understates
    /// them, so the higher of heart rate and reported effort wins when both
    /// exist. Falls back to the ordinary ladder otherwise.
    ///
    /// Energy is deliberately **not** in this maximum, though it is in the
    /// strength one. Court and combat sports hold the optical signal well, so
    /// heart rate is a real measurement here rather than the systematic
    /// under-read it is at a barbell; letting the coarser energy inference
    /// outbid it turned a 90-minute social tennis match into 36 hours.
    public static func mixedLoad(for session: SessionInput) -> SessionLoad {
        let hr = heartRateLoad(for: session)
        let effort = reportedEffortLoad(for: session)
        switch (hr, effort) {
        case let (.some(hr), .some(effort)):
            return hr.value >= effort.value ? hr : effort
        default:
            return load(for: session)
        }
    }

    /// Dispatches to the profile's load rule. Callers should use this rather
    /// than `load(for:)` directly.
    ///
    /// An **intensity override short-circuits the whole ladder.** Every branch
    /// below weighs sensor readings against each other, and the reason somebody
    /// reaches for the override is that those readings were wrong about this
    /// session. Folding the answer in as one more candidate — even as the
    /// maximum, which is what strength does — leaves "Hard" doing nothing on a
    /// session whose heart-rate trace already read harder, and a control that
    /// silently does nothing is worse than no control.
    public static func profiledLoad(for session: SessionInput) -> SessionLoad {
        if let override = session.intensityOverride {
            return overriddenLoad(for: session, intensity: override)
        }
        switch session.profile {
        case .strength: return strengthLoad(for: session)
        case .mixed: return mixedLoad(for: session)
        case .endurance, .easy: return load(for: session)
        }
    }

    /// The load for a session the user has rated by hand. Monotone in the three
    /// bands by construction, which is what makes moving the control visibly
    /// change the countdown in the direction the label promises.
    static func overriddenLoad(for session: SessionInput, intensity: SessionIntensity) -> SessionLoad {
        SessionLoad(
            value: costedMinutes(for: session, atReserve: intensity.assumedEffort / 10)
                * intensity.assumedEffort * effortToTrimpScale,
            source: .reportedEffort,
            heartRateCoverage: session.heartRateCoverage
        )
    }

    // MARK: - Sources

    /// Fraction of heart-rate reserve the session sustained, when the heart-rate
    /// signal is trustworthy enough to say so.
    ///
    /// Deliberately heart-rate only, with no fall-through to reported effort.
    /// `PersonalRecoveryModel` uses this to ask whether a session held its usual
    /// intensity, and comparing a reserve fraction against an RPE-derived one
    /// would answer that question with a change of units.
    public static func intensityFraction(for session: SessionInput) -> Double? {
        guard session.heartRateCoverage >= minimumHeartRateCoverage,
              let average = session.averageHeartRate,
              average.isFinite,
              average > 0
        else { return nil }

        let resting = session.restingHeartRate ?? defaultRestingHeartRate
        let max = session.maxHeartRate ?? defaultMaxHeartRate
        guard resting.isFinite, max.isFinite, max > resting else { return nil }
        return min(Swift.max((average - resting) / (max - resting), 0), 1)
    }

    /// Banister's exponential weighting of one minute at a given fraction of
    /// heart-rate reserve. The single definition of what a minute of work
    /// costs: both the measured path and the inferred one go through it, so
    /// they cannot drift into different shapes.
    ///
    /// Above `supraThresholdReserve` each minute carries an extra weight on top
    /// of Banister's. His curve was fitted to blood lactate, and it is too gentle
    /// at the top for the quantity Garmin's recovery time is built on: EPOC
    /// climbs steeply once work is above threshold. Without it a parkrun 5k
    /// raced at 92% of reserve scored 15 hours, a third of what Garmin gives a
    /// race, while every session at or below 85% (the threshold hour, the
    /// interval anchors) is exactly where it was.
    static func trimpPerMinute(atReserve reserve: Double) -> Double {
        let r = min(max(reserve.isFinite ? reserve : 0, 0), 1)
        let supra = 1 + supraThresholdSlope * max(r - supraThresholdReserve, 0)
        return r * trimpWeightConstant * exp(trimpExponent * r) * supra
    }

    /// Where the extra weight above threshold starts, and how fast it grows:
    /// 1.56x at 92% of reserve, 2.2x at the maximum.
    static let supraThresholdReserve = 0.85
    static let supraThresholdSlope = 8.0

    // MARK: - Duration

    /// Minutes after which steady work below threshold stops accumulating at
    /// the full rate.
    static let steadyStateMinutes = 60.0

    /// The share of each minute past `steadyStateMinutes` that still counts, as
    /// a function of the fraction of heart-rate reserve it was done at.
    ///
    /// TRIMP is linear in duration, and EPOC (what Garmin's recovery time is
    /// derived from) is not. Below threshold, oxygen debt reaches a steady state
    /// within the first part of a session and an extra hour adds comparatively
    /// little; above it, the slow component keeps it climbing for as long as the
    /// effort lasts. Scored linearly, a three-hour zone-two ride cost more than a
    /// sixty-minute threshold run (59h against 38h for the reference athlete),
    /// where Garmin puts the ride in its long-session band (24-48h) and the
    /// threshold hour above it. Full weight from 80% of reserve, which is about
    /// where threshold sits, falling linearly to a floor of 0.4: a five-hour
    /// hike still costs more than a three-hour one.
    static func continuationWeight(atReserve reserve: Double) -> Double {
        let r = reserve.isFinite ? reserve : 0
        return min(max((r - 0.35) / 0.45, 0.4), 1)
    }

    /// Duration as it is costed: the first `steadyStateMinutes` in full, the
    /// rest at `continuationWeight`. Monotone in both arguments, so a longer or
    /// harder session can never score less.
    static func effectiveMinutes(_ minutes: Double, atReserve reserve: Double) -> Double {
        guard minutes > steadyStateMinutes else { return max(minutes, 0) }
        return steadyStateMinutes + (minutes - steadyStateMinutes) * continuationWeight(atReserve: reserve)
    }

    /// The session's duration as every load source costs it.
    ///
    /// Strength is exempt. Resistance work is not a steady aerobic state that
    /// plateaus, it is sets, and session-RPE (the scale its effort answers are
    /// on) is linear in duration by construction. Damping it would also let the
    /// sources disagree more than they already do, because the effort answer
    /// and the blind fallback sit at different intensities.
    static func costedMinutes(for session: SessionInput, atReserve reserve: Double) -> Double {
        session.profile == .strength
            ? session.durationMinutes
            : effectiveMinutes(session.durationMinutes, atReserve: reserve)
    }

    /// Heart-rate-reserve TRIMP. Needs an average heart rate, a resting figure,
    /// a max, and enough sample coverage to believe the average.
    ///
    /// When the session's time-in-zone distribution was imported it is costed
    /// minute by minute instead of from the average. Banister's weighting is
    /// convex, so an interval session (four minutes near the top, three easy,
    /// repeated) costs more than a steady session at the same average heart
    /// rate, which is the intervals-versus-steady behaviour Garmin users expect
    /// and the average alone cannot see.
    static func heartRateLoad(for session: SessionInput) -> SessionLoad? {
        guard session.durationMinutes > 0,
              let reserve = intensityFraction(for: session)
        else { return nil }

        let value = distributionLoad(for: session)
            ?? costedMinutes(for: session, atReserve: reserve) * trimpPerMinute(atReserve: reserve)
        return SessionLoad(
            value: value,
            source: .heartRate,
            heartRateCoverage: session.heartRateCoverage
        )
    }

    /// TRIMP summed over the time-in-zone distribution, scaled from the covered
    /// minutes to the whole session. Nil when there is no usable distribution,
    /// so the caller falls back to the average.
    static func distributionLoad(for session: SessionInput) -> Double? {
        guard let distribution = session.heartRateDistribution,
              distribution.totalSeconds > 0,
              session.durationMinutes > 0
        else { return nil }
        let resting = session.restingHeartRate ?? defaultRestingHeartRate
        let max = session.maxHeartRate ?? defaultMaxHeartRate
        guard resting.isFinite, max.isFinite, max > resting else { return nil }

        var covered = 0.0
        for (bpm, seconds) in distribution.buckets {
            let reserve = min(Swift.max((bpm - resting) / (max - resting), 0), 1)
            // Each minute keeps the continuation weight of the intensity it was
            // done at, so the easy half of an interval session is discounted
            // past the hour and the hard half never is.
            let weight = costedMinutes(for: session, atReserve: reserve) / session.durationMinutes
            covered += seconds / 60 * trimpPerMinute(atReserve: reserve) * weight
        }
        // The distribution covers the minutes the sensor saw. Scale to the
        // whole session, bounded so a sparse trace cannot more than double it.
        let scale = min(Swift.max(session.durationMinutes / (distribution.totalSeconds / 60), 0.5), 2)
        return covered * scale
    }

    static func reportedEffortLoad(for session: SessionInput) -> SessionLoad? {
        guard let effort = session.reportedEffort, session.durationMinutes > 0 else { return nil }
        return SessionLoad(
            value: costedMinutes(for: session, atReserve: effort / 10) * effort * effortToTrimpScale,
            source: .reportedEffort,
            heartRateCoverage: session.heartRateCoverage
        )
    }

    /// Infers the fraction of aerobic reserve the session sustained from its
    /// burn rate, then costs it on the same curve the measured path uses.
    ///
    /// The previous version mapped kilocalories per minute onto a perceived
    /// effort and then onto the effort scale, and the two curves had different
    /// shapes: it agreed with the heart-rate reading for a hard session and
    /// roughly doubled it for an easy one. That is how a 60-minute easy run
    /// scored *no countdown at all* with a good heart-rate trace and eighteen
    /// hours from the phone's calorie estimate alone — the same session, logged
    /// on two devices, disagreeing about whether it even happened.
    /// `RecoveryMatrixTests` found it by sweeping the sensor scenarios rather
    /// than reasoning about them.
    ///
    /// Estimating the same quantity the heart-rate path measures makes the two
    /// agree by construction for the reference adult. The residual that used to
    /// leave — it scaled with body mass, so a heavier person's calorie-derived
    /// sessions all read harder than they were — is now corrected directly from
    /// Health's own weight through `referenceEnergy(forBodyMass:)`. What is left
    /// is fitness: at the same reserve fraction a fitter person of the same mass
    /// burns more, and nothing in Health measures that closely enough to divide
    /// by. So this path still never rates better than low confidence on a
    /// session that can set a long window.
    ///
    /// There is no longer a strength-specific floor here. It was redundant:
    /// `strengthLoad` already takes the maximum against `durationLoad`, which
    /// is the same floor expressed once, in the place that documents why.
    static func energyLoad(for session: SessionInput) -> SessionLoad? {
        guard let energy = session.activeEnergyKilocalories,
              energy.isFinite,
              energy > 0,
              session.durationMinutes > 0
        else { return nil }

        let perMinute = energy / session.durationMinutes
        let reserve = min(
            max(perMinute / referenceEnergy(forBodyMass: session.bodyMassKilograms), 0),
            1
        )
        return SessionLoad(
            value: costedMinutes(for: session, atReserve: reserve) * trimpPerMinute(atReserve: reserve),
            source: .energy,
            heartRateCoverage: session.heartRateCoverage
        )
    }

    static func durationLoad(for session: SessionInput) -> SessionLoad {
        SessionLoad(
            value: costedMinutes(for: session, atReserve: session.profile.assumedEffort / 10)
                * session.profile.assumedEffort * effortToTrimpScale,
            source: .duration,
            heartRateCoverage: session.heartRateCoverage
        )
    }
}
