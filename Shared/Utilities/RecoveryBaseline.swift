import Foundation

/// Stage 2 of the model: what "normal" looks like for this person.
///
/// Everything is computed from their own recent sessions rather than a fixed
/// table, because a 60-minute threshold run is a routine Tuesday for one user
/// and the hardest thing they have done all month for another.
public struct RecoveryBaseline: Sendable, Equatable {
    /// Prior session loads for the profile being scored, most recent first is
    /// not required — the statistics are order-independent.
    public let loads: [Double]

    /// The same history totalled **by day**.
    ///
    /// This is what `typicalLoad` is built from, and separating the two is the
    /// fix for the worst inversion the model has had. Relative load asks "how
    /// big was this session against what this person is adapted to", and
    /// adaptation is a property of how much they train, not of how they slice
    /// it up. Somebody who rides three times a day was being described by the
    /// *median of one of those rides*, so their normal Tuesday read as five
    /// times normal and pinned the 72-hour ceiling — and every extra session
    /// they did made it worse, because it pulled the median further down.
    ///
    /// Totalled per day, three twenty-minute rides are one day of training,
    /// which is what they are. Frequency now raises the denominator instead of
    /// lowering it, so training more shortens the window, which is the direction
    /// the app claims everywhere else.
    ///
    /// `quietThreshold` deliberately stays on the per-session figures below:
    /// "was this session substantial enough to start a countdown" is a question
    /// about the session, not about the day it landed in.
    public let dailyLoads: [Double]

    public let profile: WorkoutProfile

    /// Below this many samples the percentile statistics are noise and the
    /// estimate is labelled as still building a baseline.
    public static let minimumSamples = 8

    /// Window of history the baseline is built from.
    public static let historyDays = 42

    /// - Parameter dailyLoads: the same history totalled by day. Defaults to the
    ///   session loads themselves, which is the right reading for a caller that
    ///   has no dates: one session per day is the assumption that changes
    ///   nothing.
    public init(loads: [Double], profile: WorkoutProfile, dailyLoads: [Double]? = nil) {
        let sessions = loads.filter { $0 > 0 }.sorted()
        self.loads = sessions
        self.dailyLoads = (dailyLoads ?? loads).filter { $0 > 0 }.sorted()
        self.profile = profile
    }

    public var sampleCount: Int { loads.count }

    /// Training days in the window. What `typicalLoad` is actually averaging
    /// over, and the honest sample size for it.
    public var dayCount: Int { dailyLoads.count }

    public var hasEnoughSamples: Bool { sampleCount >= Self.minimumSamples }

    /// What a typical training day costs this person: the **geometric mean** of
    /// their own daily loads, shrunk toward the profile's population reference
    /// while the sample is still thin.
    ///
    /// ### Why a geometric mean and not the median
    ///
    /// It was the median, and the median has a second version of the bug
    /// `dailyLoads` was introduced to fix. Totalling per day stopped a *frequent*
    /// trainer from being described by one of their short sessions. It does
    /// nothing for a *polarised* one, whose week is a lot of small days and two
    /// big ones: the middle day is small, so the median is small, and their real
    /// session still reads as a large multiple of "normal".
    ///
    /// The reported case is exactly this shape. Three short spins on most days
    /// and two hard rides a week is 647 load units a week against a population
    /// reference of 210 — genuinely high volume — but the median *day* is 57.5,
    /// which is **below** the reference day of 70. So the model called his
    /// ordinary hard ride twice his normal and gave him a longer window than the
    /// free tier would have. Training more still bought a longer window; the
    /// daily-total fix had only moved where it happened.
    ///
    /// A geometric mean is the honest central tendency for a quantity this
    /// skewed. Training loads are roughly log-normal, and for a log-normal
    /// sample the geometric mean *is* the median, so on an evenly distributed
    /// history this changes nothing measurable (a light user's 44.0 became
    /// 43.8). The two separate exactly when the distribution is skewed, which is
    /// the case we need noticed. And unlike an arithmetic mean it cannot be
    /// dragged around by one outlier: the log compresses a single three-hour
    /// ultra instead of letting it redefine what a normal day costs. The
    /// polarised rider's figure moves 57.5 to 75.2, and his hard ride from 35.9h
    /// to 24.6h, now below the 27.3h standard where it belongs.
    ///
    /// It is also the operation this file already performs one line further
    /// down, so both halves of the baseline now combine evidence the same way.
    ///
    /// ### Why it is shrunk
    ///
    /// This is the denominator of every relative load, so on a three-session
    /// history the whole model is dividing by a description of three sessions.
    /// `RecoveryMatrixTests` found what that does: a 24-year-old three days into
    /// using the app got 57 hours for an ordinary 60-minute lift, and a
    /// 66-year-old got the full 72-hour cap, because a moderate session is a
    /// large multiple of a small number.
    ///
    /// So personalisation earns its way in. The weight grows linearly with the
    /// day count and the blend is geometric, which is the same shape
    /// `PersonalRecoveryModel` uses to fold evidence into the questionnaire
    /// prior: on day three the estimate is mostly the standard table, and by
    /// eight training days it is entirely the person's own.
    public var typicalLoad: Double {
        guard !dailyLoads.isEmpty else { return profile.standardTypicalLoad }
        let personal = Self.geometricMean(of: dailyLoads)
        guard personal > 0 else { return profile.standardTypicalLoad }
        let weight = min(Double(dayCount) / Double(Self.minimumSamples), 1)
        guard weight < 1 else { return personal }
        return exp(weight * log(personal) + (1 - weight) * log(profile.standardTypicalLoad))
    }

