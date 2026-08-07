import SwiftUI
import WatchKit

@main
struct RechargeWatchApp: App {
    @WKApplicationDelegateAdaptor(WatchAppDelegate.self) private var delegate

    var body: some Scene {
        WindowGroup {
            WatchTodayView()
        }
    }
}

/// Activates WatchConnectivity at launch rather than waiting for the view.
///
/// The phone pushes the snapshot through the application context, and the
/// system delivers that by waking the Watch app in the background — but only if
/// a `WCSession` has been activated with a delegate attached. Doing it in
/// `WatchTodayView.onAppear` alone meant the complication could only ever be as
/// fresh as the last time the user opened the app, which is precisely backwards
/// for a face complication.
final class WatchAppDelegate: NSObject, WKApplicationDelegate {
    func applicationDidFinishLaunching() {
        Task { @MainActor in
            PhoneWatchSession.shared.activate()
        }
    }

    func handle(_ backgroundTasks: Set<WKRefreshBackgroundTask>) {
        for task in backgroundTasks {
            Task { @MainActor in
                PhoneWatchSession.shared.activate()
                task.setTaskCompletedWithSnapshot(false)
            }
        }
    }
}
