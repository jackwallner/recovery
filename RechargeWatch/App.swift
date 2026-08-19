import SwiftUI
import WatchKit
import WidgetKit

@main
struct RechargeWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
        }
    }
}

/// The Watch app is a mirror, and this delegate is the whole reason it can be
/// one without the user ever opening it.
///
/// The user should never have to launch the Watch app for the complication to
/// work, and nothing about the architecture requires it. The phone owns the
/// model and pushes every recalculation through `updateApplicationContext`; the
/// system wakes this app in the background to take delivery; this app writes the
/// snapshot into the Watch's App Group and reloads the timelines. The
/// complication then reads it off disk, which is all a widget extension can do —
/// it is not a running process that can be sent anything, it is spun up to
/// answer "give me a timeline" and torn down again, so whatever it needs has to
/// already be on disk when it is asked.
///
/// Three things in the previous version of `handle(_:)` broke that chain, and
/// between them they made "open the Watch app first" the normal case rather than
/// the rare one:
///
/// 1. **It completed every task immediately.** A
///    `WKWatchConnectivityRefreshBackgroundTask` is the system saying "I am
///    waking you because data is arriving"; completing it before
///    `hasContentPending` clears tells the system the app is done and the
///    payload can be dropped. This is the one that mattered most: it is the
///    exact task the phone's push generates.
/// 2. **It never scheduled the next refresh.** watchOS background refresh is a
///    chain — a handler that does not schedule its successor gets no more — so
///    the app went quiet after the first wake and the face went stale.
/// 3. **It treated every task type alike.** A snapshot task has its own
///    completion call and does not take `setTaskCompletedWithSnapshot`.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {

    /// Backstop cadence. WatchConnectivity delivery is the primary path and is
    /// event-driven; this only covers the case where a push was missed entirely.
    private static let refreshInterval: TimeInterval = 30 * 60

    /// How long a connectivity wake may wait for the payload to finish landing.
    /// watchOS gives a background task a few seconds of runtime, so this is a
    /// ceiling that should never be reached rather than a timeout to plan for.
    private static let connectivityDeliveryTimeout: TimeInterval = 8

    func applicationDidFinishLaunching() {
        Task { @MainActor in
            PhoneWatchSession.shared.activate()
            Self.scheduleNextRefresh()
#if DEBUG
            if ScreenshotConfig.isEnabled {
                UserDefaults(suiteName: rechargeAppGroupID)?.set(true, forKey: "rechargeScreenshotMode")
                RecoverySnapshotStore.save(ScreenshotFixtures.snapshot())
                WidgetCenter.shared.reloadAllTimelines()
            } else {
                UserDefaults(suiteName: rechargeAppGroupID)?.removeObject(forKey: "rechargeScreenshotMode")
            }
#endif
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            switch task {
            case let connectivity as WKWatchConnectivityRefreshBackgroundTask:
                // Hold the task open until WatchConnectivity says it has handed
                // everything over. `applyInboundSnapshot` runs off the delegate
                // callback during this window and is what actually writes the
                // App Group and reloads the complication.
                Task { @MainActor in
                    PhoneWatchSession.shared.activate()
                    await PhoneWatchSession.shared.waitForPendingContent(
                        timeout: Self.connectivityDeliveryTimeout
                    )
                    connectivity.setTaskCompletedWithSnapshot(false)
                }

            case let refresh as WKApplicationRefreshBackgroundTask:
                Task { @MainActor in
                    PhoneWatchSession.shared.activate()
                    // Schedule the successor before completing, or the chain
                    // ends here and this is the last time the app ever runs on
                    // its own.
                    Self.scheduleNextRefresh()
                    // `activate()` is asynchronous, and this task almost always
                    // runs in a *fresh* process — the app is killed between
                    // wakes — so completing here would suspend the app before
                    // the session finished activating and before
                    // `receivedApplicationContext` could be replayed into the
                    // App Group. That made the backstop wake a no-op in exactly
                    // the case it exists for: a push that was missed entirely.
                    await PhoneWatchSession.shared.waitForPendingContent(
                        timeout: Self.connectivityDeliveryTimeout
                    )
                    refresh.setTaskCompletedWithSnapshot(false)
                }

            case let snapshot as WKSnapshotRefreshBackgroundTask:
                snapshot.setTaskCompleted(
                    restoredDefaultState: true,
                    estimatedSnapshotExpiration: .distantFuture,
                    userInfo: nil
                )

            default:
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }

    @MainActor
    private static func scheduleNextRefresh() {
        WKApplication.shared().scheduleBackgroundRefresh(
            withPreferredDate: Date(timeIntervalSinceNow: refreshInterval),
            userInfo: nil
        ) { _ in }
    }
}