    /// Geometric mean of a positive sample. Empty or non-positive input returns
    /// zero, which callers read as "no usable history".
    static func geometricMean(of sample: [Double]) -> Double {
        let positive = sample.filter { $0 > 0 }
        guard !positive.isEmpty else { return 0 }
        return exp(positive.reduce(0) { $0 + log($1) } / Double(positive.count))
    }

    /// The 25th percentile of individual **sessions**. Sessions below this (and
    /// below the absolute floor) do not start a countdown at all.
    ///
    /// Per-session on purpose, unlike `typicalLoad`. Whether a workout was
    /// substantial enough to be worth a countdown is a question about that
    /// workout; how big it was relative to what the person is used to is a
    /// question about their training. Running both off the daily totals would
    /// mean somebody who trains three times a day needs a single session as big
    /// as an average person's whole day before the app acknowledges it.
    public var quietThreshold: Double {
        guard hasEnoughSamples else { return RecoveryCalculator.absoluteCountdownFloor }
        return max(percentile(0.25), RecoveryCalculator.absoluteCountdownFloor)
    }

    /// Linear-interpolated percentile over the sorted per-session sample.
    public func percentile(_ fraction: Double) -> Double {
        Self.percentile(fraction, in: loads)
    }

    /// Linear-interpolated percentile over any sorted sample.
    static func percentile(_ fraction: Double, in sorted: [Double]) -> Double {
        guard !sorted.isEmpty else { return 0 }
        guard sorted.count > 1 else { return sorted[0] }
        let position = min(max(fraction, 0), 1) * Double(sorted.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, sorted.count - 1)
        let weight = position - Double(lower)
        return sorted[lower] + (sorted[upper] - sorted[lower]) * weight
    }

    /// The population reference the free tier scores against: no samples, so
    /// `typicalLoad` is the profile's standard reference and `quietThreshold` is
    /// the absolute floor.
    ///
    /// This is what makes the standard estimate the same for everyone. A given
    /// session type, length, and intensity produces the same number of hours
    /// whoever did it — which is the honest thing for a tier that has been told
    /// not to look at the person's history.
    public static func standard(for profile: WorkoutProfile) -> RecoveryBaseline {
        RecoveryBaseline(loads: [], profile: profile)
    }

    /// Builds a baseline for `profile` from a mixed history. Falls back to the
    /// whole history when the profile itself is too sparse, so a user's first
    /// ever HYROX session is still scored against something real.
    public static func build(
        from history: [(profile: WorkoutProfile, load: Double, date: Date)],
        for profile: WorkoutProfile,
        now: Date = .now,
        historyDays: Int = RecoveryBaseline.historyDays
    ) -> RecoveryBaseline {
        let cutoff = now.addingTimeInterval(-Double(historyDays) * 86_400)
        let recent = history.filter { $0.date >= cutoff && $0.profile != .easy }

        let inProfile = recent.filter { $0.profile == profile }
        if inProfile.count >= minimumSamples {
            return baseline(from: inProfile, for: profile)
        }

        // Not enough same-profile history. Pooling across profiles is a worse
        // comparison but a much better one than the standard reference, so use
        // it whenever it clears the threshold.
        if recent.count >= minimumSamples {
            return baseline(from: recent, for: profile)
        }

        return baseline(from: inProfile.isEmpty ? recent : inProfile, for: profile)
    }

    /// Sessions and their per-day totals, which are the two different questions
    /// `quietThreshold` and `typicalLoad` ask.
    private static func baseline(
        from entries: [(profile: WorkoutProfile, load: Double, date: Date)],
        for profile: WorkoutProfile
    ) -> RecoveryBaseline {
        var byDay: [String: Double] = [:]
        for entry in entries {
            byDay[DateHelpers.dayKey(for: entry.date), default: 0] += entry.load
        }
        return RecoveryBaseline(
            loads: entries.map(\.load),
            profile: profile,
            dailyLoads: Array(byDay.values)
        )
    }
}
