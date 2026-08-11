import Foundation

/// The Recharge+ half of the model: what the last thirty days say about how
/// *this* person recovers, expressed as one bounded multiplier on the standard
/// window.
///
/// The standard model answers "how much did that session cost". This answers
/// "how fast does this person pay it back", which is the part no fixed table can
/// know. Three independent lines of evidence, each computed from data the app
/// already imports:
///
/// | Signal | What it observes | Why it is believable |
/// |---|---|---|
/// | Rebound | How much of the day-after disturbance in resting heart rate and HRV is still there on day two | The closest thing to a direct measurement of individual recovery kinetics that a wrist sensor can produce |
/// | Tolerance | Whether sessions started *inside* a predicted window held their intensity | Revealed preference: what actually happened when they trained through it |
/// | Density | Chronic weekly load against a population reference | The classic activity-class adjustment; someone doing 500 load-units a week is adapted to a shorter turnaround than someone doing 150 |
///
/// Each is a mild multiplier. They are blended with the onboarding prior on a
/// weight that grows with the amount of evidence, so a Recharge+ user gets a
/// personalised number on day one from their answers and a progressively more
/// earned one as the weeks accumulate.
///
/// Pure and `Sendable`. No HealthKit, no SwiftData, no clock of its own.
///
/// This is a cardiovascular training estimate. None of it measures tissue
/// repair, illness, or injury risk.
public enum PersonalRecoveryModel {

    // MARK: - Bounds

    /// The window the analysis is built from. Long enough to hold a training
    /// block, short enough that it tracks the person they are now.
    public static let windowDays = 30

    /// Hard bounds on the personal factor. A 30% swing either way is already a
    /// day's difference on a two-day window; anything wider is the model
    /// asserting more than three signals can support.
    public static let minimumFactor = 0.72
    public static let maximumFactor = 1.32

    /// Evidence needed before a signal is used at all.
    static let minimumReboundSamples = 3
    static let minimumToleranceSamples = 3

    /// Evidence count at which history has taken over from the questionnaire as
    /// far as it ever will.
    static let saturationSamples = 12.0

    /// The ceiling on how much of the blend evidence may claim. The prior is
    /// never fully discarded: it carries age, which nothing in the history can
    /// observe.
    static let maximumEvidenceWeight = 0.70

    /// Population reference for weekly load, in the same units as
    /// `SessionLoadCalculator`. Three endurance sessions at the standard typical
    /// load.
    static let referenceWeeklyLoad = 3 * WorkoutProfile.endurance.standardTypicalLoad

    // MARK: - Inputs

    /// One scored session, as the analysis needs to see it.
    public struct HistorySession: Sendable, Equatable {
        public let id: String
        public let profile: WorkoutProfile
        public let endDate: Date
        public let load: Double
        /// Fraction of heart-rate reserve sustained, when the session had usable
        /// heart-rate coverage. The intensity-held check needs a comparable
        /// quality measure, and reserve fraction is the only one that survives
        /// across sports.
        public let intensityFraction: Double?
        /// Hours the *standard* model gave this session. Used to ask whether the
        /// next session started inside the window or after it.
        public let standardHours: Double

        public init(
            id: String,
            profile: WorkoutProfile,
            endDate: Date,
            load: Double,
            intensityFraction: Double? = nil,
            standardHours: Double
        ) {
            self.id = id
            self.profile = profile
            self.endDate = endDate
            self.load = load
            self.intensityFraction = intensityFraction
            self.standardHours = standardHours
        }
    }

    /// One day of overnight context.
    public struct DayPoint: Sendable, Equatable {
        public let date: Date
        public let restingHeartRate: Double?
        public let heartRateVariability: Double?

        public init(date: Date, restingHeartRate: Double? = nil, heartRateVariability: Double? = nil) {
            self.date = date
            self.restingHeartRate = restingHeartRate
            self.heartRateVariability = heartRateVariability
        }
    }

    // MARK: - Output

    /// The analysis, kept whole rather than collapsed to a number, because the
    /// Recharge+ screens have to be able to say *why* the window moved.
    public struct Analysis: Sendable, Equatable {
        public let factor: Double
        public let prior: Double?
        public let reboundFactor: Double?
        public let reboundSamples: Int
        public let toleranceFactor: Double?
        public let toleranceSamples: Int
        public let densityFactor: Double?
        public let weeklyLoad: Double
        public let sessionsPerWeek: Double
        public let qualifyingSessions: Int
        /// How much of the blend came from observed history, 0...1.
        public let evidenceWeight: Double

