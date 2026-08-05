import Foundation

public extension Notification.Name {
    /// Posted when a countdown reaches Ready — the app's one genuinely good
    /// moment. The host may open the enjoyment funnel shortly afterwards.
    static let rechargePositiveMomentForReview =
        Notification.Name("com.jackwallner.recovery.positiveMomentForReview")
}

/// How the user last resolved the review / feedback prompt.
public enum ReviewPromptOutcome: String, Sendable {
    case openedWriteReview
    case submittedFeedback
}

/// Pure eligibility rules for the enjoyment funnel, kept free of `UserDefaults`
/// so the thresholds can be unit-tested directly.
public struct ReviewPromptEligibility: Sendable {
    /// Countdowns the user has watched run out. The moment the app exists for.
    public var readyMomentCount: Int
    public var appLaunchCount: Int
    public var daysSinceFirstOpen: Int
    /// True once at least one estimate has been produced.
    public var hasSeenEstimate: Bool

    public enum Trigger: Equatable, Sendable {
        case readyMoment
        case engagedUse
    }

    public static let minimumLaunchCount = 3
    public static let minimumDaysSinceFirstOpen = 3
    /// Two completed countdowns means the loop has actually paid off twice,
    /// which is a much better moment to ask than the first one.
    public static let minimumReadyMoments = 2

    public static let engagedLaunchCount = 6
    public static let engagedDaysSinceFirstOpen = 7

    public init(
        readyMomentCount: Int,
        appLaunchCount: Int,
        daysSinceFirstOpen: Int,
        hasSeenEstimate: Bool
    ) {
        self.readyMomentCount = readyMomentCount
        self.appLaunchCount = appLaunchCount
        self.daysSinceFirstOpen = daysSinceFirstOpen
        self.hasSeenEstimate = hasSeenEstimate
    }

    public var trigger: Trigger? {
        if readyMomentCount >= Self.minimumReadyMoments,
           appLaunchCount >= Self.minimumLaunchCount,
           daysSinceFirstOpen >= Self.minimumDaysSinceFirstOpen {
            return .readyMoment
        }
        // No point asking someone who has never seen a countdown whether they
        // are enjoying an app whose whole job is showing one.
        if hasSeenEstimate,
           appLaunchCount >= Self.engagedLaunchCount,
           daysSinceFirstOpen >= Self.engagedDaysSinceFirstOpen {
            return .engagedUse
        }
        return nil
    }
}

/// Persists launch counts, Ready moments, and prompt eligibility in the App Group.
@MainActor
public enum ReviewPromptTracker {
    private static let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let outcomeKey = "reviewPrompt.outcome"
    private static let readyMomentCountKey = "reviewPrompt.readyMomentCount"
    private static let pendingReadyMomentKey = "reviewPrompt.pendingReadyMoment"
    private static let softDeferKey = "reviewPrompt.softDefer"
    private static let hasSeenEstimateKey = "reviewPrompt.hasSeenEstimate"
    private static let seenReadySessionsKey = "reviewPrompt.seenReadySessions"

    public static let cooldownDays = 120
    /// Shorter cooldown after "Maybe later" — Apple's `requestReview()` often
    /// shows nothing, so a 120-day jail burns asks for free.
    public static let softDeferCooldownDays = 30

    public static var appLaunchCount: Int {
        get { max(defaults.integer(forKey: launchCountKey), 0) }
        set { defaults.set(newValue, forKey: launchCountKey) }
    }

    public static var firstAppOpenDate: Date? {
        get { defaults.object(forKey: firstOpenKey) as? Date }
        set {
            if let date = newValue { defaults.set(date, forKey: firstOpenKey) }
            else { defaults.removeObject(forKey: firstOpenKey) }
        }
    }

    public static var lastShownDate: Date? {
        get { defaults.object(forKey: lastShownKey) as? Date }
        set {
            if let date = newValue { defaults.set(date, forKey: lastShownKey) }
            else { defaults.removeObject(forKey: lastShownKey) }
        }
    }

    public static var outcome: ReviewPromptOutcome? {
        get { defaults.string(forKey: outcomeKey).flatMap(ReviewPromptOutcome.init(rawValue:)) }
        set {
            if let value = newValue { defaults.set(value.rawValue, forKey: outcomeKey) }
            else { defaults.removeObject(forKey: outcomeKey) }
        }
    }

