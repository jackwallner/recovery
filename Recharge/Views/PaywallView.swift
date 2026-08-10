import SwiftUI
@preconcurrency import RevenueCat

/// What Recharge Pro sells. One list, referenced by the paywall, the onboarding
/// trial page, and the What's New sheet, so the pitch can never drift between
/// surfaces.
enum ProFeature: CaseIterable {
    case bodySignals
    case weeklyLoad
    case sessionOverrides
    case readyAlerts

    var symbol: String {
        switch self {
        case .bodySignals: "waveform.path.ecg"
        case .weeklyLoad: "chart.bar.fill"
        case .sessionOverrides: "slider.horizontal.3"
        case .readyAlerts: "bell.badge"
        }
    }

    var title: String {
        switch self {
        case .bodySignals: "Sleep, HRV, and resting heart rate"
        case .weeklyLoad: "Weekly load against your 4-week average"
        case .sessionOverrides: "Correct a session's workout type"
        case .readyAlerts: "A notification the moment you're Ready"
        }
    }

    var detail: String {
        switch self {
        case .bodySignals:
            "Short sleep, a depressed HRV, or an elevated resting heart rate nudge the estimate within a bounded range."
        case .weeklyLoad:
            "How hard this week has been compared with your own four-week average."
        case .sessionOverrides:
            "Override a misclassified session and recalculate its estimate."
        case .readyAlerts:
            "Optional, and off by default."
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

    @EnvironmentObject private var store: StoreService
    @Environment(\.dismiss) private var dismiss

    @State private var selected: Package?
    @State private var errorMessage: String?
    @State private var didPurchase = false

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: 22) {
                    hero
                    features
                    plans
                    footer
                }
                .padding(.horizontal, 20)
                .padding(.bottom, 12)
            }
            .background(Theme.background)
            // The hero, features, and three plan cards are taller than the sheet
            // on every current iPhone, so a CTA at the end of the scroll view
            // was below the fold on first presentation: the user could read the
            // prices but could not see the action, and the auto-renew disclosure
            // Apple 3.1.2 wants beside the button went with it. Pinning both
            // keeps the decision and its terms on screen at every scroll offset.
            .safeAreaInset(edge: .bottom) {
                cta
                    .padding(.horizontal, 20)
                    .padding(.top, 10)
                    .padding(.bottom, 8)
                    .background(.regularMaterial)
            }
            .navigationBarTitleDisplayMode(.inline)
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
            .task {
                store.trackPaywallImpression(id: "paywall_\(source)")
                if store.products.isEmpty { await store.fetchProducts() }
                selectDefaultPackage()
            }
            .onChange(of: store.products.count) { _, _ in selectDefaultPackage() }
            .onChange(of: store.isPro) { _, isPro in
                if isPro, didPurchase { dismiss() }
            }
        }
    }

    // MARK: - Hero

    private var hero: some View {
        VStack(spacing: 10) {
            Image(systemName: "bolt.badge.clock.fill")
                .font(.system(size: 46))
                .foregroundStyle(Theme.pro)
                .padding(.top, 8)
            Text(RechargeConversionCopy.proName)
                .font(.system(.title, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Add body signals, load trends, session corrections, and Ready alerts.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)
        }
    }

    private var features: some View {
        VStack(spacing: 12) {
            ForEach(ProFeature.allCases, id: \.self) { feature in
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: feature.symbol)
                        .font(.system(size: 17))
                        .frame(width: 26)
                        .foregroundStyle(Theme.pro)
                    VStack(alignment: .leading, spacing: 2) {
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
            ProgressView().padding(.vertical, 30)
        } else if store.products.isEmpty {
            VStack(spacing: 8) {
                Text("Couldn't load plans")
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
            .padding(.vertical, 20)
        } else {
            VStack(spacing: 10) {
                ForEach(store.products, id: \.identifier) { package in
                    planCard(package)
                }
            }
        }
    }

    private func planCard(_ package: Package) -> some View {
        let isSelected = selected?.identifier == package.identifier
        let trialLabel = store.eligibleIntroLabel(for: package)
        let isPopular = package.rechargePackageKind == .yearly

        return Button {
            selected = package
        } label: {
            HStack(spacing: 12) {
                Image(systemName: isSelected ? "largecircle.fill.circle" : "circle")
                    .font(.title3)
                    .foregroundStyle(isSelected ? Theme.pro : Theme.textTertiary)

                VStack(alignment: .leading, spacing: 3) {
                    HStack(spacing: 6) {
                        Text(package.rechargeDisplayName)
                            .font(.system(.headline, design: .rounded))
                            .foregroundStyle(Theme.textPrimary)
                        if isPopular {
                            Text("POPULAR")
                                .font(.system(size: 9, weight: .bold, design: .rounded))
                                .padding(.horizontal, 6)
                                .padding(.vertical, 2)
                                .background(Theme.pro, in: Capsule())
                                .foregroundStyle(.white)
                        }
                    }
                    // Largest pricing element on the card: the amount actually
                    // billed, phrased as a commitment.
                    Text(RechargeConversionCopy.billedAmount(priceLabel: package.rechargePriceLabel))
                        .font(.system(.subheadline, design: .rounded, weight: .medium))
                        .foregroundStyle(Theme.textPrimary)
                    Text(RechargeConversionCopy.billedNote(
                        trialLabel: trialLabel,
                        eligibleForTrial: trialLabel != nil,
                        isRecurring: package.storeProduct.subscriptionPeriod != nil
                    ))
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                }

                Spacer()

            }
            .padding(14)
            .background(
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(Theme.cardSurface)
                    .overlay(
                        RoundedRectangle(cornerRadius: 16, style: .continuous)
                            .stroke(isSelected ? Theme.pro : .clear, lineWidth: 2)
                    )
            )
        }
        .buttonStyle(.plain)
    }

    // MARK: - CTA

    private var cta: some View {
        VStack(spacing: 10) {
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
                .padding(.vertical, 16)
                .background(Theme.pro, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(selected == nil || store.purchaseInFlight)
            .opacity(selected == nil ? 0.5 : 1)

            if let disclosure {
                Text(disclosure)
                    .font(.system(size: 11, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
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
        guard let selected else { return "Continue with \(RechargeConversionCopy.proName)" }
        return RechargeConversionCopy.ctaLabel(
            trialLabel: selected.rechargeIntroOfferLabel,
            priceLabel: selected.rechargePriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(selected)
        )
    }

    /// Apple 3.1.2 requires this next to the button, and it must describe the
    /// plan actually selected — not the yearly one by default.
    private var disclosure: String? {
        guard let selected else { return nil }
        if selected.rechargePackageKind == .lifetime {
            return "\(selected.storeProduct.localizedPriceString) once. No subscription, no renewal."
        }
        return RechargeConversionCopy.disclosure(
            trialLabel: selected.rechargeIntroOfferLabel,
            priceLabel: selected.rechargePriceLabel,
            eligibleForTrial: store.isEligibleForIntroOffer(selected)
        )
    }

    // MARK: - Footer

    private var footer: some View {
        VStack(spacing: 10) {
            HStack(spacing: 18) {
                Button("Restore") {
                    Task {
                        await store.restorePurchases()
                        errorMessage = store.lastError
                    }
                }
                Link("Terms", destination: URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!)
                Link("Privacy", destination: URL(string: "https://jackwallner.github.io/recovery/privacy-policy.html")!)
            }
            .font(.system(.footnote, design: .rounded))
            .foregroundStyle(Theme.textSecondary)

            Text("Recharge gives a cardiovascular training estimate. It is not medical advice.")
                .font(.system(size: 10, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
        }
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
                didPurchase = true
                dismiss()
            case .cancelled:
                errorMessage = store.purchaseCancelledMessage(for: package)
            case .pending:
                errorMessage = "Your purchase is pending approval."
            }
        } catch {
            errorMessage = store.purchaseFailedMessage(for: package)
        }
    }
}
