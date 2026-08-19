import Foundation
import WatchConnectivity
import WidgetKit
import os
#if os(watchOS)
import WatchKit
#endif

private let connectivityLogger = Logger(subsystem: "com.jackwallner.recovery", category: "Connectivity")

/// The two-way link between the phone and the Watch.
///
/// The phone owns the model: it has the full HealthKit store and the long
/// history, so it calculates and everything else reads. But "reads" cannot mean
/// "reads the App Group" across devices — the iPhone and the Watch have
/// *separate* App Group containers, and nothing the phone writes to
/// `group.com.jackwallner.recovery` on iOS is ever visible to the watchOS app or
/// its complication. WatchConnectivity is the only bridge, so both directions
/// run through here.
///
/// **Phone → Watch (the snapshot).** `RecoveryEngine.publish` hands the freshly
/// calculated `RecoverySnapshot` to `sendSnapshot`, which puts it in the
/// application context: a single latest-value-wins dictionary the system
/// delivers in the background, replaying the most recent one on activation. The
/// Watch writes it into its *own* App Group so `WatchTodayView` and
/// `RecoveryTimelineProvider` keep reading `RecoverySnapshotStore` exactly as
/// they did. The complication style rides along, because the extension reads it
/// from the same suite.
///
/// **Watch → phone (the effort answer).** The RPE tap has to travel the other
/// way, because the user answers it on the wrist right after a lifting session
/// and only the phone can recalculate. Three delivery routes, in order of
/// preference:
///
/// 1. `sendMessage` when the phone is reachable — instant, the countdown updates
///    while the user is still looking at the watch;
/// 2. `transferUserInfo` otherwise — a FIFO queue the system drains when the
///    phone comes back, which survives the app being killed;
/// 3. a local App Group queue as the backstop, replayed on the next launch, for
///    the case where WatchConnectivity itself is unavailable.
@MainActor
public final class PhoneWatchSession: NSObject, ObservableObject {
    public static let shared = PhoneWatchSession()

    public enum MessageKey {
        public static let action = "action"
        public static let sessionID = "sessionID"
        public static let effort = "effort"
        public static let sentAt = "sentAt"
        public static let snapshot = "snapshot"
        public static let pendingEffortSessionID = "pendingEffortSessionID"
        public static let complicationStyle = "complicationStyle"
    }

    public enum Action {
        public static let recordEffort = "recordEffort"
        /// Watch → phone: "I am not rating this one." Travels the same three
        /// routes as an answer, because a decline that never arrives means the
        /// phone keeps re-issuing the request.
        public static let declineEffort = "declineEffort"
        /// Watch → phone: "I have just launched, send me the current model."
        /// Covers the cold start where no application context has been queued
        /// since the app was installed.
        public static let requestSnapshot = "requestSnapshot"
    }

    /// Last user-facing status, e.g. "Saved" or "Will sync with iPhone".
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var isReachable = false
    /// Bumped every time an inbound snapshot lands, so the Watch view re-reads
    /// the App Group without polling for it.
    @Published public private(set) var snapshotRevision = 0
    /// When the Watch last received a snapshot from the phone. `nil` means the
    /// two have never talked, which is a different state from "no workout yet".
    @Published public private(set) var lastSnapshotReceived: Date?

    private static let pendingQueueKey = "pendingEffortQueue"
    private static let lastSnapshotReceivedKey = "lastSnapshotReceived"
    /// The phone-side `sentAt` of the newest payload the Watch has accepted.
    /// Persisted rather than held in memory because the Watch app is killed
    /// between background wakes, and an ordering rule that forgets its high
    /// water mark on every launch is not an ordering rule.
    private static let lastAcceptedSentAtKey = "lastAcceptedSentAt"
    private var clearTask: Task<Void, Never>?
    private var isSnapshotRequestInFlight = false

    private override init() {
        super.init()
        lastSnapshotReceived = UserDefaults(suiteName: rechargeAppGroupID)?
            .object(forKey: Self.lastSnapshotReceivedKey) as? Date
    }

    public func activate() {
        guard WCSession.isSupported() else {
            connectivityLogger.info("WatchConnectivity unavailable on this device")
            return
        }
        let session = WCSession.default
        session.delegate = self
        session.activate()
        isReachable = session.isReachable
        #if os(watchOS)
        // The system replays the last application context on activation, but
        // only into `receivedApplicationContext` — the delegate callback does
        // not fire again for something already delivered. Read it by hand.
        applyInboundSnapshot(session.receivedApplicationContext)
        flushPendingQueue()
        requestSnapshotIfReachable()
        #endif
    }

