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

    /// The whole page is one scroll view pinned to at least the height of its
    /// container, so at normal sizes the `Spacer()`s still distribute exactly as
    /// they did and nothing scrolls. Without it, an accessibility content size
    /// overflows the fixed stack and SwiftUI resolves that by *truncating*: the
    /// headline, the price, the trial length, and the purchase button itself all
    /// rendered ellipsized, which is an informed-consent failure and not just a
    /// layout defect.
    var body: some View {
        GeometryReader { proxy in
            ScrollView {
                content
                    .frame(minHeight: proxy.size.height)
            }
            .scrollBounceBehavior(.basedOnSize)
        }
    }

    private var content: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Image(systemName: "bolt.badge.clock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.pro)
                .padding(.bottom, 20)

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

            if showsPersonalization, let comparison {
                personalizedComparison(comparison)
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

            Spacer()

            price
                .padding(.bottom, 14)

            Button {
                Task { await purchase() }
            } label: {
                Group {
                    if store.purchaseInFlight {
                        ProgressView().tint(.white)
                    } else {
                        Text(store.onboardingTrialCTALabel)
                            .font(.system(.headline, design: .rounded))
                    }
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(Theme.pro, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(package == nil || store.purchaseInFlight)
            .opacity(package == nil ? 0.5 : 1)

            if let disclosure = store.yearlySheetDisclosureText {
                Text(disclosure)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.top, 8)
            }

            if let errorMessage {
                Text(errorMessage)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .padding(.top, 6)
            }

            purchaseFooter
                .padding(.top, 10)

            Button(declineTitle, action: onDecline)
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .padding(.top, 12)
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
        .task {
            store.trackPaywallImpression(id: "onboarding_trial")
            if store.products.isEmpty { await store.fetchProducts() }
        }
    }

    private var purchaseFooter: some View {
        HStack(spacing: 16) {
            Button("Restore") {
                Task { await restore() }
            }
            .disabled(isRestoring)
            Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
            Link("Privacy", destination: URL(string: "https://jackwallner.github.io/recovery/privacy-policy.html")!)
        }
        .font(.system(.caption, design: .rounded))
        .foregroundStyle(Theme.textSecondary)
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
                Text(RechargeConversionCopy.billedNote(
                    trialLabel: store.eligibleIntroLabel(for: package),
                    eligibleForTrial: store.isEligibleForIntroOffer(package)
                ))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
            }
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
            return store.canPitchFreeTrial ? "Try Recharge Pro free" : "Go further with Recharge Pro"
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

    // MARK: - The comparison

    /// Standard hours against personalized hours, on a session the user actually
    /// did wherever possible.
    ///
    /// Returns `nil` when personalisation would change nothing — a pitch that
    /// promises a different number and then shows the same one twice is worse
    /// than no pitch at all.
    private var comparison: (label: String, standard: Double, personalized: Double, isExample: Bool)? {
        let factor = engine.personalAnalysis.factor
        guard engine.personalAnalysis.isPersonalised, abs(factor - 1) >= 0.03 else { return nil }

        if let estimate = engine.estimates.first(where: { $0.producesCountdown }) {
            let standard = estimate.standardHours
            guard standard > 0 else { return nil }
            return ("Your last \(estimate.activityLabel)", standard, standard * factor, false)
        }
        let reference = RecoveryCalculator.referenceHardSessionHours
        return ("A hard 60-minute session", reference, reference * factor, true)
    }

    private func personalizedComparison(
        _ comparison: (label: String, standard: Double, personalized: Double, isExample: Bool)
    ) -> some View {
        VStack(spacing: 10) {
            Text(comparison.label + (comparison.isExample ? ", for example" : ""))
                .font(.system(.footnote, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            HStack(spacing: 0) {
                comparisonColumn(
                    title: "Standard",
                    value: CountdownFormat.hours(comparison.standard),
                    tint: Theme.textSecondary
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 13, weight: .semibold))
                    .foregroundStyle(Theme.textTertiary)
                    .padding(.horizontal, 4)
                comparisonColumn(
                    title: "Yours",
                    value: CountdownFormat.hours(comparison.personalized),
                    tint: Theme.pro
                )
            }

            ForEach(PersonalRecoveryModel.summary(engine.personalAnalysis).prefix(2), id: \.self) { line in
                Text(line)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .padding(16)
        .frame(maxWidth: .infinity)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
        .accessibilityElement(children: .combine)
    }

    private func comparisonColumn(title: String, value: String, tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(title)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textTertiary)
                .textCase(.uppercase)
            Text(value)
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(tint)
                .minimumScaleFactor(0.6)
                .lineLimit(1)
        }
        .frame(maxWidth: .infinity)
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
                ?? "No active Recharge Pro purchase was found for this Apple ID."
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
