import BackgroundTasks
import SwiftData
import SwiftUI
import UserNotifications

@main
struct RechargeApp: App {
    @Environment(\.scenePhase) private var scenePhase
    @StateObject private var settings = RechargeSettings.shared
    @StateObject private var store = StoreService.shared
    @StateObject private var engine = RecoveryEngine.shared

    /// Declared in `Info.plist` under `BGTaskSchedulerPermittedIdentifiers`.
    /// It was declared there and never registered, which is a background mode
    /// the app claims and does not use.
    private static let refreshTaskID = "com.jackwallner.recovery.refresh"

    /// How long a background wake may wait for `WCSession` to activate before
    /// giving up and doing the work anyway. Activation is normally immediate;
    /// this is a ceiling, not a budget to plan around.
    private static let activationTimeout: TimeInterval = 5

    init() {
        UNUserNotificationCenter.current().delegate = RechargeNotificationDelegate.shared
        ReviewPromptTracker.recordAppLaunch()

        BGTaskScheduler.shared.register(forTaskWithIdentifier: Self.refreshTaskID, using: DispatchQueue.main) { task in
            guard let task = task as? BGAppRefreshTask else { return }
            Self.handleAppRefresh(task)
        }
        Self.scheduleAppRefresh()

        // **This has to run on every launch, including the background ones
        // nobody sees.** It used to be reachable only from the scene's `.task`,
        // by way of `synchronizeAuthorization`, and a scene is not connected
        // when HealthKit background delivery relaunches the app — so the wake
        // that a finished workout generates arrived at an app with no observer
        // query running and did nothing at all. The phone then never
        // recalculated and never published, and the wrist stayed on the old
        // countdown until somebody opened the phone app by hand, which is the
        // exact failure the Watch background-wake path was built to avoid.
        // Apple's own guidance is to re-execute observer queries as early in
        // launch as possible, and `enableBackgroundDelivery` is idempotent
        // (`installedObserverTypes` de-duplicates), so the scene path calling
        // it again costs nothing.
        if RechargeSettings.shared.hasCompletedSetup, !RechargeSettings.shared.hasDeferredHealthAccess {
            HealthKitService.shared.enableBackgroundDelivery()
        }

        // Same reasoning, one link further along the chain, and moving only the
        // observer left this one behind. `sendSnapshot` is guarded on
        // `activationState == .activated` and returns silently otherwise, so a
        // background wake that recalculated perfectly well still published to
        // nobody: the phone's own App Group and the iOS widgets updated, and the
        // wrist heard nothing until the app was next opened by hand. Apple's
        // guidance is to configure and activate the session early in the app's
        // life cycle, not when a view appears.
        PhoneWatchSession.shared.activate()
    }

    /// The backstop wake. HealthKit background delivery is the primary path and
    /// is event-driven; this only covers a delivery that was missed entirely,
    /// and it is also what keeps `readyAt` crossing into Ready on the widgets
    /// while the app is never opened.
    private static func scheduleAppRefresh() {
        let request = BGAppRefreshTaskRequest(identifier: refreshTaskID)
        request.earliestBeginDate = Date(timeIntervalSinceNow: 30 * 60)
        try? BGTaskScheduler.shared.submit(request)
    }

    private static func handleAppRefresh(_ task: BGAppRefreshTask) {
        // Before the work, not after: the chain ends here if this throws or the
        // system expires us mid-refresh.
        scheduleAppRefresh()

        let work = Task { @MainActor in
            // Before the refresh, so the `publish()` at the end of it has a
            // session to send on. `activationDidCompleteWith` republishes as a
            // backstop, but only if the process is still alive to receive it,
            // and this task is what keeps it alive.
            await PhoneWatchSession.shared.waitForActivation(timeout: activationTimeout)
            await RecoveryEngine.shared.refresh(force: true)
        }
        task.expirationHandler = { work.cancel() }
        Task {
            await work.value
            task.setTaskCompleted(success: !work.isCancelled)
        }
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
                    // `PhoneWatchSession.activate()` is in `init` above, not
                    // here: a scene is not connected on a background wake, and
                    // the phone is the side that has to be able to push.
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
