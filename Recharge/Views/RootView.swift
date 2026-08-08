import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine
    @Environment(\.requestReview) private var requestReview

    @State private var selectedTab = Tab.today
    @State private var showWhatsNew = false
    @State private var showReviewPrompt = false
    @State private var showPaywall = false
    @State private var pendingNativeReviewAfterDismiss = false

    enum Tab: Hashable {
        case today, history, settings
    }

    var body: some View {
        Group {
            if settings.hasCompletedSetup {
                main
            } else {
                OnboardingView()
            }
        }
        .animation(.easeInOut(duration: 0.25), value: settings.hasCompletedSetup)
    }

    private var main: some View {
        TabView(selection: $selectedTab) {
            TodayView()
                .tabItem { Label("Today", systemImage: "hourglass") }
                .tag(Tab.today)

            HistoryView()
                .tabItem { Label("History", systemImage: "list.bullet.rectangle") }
                .tag(Tab.history)

            SettingsView()
                .tabItem { Label("Settings", systemImage: "gearshape") }
                .tag(Tab.settings)
        }
        .task { await evaluateLaunchSurfaces() }
        .onReceive(NotificationCenter.default.publisher(for: .rechargePositiveMomentForReview)) { _ in
            Task { await evaluateReviewPrompt(afterReadyMoment: true) }
        }
        // A Ready notification and both widget families point at the countdown.
        // Neither can assume the user was already looking at Today.
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.routeRequested)) { note in
            guard (note.userInfo?[NotificationService.routeKey] as? String)
                    == NotificationService.readyRouteValue else { return }
            selectedTab = .today
        }
        .onOpenURL { url in
            guard url.scheme == "recharge", url.host == "today" else { return }
            selectedTab = .today
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showReviewPrompt, onDismiss: requestPendingNativeReview) {
            ReviewPromptSheet(onFinish: handleReviewPromptFinish)
        }
        #if DEBUG
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "capture")
                .environmentObject(store)
        }
        .onAppear {
            if ScreenshotConfig.wantsHistory { selectedTab = .history }
            if ScreenshotConfig.wantsSettings { selectedTab = .settings }
            // The paywall renders empty under plain `simctl launch` (no StoreKit
            // products, no RevenueCat on simulator), so it can only be verified
            // from a UI test where the scheme's .storekit file is active. This
            // is the hook that test drives.
            if ScreenshotConfig.wantsPaywall { showPaywall = true }
        }
        #endif
    }

    // MARK: - Launch surfaces

    /// One place decides what, if anything, interrupts the user at launch. The
    /// ordering matters: an announcement and a review ask must never stack.
    private func evaluateLaunchSurfaces() async {
        guard !ScreenshotConfig.isEnabled else { return }

        if WhatsNew.shouldShow(lastShown: settings.lastWhatsNewVersionShown) {
            showWhatsNew = true
            settings.lastWhatsNewVersionShown = WhatsNew.currentVersion
            return
        }
        await evaluateReviewPrompt(afterReadyMoment: false)
    }

    private func evaluateReviewPrompt(afterReadyMoment: Bool) async {
        guard !showWhatsNew, !showReviewPrompt else { return }
        let eligible = afterReadyMoment
            ? ReviewPromptTracker.shouldShowAfterReadyMoment(hasCompletedSetup: settings.hasCompletedSetup)
            : ReviewPromptTracker.shouldShowForEngagedUse(hasCompletedSetup: settings.hasCompletedSetup)
        guard eligible else { return }
        // A beat after the Ready state lands, so the win registers first.
        try? await Task.sleep(for: .seconds(afterReadyMoment ? 1.2 : 0.6))
        ReviewPromptTracker.markShown()
        showReviewPrompt = true
    }

    private func handleReviewPromptFinish(_ outcome: ReviewPromptDismissOutcome) {
        pendingNativeReviewAfterDismiss = outcome == .enjoyedMaybeLater
    }

    private func requestPendingNativeReview() {
        guard pendingNativeReviewAfterDismiss else { return }
        pendingNativeReviewAfterDismiss = false
        requestReview()
    }
}
