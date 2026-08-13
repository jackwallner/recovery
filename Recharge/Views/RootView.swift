import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine
    @Environment(\.requestReview) private var requestReview

    @State private var selectedTab = Tab.today
    @State private var showWhatsNew = false
    @State private var showReviewPrompt = false
    @State private var showTrialOffer = false
    @State private var showPaywall = false
    /// Today raises its own sheets (the readiness question, the effort question,
    /// its paywall). SwiftUI will not present a second sheet over them, and a
    /// review ask that silently fails to appear still spends the one chance the
    /// funnel gets, so this file has to know when the tab below is busy.
    @State private var todayIsPresentingSheet = false
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
            TodayView(isPresentingSheet: $todayIsPresentingSheet)
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
            Task { await evaluateReadyMomentSurfaces() }
        }
        .onChange(of: store.customerInfo != nil) { _, resolved in
            if resolved { evaluateTrialOffer() }
        }
        .onChange(of: store.yearlyPackage?.identifier) { _, identifier in
            if identifier != nil { evaluateTrialOffer() }
        }
        // A Ready notification points at the countdown. It cannot assume the
        // user was already looking at Today.
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.routeRequested)) { note in
            guard (note.userInfo?[NotificationService.routeKey] as? String)
                    == NotificationService.readyRouteValue else { return }
            selectedTab = .today
        }
        .sheet(isPresented: $showWhatsNew) {
            WhatsNewSheet()
                .environmentObject(store)
        }
        .sheet(isPresented: $showReviewPrompt, onDismiss: requestPendingNativeReview) {
            ReviewPromptSheet(onFinish: handleReviewPromptFinish)
        }
        .sheet(isPresented: $showTrialOffer) {
            TrialOfferSheet()
                .environmentObject(store)
                .environmentObject(engine)
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
    /// ordering matters: an announcement, a review ask, and a trial pitch must
    /// never stack.
    private func evaluateLaunchSurfaces() async {
        guard !ScreenshotConfig.isEnabled else { return }

        if WhatsNew.shouldShow(lastShown: settings.lastWhatsNewVersionShown) {
            showWhatsNew = true
            settings.lastWhatsNewVersionShown = WhatsNew.currentVersion
            return
        }
        await evaluateReviewPrompt(afterReadyMoment: false)
        if !showReviewPrompt { evaluateTrialOffer() }
    }

    /// A countdown reaching Ready is the app's one genuine win, and the only
    /// honest place to ask for anything. Two things want that moment, and the
    /// readiness question owns it first, so they run in priority order and stop
    /// at the first one that fires.
    private func evaluateReadyMomentSurfaces() async {
        await evaluateReviewPrompt(afterReadyMoment: true)
        if !showReviewPrompt { evaluateTrialOffer() }
    }

    private func evaluateReviewPrompt(afterReadyMoment: Bool) async {
        guard !isPresentingSomething else { return }
        let eligible = afterReadyMoment
            ? ReviewPromptTracker.shouldShowAfterReadyMoment(hasCompletedSetup: settings.hasCompletedSetup)
            : ReviewPromptTracker.shouldShowForEngagedUse(hasCompletedSetup: settings.hasCompletedSetup)
        guard eligible else { return }
        // A beat after the Ready state lands, so the win registers first.
        try? await Task.sleep(for: .seconds(afterReadyMoment ? 1.2 : 0.6))
        // The sleep is long enough for the readiness sheet to have appeared in
        // the meantime, so the guard has to be re-checked, not just entered.
        guard !isPresentingSomething else { return }
        ReviewPromptTracker.markShown()
        showReviewPrompt = true
    }

    /// The passive trial offer: the same single decision from onboarding, shown
    /// again to someone who skipped it and has since seen the app work.
    ///
    /// Gated on the 14-day cooldown in `RechargeSettings`, on RevenueCat having
    /// actually answered (a pitch raised before entitlements resolve can land in
    /// front of someone who is already Pro), and on a real package being
    /// loaded, because an interruption that says "couldn't load the offer" is
    /// worse than no interruption at all.
    private func evaluateTrialOffer() {
        guard !ScreenshotConfig.isEnabled,
              settings.hasCompletedSetup,
              !isPresentingSomething,
              !store.isPro,
              store.customerInfo != nil,
              store.yearlyPackage != nil,
              settings.passiveTrialOfferAllowed()
        else { return }
        settings.lastTrialOfferShownDate = .now
        showTrialOffer = true
    }

    /// Every sheet this file or Today can raise. The readiness question belongs
    /// to `TodayView`, but it is the one surface that has to win the moment a
    /// countdown expires, so nothing here may talk over it.
    private var isPresentingSomething: Bool {
        showWhatsNew || showReviewPrompt || showTrialOffer || todayIsPresentingSheet
    }

    private func handleReviewPromptFinish(_ outcome: ReviewPromptDismissOutcome) {
        pendingNativeReviewAfterDismiss = outcome == .requestNativeReview
    }

    private func requestPendingNativeReview() {
        guard pendingNativeReviewAfterDismiss else { return }
        pendingNativeReviewAfterDismiss = false
        requestReview()
    }
}
