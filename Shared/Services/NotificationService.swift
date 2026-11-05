import Foundation
import UserNotifications
import os

/// One local notification: the moment a recovery estimate expires.
///
/// It is scheduled at the exact `readyAt`, so unlike a recap nudge it can carry
/// real content, the app already knows when the estimate will end. Available on
/// every tier when notifications are allowed.
///
/// Not actor-isolated: every call goes through the thread-safe
/// `UNUserNotificationCenter`, and the routing constants have to be readable
/// from the (nonisolated) notification-center delegate.
public enum NotificationService {
    /// Stable identifier so re-scheduling replaces rather than stacks.
    public static let readyNotificationID = "recharge.ready"

    public static let routeKey = "route"
    public static let readyRouteValue = "today"

    /// Posted when a tap should move the user to a tab. `RootView` listens.
    /// A `Notification.Name` rather than a shared route object because the
    /// delegate is nonisolated and the only consumer is one view.
    public static let routeRequested = Notification.Name("rechargeRouteRequested")

    private static let logger = Logger(subsystem: "com.jackwallner.recovery", category: "Notifications")

    @discardableResult
    public static func requestAuthorization() async -> Bool {
        do {
            let granted = try await UNUserNotificationCenter.current()
                .requestAuthorization(options: [.alert, .sound, .badge])
            logger.info("Notification authorization granted=\(granted, privacy: .private)")
            return granted
        } catch {
            logger.error("Notification authorization failed: \(String(describing: error), privacy: .private)")
            return false
        }
    }

    public static func isAuthorized() async -> Bool {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Every call into the notification center that is not `async` is a
    /// synchronous XPC round trip to `usernotificationsd`
    /// (`removePendingNotificationRequests` blocks on the reply). `publish()`
    /// runs on the main actor, so on a loaded machine the main thread sat in
    /// `xpc_connection_send_message_with_reply_sync` for a minute or more: the
    /// app never went idle and every UI query against it timed out (spindump of
    /// the CI failures, 2026-11-01). They run here, in order, off the main thread.
    private static let queue = DispatchQueue(label: "com.jackwallner.recovery.ready-notification", qos: .utility)

    /// Schedules the Ready alert for a snapshot, replacing any previous one.
    /// A snapshot with no live countdown just cancels. Returns immediately.
    public static func scheduleReadyNotification(for snapshot: RecoverySnapshot, now: Date = .now) {
        guard let readyAt = snapshot.readyAt, readyAt > now else {
            cancelReadyNotification()
            return
        }

        let body = readyBody(for: snapshot)
        let interval = max(readyAt.timeIntervalSince(now), 1)
        queue.async {
            let content = UNMutableNotificationContent()
            content.title = readyTitle
            content.body = body
            content.sound = .default
            content.userInfo = [routeKey: readyRouteValue]

            let trigger = UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false)
            let request = UNNotificationRequest(
                identifier: readyNotificationID, content: content, trigger: trigger
            )

            let center = UNUserNotificationCenter.current()
            center.removePendingNotificationRequests(withIdentifiers: [readyNotificationID])
            center.add(request) { error in
                if let error {
                    logger.error("Ready notification not scheduled: \(String(describing: error), privacy: .private)")
                }
            }
        }
    }

    /// "Ready" is the token every other surface uses for this moment, so the
    /// alert announcing it should not invent a third phrasing.
    static var readyTitle: String { String(localized: "Ready", bundle: .recharge) }

    /// Names the session the countdown came from when there is one. The copy
    /// this replaced said the countdown was complete and then said it again
    /// ("Your recovery countdown is complete. No countdown is active."), which
    /// reads like two notifications stapled together.
    ///
    /// Compliance: an estimate about training, never a claim about the body.
    static func readyBody(for snapshot: RecoverySnapshot) -> String {
        snapshot.activityLabel.isEmpty
            ? String(localized: "Your recovery countdown has finished.", bundle: .recharge)
            : WorkoutClassifier.readyBody(snapshot.activityLabel)
    }

    public static func cancelReadyNotification() {
        queue.async {
            UNUserNotificationCenter.current()
                .removePendingNotificationRequests(withIdentifiers: [readyNotificationID])
        }
    }
}

/// Routes a notification tap and keeps the alert visible in the foreground —
/// the Ready moment is the whole point of the app, so it should not be
/// swallowed just because the user happens to be looking at the screen.
public final class RechargeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Stateless — every method hops to the main actor before touching anything —
    /// so the unchecked conformance is describing what the type already is.
    public static let shared = RechargeNotificationDelegate()

    /// Extra main-actor work to run when a notification is tapped, installed by
    /// `RechargeApp.init`. It is a closure rather than a direct
    /// `RecoveryEngine.shared.publish()` so this file carries no HealthKit or
    /// SwiftData dependency and the thing that actually broke here, which thread
    /// the completion handler is called on, is testable on its own.
    public static let onTap = MainActorBox<() -> Void>({})

    private override init() { super.init() }

    // **Both callbacks take the completion-handler form deliberately.** The
    // `async` spelling reads better, but the compiler-generated `@objc` thunk
    // resumes on a cooperative thread and calls UIKit's completion handler from
    // there. UIKit answers a tap by writing the state-restoration archive
    // (`_updateSnapshotAndStateRestorationWithAction:`), which asserts the main
    // thread, so every tap on the Ready alert aborted the app with SIGABRT.
    // Dispatching to `.main` ourselves is the only way to control that thread.

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification,
        withCompletionHandler completionHandler: @escaping (UNNotificationPresentationOptions) -> Void
    ) {
        let handler = UncheckedBox(completionHandler)
        DispatchQueue.main.async {
            handler.value([.banner, .sound])
        }
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse,
        withCompletionHandler completionHandler: @escaping () -> Void
    ) {
        let route = response.notification.request.content.userInfo[NotificationService.routeKey] as? String
        Self.handleTap(route: route, completionHandler: completionHandler)
    }

    /// The body of the tap, split out from the `@objc` entry point so a test can
    /// call it off the main thread without having to forge a
    /// `UNNotificationResponse`, which has no public initialiser. The entry
    /// point above does nothing but read the route out of `userInfo`.
    static func handleTap(route: String?, completionHandler: @escaping () -> Void) {
        let handler = UncheckedBox(completionHandler)
        DispatchQueue.main.async {
            onTap.value()
            // The alert promised a Ready answer, so the tap has to land on it.
            // Republishing alone leaves a user who was reading History exactly
            // where they were, with nothing to show for the tap.
            if route == NotificationService.readyRouteValue {
                NotificationCenter.default.post(
                    name: NotificationService.routeRequested,
                    object: nil,
                    userInfo: [NotificationService.routeKey: NotificationService.readyRouteValue]
                )
            }
            // Last, and unconditionally: UIKit watchdogs a response that is
            // never acknowledged.
            handler.value()
        }
    }
}

/// A `let` holding a `var` that only the main actor may touch, so the installed
/// tap handler is mutable without being a concurrency hazard.
public final class MainActorBox<T>: @unchecked Sendable {
    private var stored: T
    public init(_ value: T) { stored = value }
    @MainActor public var value: T {
        get { stored }
        set { stored = newValue }
    }
}

/// Carries a non-`Sendable` UIKit completion handler across the one hop to the
/// main queue. The handler is only ever called there, exactly once.
private struct UncheckedBox<T>: @unchecked Sendable {
    let value: T
    init(_ value: T) { self.value = value }
}
