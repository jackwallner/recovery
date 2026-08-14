import Foundation

// MARK: - Model version

/// Bumped whenever the calculator's numbers change. Stored on every estimate so
/// history can explain why an old window disagrees with what the same session
/// would produce today, and so the determinism test has something to pin to.
///
/// 2: the standard/personalized split. Version 1 scored every user against their
/// own median session; the free tier now scores against a fixed population
/// reference, and Recharge+ adds `PersonalRecoveryModel` on top.
public let recoveryModelVersion = 2

// MARK: - Tier

/// Which of the two models produced an estimate.
///
/// Stored on every estimate, because the two answer subtly different questions
/// and a history list that mixes them without saying so is lying by omission.
public enum RecoveryTier: String, Codable, Sendable {
    /// The same table for everyone: session type, duration, and intensity in,
    /// hours out. No personal history, no overnight context, no calibration.
    case standard
    /// The person's own baseline, their thirty-day recovery analysis, overnight
    /// context, and their calibration feedback.
    case personalized

    public var label: String {
        switch self {
        case .standard: "Standard"
        case .personalized: "Personalized"
        }
    }
}

/// The Recharge+ multiplier, carried into the calculator as one value so the
/// calculator itself stays free of any notion of entitlement.
public struct RecoveryPersonalization: Sendable, Equatable {
    public let tier: RecoveryTier
    /// Multiplier on the standard window. Exactly 1 for `.standard`.
    public let factor: Double

    public static let standard = RecoveryPersonalization(tier: .standard, factor: 1)

    public static func personalized(factor: Double) -> RecoveryPersonalization {
        RecoveryPersonalization(tier: .personalized, factor: PersonalRecoveryModel.clamp(factor))
    }

    private init(tier: RecoveryTier, factor: Double) {
        self.tier = tier
        self.factor = factor
    }
}

// MARK: - Profiles

/// The four recovery curves. A session is classified into exactly one; the load
/// source and the shape of the decay both depend on which.
public enum WorkoutProfile: String, Codable, CaseIterable, Sendable {
    /// Run, ride, row, swim. Heart-rate reserve TRIMP is reliable here.
    case endurance
    /// Lifting. Optical HR is unreliable under grip and bar contact, so this
    /// leans on perceived effort; longer tail than endurance at equal effort.
    case strength
    /// HYROX, CrossFit, circuits. Both systems taxed, so the longest window.
    case mixed
    /// Walk, yoga, mobility. Contributes nothing and never starts or extends a
    /// countdown.
    case easy

    public var label: String {
        switch self {
        case .endurance: "Endurance"
        case .strength: "Strength"
        case .mixed: "Mixed"
        case .easy: "Easy"
        }
    }

    /// Recovery-window multiplier relative to the endurance baseline curve.
    /// `easy` is zero because an active-recovery session must never produce a
    /// countdown at all.
    public var windowMultiplier: Double {
        switch self {
        case .endurance: 1.0
        case .strength: 1.15
        case .mixed: 1.30
        case .easy: 0.0
        }
    }

    /// Perceived effort assumed when a session has neither usable heart rate nor
    /// energy data. Deliberately mid-range: enough to register, not enough to
    /// dominate a countdown on a guess.
    public var assumedEffort: Double {
        switch self {
        case .endurance: 5
        case .strength: 6
        case .mixed: 7
        case .easy: 2
        }
    }

    /// The population reference a session is measured against when there is no
    /// personal history to use: the whole of the standard tier, and the
    /// bootstrap for a Recharge+ user in their first few weeks.
    ///
    /// Each is one moderately trained adult's typical session, put through
    /// `SessionLoadCalculator` rather than picked:
    ///
    /// | Profile | Reference session | Load |
    /// |---|---|---|
    /// | endurance | 50 min at 70% heart-rate reserve | ~86 |
    /// | strength | 55 min at RPE 6.5 | ~107 |
    /// | mixed | 50 min at RPE 7.5 | ~113 |
    ///
    /// These were 70 / 80 / 95, which were only ever meant to keep a first-ever
    /// workout from dividing by zero. Load-bearing for every free user, they put
    /// a routine 45-minute run at 0.79 of "typical" and both a 60-minute
    /// threshold run and a 90-minute steady run at 2.25 — far enough up the
    /// curve that two quite different sessions clipped to the same 42-hour
    /// window. Raising the reference to a real typical session is what puts the
    /// interesting range back in the middle of the curve, where it can separate
    /// them.
    public var standardTypicalLoad: Double {
        switch self {
        case .endurance: 85
        case .strength: 105
        case .mixed: 115
        case .easy: 20
        }
    }

