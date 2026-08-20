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
    /// its Settings sheet). SwiftUI will not present a second sheet over them,
    /// and a review ask that silently fails to appear still spends the one
    /// chance the funnel gets, so this file has to know when the tab below is
    /// busy.
    @State private var todayIsPresentingSheet = false
    @State private var pendingNativeReviewAfterDismiss = false
    /// The third tab is built on first visit rather than at launch. See
    /// `tabContent(.plus)`.
    @State private var hasVisitedPlusTab = false

    /// Three tabs, the Vitals shape: the number, the record of it, and the
    /// upgrade. **Settings is not a tab**, it is a gear button on Today, because
    /// a tab is a place the user is meant to go and Settings is a place they go
    /// twice.
    enum Tab: Hashable {
        case today, history, plus
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

    /// A translucent capsule floating **over** the content, which is the shape
    /// Vitals and Protein use and the shape this had before it was given a
    /// layout row of its own.
    ///
    /// That row was the bug: `VStack { content; tabBar.background(Theme.background) }`
    /// paints an opaque strip the full width of the screen under the capsule, so
    /// on a dark background the bar reads as a black box with a pill inside it
    /// rather than as a floating control. Overlaying costs one thing in return —
    /// every scrollable tab has to reserve room for the bar at rest — and
    /// `tabBarClearance()` is that, applied *inside* each `NavigationStack`.
    private var main: some View {
        ZStack(alignment: .bottom) {
            tabContent(.today) { TodayView(isPresentingSheet: $todayIsPresentingSheet) }
            tabContent(.history) { HistoryView() }
            tabContent(.plus) {
                Group {
                    // Built only once the tab has been visited. Two reasons, and
                    // the second is the one that bites: the paywall fetches
                    // products and would do it on every cold launch whether or
                    // not anybody looked at it, and an unbuilt tab is not in the
                    // accessibility tree — an opacity-zero `PaywallView` sitting
                    // behind Today puts a second element with every one of its
                    // identifiers into the hierarchy, so `firstMatch` on the
                    // purchase button can pick the invisible one and then
                    // truthfully report that it is not hittable.
                    if !hasVisitedPlusTab {
                        Color.clear
                    } else if store.isPro {
                        RechargePlusView()
                    } else {
                        PaywallView(source: "plus_tab", displayCloseButton: false)
                    }
                }
                // The paywall's CTA sits in its own bottom bar rather than in
                // the scroll view, so it cannot reserve its own clearance the
                // way a `ScrollView` can.
                .safeAreaInset(edge: .bottom, spacing: 0) {
                    Color.clear.frame(height: TabBarMetrics.clearance)
                }
            }

            tabBar
        }
        .ignoresSafeArea(edges: .bottom)
        .tint(Theme.recovering)
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
        // A tap on a locked feature anywhere in the app lands here, so the pitch
        // is raised in one place and can be ordered against the others.
        .onReceive(NotificationCenter.default.publisher(for: .rechargeUpgradeRequested)) { _ in
            presentUpgrade()
        }
        .onReceive(NotificationCenter.default.publisher(for: .rechargePlusRequested)) { _ in
            hasVisitedPlusTab = true
            selectedTab = .plus
        }
        // A Ready notification points at the countdown. It cannot assume the
        // user was already looking at Today.
        .onReceive(NotificationCenter.default.publisher(for: NotificationService.routeRequested)) { note in
            guard (note.userInfo?[NotificationService.routeKey] as? String)
                    == NotificationService.readyRouteValue else { return }
            selectedTab = .today
        }
        .onOpenURL { url in
            guard url.scheme == "recharge" else { return }
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
                .environmentObject(settings)
                // A half sheet, as in Vitals: an interruption that covers the
                // whole screen reads as a wall, and the number it is arguing
                // about is the thing still visible behind it.
                .presentationDetents([.height(TrialOfferSheet.detentHeight)])
                .presentationDragIndicator(.visible)
        }
        .sheet(isPresented: $showPaywall) {
            PaywallView(source: "root")
                .environmentObject(store)
        }
        #if DEBUG
        .onAppear {
            if ScreenshotConfig.wantsHistory { selectedTab = .history }
            if ScreenshotConfig.wantsSettings { selectedTab = .today }
            // The paywall renders empty under plain `simctl launch` (no StoreKit
            // products, no RevenueCat on simulator), so it can only be verified
            // from a UI test where the scheme's .storekit file is active. This
            // is the hook that test drives.
            if ScreenshotConfig.wantsPaywall { showPaywall = true }
        }
        #endif
    }

    private var tabBar: some View {
        HStack(spacing: 0) {
            TabButton(icon: "hourglass", label: "Today", isSelected: selectedTab == .today) {
                selectedTab = .today
            }
            TabButton(
                icon: "list.bullet.rectangle",
                label: "History",
                isSelected: selectedTab == .history
            ) { selectedTab = .history }
            TabButton(
                icon: store.isPro ? "sparkles" : "lock.fill",
                label: store.isPro ? "Recharge+" : "Upgrade",
                tint: Theme.pro,
                isSelected: selectedTab == .plus
            ) {
                hasVisitedPlusTab = true
                selectedTab = .plus
            }
        }
        .padding(.horizontal, 8)
        .padding(.vertical, TabBarMetrics.verticalPadding)
        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
        .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
        .padding(.bottom, TabBarMetrics.bottomPadding)
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

    /// Somebody tapped a locked feature. Intent, so the cooldown does not apply
    /// — but the half sheet still leads, and the full plan picker is one tap
    /// inside it. Falls back to the Upgrade tab when there is nothing to buy,
    /// which is the one state a sheet cannot usefully show.
    private func presentUpgrade() {
        guard !store.isPro else { return }
        guard !isPresentingSomething else { return }
        if store.yearlyPackage == nil {
            hasVisitedPlusTab = true
            selectedTab = .plus
            return
        }
        settings.lastTrialOfferShownDate = .now
        showTrialOffer = true
    }

    /// Every sheet this file or Today can raise. The readiness question belongs
    /// to `TodayView`, but it is the one surface that has to win the moment a
    /// countdown expires, so nothing here may talk over it.
    private var isPresentingSomething: Bool {
        showWhatsNew || showReviewPrompt || showTrialOffer || showPaywall || todayIsPresentingSheet
    }

    /// Every tab stays alive and keeps its scroll position and navigation stack,
    /// which is what a system `TabView` does and what a plain `if` would throw
    /// away on every switch.
    @ViewBuilder
    private func tabContent<Content: View>(
        _ tab: Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .frame(maxWidth: .infinity, maxHeight: .infinity)
            .opacity(selectedTab == tab ? 1 : 0)
            .allowsHitTesting(selectedTab == tab)
            .accessibilityHidden(selectedTab != tab)
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

/// Raised by any locked surface that wants the upgrade pitch. `RootView` owns
/// the presentation so a feature tap can never stack a sheet on top of the
/// review ask or the What's New announcement.
extension Notification.Name {
    static let rechargeUpgradeRequested = Notification.Name("rechargeUpgradeRequested")
    /// The subscriber's version of the same tap: show them what they bought
    /// rather than a pitch for it.
    static let rechargePlusRequested = Notification.Name("rechargePlusRequested")
}

/// One tab. Ported from Protein, which is where this bar's shape comes from.
/// The tab bar's geometry lives in one place so the bar and the room made for
/// it stay equal.
///
/// Constants rather than a measured height on purpose: every term below is
/// fixed, including `buttonHeight` and the 10pt label inside it, so the bar is
/// the same size at every Dynamic Type setting and there is nothing to measure.
/// If the bar is ever allowed to grow with text, this becomes a measurement and
/// `RootView` has to read it back, not a constant somebody remembers to update.
enum TabBarMetrics {
    /// Matches `TabButton`'s frame, which is 44 because that is the minimum
    /// comfortable touch target.
    static let buttonHeight: CGFloat = 44
    static let verticalPadding: CGFloat = 6
    static let bottomPadding: CGFloat = 12

    /// The capsule's full height plus the gap under it.
    static var clearance: CGFloat { buttonHeight + verticalPadding * 2 + bottomPadding }
}

extension View {
    /// Reserves room for the floating tab bar at the bottom of a scrollable tab.
    ///
    /// **This has to be applied inside the `NavigationStack`, not around it.**
    /// One call wrapping all three tabs in `RootView` would be less code and
    /// would not work: a `NavigationStack` manages the safe area of its own
    /// content, so an inset applied from outside never reaches the scroll view
    /// within. Nothing about that failure is visible — it compiles, the layout
    /// looks unchanged, and the last row still sits under the blur.
    ///
    /// An inset rather than bottom padding, so the scroll-behind look survives:
    /// it moves where the content comes to rest rather than the scroll view's
    /// frame, so passing content still runs under the capsule and only the last
    /// row is guaranteed to clear it.
    func tabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: TabBarMetrics.clearance)
        }
    }
}

private struct TabButton: View {
    let icon: String
    let label: String
    var tint: Color = Theme.recovering
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? tint : Color(.tertiaryLabel))
            .frame(width: 78, height: TabBarMetrics.buttonHeight)
            .background(
                isSelected ? tint.opacity(0.14) : .clear,
                in: Capsule()
            )
            // Without a content shape the tap area shrinks to the icon and
            // label, which reports a target well under 44pt.
            .contentShape(Capsule())
        }
        .buttonStyle(.plain)
        .animation(.easeInOut(duration: 0.2), value: isSelected)
        // Without this VoiceOver reads all three tabs identically and never says
        // which one you are on.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
