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
    public let profile: WorkoutProfile

    /// Below this many samples the percentile statistics are noise and the
    /// estimate is labelled as still building a baseline.
    public static let minimumSamples = 8

    /// Window of history the baseline is built from.
    public static let historyDays = 42

    public init(loads: [Double], profile: WorkoutProfile) {
        self.loads = loads.filter { $0 > 0 }.sorted()
        self.profile = profile
    }

    public var sampleCount: Int { loads.count }

    public var hasEnoughSamples: Bool { sampleCount >= Self.minimumSamples }

    /// What a typical session costs this person: their own median, shrunk
    /// toward the profile's population reference while the sample is still thin.
    ///
    /// The median alone was the whole story, and on a full history it still is —
    /// at `minimumSamples` and above this returns exactly `percentile(0.5)`.
    /// Below it, a median of three sessions is not a description of the person,
    /// it is a description of the three sessions the app happened to see, and
    /// every relative load is divided by it. `RecoveryMatrixTests` found what
    /// that does: a 24-year-old three sessions into using the app got 57 hours
    /// for an ordinary 60-minute lift, and a 66-year-old got the full 72-hour
    /// cap, because a moderate session is a large multiple of a small number.
    ///
    /// So personalisation earns its way in. The weight grows linearly with the
    /// sample count and the blend is geometric, which is the same shape
    /// `PersonalRecoveryModel` uses to fold evidence into the questionnaire
    /// prior: on day three the estimate is mostly the standard table, and by
    /// eight sessions it is entirely the person's own.
    public var typicalLoad: Double {
        guard !loads.isEmpty else { return profile.standardTypicalLoad }
        let personal = percentile(0.5)
        guard personal > 0 else { return profile.standardTypicalLoad }
        let weight = min(Double(sampleCount) / Double(Self.minimumSamples), 1)
        guard weight < 1 else { return personal }
        return exp(weight * log(personal) + (1 - weight) * log(profile.standardTypicalLoad))
    }

    /// The 25th percentile. Sessions below this (and below the absolute floor)
    /// do not start a countdown at all.
    public var quietThreshold: Double {
        guard hasEnoughSamples else { return RecoveryCalculator.absoluteCountdownFloor }
        return max(percentile(0.25), RecoveryCalculator.absoluteCountdownFloor)
    }

    /// Linear-interpolated percentile over the sorted sample.
    public func percentile(_ fraction: Double) -> Double {
        guard !loads.isEmpty else { return 0 }
        guard loads.count > 1 else { return loads[0] }
        let position = min(max(fraction, 0), 1) * Double(loads.count - 1)
        let lower = Int(position.rounded(.down))
        let upper = min(lower + 1, loads.count - 1)
        let weight = position - Double(lower)
        return loads[lower] + (loads[upper] - loads[lower]) * weight
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

        let inProfile = recent.filter { $0.profile == profile }.map(\.load)
        if inProfile.count >= minimumSamples {
            return RecoveryBaseline(loads: inProfile, profile: profile)
        }

        // Not enough same-profile history. Pooling across profiles is a worse
        // comparison but a much better one than the standard reference, so use
        // it whenever it clears the threshold.
        let pooled = recent.map(\.load)
        if pooled.count >= minimumSamples {
            return RecoveryBaseline(loads: pooled, profile: profile)
        }

        return RecoveryBaseline(loads: inProfile.isEmpty ? pooled : inProfile, profile: profile)
    }
}
