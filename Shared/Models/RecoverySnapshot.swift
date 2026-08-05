import Foundation

/// App Group identifier. Declared at module level (not inside the `@MainActor`
/// `DataService`) so widget and complication targets can reach it from any
/// isolation context.
public let rechargeAppGroupID = "group.com.jackwallner.recharge"

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
    /// Mirrors the live entitlement so extensions can gate Pro-only detail
    /// without a StoreKit round-trip.
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
            hours: estimate.hours,
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
        guard let data = (defaults ?? .standard).data(forKey: key),
              let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: data)
        else { return .empty }
        return snapshot
    }

    public static func save(
        _ snapshot: RecoverySnapshot,
        defaults: UserDefaults? = UserDefaults(suiteName: rechargeAppGroupID)
    ) {
        guard let data = try? JSONEncoder().encode(snapshot) else { return }
        (defaults ?? .standard).set(data, forKey: key)
    }
}
