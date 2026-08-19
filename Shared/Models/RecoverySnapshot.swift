import Foundation

/// App Group identifier. Declared at module level (not inside the `@MainActor`
/// `DataService`) so widget and complication targets can reach it from any
/// isolation context.
public let rechargeAppGroupID = "group.com.jackwallner.recovery"

/// The compact record the phone writes and every other surface reads.
///
/// The phone owns the model: it has the full HealthKit store and the long
/// history. The Watch app and both widget extensions only ever read this
/// snapshot, which is why it is a small `Codable` value in App Group
/// `UserDefaults` rather than a second SwiftData schema every extension would
/// have to mirror.
public struct RecoverySnapshot: Codable, Sendable, Equatable {
    public var readyAt: Date?
    public var sessionEnd: Date?
    public var hours: Double
    public var windowLowHours: Double
    public var windowHighHours: Double
    public var profile: WorkoutProfile?
    public var activityLabel: String
    public var category: LoadCategory?
    public var confidence: RecoveryConfidence
    public var reasons: [String]
    public var calculatedAt: Date
    public var modelVersion: Int
    /// Which tier produced this window, carried so a surface that has no
    /// StoreKit access can still say. Nothing on the wrist gates on it today:
    /// the tier is already baked into `hours`, and a complication has no room
    /// to explain the difference.
    public var isPro: Bool

    public static let empty = RecoverySnapshot()

    public init(
        readyAt: Date? = nil,
        sessionEnd: Date? = nil,
        hours: Double = 0,
        windowLowHours: Double = 0,
        windowHighHours: Double = 0,
        profile: WorkoutProfile? = nil,
        activityLabel: String = "",
        category: LoadCategory? = nil,
        confidence: RecoveryConfidence = .buildingBaseline,
        reasons: [String] = [],
        calculatedAt: Date = .distantPast,
        modelVersion: Int = recoveryModelVersion,
        isPro: Bool = false
    ) {
        self.readyAt = readyAt
        self.sessionEnd = sessionEnd
        self.hours = hours
        self.windowLowHours = windowLowHours
        self.windowHighHours = windowHighHours
        self.profile = profile
        self.activityLabel = activityLabel
        self.category = category
        self.confidence = confidence
        self.reasons = reasons
        self.calculatedAt = calculatedAt
        self.modelVersion = modelVersion
        self.isPro = isPro
    }

    public init(estimate: RecoveryEstimate, isPro: Bool) {
        self.init(
            readyAt: estimate.producesCountdown ? estimate.readyAt : nil,
            sessionEnd: estimate.sessionEnd,
            // The stacked total, not the session's own cost: everything reading
            // a snapshot is drawing a countdown, and the countdown runs for the
            // total. `windowLowHours`/`windowHighHours` already spread around
            // it.
            hours: estimate.totalHours,
            windowLowHours: estimate.windowLowHours,
            windowHighHours: estimate.windowHighHours,
            profile: estimate.profile,
            activityLabel: estimate.activityLabel,
            category: estimate.category,
            confidence: estimate.confidence,
            reasons: estimate.reasons,
            calculatedAt: estimate.calculatedAt,
            modelVersion: estimate.modelVersion,
            isPro: isPro
        )
    }

    private enum CodingKeys: String, CodingKey {
        case readyAt
        case sessionEnd
        case hours
        case windowLowHours
        case windowHighHours
        case profile
        case activityLabel
        case category
        case confidence
        case reasons
        case calculatedAt
        case modelVersion
        case isPro
    }