    public static var readyMomentCount: Int {
        get { max(defaults.integer(forKey: readyMomentCountKey), 0) }
        set { defaults.set(newValue, forKey: readyMomentCountKey) }
    }

    public static var hasPendingReadyMoment: Bool {
        get { defaults.bool(forKey: pendingReadyMomentKey) }
        set { defaults.set(newValue, forKey: pendingReadyMomentKey) }
    }

    public static var hasSeenEstimate: Bool {
        get { defaults.bool(forKey: hasSeenEstimateKey) }
        set { defaults.set(newValue, forKey: hasSeenEstimateKey) }
    }

    /// Call once per process launch.
    public static func recordAppLaunch(now: Date = .now) {
        if firstAppOpenDate == nil { firstAppOpenDate = now }
        appLaunchCount += 1
    }

    /// Records that a specific countdown has run out. Keyed on the session so
    /// re-opening the app during the same Ready state cannot inflate the count.
    public static func recordReadyMoment(sessionID: String) {
        var seen = Set(defaults.stringArray(forKey: seenReadySessionsKey) ?? [])
        guard !seen.contains(sessionID) else { return }
        seen.insert(sessionID)
        // Bound the set; only recency matters and this lives in the App Group.
        if seen.count > 200 { seen = Set(seen.prefix(200)) }
        defaults.set(Array(seen), forKey: seenReadySessionsKey)
        readyMomentCount += 1
        hasPendingReadyMoment = true
        NotificationCenter.default.post(name: .rechargePositiveMomentForReview, object: nil)
    }

    public static func recordEstimateAvailable() {
        guard !hasSeenEstimate else { return }
        hasSeenEstimate = true
    }

    public static func consumePendingReadyMoment() {
        hasPendingReadyMoment = false
    }

    public static func passivePromptAllowed(now: Date = .now) -> Bool {
        guard outcome == nil else { return false }
        guard let last = lastShownDate else { return true }
        let days = defaults.bool(forKey: softDeferKey) ? softDeferCooldownDays : cooldownDays
        return now.timeIntervalSince(last) >= TimeInterval(days) * 86_400
    }

    public static func eligibilityTrigger(
        hasCompletedSetup: Bool,
        now: Date = .now
    ) -> ReviewPromptEligibility.Trigger? {
        guard !ScreenshotConfig.isEnabled else { return nil }
        guard hasCompletedSetup else { return nil }
        guard passivePromptAllowed(now: now) else { return nil }
        guard let first = firstAppOpenDate else { return nil }
        return ReviewPromptEligibility(
            readyMomentCount: readyMomentCount,
            appLaunchCount: appLaunchCount,
            daysSinceFirstOpen: Int(now.timeIntervalSince(first) / 86_400),
            hasSeenEstimate: hasSeenEstimate
        ).trigger
    }

    public static func canPresentEnjoymentPrompt(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        eligibilityTrigger(hasCompletedSetup: hasCompletedSetup, now: now) != nil
    }

    public static func shouldShowAfterReadyMoment(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard hasPendingReadyMoment else { return false }
        return eligibilityTrigger(hasCompletedSetup: hasCompletedSetup, now: now) == .readyMoment
    }

    /// For users who keep coming back without accumulating Ready moments. There
    /// is no pending token to consume here, so the host must call `markShown()`
    /// when it presents or a swipe-away re-prompts on every launch.
    public static func shouldShowForEngagedUse(hasCompletedSetup: Bool, now: Date = .now) -> Bool {
        guard !hasPendingReadyMoment else { return false }
        return eligibilityTrigger(hasCompletedSetup: hasCompletedSetup, now: now) == .engagedUse
    }

    public static func markShown(now: Date = .now) {
        lastShownDate = now
        defaults.set(false, forKey: softDeferKey)
        consumePendingReadyMoment()
    }

    /// True after "Maybe later" until the next hard `markShown` / outcome. Hosts
    /// must not call `markShown()` on sheet dismiss while this holds — that
    /// would clear the flag and apply the 120-day cooldown instead.
    public static var isSoftDeferred: Bool { defaults.bool(forKey: softDeferKey) }

    public static func markSoftDeferred(now: Date = .now) {
        lastShownDate = now
        defaults.set(true, forKey: softDeferKey)
        consumePendingReadyMoment()
    }

    public static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    public static func markFeedbackSubmitted() {
        outcome = .submittedFeedback
        markShown()
    }
}
