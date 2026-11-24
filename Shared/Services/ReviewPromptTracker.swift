import Foundation

public extension Notification.Name {
    /// Posted at a good moment (see `ReviewMoment`). The host may call Apple's
    /// review prompt a few seconds afterwards, if nothing else is on screen.
    static let rechargePositiveMomentForReview =
        Notification.Name("com.jackwallner.recovery.positiveMomentForReview")
}

/// What the user did about a review. Only opening the write-review page ends
/// the passive asks: someone who sent feedback can still rate later.
public enum ReviewPromptOutcome: String, Sendable {
    case openedWriteReview
    /// Written by builds before the star prompt moved to good moments. Kept so
    /// those installs decode it; it no longer stops anything.
    case submittedFeedback
}

/// The moments this app asks at, and whether each one is a good result.
///
/// The app's one win is a countdown running out into Ready. Two things can
/// follow it, and each is its own moment:
/// - the countdown reached Ready and no readiness question is owed (free tier,
///   or the question was already answered), so nothing else is competing;
/// - the readiness question was answered "Felt ready", the clearest good
///   result the app ever records.
/// "Okay but not fresh" and "Not ready" are not good results, and neither is
/// a Ready whose question is still waiting: that answer is the next moment.
public enum ReviewMoment: Equatable, Sendable {
    case countdownReady(questionPending: Bool)
    case readinessAnswered(ReadinessFeedback)

    public var isGoodResult: Bool {
        switch self {
        case .countdownReady(let questionPending): !questionPending
        case .readinessAnswered(let answer): answer == .feltReady
        }
    }
}

/// Pure rules for Apple's rating prompt, free of `UserDefaults` so the gates
/// can be tested directly.
///
/// No question goes in front of the prompt: asking "Enjoying Recharge?" and
/// sending only the yeses to a rating is review gating (App Review 5.6.1).
/// The job is to ask early and often enough inside Apple's limits: from the
/// second launch on, at a good moment, at most once every 30 days. Apple shows
/// the prompt at most three times a year and decides each time; a call it
/// swallows costs nothing.
public struct ReviewPromptGate: Sendable {
    /// Not in the first session: a second cold start is the only tenure gate.
    public static let minimumLaunchCount = 2
    /// Days between our calls. Paces the asks, not the user's answers.
    public static let cooldownDays = 30

    public var launchCount: Int
    public var lastAsked: Date?
    public var openedWriteReview: Bool

    public init(launchCount: Int, lastAsked: Date?, openedWriteReview: Bool) {
        self.launchCount = launchCount
        self.lastAsked = lastAsked
        self.openedWriteReview = openedWriteReview
    }

    public func allows(_ moment: ReviewMoment, now: Date = .now) -> Bool {
        guard moment.isGoodResult else { return false }
        guard !openedWriteReview else { return false }
        guard launchCount >= Self.minimumLaunchCount else { return false }
        // A stamp from a clock that ran ahead is in the future: it is no
        // evidence of an ask, and would hold the cooldown shut for as long.
        guard let last = lastAsked, last <= now else { return true }
        return now.timeIntervalSince(last) >= TimeInterval(Self.cooldownDays) * 86_400
    }
}

/// Persists the launch count and the last ask in the App Group.
@MainActor
public enum ReviewPromptTracker {
    private static let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard

    private static let launchCountKey = "reviewPrompt.appLaunchCount"
    private static let firstOpenKey = "reviewPrompt.firstAppOpenDate"
    private static let lastShownKey = "reviewPrompt.lastShownDate"
    private static let outcomeKey = "reviewPrompt.outcome"
    public static let momentUserInfoKey = "moment"
    private static let seenReadySessionsKey = "reviewPrompt.seenReadySessions"

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

    /// Call once per process, when it first comes to the foreground. A
    /// background relaunch is not a launch the user made.
    public static func recordAppLaunch(now: Date = .now) {
        if firstAppOpenDate == nil { firstAppOpenDate = now }
        appLaunchCount += 1
    }

    /// Whether a moment right now may call `requestReview()`.
    public static func shouldRequestReview(
        for moment: ReviewMoment,
        hasCompletedSetup: Bool,
        now: Date = .now
    ) -> Bool {
        guard !ScreenshotConfig.isEnabled, hasCompletedSetup else { return false }
        return ReviewPromptGate(
            launchCount: appLaunchCount,
            lastAsked: lastShownDate,
            openedWriteReview: outcome == .openedWriteReview
        ).allows(moment, now: now)
    }

    /// A countdown has run out. Keyed on the session so re-opening the app
    /// during the same Ready state cannot announce it twice.
    public static func recordReadyMoment(sessionID: String, questionPending: Bool) {
        var seen = Set(defaults.stringArray(forKey: seenReadySessionsKey) ?? [])
        guard !seen.contains(sessionID) else { return }
        seen.insert(sessionID)
        // Bound the set; only recency matters and this lives in the App Group.
        if seen.count > 200 { seen = Set(seen.prefix(200)) }
        defaults.set(Array(seen), forKey: seenReadySessionsKey)
        recordMoment(.countdownReady(questionPending: questionPending))
    }

    /// Announces a moment. The host asks only for a good result (`allows`
    /// refuses the rest), a few seconds later and only if the screen is still
    /// clear.
    public static func recordMoment(_ moment: ReviewMoment) {
        NotificationCenter.default.post(
            name: .rechargePositiveMomentForReview,
            object: nil,
            userInfo: [Self.momentUserInfoKey: moment]
        )
    }

    /// Recorded when the call is made: Apple may show nothing, and there is no
    /// answer to wait for.
    public static func markShown(now: Date = .now) {
        lastShownDate = now
    }

    /// Settings > Write a review. The one thing that ends the passive asks.
    public static func markOpenedWriteReview() {
        outcome = .openedWriteReview
        markShown()
    }

    /// For tests: clears everything this type stores.
    public static func resetForTesting() {
        [launchCountKey, firstOpenKey, lastShownKey, outcomeKey, seenReadySessionsKey]
            .forEach(defaults.removeObject(forKey:))
    }
}