    /// Newer fields must not turn an older snapshot into a never-synced state.
    /// The Watch can receive a payload written by the previous app version while
    /// its extension is still being updated, so absent additive fields use the
    /// same defaults as a newly-created snapshot.
    public init(from decoder: Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        readyAt = try container.decodeIfPresent(Date.self, forKey: .readyAt)
        sessionEnd = try container.decodeIfPresent(Date.self, forKey: .sessionEnd)
        hours = try container.decodeIfPresent(Double.self, forKey: .hours) ?? 0
        windowLowHours = try container.decodeIfPresent(Double.self, forKey: .windowLowHours) ?? 0
        windowHighHours = try container.decodeIfPresent(Double.self, forKey: .windowHighHours) ?? 0
        profile = try container.decodeIfPresent(WorkoutProfile.self, forKey: .profile)
        activityLabel = try container.decodeIfPresent(String.self, forKey: .activityLabel) ?? ""
        category = try container.decodeIfPresent(LoadCategory.self, forKey: .category)
        confidence = try container.decodeIfPresent(RecoveryConfidence.self, forKey: .confidence) ?? .buildingBaseline
        reasons = try container.decodeIfPresent([String].self, forKey: .reasons) ?? []
        calculatedAt = try container.decodeIfPresent(Date.self, forKey: .calculatedAt) ?? .distantPast
        modelVersion = try container.decodeIfPresent(Int.self, forKey: .modelVersion) ?? recoveryModelVersion
        isPro = try container.decodeIfPresent(Bool.self, forKey: .isPro) ?? false
    }

    /// True when there is nothing to talk about yet — no import has run, or no
    /// qualifying session exists.
    public var hasSession: Bool { sessionEnd != nil }

    public func phase(at now: Date) -> RecoveryPhase {
        guard let sessionEnd else { return .noRecentWorkout }
        if now.timeIntervalSince(sessionEnd) > 4 * 86_400 { return .noRecentWorkout }
        guard let readyAt else { return .ready }
        let remaining = readyAt.timeIntervalSince(now)
        if remaining <= 0 { return .ready }
        if remaining <= 2 * 3600 { return .readySoon }
        return .recovering
    }

    public func remainingSeconds(at now: Date) -> TimeInterval {
        guard let readyAt else { return 0 }
        return max(readyAt.timeIntervalSince(now), 0)
    }

    /// Fraction of the original window still to run, 0...1. Drives the ring.
    public func progress(at now: Date) -> Double {
        guard hasSession else { return 0 }
        guard hours > 0, let readyAt else { return 1 }
        let total = hours * 3600
        let remaining = max(readyAt.timeIntervalSince(now), 0)
        return min(max(1 - remaining / total, 0), 1)
    }
}

// MARK: - App Group storage

/// Read/write of the snapshot. Free functions rather than a service so widget
/// timeline providers can call them without `@MainActor` hops.
public enum RecoverySnapshotStore {
    static let key = "recoverySnapshot"

    public static func load(defaults: UserDefaults? = UserDefaults(suiteName: rechargeAppGroupID)) -> RecoverySnapshot {
        loadIfPresent(defaults: defaults) ?? .empty
    }

    /// nil when nothing has ever been written here, which on the Watch is a
    /// genuinely different state from a snapshot that happens to be empty.
    ///
    /// `load` collapses the two, and every reader used to go through it, so a
    /// user who had synced perfectly well but simply had no qualifying workout
    /// got the same `RecoverySnapshot.empty` as a Watch that had never heard
    /// from the phone, and the complication told them to open Recharge to set
    /// it up, forever, with nothing to set up. Presence of the key is the only
    /// thing that can tell them apart, because an empty snapshot and a default
    /// one are equal by construction.
    public static func loadIfPresent(
        defaults: UserDefaults? = UserDefaults(suiteName: rechargeAppGroupID)
    ) -> RecoverySnapshot? {
        guard let data = (defaults ?? .standard).data(forKey: key) else { return nil }
        return try? JSONDecoder().decode(RecoverySnapshot.self, from: data)
    }

    /// Whether the phone has ever published into this container.
    public static func hasEverSynced(
        defaults: UserDefaults? = UserDefaults(suiteName: rechargeAppGroupID)
    ) -> Bool {
        (defaults ?? .standard).data(forKey: key) != nil
    }

    @discardableResult
    public static func save(
        _ snapshot: RecoverySnapshot,
        defaults: UserDefaults? = UserDefaults(suiteName: rechargeAppGroupID)
    ) -> Bool {
        guard let data = try? JSONEncoder().encode(snapshot) else { return false }
        (defaults ?? .standard).set(data, forKey: key)
        return true
    }
}