        public init(
            factor: Double,
            prior: Double?,
            reboundFactor: Double?,
            reboundSamples: Int,
            toleranceFactor: Double?,
            toleranceSamples: Int,
            densityFactor: Double?,
            weeklyLoad: Double,
            sessionsPerWeek: Double,
            qualifyingSessions: Int,
            evidenceWeight: Double
        ) {
            self.factor = factor
            self.prior = prior
            self.reboundFactor = reboundFactor
            self.reboundSamples = reboundSamples
            self.toleranceFactor = toleranceFactor
            self.toleranceSamples = toleranceSamples
            self.densityFactor = densityFactor
            self.weeklyLoad = weeklyLoad
            self.sessionsPerWeek = sessionsPerWeek
            self.qualifyingSessions = qualifyingSessions
            self.evidenceWeight = evidenceWeight
        }

        public static let neutral = Analysis(
            factor: 1,
            prior: nil,
            reboundFactor: nil,
            reboundSamples: 0,
            toleranceFactor: nil,
            toleranceSamples: 0,
            densityFactor: nil,
            weeklyLoad: 0,
            sessionsPerWeek: 0,
            qualifyingSessions: 0,
            evidenceWeight: 0
        )

        /// True when the analysis is doing anything at all.
        public var isPersonalised: Bool { prior != nil || evidenceWeight > 0 }

        /// Shorter than standard, longer than standard, or the same.
        public var direction: Direction {
            if factor <= 0.97 { return .shorter }
            if factor >= 1.03 { return .longer }
            return .similar
        }

        public enum Direction: Sendable { case shorter, similar, longer }

        /// Percentage difference from the standard window, rounded for display.
        public var percentDifference: Int { Int(((factor - 1) * 100).rounded()) }
    }

    // MARK: - Entry point

    /// Builds the analysis for one person.
    ///
    /// - Parameters:
    ///   - profile: the onboarding answers and whatever Health supplied. Used as
    ///     the prior, and as the whole answer while history is thin.
    ///   - sessions: scored sessions, any order. Only the ones inside the window
    ///     are used.
    ///   - days: overnight context, any order.
    ///   - now: the calculation instant. Injected so tests are deterministic.
    public static func analyse(
        profile: AthleteProfile,
        sessions: [HistorySession],
        days: [DayPoint],
        now: Date = .now
    ) -> Analysis {
        let cutoff = now.addingTimeInterval(-Double(windowDays) * 86_400)
        let window = sessions
            .filter { $0.endDate >= cutoff && $0.endDate <= now && $0.profile != .easy }
            .sorted { $0.endDate < $1.endDate }

        let weeklyLoad = window.reduce(0) { $0 + $1.load } / (Double(windowDays) / 7)
        let sessionsPerWeek = Double(window.count) / (Double(windowDays) / 7)

        let rebound = reboundEvidence(sessions: window, days: days)
        let tolerance = toleranceEvidence(sessions: window)
        let density = window.count >= 4 ? densityFactor(weeklyLoad: weeklyLoad) : nil

        // Density is a weaker inference than the other two — it says what the
        // person trains, not how they respond — so it is capped at a third of
        // the sample weight the observed signals can reach.
        var weighted: [(factor: Double, weight: Double)] = []
        if let value = rebound.factor { weighted.append((value, Double(rebound.samples))) }
        if let value = tolerance.factor { weighted.append((value, Double(tolerance.samples))) }
        if let value = density { weighted.append((value, min(Double(window.count), saturationSamples / 3))) }

        let prior = profile.prior
        let totalWeight = weighted.reduce(0) { $0 + $1.weight }

        guard totalWeight > 0 else {
            // Nothing observed yet. The questionnaire is the whole answer, which
            // is exactly what it is for.
            return Analysis(
                factor: clamp(prior ?? 1),
                prior: prior,
                reboundFactor: nil,
                reboundSamples: rebound.samples,
                toleranceFactor: nil,
                toleranceSamples: tolerance.samples,
                densityFactor: nil,
                weeklyLoad: weeklyLoad,
                sessionsPerWeek: sessionsPerWeek,
                qualifyingSessions: window.count,
                evidenceWeight: 0
            )
        }

        let evidence = geometricMean(weighted)
        let evidenceWeight = min(totalWeight / saturationSamples, 1) * maximumEvidenceWeight

        // Geometric blend: these are multipliers, so they interpolate on the log
        // scale. An arithmetic blend of 0.8 and 1.25 is 1.025, which is not the
        // midpoint between "20% faster" and "25% slower".
        let blended: Double
        if let prior {
            blended = exp(log(prior) * (1 - evidenceWeight) + log(evidence) * evidenceWeight)
        } else {
            blended = evidence
        }

        return Analysis(
            factor: clamp(blended),
            prior: prior,
            reboundFactor: rebound.factor,
            reboundSamples: rebound.samples,
            toleranceFactor: tolerance.factor,
            toleranceSamples: tolerance.samples,
            densityFactor: density,
            weeklyLoad: weeklyLoad,
            sessionsPerWeek: sessionsPerWeek,
            qualifyingSessions: window.count,
            evidenceWeight: prior == nil ? 1 : evidenceWeight
        )
    }