    /// Waits for `WCSession` to finish activating, which `activate()` starts
    /// and does not await.
    ///
    /// Both platforms need this and for the same reason: a background wake runs
    /// in a process that has only just called `activate()`, and every send and
    /// every delivery check is guarded on `activationState == .activated`. A
    /// task that completes before activation lands does its work against a
    /// session that cannot carry it — silently, because each of those guards is
    /// a bare `return`.
    ///
    /// - Returns: whether the session reached `.activated` within the timeout.
    @discardableResult
    public func waitForActivation(timeout: TimeInterval) async -> Bool {
        let deadline = Date.now.addingTimeInterval(timeout)
        while WCSession.default.activationState != .activated, Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
        guard WCSession.default.activationState == .activated else {
            connectivityLogger.error("Connectivity activation timed out")
            return false
        }
        return true
    }

    // MARK: - Watch side

    #if os(watchOS)
    /// Sends one effort answer to the phone, queueing it if the phone is not
    /// reachable. Always reports success to the user: the answer is durably
    /// recorded either way, and a "couldn't send" toast for something the system
    /// will deliver in a minute is just noise.
    public func sendEffort(_ effort: Double, forSessionID sessionID: String) {
        send(
            payload: [
                MessageKey.action: Action.recordEffort,
                MessageKey.sessionID: sessionID,
                MessageKey.effort: effort,
                MessageKey.sentAt: Date.now.timeIntervalSince1970
            ],
            confirmation: "Saved."
        )
    }

    /// Tells the phone to stop asking about this session, and retires the
    /// request locally straight away so the button disappears on the tap rather
    /// than on the round trip.
    public func declineEffort(forSessionID sessionID: String) {
        UserDefaults(suiteName: rechargeAppGroupID)?.removeObject(forKey: "pendingEffortSessionID")
        snapshotRevision &+= 1
        send(
            payload: [
                MessageKey.action: Action.declineEffort,
                MessageKey.sessionID: sessionID,
                MessageKey.sentAt: Date.now.timeIntervalSince1970
            ],
            confirmation: nil
        )
    }