    /// True when perceived effort is worth asking the user for. Strength and
    /// mixed sessions are exactly the ones heart rate gets wrong.
    public var wantsEffortInput: Bool {
        self == .strength || self == .mixed
    }
}

// MARK: - Load

/// Which of the three fallbacks actually produced the session load. Drives both
/// the confidence rating and the "why" copy.
public enum LoadSource: String, Codable, Sendable {
    /// Heart-rate-reserve TRIMP from in-workout heart-rate samples.
    case heartRate
    /// User-reported effort (session RPE).
    case reportedEffort
    /// Duration + active energy, with an intensity inferred from the burn rate.
    case energy
    /// Duration and profile only. Weakest signal we will act on.
    case duration

    public var label: String {
        switch self {
        case .heartRate: "heart rate"
        case .reportedEffort: "your effort rating"
        case .energy: "duration and energy"
        case .duration: "duration"
        }
    }
}

/// One session scored both ways: the standard window beside the personalized
/// one. What every Recharge+ conversion surface argues from.
///
/// The two figures are always computed, never derived by multiplying the
/// standard hours by the thirty-day factor. Personalisation changes the
/// *baseline* a session is measured against as well as applying the multiplier,
/// and the derived version dropped the larger of the two effects.
public struct PersonalizedPreview: Sendable, Equatable {
    public let label: String
    public let standardHours: Double
    public let personalizedHours: Double
    /// True when there was no qualifying session to use and the figures come
    /// from the canonical hard endurance session instead. Surfaces have to say
    /// so: "for example" is the difference between a projection and a claim
    /// about the user's own training.
    public let isExample: Bool

    public init(label: String, standardHours: Double, personalizedHours: Double, isExample: Bool) {
        self.label = label
        self.standardHours = standardHours
        self.personalizedHours = personalizedHours
        self.isExample = isExample
    }

    /// The fallback for a user with no qualifying session yet: a real point on
    /// the real curve, so even day one shows arithmetic rather than a mock-up.
    public static func reference(factor: Double) -> PersonalizedPreview {
        let hours = RecoveryCalculator.referenceHardSessionHours
        return PersonalizedPreview(
            label: "A hard 60-minute session",
            standardHours: hours,
            personalizedHours: hours * factor,
            isExample: true
        )
    }

    /// Whether the two figures would render as the same string. The conversion
    /// card leads with the difference, so a surface has to be able to ask.
    public var isVisiblyDifferent: Bool {
        abs(personalizedHours - standardHours) >= 0.5
    }
}

/// Where a session sits against the person's own recent history.
public enum LoadCategory: String, Codable, Sendable {
    case easy
    case typical
    case hard
    case unusuallyHard

    /// One intensity ladder, four rungs.
    ///
    /// "Easy" and "Typical" were the original words and they were reading as two
    /// different kinds of statement: one about how hard the session felt, one
    /// about how it compared to something the label never named. Light /
    /// Moderate / Hard / Very hard is a single scale, and the "for you" suffix
    /// is what names the comparison.
    public var label: String {
        switch self {
        case .easy: "Light for you"
        case .typical: "Moderate for you"
        case .hard: "Hard for you"
        case .unusuallyHard: "Very hard for you"
        }
    }

