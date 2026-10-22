import SwiftUI

struct RootView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine
    @Environment(\.requestReview) private var requestReview
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @Environment(\.dynamicTypeSize) private var dynamicTypeSize
    @Environment(\.horizontalSizeClass) private var horizontalSizeClass

    @State private var selectedTab = Tab.today
    @State private var showWhatsNew = false
    @State private var showTrialOffer = false
    @State private var trialOfferDetent: PresentationDetent = .height(TrialOfferSheet.detentHeight)
    @State private var showPaywall = false
    /// Today raises its own sheets (the readiness question, the effort question,
    /// its Settings sheet). SwiftUI will not present a second sheet over them,
    /// and a review ask that silently fails to appear still spends the one
    /// chance the funnel gets, so this file has to know when the tab below is
    /// busy.
    @State private var todayIsPresentingSheet = false
    /// The third tab is built on first visit rather than at launch. See
    /// `tabContent(.plus)`.
    @State private var hasVisitedPlusTab = false
    /// The container's width and fold, measured so the unfolded iPhone Duo can
    /// put Today and History on opposite sides of the fold.
    @State private var paneGeometry = PaneGeometry(width: 0, fold: nil)
    /// Settings or one session's detail, opened from Today or History. Split,
    /// it covers History in the trailing pane; folded it is a sheet, which only
    /// happens when the Duo closes with a pane open.
    @State private var trailingPanel: TrailingPanel?

    /// Three tabs, the Vitals shape: the number, the record of it, and the
    /// upgrade. **Settings is not a tab**, it is a gear button on Today, because
    /// a tab is a place the user is meant to go and Settings is a place they go
    /// twice.
    enum Tab: Hashable {
        case today, history, plus
    }

    /// Unfolded, History has its own pane beside Today, so it is never a tab.
    private var split: UnfoldedSplit? {
        UnfoldedSplit.make(
            width: paneGeometry.width,
            isRegularWidth: horizontalSizeClass == .regular,
            fold: paneGeometry.fold
        )
    }

    /// The panel as a sheet, for the one case it is not a pane: the Duo closed
    /// while it was open. The sheet's own dismissal must not close a pane.
    private var trailingPanelSheet: Binding<TrailingPanel?> {
        Binding(
            get: { split == nil ? trailingPanel : nil },
            set: { if $0 == nil, split == nil { trailingPanel = nil } }
        )
    }

    var body: some View {
        Group {
            if settings.hasCompletedSetup {
                main
            } else {
                OnboardingView()
            }
        }
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.25), value: settings.hasCompletedSetup)
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
    ///
    /// One view tree in every pose: opening or closing the Duo only moves these
    /// frames, so no tab is rebuilt and each keeps its scroll position.
    private var main: some View {
        ZStack(alignment: .bottomLeading) {
            // Behind the fold, which the panes leave uncovered.
            Theme.background.ignoresSafeArea()

            tabContent(.today, isVisible: selectedTab == .today, pane: .leading) {
                TodayView(isPresentingSheet: $todayIsPresentingSheet)
            }
            tabContent(.history, isVisible: showsHistory, pane: .trailing) { HistoryView() }
            tabContent(.plus, isVisible: selectedTab == .plus, pane: .leading) {
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
                        PaywallView(
                            source: "plus_tab",
                            displayCloseButton: false,
                            bottomClearance: TabBarMetrics.clearance
                        )
                    }
                }
                // `RechargePlusView` is a scroll view and reserves its own
                // room inside its `NavigationStack`. The paywall's action row
                // is not a scroll view at all, so it takes `bottomClearance`
                // above. Neither of them can be served from out here: an inset
                // applied around a `NavigationStack` never reaches the content
                // inside it.
            }

            panelOverHistory

            tabBar
                // Within the leading pane while split, never across the fold.
                .frame(maxWidth: split?.primaryWidth ?? .infinity)
                .zIndex(2)
        }
        .onGeometryChange(for: PaneGeometry.self) { proxy in
            PaneGeometry(width: proxy.size.width, fold: proxy.verticalFold())
        } action: { paneGeometry = $0 }
        .environment(\.openInTrailingPane, split == nil ? nil : TrailingPaneAction(open: { showPanel($0) }))
        .onChange(of: split != nil) { _, isSplit in
            if isSplit, selectedTab == .history { selectedTab = .today }
        }
        // Notification routes and the screenshot hook still ask for History.
        .onChange(of: selectedTab) { _, tab in
            if tab == .history, split != nil { selectedTab = .today }
        }
        .ignoresSafeArea(edges: .bottom)
        .tint(Theme.recovering)
        .sheet(item: trailingPanelSheet) { panel in
            trailingPanelContent(panel)
        }
        #if DEBUG
        .onChange(of: paneGeometry) { _, geometry in
            guard DuoScreenshotTour.isEnabled else { return }
            NSLog("DUOGEOM width=%.1f fold=%@ split=%@", geometry.width,
                  String(describing: geometry.fold), String(describing: split))
        }
        .task(id: split != nil) { await runDuoTour(split: split != nil) }
        #endif
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
        .sheet(isPresented: $showTrialOffer) {
            TrialOfferSheet()
                .environmentObject(store)
                .environmentObject(engine)
                .environmentObject(settings)
                // A half sheet, as in Vitals: an interruption that covers the
                // whole screen reads as a wall, and the number it is arguing
                // about is the thing still visible behind it.
                .presentationDetents(
                    [.height(TrialOfferSheet.detentHeight), .large],
                    selection: $trialOfferDetent
                )
                .presentationDragIndicator(.visible)
                .presentationContentInteraction(.scrolls)
                .onAppear {
                    if dynamicTypeSize.isAccessibilitySize {
                        trialOfferDetent = .large
                    }
                }
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
                select(.today)
            }
            if split == nil {
                TabButton(
                    icon: "list.bullet.rectangle",
                    label: "History",
                    isSelected: selectedTab == .history
                ) { select(.history) }
            }
            TabButton(
                icon: store.isPro ? "sparkles" : "lock.fill",
                label: store.isPro ? "Recharge+" : "Upgrade",
                tint: Theme.pro,
                isSelected: selectedTab == .plus
            ) {
                hasVisitedPlusTab = true
                select(.plus)
            }
        }
        .padding(.horizontal, Theme.Space.xs)
        .padding(.vertical, TabBarMetrics.verticalPadding)
        .background(.ultraThinMaterial.opacity(0.9), in: Capsule())
        .overlay(Capsule().stroke(Color(.separator).opacity(0.3), lineWidth: 0.5))
        .padding(.bottom, TabBarMetrics.bottomPadding)
    }

    /// Every tab change goes through here so the tap is confirmed in the hand
    /// as well as on the screen, and so a re-tap of the tab you are already on
    /// stays silent: a haptic that fires when nothing changed teaches the user
    /// to stop trusting it.
    private func select(_ tab: Tab) {
        guard selectedTab != tab else { return }
        Haptics.selection()
        selectedTab = tab
    }

    // MARK: - Launch surfaces

    /// One place decides what, if anything, interrupts the user at launch. The
    /// ordering matters: an announcement, a review ask, and a trial pitch must
    /// never stack.
    private func evaluateLaunchSurfaces() async {
        guard !ScreenshotConfig.isEnabled else { return }
        #if DEBUG
        // The RevenueCat funnel probe launches a simulated purchase from app
        // startup. A launch sheet can cover its confirmation alert, so probe
        // runs must stay on the plain app surface.
        guard !RevenueCatProbe.isEnabled else { return }
        #endif

        if WhatsNew.shouldShow(lastShown: settings.lastWhatsNewVersionShown) {
            showWhatsNew = true
            settings.lastWhatsNewVersionShown = WhatsNew.currentVersion
            return
        }
        if await !requestReviewIfEligible(afterReadyMoment: false) { evaluateTrialOffer() }
    }

    /// A countdown reaching Ready is the app's one genuine win, and the only
    /// honest place to ask for anything. Two things want that moment, and the
    /// readiness question owns it first, so they run in priority order and stop
    /// at the first one that fires.
    private func evaluateReadyMomentSurfaces() async {
        if await !requestReviewIfEligible(afterReadyMoment: true) { evaluateTrialOffer() }
    }

    /// Apple's own prompt, asked of everyone who qualifies, with no question
    /// first (guideline 5.6.1). Returns whether it asked, so the trial offer
    /// does not land in the same moment.
    private func requestReviewIfEligible(afterReadyMoment: Bool) async -> Bool {
        guard !isPresentingSomething else { return false }
        let eligible = afterReadyMoment
            ? ReviewPromptTracker.shouldShowAfterReadyMoment(hasCompletedSetup: settings.hasCompletedSetup)
            : ReviewPromptTracker.shouldShowForEngagedUse(hasCompletedSetup: settings.hasCompletedSetup)
        guard eligible else { return false }
        // A beat after the Ready state lands, so the win registers first.
        try? await Task.sleep(for: .seconds(afterReadyMoment ? 1.2 : 0.6))
        // The sleep is long enough for the readiness sheet to have appeared in
        // the meantime, so the guard has to be re-checked, not just entered.
        guard !isPresentingSomething else { return false }
        ReviewPromptTracker.markShown()
        requestReview()
        return true
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
        #if DEBUG
        // This method also runs directly from RevenueCat state changes, after
        // `evaluateLaunchSurfaces` has returned during a probe launch.
        guard !RevenueCatProbe.isEnabled else { return }
        #endif
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
        showWhatsNew || showTrialOffer || showPaywall || todayIsPresentingSheet
            || trailingPanelSheet.wrappedValue != nil
    }

    // MARK: - Unfolded panes

    /// History fills the trailing pane unless Settings or a detail covers it.
    private var showsHistory: Bool {
        split == nil ? selectedTab == .history : trailingPanel == nil
    }

    /// Settings or a session's detail, over History in the trailing pane.
    @ViewBuilder
    private var panelOverHistory: some View {
        if let split, let trailingPanel {
            trailingPanelContent(trailingPanel)
                .id(trailingPanel.id)
                .environment(\.horizontalSizeClass, .compact)
                .horizontalToolbarInPane(true)
                .frame(width: split.secondaryWidth)
                .frame(maxHeight: .infinity)
                .padding(.leading, split.secondaryX)
                .transition(.opacity)
                .zIndex(1)
        }
    }

    private func showPanel(_ panel: TrailingPanel?) {
        withAnimation(reduceMotion ? nil : .easeInOut(duration: 0.2)) { trailingPanel = panel }
    }

    private func trailingPanelContent(_ panel: TrailingPanel) -> some View {
        Group {
            switch panel {
            case .settings:
                SettingsView(onDone: { showPanel(nil) })
            case .estimate(let estimate):
                EstimateDetailView(capturedEstimate: estimate, onDone: { showPanel(nil) })
            }
        }
        .environmentObject(settings)
        .environmentObject(store)
        .environmentObject(engine)
    }

    #if DEBUG
    /// See `DuoScreenshotTour`. Each route starts from Today with no panel.
    private func runDuoTour(split isSplit: Bool) async {
        guard DuoScreenshotTour.isEnabled else { return }
        try? await Task.sleep(for: .seconds(DuoScreenshotTour.firstDelay))
        // Loops until the panes split or join, so a slow capture still lands
        // on every route.
        while !Task.isCancelled {
            for route in DuoScreenshotTour.routes(split: isSplit) {
                guard !Task.isCancelled else { return }
                NSLog("DUOTOUR %@ route=%@", isSplit ? "inner" : "outer", route)
                withAnimation { trailingPanel = nil }
                try? await Task.sleep(for: .milliseconds(700))
                withAnimation { openDuoRoute(route) }
                try? await Task.sleep(for: .seconds(DuoScreenshotTour.step))
            }
        }
    }

    /// `tab/panel`, either half optional: `plus/detail:4`, `settings`.
    private func openDuoRoute(_ route: String) {
        for part in route.split(separator: "/").map(String.init) {
            switch part {
            case "today": selectedTab = .today
            case "history": selectedTab = .history
            case "plus":
                hasVisitedPlusTab = true
                selectedTab = .plus
            case "settings": trailingPanel = .settings
            case _ where part.hasPrefix("detail"):
                let index = Int(part.split(separator: ":").last ?? "") ?? 0
                let estimates = engine.estimates.sorted { $0.sessionEnd > $1.sessionEnd }
                if estimates.indices.contains(index) { trailingPanel = .estimate(estimates[index]) }
            default: break
            }
        }
    }
    #endif

    /// Every tab stays alive and keeps its scroll position and navigation stack,
    /// which is what a system `TabView` does and what a plain `if` would throw
    /// away on every switch.
    ///
    /// `pane` is the side of the fold the tab takes while split. Each pane is
    /// phone-width and laid out as on a phone.
    @ViewBuilder
    private func tabContent<Content: View>(
        _ tab: Tab,
        isVisible: Bool,
        pane: UnfoldedPane,
        @ViewBuilder content: () -> Content
    ) -> some View {
        content()
            .environment(\.unfoldedPane, split == nil ? nil : pane)
            .environment(\.horizontalSizeClass, split == nil ? horizontalSizeClass : .compact)
            .horizontalToolbarInPane(split != nil)
            .frame(maxWidth: paneWidth(pane), maxHeight: .infinity)
            .padding(.leading, pane == .trailing ? split?.secondaryX ?? 0 : 0)
            .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
            .opacity(isVisible ? 1 : 0)
            .allowsHitTesting(isVisible)
            .accessibilityHidden(!isVisible)
            // The selected tab is also the frontmost one. `accessibilityHidden`
            // does not reach into the UIKit navigation stack each tab hosts, so
            // a History that had been scrolled still answered the accessibility
            // hit test over Today: VoiceOver touch exploration found invisible
            // History rows, and the ring could not be tapped from a UI test.
            .zIndex(isVisible ? 1 : 0)
    }

    private func paneWidth(_ pane: UnfoldedPane) -> CGFloat {
        guard let split else { return .infinity }
        return pane == .leading ? split.primaryWidth : split.secondaryWidth
    }
}