    /// Always reports success to the user: the payload is durably recorded
    /// either way, and a "couldn't send" toast for something the system will
    /// deliver in a minute is just noise. `confirmation` is nil for a decline,
    /// which needs no reassurance that anything was saved.
    private func send(payload: [String: Any], confirmation: String?) {
        let session = WCSession.default
        guard session.activationState == .activated else {
            enqueue(payload)
            confirm(confirmation.map { _ in "Saved. Will sync with iPhone." })
            return
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                connectivityLogger.error("sendMessage failed: \(String(describing: error), privacy: .public)")
                // The immediate path failed, so fall back to the durable queue
                // rather than dropping the user's answer.
                Task { @MainActor in
                    _ = session.transferUserInfo(payload)
                    // `transferUserInfo` is already the durable FIFO path. Do
                    // not also place the same payload in the local backstop,
                    // or activation would deliver the answer twice.
                }
            }
            confirm(confirmation)
        } else {
            // FIFO, survives termination, drains when the phone reappears.
            session.transferUserInfo(payload)
            confirm(confirmation.map { _ in "Saved. Will sync with iPhone." })
        }
    }

    private func confirm(_ message: String?) {
        guard let message else { return }
        WKInterfaceDevice.current().play(.success)
        statusMessage = message
        clearTask?.cancel()
        clearTask = Task { @MainActor [weak self] in
            try? await Task.sleep(for: .seconds(3))
            guard !Task.isCancelled else { return }
            self?.statusMessage = nil
        }
    }

    /// Backstop queue in the App Group, replayed on activation. Only used when
    /// `transferUserInfo` itself could not be reached.
    private func enqueue(_ payload: [String: Any]) {
        let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard
        var queue = defaults.array(forKey: Self.pendingQueueKey) as? [[String: Any]] ?? []
        // Newer answers for the same session replace older ones.
        queue.removeAll { ($0[MessageKey.sessionID] as? String) == (payload[MessageKey.sessionID] as? String) }
        queue.append(payload)
        defaults.set(queue, forKey: Self.pendingQueueKey)
    }

    private func flushPendingQueue() {
        let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard
        guard let queue = defaults.array(forKey: Self.pendingQueueKey) as? [[String: Any]], !queue.isEmpty else {
            return
        }
        let session = WCSession.default
        guard session.activationState == .activated else { return }
        for payload in queue {
            session.transferUserInfo(payload)
        }
        defaults.removeObject(forKey: Self.pendingQueueKey)
        connectivityLogger.info("Flushed \(queue.count, privacy: .public) queued effort answers")
    }

    /// Inbound snapshots handed over by the WatchConnectivity delegate queue
    /// but not yet written to the App Group. See `waitForPendingContent`.
    private nonisolated static let inflightApplies = OSAllocatedUnfairLock(initialState: 0)

    /// Waits until WatchConnectivity has finished handing over whatever it woke
    /// us for.
    ///
    /// `WKWatchConnectivityRefreshBackgroundTask` is the system saying "data is
    /// arriving, stay alive". Completing that task before `hasContentPending`
    /// clears tells the system the app is done and lets the payload be dropped —
    /// which is the difference between a complication that updates itself after
    /// a workout and one the user has to open the Watch app to refresh.
    ///
    /// Polled rather than awaited on a callback because WatchConnectivity offers
    /// no completion for "the queue is now empty"; `hasContentPending` is the
    /// documented way to ask.
    public func waitForPendingContent(timeout: TimeInterval) async {
        let deadline = Date.now.addingTimeInterval(timeout)
        // A false `hasContentPending` value before activation completes means
        // "not ready to report", not "the payload has landed".
        guard await waitForActivation(timeout: timeout) else { return }

        // `hasContentPending` clearing is not the same as the payload being on
        // disk. WatchConnectivity calls its delegate on its own queue, and
        // `forwardSnapshot` has to hop to the main actor before
        // `applyInboundSnapshot` writes the App Group — so the flag can go
        // false with that hop still queued. Completing the task there suspends
        // the app between "delivered" and "saved", which loses the payload as
        // surely as completing the task too early does, and leaves the
        // complication rendering the previous countdown. The counter is
        // incremented on the delegate queue, before the hop, so by the time
        // `hasContentPending` is false every delivery is accounted for.
        while WCSession.default.hasContentPending || Self.inflightApplies.withLock({ $0 > 0 }),
              Date.now < deadline {
            try? await Task.sleep(for: .milliseconds(150))
        }
        if WCSession.default.hasContentPending {
            connectivityLogger.error("Connectivity wake timed out with content still pending")
        }
        applyReplayedContext()
    }

    /// Pulls a fresh snapshot when the phone is right there. The application
    /// context alone would eventually arrive, but "eventually" is not good
    /// enough for a user who just raised their wrist.
    private func requestSnapshotIfReachable() {
        let session = WCSession.default
        guard session.activationState == .activated,
              session.isReachable,
              !isSnapshotRequestInFlight
        else { return }
        isSnapshotRequestInFlight = true
        session.sendMessage(
            [MessageKey.action: Action.requestSnapshot],
            replyHandler: Self.receiveSnapshotReply,
            errorHandler: Self.receiveSnapshotError
        )
    }

    /// WatchConnectivity invokes reply handlers on its delegate queue. Keep the
    /// callback itself nonisolated, then narrow the property-list payload before
    /// crossing to the main actor.
    private nonisolated static func receiveSnapshotReply(_ payload: [String: Any]) {
        let data = payload[MessageKey.snapshot] as? Data
        let pending = payload[MessageKey.pendingEffortSessionID] as? String
        let style = payload[MessageKey.complicationStyle] as? Int
        let sentAt = payload[MessageKey.sentAt] as? TimeInterval
        Task { @MainActor in
            PhoneWatchSession.shared.isSnapshotRequestInFlight = false
            guard data != nil else { return }
            var narrowed: [String: Any] = [:]
            narrowed[MessageKey.snapshot] = data
            narrowed[MessageKey.pendingEffortSessionID] = pending
            narrowed[MessageKey.complicationStyle] = style
            narrowed[MessageKey.sentAt] = sentAt
            // A direct answer to "send me the current model" is current by
            // construction, and it is also the only way out if the phone's
            // clock ever moves backwards far enough to wedge the ordering rule.
            PhoneWatchSession.shared.applyInboundSnapshot(narrowed, isAuthoritative: true)
        }
    }

    private nonisolated static func receiveSnapshotError(_ error: Error) {
        // Not a user-facing failure: the application context still arrives.
        connectivityLogger.info("Snapshot request failed: \(String(describing: error), privacy: .public)")
        Task { @MainActor in
            PhoneWatchSession.shared.isSnapshotRequestInFlight = false
        }
    }

    /// Writes a phone-authored payload into the Watch's own App Group, which is
    /// what every Watch surface already reads.
    ///
    /// **Late payloads are dropped.** The phone reaches the wrist by two routes
    /// with different delivery semantics: the application context is a single
    /// latest-value-wins slot, while `transferUserInfo` is a FIFO queue that
    /// drains whenever the two next manage to talk. A queued transfer from
    /// before a reconnect can therefore arrive *after* a newer context and
    /// overwrite it, which on screen is a countdown that jumps backwards to a
    /// window the user already watched expire. That reads as a broken app, and
    /// worse, it can change what somebody does next.
    ///
    /// `sentAt` was already on every payload as a cache-buster, because
    /// `updateApplicationContext` is free to no-op on a byte-identical dict. It
    /// costs nothing to also believe it.
    ///
    /// The snapshot's own `calculatedAt` would be the more natural key and is
    /// the wrong one: `RecoverySnapshot.empty` carries `.distantPast`, and the
    /// phone legitimately publishes an empty snapshot when the last workout is
    /// deleted from Health. Ordering on `calculatedAt` would refuse the one
    /// payload whose whole job is to clear the wrist.
    ///
    /// - Parameter isAuthoritative: skips the ordering check for a payload that
    ///   is current by construction, i.e. the reply to an explicit request.
    private func applyInboundSnapshot(_ payload: [String: Any], isAuthoritative: Bool = false) {
        guard let data = payload[MessageKey.snapshot] as? Data,
              let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: data)
        else { return }

        let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard
        let sentAt = payload[MessageKey.sentAt] as? TimeInterval
        if !isAuthoritative, let sentAt, let accepted = lastAcceptedSentAt(defaults: defaults),
           sentAt < accepted {
            connectivityLogger.info(
                "Dropped a late snapshot, sentAt=\(sentAt, privacy: .public) behind \(accepted, privacy: .public)"
            )
            return
        }

        // Applying the same payload twice is normal and has to stay cheap. The
        // system replays the last application context on every activation, so
        // a wrist that has heard nothing new since yesterday still runs this
        // path on each background wake, and `reloadAllTimelines` spends
        // WidgetKit's refresh budget whether or not anything moved.
        let pendingSessionID = payload[MessageKey.pendingEffortSessionID] as? String
        let style = payload[MessageKey.complicationStyle] as? Int
        let isUnchanged = RecoverySnapshotStore.loadIfPresent(defaults: defaults) == snapshot
            && pendingSessionID == defaults.string(forKey: "pendingEffortSessionID")
            && (style == nil || style == defaults.integer(forKey: SettingsKeys.complicationStyle))

        RecoverySnapshotStore.save(snapshot, defaults: defaults)
        // A payload with no `sentAt` is a degraded path rather than an error:
        // it is applied, but it must not advance the high water mark, or one
        // undated delivery would start rejecting dated ones.
        if let sentAt { defaults.set(sentAt, forKey: Self.lastAcceptedSentAtKey) }

        if let pendingSessionID {
            defaults.set(pendingSessionID, forKey: "pendingEffortSessionID")
        } else {
            defaults.removeObject(forKey: "pendingEffortSessionID")
        }
        if let style {
            defaults.set(style, forKey: SettingsKeys.complicationStyle)
        }
        let now = Date.now
        defaults.set(now, forKey: Self.lastSnapshotReceivedKey)
        lastSnapshotReceived = now

        guard !isUnchanged else {
            connectivityLogger.info("Re-applied an unchanged phone snapshot; timelines left alone")
            return
        }
        snapshotRevision &+= 1
        WidgetCenter.shared.reloadAllTimelines()
        connectivityLogger.info("Applied phone snapshot, readyAt=\(String(describing: snapshot.readyAt), privacy: .public)")
    }

    /// Writes whatever the system replayed into `receivedApplicationContext`,
    /// synchronously, on the main actor.
    ///
    /// The delegate route cannot cover this. `didReceiveApplicationContext`
    /// fires only for something newly delivered, and the replay on activation
    /// arrives with no callback at all — `activationDidCompleteWith` reads it,
    /// but through a `Task` hop that a background task is free to complete out
    /// from under. On a backstop wake there is no pending content to wait for,
    /// so that hop is the *only* thing that would have written the App Group,
    /// and it loses the race by default. Idempotent: an unchanged payload stops
    /// before touching the timelines.
    private func applyReplayedContext() {
        applyInboundSnapshot(WCSession.default.receivedApplicationContext)
    }

    /// The newest `sentAt` accepted so far, or nil when the two have never
    /// talked. Read back off disk rather than cached, because a widget-driven
    /// background wake gets a fresh process.
    private func lastAcceptedSentAt(defaults: UserDefaults) -> TimeInterval? {
        defaults.object(forKey: Self.lastAcceptedSentAtKey) as? TimeInterval
    }
    #endif

    // MARK: - Phone side

    #if os(iOS)
    /// Applies an inbound effort answer, or a decline, and recalculates
    /// immediately.
    fileprivate func apply(action: String, sessionID: String, effort: Double?) {
        switch action {
        case Action.recordEffort:
            guard let effort else { return }
            connectivityLogger.info("Effort \(effort, privacy: .public) received for session \(sessionID, privacy: .public)")
            RecoveryEngine.shared.recordEffort(effort, forSessionID: sessionID)
        case Action.declineEffort:
            connectivityLogger.info("Effort declined for session \(sessionID, privacy: .public)")
            RecoveryEngine.shared.declineEffort(forSessionID: sessionID)
        default:
            return
        }
    }

    /// Pushes the model to the Watch. Called from `RecoveryEngine.publish`, so
    /// every recalculation the phone does reaches the wrist by the same route
    /// that reaches the iOS widgets.
    ///
    /// The application context is a single latest-value-wins slot: a snapshot
    /// queued while the Watch is off the wrist is simply replaced by the next
    /// one, which is the right semantics for a countdown. `sentAt` guarantees
    /// two consecutive publishes are never byte-identical, because
    /// `updateApplicationContext` is free to no-op on an unchanged payload.
    public func sendSnapshot(
        _ snapshot: RecoverySnapshot,
        pendingEffortSessionID: String?,
        complicationStyle: Int
    ) {
        guard WCSession.isSupported() else { return }
        let session = WCSession.default
        guard session.activationState == .activated, session.isPaired, session.isWatchAppInstalled else { return }
        guard let data = try? JSONEncoder().encode(snapshot) else { return }

        var payload: [String: Any] = [
            MessageKey.snapshot: data,
            MessageKey.complicationStyle: complicationStyle,
            MessageKey.sentAt: Date.now.timeIntervalSince1970
        ]
        if let pendingEffortSessionID {
            payload[MessageKey.pendingEffortSessionID] = pendingEffortSessionID
        }

        do {
            try session.updateApplicationContext(payload)
        } catch {
            connectivityLogger.error("Snapshot context failed: \(String(describing: error), privacy: .public)")
            // The context slot rejected the payload, so fall back to the FIFO
            // queue rather than leaving the Watch on a stale countdown.
            session.transferUserInfo(payload)
        }
    }

    /// The payload the Watch asks for on launch. Built from the App Group so it
    /// is exactly what the phone last published, with no re-entry into the
    /// engine from a background delegate callback — which also means it can be
    /// answered straight from the WatchConnectivity queue. `UserDefaults` is
    /// thread-safe; hopping to the main actor first would mean sending the
    /// non-`Sendable` reply handler across an isolation boundary.
    fileprivate nonisolated static func currentSnapshotPayload() -> [String: Any] {
        let defaults = UserDefaults(suiteName: rechargeAppGroupID)
        var payload: [String: Any] = [
            MessageKey.complicationStyle: defaults?.integer(forKey: SettingsKeys.complicationStyle) ?? 0,
            MessageKey.sentAt: Date.now.timeIntervalSince1970
        ]
        if let data = try? JSONEncoder().encode(RecoverySnapshotStore.load(defaults: defaults)) {
            payload[MessageKey.snapshot] = data
        }
        if let pending = defaults?.string(forKey: "pendingEffortSessionID") {
            payload[MessageKey.pendingEffortSessionID] = pending
        }
        return payload
    }
    #endif
}

