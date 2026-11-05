import SwiftUI
@preconcurrency import RevenueCat

/// What Recharge+ sells. One list, referenced by the paywall, the onboarding
/// trial page, and the What's New sheet, so the pitch can never drift between
/// surfaces.
enum ProFeature: CaseIterable {
    /// The headline difference between the two tiers. Free is the standard
    /// model at the training level the user stated; this is the one that reads
    /// what they have actually done.
    case personalizedTime
    case bodySignals
    case weeklyLoad
    case sessionOverrides

    var symbol: String {
        switch self {
        case .personalizedTime: "person.crop.circle.badge.clock"
        case .bodySignals: "waveform.path.ecg"
        case .weeklyLoad: "chart.bar.fill"
        case .sessionOverrides: "slider.horizontal.3"
        }
    }

    var title: String {
        switch self {
        case .personalizedTime: String(localized: "A recharge time built from your own history", bundle: .recharge)
        case .bodySignals: String(localized: "Sleep, HRV, and resting heart rate", bundle: .recharge)
        case .weeklyLoad: String(localized: "Weekly load against your 4-week average", bundle: .recharge)
        case .sessionOverrides: String(localized: "Correct a session's intensity", bundle: .recharge)
        }
    }

    var detail: String {
        switch self {
        case .personalizedTime:
            String(localized: "Every session scored against your own 42-day baseline and 30-day recovery pattern.", bundle: .recharge)
        case .bodySignals:
            String(localized: "The nights before and after a session move the countdown within a bounded range, as they do on Garmin.", bundle: .recharge)
        case .weeklyLoad:
            String(localized: "How hard this week has been compared with your own four-week average.", bundle: .recharge)
        case .sessionOverrides:
            String(localized: "Override Light, Moderate, or Hard and recalculate its estimate.", bundle: .recharge)
        }
    }
}

/// The full three-plan paywall. Lives behind Settings and every feature gate.
///
/// Apple 3.1.2 shape: the billed amount is the largest pricing element, the CTA
/// carries no pricing words, the auto-renew disclosure sits directly under the
/// button, and Restore / Terms / Privacy are always reachable.
struct PaywallView: View {
    let source: String
    /// False when the paywall *is* a tab rather than a sheet over something.
    /// A close button there has nothing to close, and the tab bar underneath is
    /// already the way out — which is also what keeps the arrangement inside
    /// Apple 3.1.2(a): the auto-renew disclosure scrolls with the content and is
    /// never covered by the bar.
    var displayCloseButton = true

    /// Room to leave under the action row for `RootView`'s floating tab bar.
    ///
    /// It has to be reserved *in here*, for the reason `tabBarClearance()`
    /// documents: this view's root is a `NavigationStack`, which manages the
    /// safe area of its own content, so the inset `RootView` applies around the
    /// tab never reaches the action row within. The CTA cleared the bar anyway
    /// because the row is tall; the auto-renew disclosure under it did not, and
    /// the last line of an Apple 3.1.2(a) disclosure was sitting behind the
    /// capsule on the one screen that takes money.
    var bottomClearance: CGFloat = 0

    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss
    @Environment(\.dynamicTypeSize) private var typeSize

    @State private var selected: Package?
    @State private var errorMessage: String?
    @State private var didPurchase = false
    @State private var isRestoring = false