private struct PaneGeometry: Equatable, Sendable {
    var width: CGFloat
    var fold: ClosedRange<CGFloat>?
}

/// Which side of the unfolded iPhone Duo's fold a screen fills. `nil` in the
/// environment everywhere else, including the folded Duo.
enum UnfoldedPane: Sendable {
    case leading, trailing
}

/// What the trailing pane can show over History.
enum TrailingPanel: Identifiable, Equatable {
    case settings
    case estimate(RecoveryEstimate)

    var id: String {
        switch self {
        case .settings: "settings"
        case .estimate(let estimate): "estimate-\(estimate.sessionID)"
        }
    }
}

/// Opens Settings or a session's detail in the trailing pane. Only set while
/// split; Today and History raise their own sheets when it is `nil`.
struct TrailingPaneAction {
    let open: (TrailingPanel) -> Void

    func callAsFunction(_ panel: TrailingPanel) { open(panel) }
}

private struct UnfoldedPaneKey: EnvironmentKey {
    static var defaultValue: UnfoldedPane? { nil }
}

private struct OpenInTrailingPaneKey: EnvironmentKey {
    static var defaultValue: TrailingPaneAction? { nil }
}

extension EnvironmentValues {
    var unfoldedPane: UnfoldedPane? {
        get { self[UnfoldedPaneKey.self] }
        set { self[UnfoldedPaneKey.self] = newValue }
    }

