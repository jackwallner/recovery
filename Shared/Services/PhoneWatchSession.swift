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
    private var clearTask: Task<Void, Never>?

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

    // MARK: - Watch side

    #if os(watchOS)
    /// Sends one effort answer to the phone, queueing it if the phone is not
    /// reachable. Always reports success to the user: the answer is durably
    /// recorded either way, and a "couldn't send" toast for something the system
    /// will deliver in a minute is just noise.
    public func sendEffort(_ effort: Double, forSessionID sessionID: String) {
        let payload: [String: Any] = [
            MessageKey.action: Action.recordEffort,
            MessageKey.sessionID: sessionID,
            MessageKey.effort: effort,
            MessageKey.sentAt: Date.now.timeIntervalSince1970
        ]

        let session = WCSession.default
        guard session.activationState == .activated else {
            enqueue(payload)
            confirm("Saved. Will sync with iPhone.")
            return
        }

        if session.isReachable {
            session.sendMessage(payload, replyHandler: nil) { error in
                connectivityLogger.error("sendMessage failed: \(String(describing: error), privacy: .public)")
                // The immediate path failed, so fall back to the durable queue
                // rather than dropping the user's answer.
                Task { @MainActor [weak self] in
                    session.transferUserInfo(payload)
                    self?.enqueue(payload)
                }
            }
            confirm("Saved.")
        } else {
            // FIFO, survives termination, drains when the phone reappears.
            session.transferUserInfo(payload)
            confirm("Saved. Will sync with iPhone.")
        }
    }

    private func confirm(_ message: String) {
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

    /// Pulls a fresh snapshot when the phone is right there. The application
    /// context alone would eventually arrive, but "eventually" is not good
    /// enough for a user who just raised their wrist.
    private func requestSnapshotIfReachable() {
        let session = WCSession.default
        guard session.activationState == .activated, session.isReachable else { return }
        session.sendMessage([MessageKey.action: Action.requestSnapshot], replyHandler: { reply in
            Task { @MainActor [weak self] in
                self?.applyInboundSnapshot(reply)
            }
        }, errorHandler: { error in
            // Not a user-facing failure: the application context still arrives.
            connectivityLogger.info("Snapshot request failed: \(String(describing: error), privacy: .public)")
        })
    }

    /// Writes a phone-authored payload into the Watch's own App Group, which is
    /// what every Watch surface already reads.
    private func applyInboundSnapshot(_ payload: [String: Any]) {
        guard let data = payload[MessageKey.snapshot] as? Data,
              let snapshot = try? JSONDecoder().decode(RecoverySnapshot.self, from: data)
        else { return }

        let defaults = UserDefaults(suiteName: rechargeAppGroupID) ?? .standard
        RecoverySnapshotStore.save(snapshot, defaults: defaults)

        if let sessionID = payload[MessageKey.pendingEffortSessionID] as? String {
            defaults.set(sessionID, forKey: "pendingEffortSessionID")
        } else {
            defaults.removeObject(forKey: "pendingEffortSessionID")
        }
        if let style = payload[MessageKey.complicationStyle] as? Int {
            defaults.set(style, forKey: SettingsKeys.complicationStyle)
        }
        defaults.set(snapshot.isPro, forKey: SettingsKeys.isProCached)

        let now = Date.now
        defaults.set(now, forKey: Self.lastSnapshotReceivedKey)
        lastSnapshotReceived = now
        snapshotRevision &+= 1

        WidgetCenter.shared.reloadAllTimelines()
        connectivityLogger.info("Applied phone snapshot, readyAt=\(String(describing: snapshot.readyAt), privacy: .public)")
    }
    #endif

    // MARK: - Phone side

    #if os(iOS)
    /// Applies an inbound effort answer and recalculates immediately.
    fileprivate func apply(action: String, sessionID: String, effort: Double) {
        guard action == Action.recordEffort else { return }
        connectivityLogger.info("Effort \(effort, privacy: .public) received for session \(sessionID, privacy: .public)")
        RecoveryEngine.shared.recordEffort(effort, forSessionID: sessionID)
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
        guard data != nil else { return }
        Task { @MainActor [weak self] in
            var narrowed: [String: Any] = [:]
            narrowed[MessageKey.snapshot] = data
            narrowed[MessageKey.pendingEffortSessionID] = pending
            narrowed[MessageKey.complicationStyle] = style
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
    private nonisolated func forward(_ payload: [String: Any]) {
        guard let action = payload[MessageKey.action] as? String,
              let sessionID = payload[MessageKey.sessionID] as? String,
              let effort = payload[MessageKey.effort] as? Double
        else {
            connectivityLogger.error("Ignoring malformed connectivity payload")
            return
        }
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