    var body: some View {
        NavigationStack {
            VStack(spacing: 0) {
                ScrollView {
                    VStack(spacing: Theme.Space.xl) {
                        hero
                        plans
                        features
                        footer
                        // At accessibility sizes the pinned action row would fill
                        // the screen and a plan card scrolled under it. It joins
                        // the content instead and scrolls with it.
                        if typeSize.isAccessibilitySize {
                            cta.padding(.bottom, bottomClearance)
                        }
                    }
                    .padding(.horizontal, Theme.Space.lg)
                    .padding(.bottom, Theme.Space.sm)
                }

                // The hero, features, and three plan cards are taller than the
                // sheet on every current iPhone. A separate action row keeps
                // the decision and its terms visible without covering a plan.
                if !typeSize.isAccessibilitySize {
                    cta
                        .padding(.horizontal, Theme.Space.lg)
                        .padding(.top, Theme.Space.sm)
                        .padding(.bottom, Theme.Space.xs + bottomClearance)
                        .background(.regularMaterial)
                }
            }
            .background(Theme.background)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                if displayCloseButton {
                    ToolbarItem(placement: .cancellationAction) {
                        Button { dismiss() } label: {
                            Image(systemName: "xmark")
                                .font(.system(size: 13, weight: .bold))
                                .foregroundStyle(Theme.textSecondary)
                        }
                        .accessibilityLabel("Close")
                    }
                }
            }
            .task {
                // This app reported no paywall impressions at all until now, so
                // everything between "installed" and "subscribed" was invisible
                // for it in RevenueCat.
                store.trackPaywallImpression(id: "recharge_paywall", oncePerSession: true)
                if store.products.isEmpty { await store.fetchProducts() }
                selectDefaultPackage()
                #if DEBUG
                ScreenshotConfig.markReady()
                #endif
            }
            .onChange(of: store.products.count) { _, _ in selectDefaultPackage() }
            .onChange(of: store.isPro) { _, isPro in
                if isPro, didPurchase { dismiss() }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: Theme.Space.sm) {
            Image(systemName: "bolt.badge.clock.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.pro)
                .padding(.top, Theme.Space.xs)
            Text(RechargeConversionCopy.proName)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Personalized recovery from your history.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(spacing: Theme.Space.sm) {
            ForEach(ProFeature.allCases, id: \.self) { feature in
                HStack(alignment: .top, spacing: Theme.Space.sm) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 17))
                        .frame(width: 26)
                        .foregroundStyle(Theme.pro)
                    VStack(alignment: .leading, spacing: Theme.Space.hair) {
                        Text(feature.title)
                            .font(.system(.subheadline, design: .rounded, weight: .semibold))
                            .foregroundStyle(Theme.textPrimary)
                        Text(feature.detail)
                            .font(.system(.caption, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                    }
                    Spacer(minLength: 0)
                }
            }
        }
    }

    // MARK: - Plans

    @ViewBuilder
    private var plans: some View {
        if store.isLoadingProducts && store.products.isEmpty {
            ProgressView().padding(.vertical, Theme.Space.xxl)
        } else if store.products.isEmpty {
            VStack(spacing: Theme.Space.xs) {
                Text("Couldn't load plans")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(store.lastError ?? String(localized: "Check your connection and try again.", bundle: .recharge))
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await store.fetchProducts() }
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
            .padding(.vertical, Theme.Space.lg)
        } else {
            VStack(spacing: Theme.Space.sm) {
                ForEach(store.products, id: \.identifier) { package in
                    planCard(package)
                }
            }
        }
    }

    private func planCard(_ package: Package) -> some View {
        let isSelected = selected?.identifier == package.identifier
        let trial = store.eligibleIntroLength(for: package)
        let isPopular = package.rechargePackageKind == .yearly

        return Button {
            Haptics.selection()
            selected = package
        } label: {
            HStack(spacing: Theme.Space.sm) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.pro : Theme.textTertiary)

                VStack(alignment: .leading, spacing: Theme.Space.xxs) {
                    HStack(spacing: Theme.Space.xs) {
                        Text(package.rechargeDisplayName)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        if isPopular {
                            Text("POPULAR")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, Theme.Space.xs)
                                .padding(.vertical, Theme.Space.hair)
                                .background(Theme.pro, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    // Largest pricing element on the card: the amount actually
                    // billed, phrased as a commitment.
                    Text(package.rechargeBilledAmountLabel)
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(RechargeConversionCopy.billedNote(
                        trial: trial,
                        eligibleForTrial: trial != nil,
                        isRecurring: package.storeProduct.subscriptionPeriod != nil
                    ))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

            }
            .padding(Theme.Space.md)
            .background(
                RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                    .fill(Theme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
                            .stroke(isSelected ? Theme.pro : .clear, lineWidth: 2)
                    )
            )
        }
        .pressable(.card)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .accessibilityValue(isSelected ? String(localized: "Selected", bundle: .recharge) : String(localized: "Not selected", bundle: .recharge))
    }

    // MARK: - CTA

    private var cta: some View {
        VStack(spacing: Theme.Space.sm) {
            Button {
                Task { await purchase() }
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView().tint(.white)
                    } else {
                        Text(ctaLabel)
                            .font(.system(.headline, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.md)
                .background(Theme.pro, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .foregroundStyle(.white)
            }
            .pressable()
            .disabled(selected == nil || store.purchaseInFlight)
            .opacity(selected == nil ? 0.5 : 1)
            // "Continue with Recharge+" is also the label on the locked-card
            // capsule in Today (`RechargeConversionCopy.shortCTALabel`), so a
            // test matching on the label alone can pick the one *behind* this
            // sheet and then correctly report that it is not hittable. The
            // identifier is what makes the layout assertion about this button.
            .accessibilityIdentifier("paywall-cta")

            if let disclosure {
                Text(disclosure)
                    .accessibilityIdentifier("paywall-disclosure")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
        }
    }

    private var ctaLabel: String {
        guard let selected else { return String(localized: "Continue with Recharge+", bundle: .recharge) }
        return RechargeConversionCopy.ctaLabel(
            trial: selected.rechargeIntroTrialLength,
            priceLabel: selected.rechargePriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(selected)
        )
    }

    /// Apple 3.1.2 requires this next to the button, and it must describe the
    /// plan actually selected — not the yearly one by default.
    private var disclosure: String? {
        guard let selected else { return nil }
        if selected.rechargePackageKind == .lifetime {
            return String(localized: "\(selected.storeProduct.localizedPriceString) once. No subscription, no renewal.", bundle: .recharge)
        }
        return RechargeConversionCopy.disclosure(
            trial: selected.rechargeIntroTrialLength,
            priceLabel: selected.rechargePriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(selected)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: Theme.Space.sm) {
            ViewThatFits(in: .horizontal) {
                HStack(spacing: Theme.Space.lg) { legalLinks }
                VStack(spacing: Theme.Space.xs) { legalLinks }
            }
            .font(.system(.footnote, design: .rounded))
            .dynamicTypeSize(...DynamicTypeSize.accessibility3)
            .foregroundStyle(Theme.textSecondary)

            Text("Recharge gives a cardiovascular training estimate. It is not medical advice. Talk with a qualified health professional before making medical decisions.")
                .font(.system(.footnote, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)

            Text("Countdown-complete notifications are included on every tier when you allow notifications.")
                .font(.system(.footnote, design: .rounded))
                .dynamicTypeSize(...DynamicTypeSize.accessibility3)
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
    }

    @ViewBuilder
    private var legalLinks: some View {
        Button("Restore") {
            Task {
                isRestoring = true
                await store.restorePurchases()
                isRestoring = false
                if store.isPro {
                    dismiss()
                } else {
                    errorMessage = store.lastError
                        ?? String(localized: "No active Recharge+ purchase was found for this Apple ID.", bundle: .recharge)
                }
            }
        }
        .disabled(isRestoring)
        Link("Terms", destination: RechargeLinks.termsOfUse)
        Link("Apple EULA", destination: RechargeLinks.standardEULA)
        Link("Privacy", destination: RechargeLinks.privacyPolicy)
    }

    // MARK: - Actions

    private func selectDefaultPackage() {
        guard selected == nil else { return }
        // Yearly by default: it is the conversion target and the only plan the
        // trial framing is built around.
        selected = store.yearlyPackage ?? store.products.first
    }

    private func purchase() async {
        guard let package = selected else { return }
        errorMessage = nil
        do {
            switch try await store.purchase(package) {
            case .purchased:
                Haptics.success()
                didPurchase = true
                dismiss()
            case .cancelled:
                errorMessage = store.purchaseCancelledMessage(for: package)
            case .pending:
                errorMessage = String(localized: "Apple has marked this purchase as pending. It may finish later. Restore purchases or reopen Recharge to check again.", bundle: .recharge)
            }
        } catch {
            Haptics.failure()
            errorMessage = store.purchaseFailedMessage(for: package)
        }
    }
}
