import Foundation

/// The fixture set from the dossier's phase-1 list, extended per profile.
///
/// Every case is a real shape a user's Health store produces, including the ones
/// that break the model's preferred input: a lifting session where the optical
/// sensor lost the signal, a HYROX session that is neither cardio nor strength,
/// duplicate imports, and a brand-new user with no history at all.
enum RecoveryFixtures {

    /// Fixed clock so every expectation is deterministic.
    static let now = Date(timeIntervalSince1970: 1_770_000_000)

    static func session(
        id: String,
        profile: WorkoutProfile,
        minutes: Double,
        endedMinutesAgo: Double = 0,
        averageHR: Double? = nil,
        restingHR: Double? = 52,
        maxHR: Double? = 188,
        coverage: Double = 0,
        energy: Double? = nil,
        effort: Double? = nil,
        label: String = "workout"
    ) -> SessionInput {
        let end = now.addingTimeInterval(-endedMinutesAgo * 60)
        return SessionInput(
            id: id,
            profile: profile,
            startDate: end.addingTimeInterval(-minutes * 60),
            endDate: end,
            durationMinutes: minutes,
            averageHeartRate: averageHR,
            restingHeartRate: restingHR,
            maxHeartRate: maxHR,
            heartRateCoverage: coverage,
            activeEnergyKilocalories: energy,
            reportedEffort: effort,
            activityLabel: label
        )
    }

    // MARK: - The named fixtures

    static var easyWalk30: SessionInput {
        session(id: "walk-30", profile: .easy, minutes: 30, averageHR: 92,
                coverage: 0.95, energy: 110, label: "walk")
    }

    static var easyRun45: SessionInput {
        session(id: "run-45-easy", profile: .endurance, minutes: 45, averageHR: 134,
                coverage: 0.97, energy: 430, label: "run")
    }

    static var thresholdRun60: SessionInput {
        session(id: "run-60-threshold", profile: .endurance, minutes: 60, averageHR: 165,
                coverage: 0.98, energy: 680, label: "run")
    }

    static var longRun90: SessionInput {
        session(id: "run-90-long", profile: .endurance, minutes: 90, averageHR: 148,
                coverage: 0.96, energy: 920, label: "run")
    }

    static var ride45: SessionInput {
        session(id: "ride-45", profile: .endurance, minutes: 45, averageHR: 142,
                coverage: 0.94, energy: 480, label: "ride")
    }

    /// The case the RPE prompt exists for: grip and bar contact kill the optical
    /// signal, so coverage is far under the TRIMP threshold.
    static var strengthNoHeartRate: SessionInput {
        session(id: "lift-60", profile: .strength, minutes: 60, averageHR: 108,
                coverage: 0.18, energy: 300, label: "lifting session")
    }

    /// The same session once the user answers the one-tap effort question.
    static var strengthWithEffort: SessionInput {
        session(id: "lift-60-rpe", profile: .strength, minutes: 60, averageHR: 108,
                coverage: 0.18, energy: 300, effort: 8, label: "lifting session")
    }

    /// HYROX-style: partial heart-rate coverage plus a high reported effort.
    static var mixedHyrox: SessionInput {
        session(id: "hyrox-70", profile: .mixed, minutes: 70, averageHR: 158,
                coverage: 0.72, energy: 760, effort: 9, label: "functional session")
    }

    /// Same workout imported twice — different UUIDs, identical everything else.
    static var duplicateA: SessionInput {
        session(id: "dupe-a", profile: .endurance, minutes: 50, averageHR: 150,
                coverage: 0.95, energy: 520, label: "run")
    }

    static var duplicateB: SessionInput {
        session(id: "dupe-b", profile: .endurance, minutes: 50, averageHR: 150,
                coverage: 0.95, energy: 520, label: "run")
    }

    /// Two sessions whose intervals overlap (a phone-logged run inside a
    /// watch-logged one).
    static var overlappingOuter: SessionInput {
        session(id: "overlap-outer", profile: .endurance, minutes: 60, endedMinutesAgo: 0,
                averageHR: 150, coverage: 0.95, energy: 600, label: "run")
    }

    static var overlappingInner: SessionInput {
        session(id: "overlap-inner", profile: .endurance, minutes: 40, endedMinutesAgo: 5,
                averageHR: 152, coverage: 0.9, energy: 410, label: "run")
    }

    // MARK: - Baselines

    /// A settled user: twelve endurance sessions spanning easy to hard.
    static func settledEnduranceBaseline() -> RecoveryBaseline {
        RecoveryBaseline(
            loads: [28, 34, 41, 47, 52, 58, 63, 68, 74, 86, 102, 131],
            profile: .endurance
        )
    }

    static func settledStrengthBaseline() -> RecoveryBaseline {
        RecoveryBaseline(
            loads: [70, 78, 84, 90, 96, 104, 112, 120, 132, 148],
            profile: .strength
        )
    }

    static func settledMixedBaseline() -> RecoveryBaseline {
        RecoveryBaseline(
            loads: [95, 108, 116, 124, 133, 141, 152, 168, 181, 205],
            profile: .mixed
        )
    }

    /// A brand-new user: no history at all.
    static func emptyBaseline(_ profile: WorkoutProfile = .endurance) -> RecoveryBaseline {
        RecoveryBaseline(loads: [], profile: profile)
    }

    /// Enough to compute something, not enough to trust it.
    static func thinBaseline(_ profile: WorkoutProfile = .endurance) -> RecoveryBaseline {
        RecoveryBaseline(loads: [45, 60, 72], profile: profile)
    }

    // MARK: - Contexts

    static let noContext = RecoveryContext.empty

    static let goodContext = RecoveryContext(
        sleepHours: 8.2,
        heartRateVariability: 74,
        heartRateVariabilityBaseline: 62,
        restingHeartRate: 49,
        restingHeartRateBaseline: 52
    )

    static let poorContext = RecoveryContext(
        sleepHours: 4.6,
        heartRateVariability: 44,
        heartRateVariabilityBaseline: 62,
        restingHeartRate: 59,
        restingHeartRateBaseline: 52
    )

    /// Sleep present, everything else missing — the common real-world shape.
    static let partialContext = RecoveryContext(sleepHours: 7.8)
}
