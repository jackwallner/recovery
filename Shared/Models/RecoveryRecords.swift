import Foundation
import SwiftData

/// One imported HealthKit workout, plus the load we computed for it.
///
/// Keyed on the HealthKit UUID so a re-import is an update rather than a
/// duplicate — Health hands the same workout back on every observer fire, and
/// two identical rows would double-count the baseline.
@Model
public final class WorkoutRecord {
    @Attribute(.unique) public var healthKitUUID: String
    public var activityCode: Int
    public var startDate: Date
    public var endDate: Date
    public var durationMinutes: Double
    public var activeEnergy: Double
    public var averageHeartRate: Double
    /// The session's own heart-rate peak, already de-spiked by
    /// `HealthKitService`. Defaulted rather than optional so SwiftData migrates
    /// an existing store in place; zero means "no usable heart rate here".
    public var peakHeartRate: Double = 0
    public var heartRateCoverage: Double
    public var sessionLoad: Double
    public var loadSourceRaw: String
    public var profileRaw: String
    /// Set when the user overrides the automatic classification for this one
    /// session (the HYROX/CrossFit case).
    public var profileOverrideRaw: String?
    /// Session RPE the user supplied, from the phone or the Watch.
    public var reportedEffort: Double?
    public var sourceName: String
    public var activityLabel: String
    public var importedAt: Date

    public init(
        healthKitUUID: String,
        activityCode: Int,
        startDate: Date,
        endDate: Date,
        durationMinutes: Double,
        activeEnergy: Double = 0,
        averageHeartRate: Double = 0,
        peakHeartRate: Double = 0,
        heartRateCoverage: Double = 0,
        sessionLoad: Double = 0,
        loadSource: LoadSource = .duration,
        profile: WorkoutProfile = .endurance,
        profileOverride: WorkoutProfile? = nil,
        reportedEffort: Double? = nil,
        sourceName: String = "",
        activityLabel: String = "workout"
    ) {
        self.healthKitUUID = healthKitUUID
        self.activityCode = activityCode
        self.startDate = startDate
        self.endDate = endDate
        self.durationMinutes = durationMinutes
        self.activeEnergy = activeEnergy
        self.averageHeartRate = averageHeartRate
        self.peakHeartRate = peakHeartRate
        self.heartRateCoverage = heartRateCoverage
        self.sessionLoad = sessionLoad
        self.loadSourceRaw = loadSource.rawValue
        self.profileRaw = profile.rawValue
        self.profileOverrideRaw = profileOverride?.rawValue
        self.reportedEffort = reportedEffort
        self.sourceName = sourceName
        self.activityLabel = activityLabel
        self.importedAt = .now
    }

    public var profile: WorkoutProfile {
        get { effectiveProfile }
        set { profileRaw = newValue.rawValue }
    }

    /// The override wins when present; that is the point of it.
    public var effectiveProfile: WorkoutProfile {
        if let raw = profileOverrideRaw, let override = WorkoutProfile(rawValue: raw) { return override }
        return WorkoutProfile(rawValue: profileRaw) ?? .endurance
    }

    public var profileOverride: WorkoutProfile? {
        get { profileOverrideRaw.flatMap(WorkoutProfile.init(rawValue:)) }
        set { profileOverrideRaw = newValue?.rawValue }
    }

    public var loadSource: LoadSource {
        get { LoadSource(rawValue: loadSourceRaw) ?? .duration }
        set { loadSourceRaw = newValue.rawValue }
    }

    /// True when the session is one the effort question is worth asking about:
    /// a strength or mixed profile whose load came from something weaker than
    /// the user's own answer.
    public var wantsEffortInput: Bool {
        guard reportedEffort == nil, effectiveProfile.wantsEffortInput else { return false }
        return loadSource == .energy || loadSource == .duration
    }
}