    // MARK: - Signal 1: rebound

    /// How much of the day-after physiological disturbance is still present on
    /// day two.
    ///
    /// For each hard session, the day-one departure from the person's own
    /// baseline is measured in resting heart rate (elevated) and HRV
    /// (depressed), then compared with the same departure on day two. The ratio
    /// is what varies between people: a fast responder is most of the way back
    /// within a day, a slow one is barely moved.
    ///
    /// Sessions with no measurable day-one disturbance count as fast responses
    /// rather than being dropped — "the hard session did not move my resting
    /// heart rate at all" is information, and dropping it would bias the sample
    /// toward the sessions that did.
    static func reboundEvidence(
        sessions: [HistorySession],
        days: [DayPoint]
    ) -> (factor: Double?, samples: Int) {
        guard !sessions.isEmpty, !days.isEmpty else { return (nil, 0) }

        let byDay = Dictionary(
            days.map { (DateHelpers.dayKey(for: $0.date), $0) },
            uniquingKeysWith: { first, _ in first }
        )
        let restingBaseline = median(days.compactMap(\.restingHeartRate).filter { $0 > 0 })
        let hrvBaseline = median(days.compactMap(\.heartRateVariability).filter { $0 > 0 })
        guard restingBaseline != nil || hrvBaseline != nil else { return (nil, 0) }

        // Only sessions at or above the person's own median load disturb
        // anything measurably, and a ratio taken on noise is noise.
        let loadThreshold = median(sessions.map(\.load)) ?? 0

        var ratios: [Double] = []
        for session in sessions where session.load >= loadThreshold {
            let dayOne = byDay[DateHelpers.dayKey(for: session.endDate.addingTimeInterval(86_400))]
            let dayTwo = byDay[DateHelpers.dayKey(for: session.endDate.addingTimeInterval(2 * 86_400))]
            guard let dayOne, let dayTwo else { continue }

            var sessionRatios: [Double] = []
            if let baseline = restingBaseline, baseline > 0,
               let first = dayOne.restingHeartRate, first > 0,
               let second = dayTwo.restingHeartRate, second > 0 {
                sessionRatios.append(
                    normalisationRatio(day1: (first - baseline) / baseline, day2: (second - baseline) / baseline)
                )
            }
            if let baseline = hrvBaseline, baseline > 0,
               let first = dayOne.heartRateVariability, first > 0,
               let second = dayTwo.heartRateVariability, second > 0 {
                // HRV moves the other way: recovery is a *depression* that lifts.
                sessionRatios.append(
                    normalisationRatio(day1: (baseline - first) / baseline, day2: (baseline - second) / baseline)
                )
            }
            guard !sessionRatios.isEmpty else { continue }
            ratios.append(sessionRatios.reduce(0, +) / Double(sessionRatios.count))
        }

        guard ratios.count >= minimumReboundSamples else { return (nil, ratios.count) }
        let mean = ratios.reduce(0, +) / Double(ratios.count)
        // 0 (fully normalised by day two) maps to a 15% shorter window; 1 (no
        // recovery at all in the second day) to 30% longer.
        return (0.85 + 0.45 * min(max(mean, 0), 1), ratios.count)
    }

    /// The share of a day-one disturbance still present on day two, clamped to
    /// 0...1. A day-one reading at or below baseline is treated as a complete
    /// response, not as a negative disturbance to divide by.
    static func normalisationRatio(day1: Double, day2: Double) -> Double {
        // Below this the session did not move the signal at all, and the
        // division would amplify sensor noise into a recovery verdict.
        let noiseFloor = 0.01
        guard day1 > noiseFloor else { return 0 }
        return min(max(day2 / day1, 0), 1)
    }

    // MARK: - Signal 2: tolerance

