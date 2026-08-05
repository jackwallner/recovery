import Foundation

// MARK: - Model version

/// Bumped whenever the calculator's numbers change. Stored on every estimate so
/// history can explain why an old window disagrees with what the same session
/// would produce today, and so the determinism test has something to pin to.
public let recoveryModelVersion = 1

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

    /// Bootstrap "typical session" load for a user with no history yet, so a
    /// first-ever workout still produces a sane relative load.
    public var bootstrapTypicalLoad: Double {
        switch self {
        case .endurance: 70
        case .strength: 80
        case .mixed: 95
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

/// Where a session sits against the person's own recent history.
public enum LoadCategory: String, Codable, Sendable {
    case easy
    case typical
    case hard
    case unusuallyHard

    public var label: String {
        switch self {
        case .easy: "Easy for you"
        case .typical: "Typical for you"
        case .hard: "Hard for you"
        case .unusuallyHard: "Unusually hard for you"
        }
    }

    public var shortLabel: String {
        switch self {
        case .easy: "Easy"
        case .typical: "Typical"
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
        modelVersion: Int = recoveryModelVersion
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