extension PhoneWatchSession: WCSessionDelegate {
    public nonisolated func session(
        _ session: WCSession,
        activationDidCompleteWith activationState: WCSessionActivationState,
        error: Error?
    ) {
        if let error {
            connectivityLogger.error("Activation failed: \(String(describing: error), privacy: .public)")
        }
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            #if os(watchOS)
            self?.applyInboundSnapshot(WCSession.default.receivedApplicationContext)
            self?.flushPendingQueue()
            self?.requestSnapshotIfReachable()
            #else
            // Activation is asynchronous, and the launch sequence is
            // `activate()` then `refresh()` then `publish()` — so the first
            // publish of the session almost always runs before the session is
            // usable and its snapshot is dropped on the guard in
            // `sendSnapshot`. Push once more now that the link is up.
            RecoveryEngine.shared.publish()
            #endif
        }
    }

    public nonisolated func sessionReachabilityDidChange(_ session: WCSession) {
        // Read the flag on the delegate queue; `WCSession` itself is not
        // `Sendable`, so only the value crosses onto the main actor.
        let reachable = session.isReachable
        Task { @MainActor [weak self] in
            self?.isReachable = reachable
            #if os(watchOS)
            if reachable {
                self?.flushPendingQueue()
                self?.requestSnapshotIfReachable()
            }
            #endif
        }
    }

    #if os(watchOS)
    public nonisolated func session(_ session: WCSession, didReceiveApplicationContext context: [String: Any]) {
        forwardSnapshot(context)
    }

    public nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        forwardSnapshot(userInfo)
    }

    /// `[String: Any]` is not `Sendable`, so the payload is narrowed to the
    /// property-list values we actually use before it crosses onto the main actor.
    private nonisolated func forwardSnapshot(_ payload: [String: Any]) {
        let data = payload[MessageKey.snapshot] as? Data
        let pending = payload[MessageKey.pendingEffortSessionID] as? String
        let style = payload[MessageKey.complicationStyle] as? Int
        let sentAt = payload[MessageKey.sentAt] as? TimeInterval
        guard data != nil else { return }
        // Counted here, on the delegate queue, rather than inside the task:
        // the whole point is to be visible before the hop, so a background wake
        // cannot complete in the gap.
        Self.inflightApplies.withLock { $0 += 1 }
        Task { @MainActor [weak self] in
            defer { Self.inflightApplies.withLock { $0 -= 1 } }
            var narrowed: [String: Any] = [:]
            narrowed[MessageKey.snapshot] = data
            narrowed[MessageKey.pendingEffortSessionID] = pending
            narrowed[MessageKey.complicationStyle] = style
            narrowed[MessageKey.sentAt] = sentAt
            self?.applyInboundSnapshot(narrowed)
        }
    }
    #endif

    #if os(iOS)
    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        forward(message)
    }

    public nonisolated func session(
        _ session: WCSession,
        didReceiveMessage message: [String: Any],
        replyHandler: @escaping ([String: Any]) -> Void
    ) {
        guard (message[MessageKey.action] as? String) == Action.requestSnapshot else {
            forward(message)
            replyHandler([:])
            return
        }
        replyHandler(Self.currentSnapshotPayload())
    }

    public nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        forward(userInfo)
    }

    /// A newly paired or reinstalled Watch starts with nothing; push the current
    /// model the moment it becomes reachable rather than waiting for the next
    /// workout.
    public nonisolated func sessionWatchStateDidChange(_ session: WCSession) {
        Task { @MainActor in
            RecoveryEngine.shared.publish()
        }
    }

    /// `[String: Any]` is not `Sendable`, so the payload is narrowed to the
    /// three values we actually use before it crosses onto the main actor.
    /// The effort is optional because a decline carries no rating.
    private nonisolated func forward(_ payload: [String: Any]) {
        guard let action = payload[MessageKey.action] as? String,
              let sessionID = payload[MessageKey.sessionID] as? String
        else {
            connectivityLogger.error("Ignoring malformed connectivity payload")
            return
        }
        let effort = payload[MessageKey.effort] as? Double
        Task { @MainActor [weak self] in
            self?.apply(action: action, sessionID: sessionID, effort: effort)
        }
    }

    // Required on iOS so a Watch re-pair does not leave the session dead.
    public nonisolated func sessionDidBecomeInactive(_ session: WCSession) {}

    public nonisolated func sessionDidDeactivate(_ session: WCSession) {
        WCSession.default.activate()
    }
    #endif
}