    /// "For you" is only true when the comparison was against the person's own
    /// sessions. On the standard tier the session is measured against a fixed
    /// population reference, so the label has to drop the claim and name the
    /// comparison it did make instead.
    public func label(for tier: RecoveryTier) -> String {
        guard tier == .standard else { return label }
        switch self {
        case .easy: return "Light session"
        case .typical: return "Moderate session"
        case .hard: return "Hard session"
        case .unusuallyHard: return "Very hard session"
        }
    }

    public var shortLabel: String {
        switch self {
        case .easy: "Light"
        case .typical: "Moderate"
        case .hard: "Hard"
        case .unusuallyHard: "Very hard"
        }
    }
}

/// The output of stage 1: one number on a common scale, plus how we got it.
public struct SessionLoad: Codable, Sendable, Equatable {
    public let value: Double
    public let source: LoadSource
    /// Fraction of the workout covered by usable heart-rate samples, 0...1.
    public let heartRateCoverage: Double

    public init(value: Double, source: LoadSource, heartRateCoverage: Double = 0) {
        self.value = max(0, value)
        self.source = source
        self.heartRateCoverage = min(max(heartRateCoverage, 0), 1)
    }
}

// MARK: - Inputs

/// Everything the calculator needs to know about one finished workout. No
/// HealthKit types: the calculator stays pure and unit-testable.
public struct SessionInput: Sendable, Equatable {
    public let id: String
    public let profile: WorkoutProfile
    public let startDate: Date
    public let endDate: Date
    /// Wall-clock minutes of the session.
    public let durationMinutes: Double
    public let averageHeartRate: Double?
    public let restingHeartRate: Double?
    public let maxHeartRate: Double?
    public let heartRateCoverage: Double
    public let activeEnergyKilocalories: Double?
    /// Session RPE on the 1-10 Borg CR10 scale, if the user supplied one.
    public let reportedEffort: Double?
    public let activityLabel: String

    public init(
        id: String,
        profile: WorkoutProfile,
        startDate: Date,
        endDate: Date,
        durationMinutes: Double? = nil,
        averageHeartRate: Double? = nil,
        restingHeartRate: Double? = nil,
        maxHeartRate: Double? = nil,
        heartRateCoverage: Double = 0,
        activeEnergyKilocalories: Double? = nil,
        reportedEffort: Double? = nil,
        activityLabel: String = "workout"
    ) {
        self.id = id
        self.profile = profile
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = durationMinutes ?? max(endDate.timeIntervalSince(startDate) / 60, 0)
        self.averageHeartRate = averageHeartRate
        self.restingHeartRate = restingHeartRate
        self.maxHeartRate = maxHeartRate
        self.heartRateCoverage = min(max(heartRateCoverage, 0), 1)
        self.activeEnergyKilocalories = activeEnergyKilocalories
        self.reportedEffort = reportedEffort.map { min(max($0, 1), 10) }
        self.activityLabel = activityLabel
    }
}

/// Sleep / HRV / resting-heart-rate context for the day the session landed in.
/// Every field is optional: absent context lowers confidence, it never blocks an
/// estimate.
public struct RecoveryContext: Sendable, Equatable {
    public let sleepHours: Double?
    public let heartRateVariability: Double?
    public let heartRateVariabilityBaseline: Double?
    public let restingHeartRate: Double?
    public let restingHeartRateBaseline: Double?

    public static let empty = RecoveryContext()

    public init(
        sleepHours: Double? = nil,
        heartRateVariability: Double? = nil,
        heartRateVariabilityBaseline: Double? = nil,
        restingHeartRate: Double? = nil,
        restingHeartRateBaseline: Double? = nil
    ) {
        self.sleepHours = sleepHours
        self.heartRateVariability = heartRateVariability
        self.heartRateVariabilityBaseline = heartRateVariabilityBaseline
        self.restingHeartRate = restingHeartRate
        self.restingHeartRateBaseline = restingHeartRateBaseline
    }

    /// True when nothing at all is known. Used to distinguish "no context" from
    /// "context that happens to be neutral".
    public var isEmpty: Bool {
        sleepHours == nil && heartRateVariability == nil && restingHeartRate == nil
    }
}

// MARK: - Outputs

