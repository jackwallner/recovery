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

    /// Median session load, or the profile's bootstrap value when the user has
    /// no usable history yet.
    public var typicalLoad: Double {
        guard !loads.isEmpty else { return profile.bootstrapTypicalLoad }
        return percentile(0.5)
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
        // comparison but a much better one than the bootstrap constant, so use
        // it whenever it clears the threshold.
        let pooled = recent.map(\.load)
        if pooled.count >= minimumSamples {
            return RecoveryBaseline(loads: pooled, profile: profile)
        }

        return RecoveryBaseline(loads: inProfile.isEmpty ? pooled : inProfile, profile: profile)
    }
}
