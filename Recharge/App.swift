import SwiftData
import SwiftUI
import UserNotifications

@main
struct RechargeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = RechargeSettings.shared
    @StateObject private var store = StoreService.shared
    @StateObject private var engine = RecoveryEngine.shared

    init() {
        UNUserNotificationCenter.current().delegate = RechargeNotificationDelegate.shared
        ReviewPromptTracker.recordAppLaunch()
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environmentObject(settings)
                .environmentObject(store)
                .environmentObject(engine)
                .preferredColorScheme(settings.appearance.colorScheme)
                .task {
                    store.start()
                    // The phone is the model owner, so it is also the side that
                    // listens for the Watch's effort answers.
                    PhoneWatchSession.shared.activate()
                    // Onboarding owns the first Health prompt — it explains what
                    // Recharge reads and why before asking. Firing the system
                    // sheet at launch would put the permission dialog in front
                    // of a user who has not seen a single screen yet.
                    if settings.hasCompletedSetup {
                        if !settings.hasDeferredHealthAccess {
                            await HealthKitService.shared.synchronizeAuthorization()
                            await engine.refresh(force: true)
                        } else {
                            // Respect "Not now" while still restoring any cached
                            // history that existed before access was deferred.
                            engine.rescore()
                            engine.publish()
                        }
                    } else if ScreenshotConfig.isEnabled {
                        await engine.refresh(force: true)
                    }
                }
                .onChange(of: scenePhase) { _, phase in
                    guard phase == .active,
                          settings.hasCompletedSetup,
                          !settings.hasDeferredHealthAccess
                    else { return }
                    // Always refresh on foreground: "no data" and "denied" are
                    // indistinguishable for reads, so gating on `isAuthorized`
                    // would blank the screen after one flaky launch-time probe.
                    Task { await engine.refresh() }
                }
        }
        .modelContainer(DataService.sharedModelContainer)
    }
}
