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

    @EnvironmentObject private var store: StoreService
    @State private var errorMessage: String?

    private var package: Package? { store.yearlyPackage }

    var body: some View {
        VStack(spacing: 0) {
            Spacer(minLength: 12)

            Image(systemName: "bolt.badge.clock.fill")
                .font(.system(size: 56))
                .foregroundStyle(Theme.pro)
                .padding(.bottom, 20)

            Text(headline)
                .font(.system(.title, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 18)

            VStack(alignment: .leading, spacing: 12) {
                ForEach([ProFeature.bodySignals, .weeklyLoad, .sessionOverrides], id: \.self) { feature in
                    HStack(alignment: .top, spacing: 10) {
                        Image(systemName: "checkmark.circle.fill")
                            .font(.system(size: 16))
                            .foregroundStyle(Theme.pro)
                        Text(feature.title)
                            .font(.system(.subheadline, design: .rounded))
                            .foregroundStyle(Theme.textSecondary)
                        Spacer(minLength: 0)
                    }
                }
            }
            .padding(.horizontal, 12)

            Spacer()

            // Largest pricing element on the page, per Apple 3.1.2(c).
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
                .padding(.bottom, 14)
            }

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

            Button("Not now", action: onDecline)
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

    private var headline: String {
        store.canPitchFreeTrial ? "Try Recharge Pro free" : "Go further with Recharge Pro"
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
}

/// The same single decision, presented as a sheet from a passive trigger later
/// in the app's life. Respects the 14-day cooldown in `RechargeSettings`.
struct TrialOfferSheet: View {
    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            TrialOfferPage(onDecline: { dismiss() }, onPurchased: { dismiss() })
                .environmentObject(store)
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