/// The five surfaces from the dossier collapse to four here: "low confidence" is
/// orthogonal to where the countdown is, so it rides on `Confidence` and is
/// rendered as a badge rather than replacing the phase.
public enum RecoveryPhase: String, Codable, Sendable {
    case noRecentWorkout
    case ready
    case readySoon
    case recovering

    public var label: String {
        switch self {
        case .noRecentWorkout: "No recent workout"
        case .ready: "Ready"
        case .readySoon: "Ready soon"
        case .recovering: "Recovering"
        }
    }
}

public enum RecoveryConfidence: String, Codable, Sendable, Comparable {
    case buildingBaseline
    case low
    case medium
    case high

    private var order: Int {
        switch self {
        case .buildingBaseline: 0
        case .low: 1
        case .medium: 2
        case .high: 3
        }
    }

    public static func < (lhs: RecoveryConfidence, rhs: RecoveryConfidence) -> Bool {
        lhs.order < rhs.order
    }

    public var label: String {
        switch self {
        case .buildingBaseline: "Building baseline"
        case .low: "Low confidence"
        case .medium: "Medium confidence"
        case .high: "High confidence"
        }
    }

    public var shortLabel: String {
        switch self {
        case .buildingBaseline: "Building"
        case .low: "Low"
        case .medium: "Medium"
        case .high: "High"
        }
    }
}

/// One finished calculation. Everything the UI, the complication, and the
/// history explanation need, with no back-reference to HealthKit.
public struct RecoveryEstimate: Codable, Sendable, Equatable, Identifiable {
    /// One estimate per session, so the session is the identity.
    public var id: String { sessionID }

    public let sessionID: String
    public let profile: WorkoutProfile
    public let activityLabel: String
    public let calculatedAt: Date
    public let sessionEnd: Date
    public let readyAt: Date
    /// Point estimate in hours. Zero means the session produced no countdown.
    public let hours: Double
    /// Bounded window we actually show, e.g. "18 to 28h".
    public let windowLowHours: Double
    public let windowHighHours: Double
    public let load: SessionLoad
    public let relativeLoad: Double
    public let category: LoadCategory
    public let confidence: RecoveryConfidence
    public let reasons: [String]
    public let modelVersion: Int
    /// Which model produced this. Defaults to `.standard` so an estimate decoded
    /// from a version-1 record still reads back.
    public let tier: RecoveryTier
    /// The Recharge+ multiplier that was applied. Exactly 1 on the standard tier.
    public let personalFactor: Double
    /// The same session scored through the Standard path. Stored explicitly
    /// because removing only `personalFactor` does not undo a personal baseline,
    /// overnight context, or calibration.
    public let standardHours: Double

    public var producesCountdown: Bool { hours > 0 }

    public init(
        sessionID: String,
        profile: WorkoutProfile,
        activityLabel: String,
        calculatedAt: Date,
        sessionEnd: Date,
        readyAt: Date,
        hours: Double,
        windowLowHours: Double,
        windowHighHours: Double,
        load: SessionLoad,
        relativeLoad: Double,
        category: LoadCategory,
        confidence: RecoveryConfidence,
        reasons: [String],
        modelVersion: Int = recoveryModelVersion,
        tier: RecoveryTier = .standard,
        personalFactor: Double = 1,
        standardHours: Double? = nil
    ) {
        self.sessionID = sessionID
        self.profile = profile
        self.activityLabel = activityLabel
        self.calculatedAt = calculatedAt
        self.sessionEnd = sessionEnd
        self.readyAt = readyAt
        self.hours = hours
        self.windowLowHours = windowLowHours
        self.windowHighHours = windowHighHours
        self.load = load
        self.relativeLoad = relativeLoad
        self.category = category
        self.confidence = confidence
        self.reasons = reasons
        self.modelVersion = modelVersion
        self.tier = tier
        self.personalFactor = personalFactor
        self.standardHours = standardHours
            ?? (personalFactor > 0 ? hours / personalFactor : hours)
    }

