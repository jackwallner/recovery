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

    /// A floating translucent bar over the content rather than a system
    /// `TabView`, the same shape Protein and Vitals use.
    ///
    /// The system bar draws an opaque slab across the bottom of a screen whose
    /// whole point is a tinted full-bleed background, and on iOS 26 it renders
    /// as a solid pill that cuts the page in half. This sits on top of the
    /// content in `ultraThinMaterial`, so the countdown and the history list run
    /// under it and the app reads as one surface.
    ///
    /// Clearance is the shell's job, not each screen's. Every tab gets the same
    /// `safeAreaInset` from `tabContent`, sized by `TabBarMetrics` from the very
    /// constants that lay the bar out, so the two cannot drift. Screens used to
    /// pad their own bottom edge and it went exactly the way hand-copied numbers
    /// go: Today padded 72, History padded 96, and `SettingsView`, a `Form`
    /// with no padding to copy onto, padded nothing at all, so the capsule sat
    /// on top of the Recovery time section explaining the model.
    ///
    /// An inset rather than padding also keeps the scroll-behind look: it moves
    /// the content's resting bottom, not the scroll view's frame, so passing
    /// content still runs under the blur and only the *last* row is guaranteed
    /// to clear it.
    private var main: some View {
        ZStack(alignment: .bottom) {
            tabContent(.today) { TodayView(isPresentingSheet: $todayIsPresentingSheet) }
            tabContent(.history) { HistoryView() }
            tabContent(.settings) { SettingsView() }

            HStack(spacing: 0) {
                TabButton(icon: "hourglass", label: "Today", isSelected: selectedTab == .today) {
                    selectedTab = .today
                }
                TabButton(
                    icon: "list.bullet.rectangle",
                    label: "History",
                    isSelected: selectedTab == .history
                ) { selectedTab = .history }
                TabButton(icon: "gearshape", label: "Settings", isSelected: selectedTab == .settings) {
                    selectedTab = .settings
                }
            }
            .padding(.horizontal, 8)
            .padding(.vertical, TabBarMetrics.verticalPadding)
            .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
            .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
            .padding(.bottom, TabBarMetrics.bottomPadding)
        }
        // Deliberately *not* `.ignoresSafeArea(edges: .bottom)`, which is what
        // Protein does. Applied here it leaks into every sheet this view
        // presents: the paywall pins its CTA to the bottom of the sheet, and
        // with the bottom inset zeroed that button sat under the home indicator
        // and stopped being hittable. `testPaywallRendersRealProductsUnderStoreKitTesting`
        // caught it. The bar sits inside the safe area instead, which costs a few
        // points and no correctness.
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

    /// Every tab stays alive and keeps its scroll position and navigation stack,
    /// which is what a system `TabView` does and what a plain `if` would throw
    /// away on every switch.
    @ViewBuilder
    private func tabContent<Content: View>(
        _ tab: Tab,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
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

/// One tab. Ported from Protein, which is where this bar's shape comes from.
/// The floating tab bar's geometry, in one place, because the bar is drawn by
/// `RootView` and cleared by every tab and those two facts have to stay equal.
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

    /// What a scrollable tab reserves at its bottom edge: the capsule's full
    /// height plus the gap under it.
    static var clearance: CGFloat { buttonHeight + verticalPadding * 2 + bottomPadding }
}

extension View {
    /// Reserves room for the floating tab bar at the bottom of a scrollable
    /// tab. Apply it to the `ScrollView`, `List` or `Form` itself.
    ///
    /// **Inside the `NavigationStack`, not outside it.** The obvious place for
    /// this is `RootView.tabContent`, one call for all three tabs, and it does
    /// not work: a `NavigationStack` manages the safe area of its own content,
    /// so an inset applied to the stack from outside never reaches the scroll
    /// view within. The symptom is silent: everything compiles, the layout
    /// looks unchanged, and the last row still sits under the blur. It was
    /// caught by `testTheTabBarDoesNotCoverTheBottomOfToday`, which measures
    /// frames rather than trusting the modifier.
    ///
    /// An inset rather than bottom padding, so the scroll-behind look survives:
    /// it moves where the content comes to rest, not the scroll view's frame,
    /// so passing content still runs under the capsule and only the last row is
    /// guaranteed to clear it.
    func tabBarClearance() -> some View {
        safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear
                .frame(height: TabBarMetrics.clearance)
                .accessibilityHidden(true)
        }
    }
}

private struct TabButton: View {
    let icon: String
    let label: String
    let isSelected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            VStack(spacing: 4) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Text(label)
                    .font(.system(size: 10, weight: .semibold, design: .rounded))
            }
            .foregroundStyle(isSelected ? Theme.recovering : Color(.tertiaryLabel))
            .frame(width: 78, height: TabBarMetrics.buttonHeight)
            .background(
                isSelected ? Theme.recovering.opacity(0.14) : .clear,
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
