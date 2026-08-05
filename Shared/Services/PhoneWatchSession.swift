import Foundation
import WatchConnectivity
import os
#if os(watchOS)
import WatchKit
#endif

private let connectivityLogger = Logger(subsystem: "com.jackwallner.recharge", category: "Connectivity")

/// Watch → phone writes for the effort (RPE) answer.
///
/// Every other data path in this app runs phone → Watch: the phone owns
/// HealthKit, writes the App Group snapshot, and the Watch reads it. The effort
/// tap is the one thing that has to travel the other way, because the user
/// answers it on the wrist right after a lifting session and only the phone can
/// recalculate.
///
/// Three delivery routes, in order of preference:
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
    }

    public enum Action {
        public static let recordEffort = "recordEffort"
    }

    /// Last user-facing status, e.g. "Saved" or "Will sync with iPhone".
    @Published public private(set) var statusMessage: String?
    @Published public private(set) var isReachable = false

    private static let pendingQueueKey = "pendingEffortQueue"
    private var clearTask: Task<Void, Never>?

    private override init() { super.init() }

    public func activate() {
        guard WCSession.isSupported() else {
            connectivityLogger.info("WatchConnectivity unavailable on this device")
            return
        }
        WCSession.default.delegate = self
        WCSession.default.activate()
        isReachable = WCSession.default.isReachable
        #if os(watchOS)
        flushPendingQueue()
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
    #endif

    // MARK: - Phone side

    #if os(iOS)
    /// Applies an inbound effort answer and recalculates immediately.
    fileprivate func apply(action: String, sessionID: String, effort: Double) {
        guard action == Action.recordEffort else { return }
        connectivityLogger.info("Effort \(effort, privacy: .public) received for session \(sessionID, privacy: .public)")
        RecoveryEngine.shared.recordEffort(effort, forSessionID: sessionID)
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
            self?.flushPendingQueue()
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
            if reachable { self?.flushPendingQueue() }
            #endif
        }
    }

    #if os(iOS)
    public nonisolated func session(_ session: WCSession, didReceiveMessage message: [String: Any]) {
        forward(message)
    }

    public nonisolated func session(_ session: WCSession, didReceiveUserInfo userInfo: [String: Any]) {
        forward(userInfo)
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