    /// What happened when the person trained again before the standard window
    /// closed.
    ///
    /// Revealed preference beats self-report. If someone repeatedly starts a
    /// session eighteen hours into a thirty-hour window and holds their usual
    /// intensity, the thirty hours were too long *for them*. If their intensity
    /// falls away, it was not.
    ///
    /// Only sessions with a usable intensity measurement take part. A session
    /// that merely *happened* early proves nothing: people train tired.
    static func toleranceEvidence(sessions: [HistorySession]) -> (factor: Double?, samples: Int) {
        guard sessions.count >= 2 else { return (nil, 0) }

        // Per-profile reference intensity, so a strength session is compared
        // with strength sessions rather than with intervals.
        var byProfile: [WorkoutProfile: [Double]] = [:]
        for session in sessions {
            guard let intensity = session.intensityFraction, intensity > 0 else { continue }
            byProfile[session.profile, default: []].append(intensity)
        }
        let reference = byProfile.compactMapValues { median($0) }

        var samples: [Double] = []
        for (previous, next) in zip(sessions, sessions.dropFirst()) {
            guard previous.standardHours > 0,
                  let intensity = next.intensityFraction, intensity > 0,
                  let usual = reference[next.profile], usual > 0
            else { continue }

            let elapsedHours = next.endDate.timeIntervalSince(previous.endDate) / 3600
            let fraction = elapsedHours / previous.standardHours
            // Only sessions started inside the window say anything about
            // tolerance. Beyond it, holding intensity is unremarkable.
            guard fraction > 0, fraction < 1 else { continue }

            let held = intensity / usual
            if held >= 0.95 {
                // Held up, and the earlier it was the more it says.
                samples.append(0.85 + 0.15 * fraction)
            } else if held < 0.85 {
                samples.append(1.10 + 0.10 * (1 - fraction))
            } else {
                samples.append(1.0)
            }
        }

        guard samples.count >= minimumToleranceSamples else { return (nil, samples.count) }
        return (samples.reduce(0, +) / Double(samples.count), samples.count)
    }

    // MARK: - Signal 3: density

    /// Chronic weekly load against a population reference, on a log scale so
    /// doubling the weekly load and halving it move the factor by the same
    /// amount in opposite directions.
    static func densityFactor(weeklyLoad: Double) -> Double? {
        guard weeklyLoad > 0 else { return nil }
        let doublings = log2(weeklyLoad / referenceWeeklyLoad)
        return min(max(1 - 0.10 * doublings, 0.90), 1.10)
    }

    // MARK: - Explanation

    /// The lines a Recharge+ screen may use to explain the difference. Same
    /// compliance rules as `RecoveryCalculator.reasons`: no "recovered", no
    /// "safe to train", no claim about the body.
    public static func summary(_ analysis: Analysis) -> [String] {
        guard analysis.isPersonalised else { return [] }
        var lines: [String] = []

        switch analysis.direction {
        case .shorter:
            lines.append("Your windows run about \(abs(analysis.percentDifference))% shorter than the standard estimate.")
        case .longer:
            lines.append("Your windows run about \(analysis.percentDifference)% longer than the standard estimate.")
        case .similar:
            lines.append("Your windows land close to the standard estimate.")
        }

        if let rebound = analysis.reboundFactor, analysis.reboundSamples >= minimumReboundSamples {
            let count = analysis.reboundSamples
            lines.append(
                rebound < 1
                    ? "Resting heart rate and HRV settle back quickly after your hard sessions (\(count) measured)."
                    : "Resting heart rate and HRV take their time settling after your hard sessions (\(count) measured)."
            )
        }

        if let tolerance = analysis.toleranceFactor, analysis.toleranceSamples >= minimumToleranceSamples {
            lines.append(
                tolerance < 1
                    ? "You have held your usual intensity training inside the estimated window."
                    : "Sessions you started inside the window came in below your usual intensity."
            )
        }

        if analysis.qualifyingSessions > 0 {
            let perWeek = String(format: "%.1f", analysis.sessionsPerWeek)
            lines.append("Based on \(analysis.qualifyingSessions) sessions in the last \(windowDays) days, about \(perWeek) a week.")
        }

        return lines
    }

    // MARK: - Helpers

    static func clamp(_ value: Double) -> Double {
        min(max(value, minimumFactor), maximumFactor)
    }

    private static func geometricMean(_ items: [(factor: Double, weight: Double)]) -> Double {
        let totalWeight = items.reduce(0) { $0 + $1.weight }
        guard totalWeight > 0 else { return 1 }
        let logSum = items.reduce(0) { $0 + log(max($1.factor, 0.01)) * $1.weight }
        return exp(logSum / totalWeight)
    }

    private static func median(_ values: [Double]) -> Double? {
        guard !values.isEmpty else { return nil }
        let sorted = values.sorted()
        let middle = sorted.count / 2
        if sorted.count % 2 == 0 { return (sorted[middle - 1] + sorted[middle]) / 2 }
        return sorted[middle]
    }
}
