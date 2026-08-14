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
    public static func profiledLoad(for session: SessionInput) -> SessionLoad {
        switch session.profile {
        case .strength: strengthLoad(for: session)
        case .mixed: mixedLoad(for: session)
        case .endurance, .easy: load(for: session)
        }
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
              average > 0
        else { return nil }

        let resting = session.restingHeartRate ?? defaultRestingHeartRate
        let max = session.maxHeartRate ?? defaultMaxHeartRate
        guard max > resting else { return nil }
        return min(Swift.max((average - resting) / (max - resting), 0), 1)
    }

    /// Heart-rate-reserve TRIMP. Needs an average heart rate, a resting figure,
    /// a max, and enough sample coverage to believe the average.
    static func heartRateLoad(for session: SessionInput) -> SessionLoad? {
        guard session.durationMinutes > 0,
              let reserve = intensityFraction(for: session)
        else { return nil }

        let weighted = reserve * trimpWeightConstant * exp(trimpExponent * reserve)
        return SessionLoad(
            value: session.durationMinutes * weighted,
            source: .heartRate,
            heartRateCoverage: session.heartRateCoverage
        )
    }

    static func reportedEffortLoad(for session: SessionInput) -> SessionLoad? {
        guard let effort = session.reportedEffort, session.durationMinutes > 0 else { return nil }
        return SessionLoad(
            value: session.durationMinutes * effort * effortToTrimpScale,
            source: .reportedEffort,
            heartRateCoverage: session.heartRateCoverage
        )
    }

    /// Infers an effort from the burn rate. Deliberately conservative for
    /// strength work, where kcal/min under-reads what the session actually
    /// cost — which is the whole reason the RPE prompt exists.
    static func energyLoad(for session: SessionInput) -> SessionLoad? {
        guard let energy = session.activeEnergyKilocalories,
              energy > 0,
              session.durationMinutes > 0
        else { return nil }

        let perMinute = energy / session.durationMinutes
        var inferredEffort = min(max(2 + (perMinute - 3) * 0.6, 1), 10)
        // The burn rate of resistance work is low for reasons that have nothing
        // to do with how hard it was, so for the profiles that raise the effort
        // prompt the inference is floored at what the session type usually
        // costs. Without this a 60-minute lift infers an effort of 2.8 out of
        // 10, which is not conservative, it is wrong.
        if session.profile == .strength {
            inferredEffort = max(inferredEffort, session.profile.assumedEffort)
        }
        return SessionLoad(
            value: session.durationMinutes * inferredEffort * effortToTrimpScale,
            source: .energy,
            heartRateCoverage: session.heartRateCoverage
        )
    }

    static func durationLoad(for session: SessionInput) -> SessionLoad {
        SessionLoad(
            value: session.durationMinutes * session.profile.assumedEffort * effortToTrimpScale,
            source: .duration,
            heartRateCoverage: session.heartRateCoverage
        )
    }
}
