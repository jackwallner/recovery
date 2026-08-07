import Foundation
import UserNotifications
import os

/// One local notification: the moment a recovery estimate expires.
///
/// It is scheduled at the exact `readyAt`, so unlike a recap nudge it can carry
/// real content — the app already knows what the answer will be. Pro-only, and
/// off by default.
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
            logger.info("Notification authorization granted=\(granted, privacy: .public)")
            return granted
        } catch {
            logger.error("Notification authorization failed: \(String(describing: error), privacy: .public)")
            return false
        }
    }

    public static func isAuthorized() async -> Bool {
        switch await UNUserNotificationCenter.current().notificationSettings().authorizationStatus {
        case .authorized, .provisional, .ephemeral: true
        default: false
        }
    }

    /// Schedules the Ready alert for a snapshot, replacing any previous one.
    /// A snapshot with no live countdown just cancels.
    public static func scheduleReadyNotification(for snapshot: RecoverySnapshot, now: Date = .now) {
        guard let readyAt = snapshot.readyAt, readyAt > now.addingTimeInterval(60) else {
            cancelReadyNotification()
            return
        }

        let content = UNMutableNotificationContent()
        content.title = "Ready"
        // Compliance: an estimate about training, never a claim about the body.
        content.body = snapshot.activityLabel.isEmpty
            ? "Your recovery estimate has run out. Ready for another hard session."
            : "Your estimate from that \(snapshot.activityLabel) has run out. Ready for another hard session."
        content.sound = .default
        content.userInfo = [routeKey: readyRouteValue]

        let trigger = UNTimeIntervalNotificationTrigger(
            timeInterval: max(readyAt.timeIntervalSince(now), 60),
            repeats: false
        )
        let request = UNNotificationRequest(
            identifier: readyNotificationID, content: content, trigger: trigger
        )

        let center = UNUserNotificationCenter.current()
        center.removePendingNotificationRequests(withIdentifiers: [readyNotificationID])
        center.add(request) { error in
            if let error {
                logger.error("Ready notification not scheduled: \(String(describing: error), privacy: .public)")
            }
        }
    }

    public static func cancelReadyNotification() {
        UNUserNotificationCenter.current()
            .removePendingNotificationRequests(withIdentifiers: [readyNotificationID])
    }
}

/// Routes a notification tap and keeps the alert visible in the foreground —
/// the Ready moment is the whole point of the app, so it should not be
/// swallowed just because the user happens to be looking at the screen.
public final class RechargeNotificationDelegate: NSObject, UNUserNotificationCenterDelegate, @unchecked Sendable {
    /// Stateless — every method hops to the main actor before touching anything —
    /// so the unchecked conformance is describing what the type already is.
    public static let shared = RechargeNotificationDelegate()

    private override init() { super.init() }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        willPresent notification: UNNotification
    ) async -> UNNotificationPresentationOptions {
        [.banner, .sound]
    }

    public func userNotificationCenter(
        _ center: UNUserNotificationCenter,
        didReceive response: UNNotificationResponse
    ) async {
        let route = response.notification.request.content.userInfo[NotificationService.routeKey] as? String
        await MainActor.run {
            RecoveryEngine.shared.publish()
            // The alert promised a Ready answer, so the tap has to land on it.
            // Republishing alone leaves a user who was reading History exactly
            // where they were, with nothing to show for the tap.
            guard route == NotificationService.readyRouteValue else { return }
            NotificationCenter.default.post(
                name: NotificationService.routeRequested,
                object: nil,
                userInfo: [NotificationService.routeKey: NotificationService.readyRouteValue]
            )
        }
    }
}