/// One calculated estimate. Persisted rather than recomputed so history can show
/// what the app actually told the user at the time, including under an older
/// `modelVersion`.
@Model
public final class RecoveryStateRecord {
    @Attribute(.unique) public var sessionID: String
    public var calculatedAt: Date
    public var sessionEnd: Date
    public var readyAt: Date
    public var hours: Double
    public var windowLowHours: Double
    public var windowHighHours: Double
    public var profileRaw: String
    public var activityLabel: String
    public var categoryRaw: String
    public var confidenceRaw: String
    public var loadValue: Double
    public var loadSourceRaw: String
    public var heartRateCoverage: Double
    public var relativeLoad: Double
    public var reasonsJoined: String
    public var modelVersion: Int
    /// Added after model version 2 reached TestFlight. Optional fields let
    /// SwiftData migrate those pre-release records without dropping the cache.
    public var tierRaw: String?
    public var personalFactor: Double?
    public var standardHours: Double?
    /// Recovery still outstanding when this session ended. Optional for the same
    /// reason the three above are: SwiftData migrates an existing store by
    /// filling new optionals with nil rather than dropping the cache.
    ///
    /// It has to be *persisted* rather than recomputed, because `readyAt` is
    /// stored and `hours` is the session's own cost, so a record that forgets
    /// what it carried rehydrates with the two disagreeing: the countdown ends
    /// where a stacked window ends while the row prints the unstacked figure.
    /// nil decodes as zero, which is truthful for every record written before
    /// stacking existed. Those estimates were not stacked.
    public var carriedHours: Double?
    /// What the session cost, whether or not it started a countdown.
    ///
    /// Persisted for exactly the reason `carriedHours` is, and it is the same
    /// trap: it is computed, published and rendered, and a record that forgets
    /// it rehydrates with History showing a walk as costing nothing while the
    /// app that produced the record said otherwise. nil decodes as `hours`,
    /// which is the truthful legacy value — for every record written before
    /// this existed, a countdown-producing session's cost *was* its hours, and
    /// a quiet session's recorded cost genuinely was zero.
    public var recoveryCostHours: Double?
    public var userFeedbackRaw: String?

    public init(estimate: RecoveryEstimate) {
        self.sessionID = estimate.sessionID
        self.calculatedAt = estimate.calculatedAt
        self.sessionEnd = estimate.sessionEnd
        self.readyAt = estimate.readyAt
        self.hours = estimate.hours
        self.windowLowHours = estimate.windowLowHours
        self.windowHighHours = estimate.windowHighHours
        self.profileRaw = estimate.profile.rawValue
        self.activityLabel = estimate.activityLabel
        self.categoryRaw = estimate.category.rawValue
        self.confidenceRaw = estimate.confidence.rawValue
        self.loadValue = estimate.load.value
        self.loadSourceRaw = estimate.load.source.rawValue
        self.heartRateCoverage = estimate.load.heartRateCoverage
        self.relativeLoad = estimate.relativeLoad
        self.reasonsJoined = estimate.reasons.joined(separator: "\u{1F}")
        self.modelVersion = estimate.modelVersion
        self.tierRaw = estimate.tier.rawValue
        self.personalFactor = estimate.personalFactor
        self.standardHours = estimate.standardHours
        self.carriedHours = estimate.carriedHours
        self.recoveryCostHours = estimate.recoveryCostHours
        self.userFeedbackRaw = nil
    }

    public var userFeedback: ReadinessFeedback? {
        get { userFeedbackRaw.flatMap(ReadinessFeedback.init(rawValue:)) }
        set { userFeedbackRaw = newValue?.rawValue }
    }

    /// Rehydrates the value type the whole UI and the resolver work in.
    public var estimate: RecoveryEstimate {
        RecoveryEstimate(
            sessionID: sessionID,
            profile: WorkoutProfile(rawValue: profileRaw) ?? .endurance,
            activityLabel: activityLabel,
            calculatedAt: calculatedAt,
            sessionEnd: sessionEnd,
            readyAt: readyAt,
            hours: hours,
            windowLowHours: windowLowHours,
            windowHighHours: windowHighHours,
            load: SessionLoad(
                value: loadValue,
                source: LoadSource(rawValue: loadSourceRaw) ?? .duration,
                heartRateCoverage: heartRateCoverage
            ),
            relativeLoad: relativeLoad,
            category: LoadCategory(rawValue: categoryRaw) ?? .typical,
            confidence: RecoveryConfidence(rawValue: confidenceRaw) ?? .low,
            reasons: reasonsJoined.isEmpty ? [] : reasonsJoined.components(separatedBy: "\u{1F}"),
            modelVersion: modelVersion,
            tier: tierRaw.flatMap(RecoveryTier.init(rawValue:)) ?? .standard,
            personalFactor: personalFactor ?? 1,
            standardHours: standardHours,
            carriedHours: carriedHours ?? 0,
            recoveryCostHours: recoveryCostHours
        )
    }

