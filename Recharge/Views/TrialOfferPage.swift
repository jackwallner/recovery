import SwiftUI
@preconcurrency import RevenueCat

/// The single-decision trial page: the final onboarding screen, and the only
/// place Recharge asks for money before the user has seen a countdown.
///
/// One plan (yearly), one button in the thumb zone, one skip. A plan grid here
/// converts worse than a single decision, and the full paywall is one tap away
/// in Settings for anyone who wants to compare.
struct TrialOfferPage: View {
    let onDecline: () -> Void
    let onPurchased: () -> Void
    /// "Not now" is right for a sheet that interrupted someone. At the end of
    /// onboarding it is wrong: declining there is not postponing anything, it is
    /// choosing the free tier and starting to use the app.
    var declineTitle: String = "Not now"
    /// Onboarding leads with what personalisation would actually do to this
    /// user's numbers. The passive sheet leads with the feature list, because by
    /// then they have seen the app work.
    var showsPersonalization: Bool = false

    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine
    @State private var errorMessage: String?
    @State private var isRestoring = false

    private var package: Package? { store.yearlyPackage }

    /// Pitch on top, one decision pinned to the thumb zone underneath — the same
    /// shape as every other onboarding page, and for the same two reasons.
    ///
    /// **The pitch scrolls.** At an accessibility content size the old fixed
    /// `VStack` overflowed the screen and SwiftUI resolved that by *truncating*:
    /// the headline, the price, the trial length, and the purchase button itself
    /// all rendered ellipsized. A user cannot consent to a subscription they
    /// cannot read.
    ///
    /// **The decision does not scroll, and neither does it move.** Everything
    /// variable — the trial callout, the billed amount, the free exit, the
    /// disclosure, an error — is handed to `OnboardingActions` as content
    /// *above* the button. The only thing below the button is the legal slot
    /// that every other page also reserves, so this CTA lands in the identical
    /// frame the four Continue buttons before it occupied.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                pitch
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            OnboardingActions(
                primaryTitle: store.onboardingTrialCTALabel,
                primaryAction: { Task { await purchase() } },
                tint: Theme.pro,
                primaryDisabled: package == nil || store.purchaseInFlight,
                isBusy: store.purchaseInFlight,
                secondaryTitle: declineTitle,
                secondaryAction: onDecline,
                above: AnyView(purchaseTerms),
                showsLegalLinks: true,
                isRestoring: isRestoring,
                onRestore: { Task { await restore() } }
            )
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .task {
            store.trackPaywallImpression(id: "onboarding_trial")
            if store.products.isEmpty { await store.fetchProducts() }
        }
    }

    private var pitch: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 0)

            Image(systemName: "bolt.badge.clock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.pro)
                .padding(.bottom, 20)
                .accessibilityHidden(true)

            Text(headline)
                .font(.system(.title, design: .rounded, weight: .bold))
                // As on the onboarding pages: capping the headline keeps it large
                // without letting it crowd out the terms that have to be read
                // before the button is pressed.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            if showsPersonalization {
                // The same table Today shows, with the same blur over the same
                // real numbers. What the user is sold here is literally what
                // they get, which is the only reason it is allowed to be the
                // pitch.
                RestPatternCard(rows: engine.restPattern, isPro: false, isCompact: true)
                    .padding(.bottom, 18)
            }

            VStack(alignment: .leading, spacing: 12) {
                ForEach(features, id: \.self) { feature in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.pro)
                        Text(feature.title)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                            .fixedSize(horizontal: false, vertical: true)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer(minLength: 0)
        }
    }

    /// Everything the purchase decision needs stated beside it, and nothing that
    /// is allowed to sit below the button. Rendered on every state of the page,
    /// so it can grow and shrink freely without touching the CTA's frame.
    private var purchaseTerms: some View {
        VStack(spacing: 12) {
            trialCallout
            price

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            } else if let disclosure = store.yearlySheetDisclosureText {
                Text(disclosure)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
    }

    /// The trial, said once and said plainly.
    ///
    /// Deliberately *not* on the button and deliberately smaller than the billed
    /// amount below it. Apple 3.1.2(c) weighs pricing elements against each
    /// other, so this is a labelled callout that names the offer and the fact
    /// that nothing is charged today, not a headline competing with the price.
    @ViewBuilder
    private var trialCallout: some View {
        if let package, let trialLabel = store.eligibleIntroLabel(for: package) {
            VStack(spacing: 6) {
                HStack(spacing: 6) {
                    Image(systemName: "gift.fill")
                        .font(.system(size: 12, weight: .semibold))
                    Text(trialLabel.replacingOccurrences(of: " free trial", with: " free"))
                        .font(.system(.subheadline, design: .rounded, weight: .bold))
                }
                .foregroundStyle(Theme.pro)
                .padding(.horizontal, 14)
                .padding(.vertical, 7)
                .background(Theme.pro.opacity(0.15), in: Capsule())

                Text("You are not charged today.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
            .accessibilityElement(children: .combine)
        }
    }

    /// Largest pricing element on the page, per Apple 3.1.2(c). When the
    /// catalogue has not arrived it explains why the button is dead instead:
    /// silence there strands a user who has already decided to subscribe.
    @ViewBuilder
    private var price: some View {
        if let package {
            VStack(spacing: 3) {
                Text(RechargeConversionCopy.billedAmount(priceLabel: package.rechargePriceLabel))
                    .font(.system(.title3, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                Text(RechargeConversionCopy.billedNote(
                    trialLabel: store.eligibleIntroLabel(for: package),
                    eligibleForTrial: store.isEligibleForIntroOffer(package)
                ))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
            }
            // Capped at the same ceiling as the CTA label above it, so the
            // billed amount stays the larger of the two at every content size.
            // Apple 3.1.2(c) weighs pricing elements against each other, and an
            // uncapped `.title3` beside a capped headline inverts that at the
            // top accessibility sizes.
            .dynamicTypeSize(...DynamicTypeSize.accessibility2)
        } else if store.isLoadingProducts {
            VStack(spacing: 8) {
                ProgressView()
                Text("Loading the offer…")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            VStack(spacing: 6) {
                Text("Couldn't load the offer")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text(store.lastError ?? "Check your connection and try again.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                Button("Try again") {
                    Task { await store.fetchProducts() }
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
            }
        }
    }

    private var headline: String {
        guard showsPersonalization else {
            return store.canPitchFreeTrial ? "Try Recharge+ free" : "Go further with Recharge+"
        }
        return "Your own\nrecharge time"
    }

    /// Personalisation leads the onboarding list, because it is the thing the
    /// previous four screens were about.
    private var features: [ProFeature] {
        showsPersonalization
            ? [.personalizedTime, .bodySignals, .weeklyLoad]
            : [.bodySignals, .weeklyLoad, .sessionOverrides]
    }

    private func purchase() async {
        guard let package else { return }
        errorMessage = nil
        do {
            switch try await store.purchase(package) {
            case .purchased: onPurchased()
            case .cancelled: errorMessage = store.purchaseCancelledMessage(for: package)
            case .pending: errorMessage = "Your purchase is pending approval."
            }
        } catch {
            errorMessage = store.purchaseFailedMessage(for: package)
        }
    }

    private func restore() async {
        isRestoring = true
        errorMessage = nil
        await store.restorePurchases()
        isRestoring = false
        if store.isPro {
            onPurchased()
        } else {
            errorMessage = store.lastError
                ?? "No active Recharge+ purchase was found for this Apple ID."
        }
    }
}

/// The same single decision, presented as a sheet from a passive trigger later
/// in the app's life. Respects the 14-day cooldown in `RechargeSettings`.
struct TrialOfferSheet: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TrialOfferPage(onDecline: { dismiss() }, onPurchased: { dismiss() })
                .environmentObject(store)
                .environmentObject(engine)
                .background(Theme.background)
                .toolbar {
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
    }
}