    var openInTrailingPane: TrailingPaneAction? {
        get { self[OpenInTrailingPaneKey.self] }
        set { self[OpenInTrailingPaneKey.self] = newValue }
    }
}

extension View {
    /// iOS 27.1 can move a stack's toolbar into a vertical bar on its trailing
    /// edge, which in a pane lands beside the fold. A pane keeps the phone's
    /// horizontal bar; folded, the system default is unchanged.
    @ViewBuilder
    func horizontalToolbarInPane(_ isPane: Bool) -> some View {
        if #available(iOS 27.1, *) {
            toolbarVerticalBehavior(isPane ? .disabled : .automatic)
        } else {
            self
        }
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
    ///
    /// The trailing pane of the unfolded iPhone Duo has no tab bar under it, so
    /// it reserves nothing.
    func tabBarClearance() -> some View {
        modifier(TabBarClearance())
    }
}

private struct TabBarClearance: ViewModifier {
    @Environment(\.unfoldedPane) private var pane

    func body(content: Content) -> some View {
        content.safeAreaInset(edge: .bottom, spacing: 0) {
            Color.clear.frame(height: pane == .trailing ? 0 : TabBarMetrics.clearance)
        }
    }
}

private struct TabButton: View {
    let icon: String
    let label: String
    var tint: Color = Theme.recovering
    let isSelected: Bool
    let action: () -> Void

    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        Button(action: action) {
            VStack(spacing: Theme.Space.xxs) {
                Image(systemName: icon)
                    .font(.system(size: 18, weight: .medium, design: .rounded))
                Text(label)
                    .font(.caption2.weight(.semibold))
                    .lineLimit(1)
                    .minimumScaleFactor(0.8)
            }
            .foregroundStyle(isSelected ? tint : Color(.tertiaryLabel))
            .frame(minWidth: 78, minHeight: TabBarMetrics.buttonHeight)
            .background(
                isSelected ? tint.opacity(0.14) : .clear,
                in: Capsule()
            )
            // Without a content shape the tap area shrinks to the icon and
            // label, which reports a target well under 44pt.
            .contentShape(Capsule())
        }
        .pressable()
        .animation(reduceMotion ? nil : .easeInOut(duration: 0.2), value: isSelected)
        // Without this VoiceOver reads all three tabs identically and never says
        // which one you are on.
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}