    /// Tier metadata arrived in model version 2, and `standardHours` was added
    /// later. Missing fields decode to the closest truthful legacy value.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        sessionID = try container.decode(String.self, forKey: .sessionID)
        profile = try container.decode(WorkoutProfile.self, forKey: .profile)
        activityLabel = try container.decode(String.self, forKey: .activityLabel)
        calculatedAt = try container.decode(Date.self, forKey: .calculatedAt)
        sessionEnd = try container.decode(Date.self, forKey: .sessionEnd)
        readyAt = try container.decode(Date.self, forKey: .readyAt)
        hours = try container.decode(Double.self, forKey: .hours)
        windowLowHours = try container.decode(Double.self, forKey: .windowLowHours)
        windowHighHours = try container.decode(Double.self, forKey: .windowHighHours)
        load = try container.decode(SessionLoad.self, forKey: .load)
        relativeLoad = try container.decode(Double.self, forKey: .relativeLoad)
        category = try container.decode(LoadCategory.self, forKey: .category)
        confidence = try container.decode(RecoveryConfidence.self, forKey: .confidence)
        reasons = try container.decode([String].self, forKey: .reasons)
        modelVersion = try container.decode(Int.self, forKey: .modelVersion)
        tier = try container.decodeIfPresent(RecoveryTier.self, forKey: .tier) ?? .standard
        personalFactor = try container.decodeIfPresent(Double.self, forKey: .personalFactor) ?? 1
        standardHours = try container.decodeIfPresent(Double.self, forKey: .standardHours)
            ?? (personalFactor > 0 ? hours / personalFactor : hours)
    }

    /// Phase at a given instant. Derived rather than stored so a cached estimate
    /// can't go stale about whether it has expired.
    public func phase(at now: Date) -> RecoveryPhase {
        guard producesCountdown else { return .ready }
        let remaining = readyAt.timeIntervalSince(now)
        if remaining <= 0 { return .ready }
        if remaining <= 2 * 3600 { return .readySoon }
        return .recovering
    }

    public func remainingSeconds(at now: Date) -> TimeInterval {
        max(readyAt.timeIntervalSince(now), 0)
    }
}

// MARK: - Calibration

/// The one-tap question asked once a countdown expires.
public enum ReadinessFeedback: String, Codable, Sendable, CaseIterable {
    case feltReady
    case okayNotFresh
    case notReady

    public var label: String {
        switch self {
        case .feltReady: "Felt ready"
        case .okayNotFresh: "Okay but not fresh"
        case .notReady: "Not ready"
        }
    }

    /// Multiplicative nudge applied to the stored calibration factor. Small on
    /// purpose: one answer should never swing the model.
    public var calibrationNudge: Double {
        switch self {
        case .feltReady: 0.95
        case .okayNotFresh: 1.0
        case .notReady: 1.05
        }
    }
}

public enum RecoveryCalibration {
    public static let minimum = 0.80
    public static let maximum = 1.25
    public static let neutral = 1.0

    /// Folds one answer into the running factor, bounded so a run of "not ready"
    /// taps can stretch windows by at most a quarter.
    public static func apply(_ feedback: ReadinessFeedback, to factor: Double) -> Double {
        min(max(factor * feedback.calibrationNudge, minimum), maximum)
    }
}

// MARK: - Complication style

/// Drives every complication family from one cached estimate. The audience for
/// this app left Garmin, so how the countdown reads is a setting rather than a
/// hardcode.
public enum ComplicationStyle: Int, Codable, Sendable, CaseIterable {
    /// Garmin-like: hours remaining plus a ring. The default.
    case countdown = 0
    /// The clock time the estimate expires at.
    case readyClock = 1
    /// The state word, with the hours demoted to a subtitle.
    case state = 2

    public var label: String {
        switch self {
        case .countdown: "Countdown"
        case .readyClock: "Ready at"
        case .state: "State"
        }
    }

    public var detail: String {
        switch self {
        case .countdown: "Hours left, with a ring. Closest to Garmin."
        case .readyClock: "The clock time you are estimated to be ready."
        case .state: "Recovering / Ready soon / Ready."
        }
    }
}