    /// Build 10 did not persist these fields. The engine rescores those records
    /// once so a personalized result is never relabelled as Standard.
    public var hasCompleteTierMetadata: Bool {
        tierRaw != nil && personalFactor != nil && standardHours != nil
    }

    public func update(from estimate: RecoveryEstimate) {
        calculatedAt = estimate.calculatedAt
        sessionEnd = estimate.sessionEnd
        readyAt = estimate.readyAt
        hours = estimate.hours
        windowLowHours = estimate.windowLowHours
        windowHighHours = estimate.windowHighHours
        profileRaw = estimate.profile.rawValue
        activityLabel = estimate.activityLabel
        categoryRaw = estimate.category.rawValue
        confidenceRaw = estimate.confidence.rawValue
        loadValue = estimate.load.value
        loadSourceRaw = estimate.load.source.rawValue
        heartRateCoverage = estimate.load.heartRateCoverage
        relativeLoad = estimate.relativeLoad
        reasonsJoined = estimate.reasons.joined(separator: "\u{1F}")
        modelVersion = estimate.modelVersion
        tierRaw = estimate.tier.rawValue
        personalFactor = estimate.personalFactor
        standardHours = estimate.standardHours
        carriedHours = estimate.carriedHours
        recoveryCostHours = estimate.recoveryCostHours
    }
}

/// One day of sleep / HRV / resting-heart-rate context, plus the load totals
/// that make up the weekly view. Written by the phone only.
@Model
public final class DailyContextRecord {
    @Attribute(.unique) public var dateKey: String
    public var date: Date
    public var sleepHours: Double
    public var restingHeartRate: Double
    public var heartRateVariability: Double
    /// Overnight breaths per minute. Defaulted rather than optional so SwiftData
    /// migrates an existing store in place; zero is "not recorded", the same
    /// convention every other field here uses.
    public var respiratoryRate: Double = 0
    /// The best one-minute heart-rate recovery Health wrote that day, in bpm.
    public var heartRateRecovery: Double = 0
    public var acuteLoad: Double
    public var chronicLoad: Double
    public var lastUpdated: Date

    public init(
        date: Date,
        sleepHours: Double = 0,
        restingHeartRate: Double = 0,
        heartRateVariability: Double = 0,
        respiratoryRate: Double = 0,
        heartRateRecovery: Double = 0,
        acuteLoad: Double = 0,
        chronicLoad: Double = 0
    ) {
        let normalized = DateHelpers.startOfDay(date)
        self.dateKey = DateHelpers.dayKey(for: normalized)
        self.date = normalized
        self.sleepHours = sleepHours
        self.restingHeartRate = restingHeartRate
        self.heartRateVariability = heartRateVariability
        self.respiratoryRate = respiratoryRate
        self.heartRateRecovery = heartRateRecovery
        self.acuteLoad = acuteLoad
        self.chronicLoad = chronicLoad
        self.lastUpdated = .now
    }

    /// Zero means "not recorded" in every field, so absent context stays absent
    /// rather than reading as a genuine zero.
    public var context: RecoveryContext {
        RecoveryContext(
            sleepHours: sleepHours > 0 ? sleepHours : nil,
            heartRateVariability: heartRateVariability > 0 ? heartRateVariability : nil,
            heartRateVariabilityBaseline: nil,
            restingHeartRate: restingHeartRate > 0 ? restingHeartRate : nil,
            restingHeartRateBaseline: nil,
            respiratoryRate: respiratoryRate > 0 ? respiratoryRate : nil,
            respiratoryRateBaseline: nil
        )
    }
}
