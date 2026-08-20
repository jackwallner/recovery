import SwiftUI
@preconcurrency import RevenueCat

/// The single-decision trial page: the final onboarding screen, and the passive
/// half sheet later in the app's life.
///
/// **One argument, made with two numbers.** The pitch used to be a headline, a
/// three-column rest-pattern table with a blur over one column, and a bulleted
/// feature list — three different shapes of claim on one screen, none of which
/// answered "what do I get" in a form anybody could hold in their head. What is
/// sold is a recovery time, so what is shown is a recovery time: the average
/// one, an arrow, and theirs. Both figures are real and both are computed the
/// same way a subscriber's would be.
///
/// Underneath it, on the onboarding page, is the receipt: everything Recharge
/// just read out of Apple Health. That is the evidence the number on the right
/// came from somewhere, and it is far more persuasive than a feature list
/// because the user recognises their own data in it.
struct TrialOfferPage: View {
    let onDecline: () -> Void
    let onPurchased: () -> Void
    /// "Not now" is right for a sheet that interrupted someone. At the end of
    /// onboarding it is wrong: declining there is not postponing anything, it is
    /// choosing the free tier and starting to use the app.
    var declineTitle: String = "Not now"
    /// Onboarding has a full screen and has just finished reading Health, so it
    /// shows the receipt. The passive sheet is a half sheet over the app the
    /// person is already using, and the list would not fit — nor does it need
    /// to, because by then they have seen the app work.
    var showsIngestProof: Bool = false

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
    /// frame the Continue buttons before it occupied.
    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                pitch
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 8)
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
            store.trackPaywallImpression(id: showsIngestProof ? "onboarding_trial" : "passive_trial")
            if store.products.isEmpty { await store.fetchProducts() }
        }
    }

    private var pitch: some View {
        VStack(spacing: 0) {
            Text(headline)
                .font(.system(.title, design: .rounded, weight: .bold))
                // Capping the headline keeps it large without letting it crowd
                // out the terms that have to be read before the button is
                // pressed.
                .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.bottom, 18)

            comparison
                .padding(.bottom, 14)

            Text(subheadline)
                .font(.system(.subheadline, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, 4)

            if showsIngestProof, !engine.healthIngest.isEmpty {
                proof.padding(.top, 20)
            } else if !showsIngestProof {
                features.padding(.top, 20)
            }
        }
    }

    // MARK: - The two numbers

    /// The whole pitch. Left is what the standard table says for somebody at
    /// this person's training level; right is what their own data says.
    ///
    /// Both are real. `RecoveryEngine.personalizedPreview` computes them on both
    /// tiers precisely so this screen never has to invent one, and it falls back
    /// to a canonical hard session — a genuine point on the genuine curve —
    /// when the user has no qualifying session yet. Neither figure is blurred
    /// here: this is the page where the difference is the argument, and hiding
    /// half of an argument is not an argument.
    private var comparison: some View {
        let preview = engine.personalizedPreview
        return VStack(spacing: 10) {
            HStack(alignment: .center, spacing: 18) {
                numberColumn(
                    "Average",
                    CountdownFormat.hours(preview.standardHours),
                    Theme.textSecondary
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                numberColumn(
                    "Yours",
                    CountdownFormat.hours(preview.personalizedHours),
                    Theme.pro
                )
            }
            .padding(.vertical, 16)
            .padding(.horizontal, 22)
            .frame(maxWidth: .infinity)
            .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))

            Text(preview.isExample
                 ? "For a hard 60-minute session. An example on the real curve until you have recorded one."
                 : preview.label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func numberColumn(_ label: String, _ value: String, _ tint: Color) -> some View {
        VStack(spacing: 2) {
            Text(value)
                .font(Theme.bigNumber(38))
                .monospacedDigit()
                .lineLimit(1)
                .minimumScaleFactor(0.6)
                .foregroundStyle(tint)
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
    }

    // MARK: - The receipt

    private var proof: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Measured from your own data")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textPrimary)
                .frame(maxWidth: .infinity, alignment: .leading)
            // Values only, no explanations: the explanations were read two pages
            // ago on the readout, and repeating them here would bury the two
            // numbers this page is actually about. Capped at five rows for the
            // same reason — the full receipt runs to nine and pushed the price
            // block off the bottom of the scroll view, so the page that takes
            // money was the one page in the flow whose terms needed scrolling
            // to.
            HealthIngestList(summary: engine.healthIngest, showsDetail: false, limit: 5)
            if engine.healthIngest.rows.count > 5 {
                Text("…and \(engine.healthIngest.rows.count - 5) more, all going into your estimate.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
        }
        .padding(16)
        .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: Theme.cardRadius, style: .continuous))
    }

    /// The sheet variant's substitute for the receipt: three lines, because a
    /// half sheet has room for three lines.
    private var features: some View {
        VStack(alignment: .leading, spacing: 10) {
            ForEach(sheetFeatures, id: \.self) { feature in
                HStack(alignment: .top, spacing: 10) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 15))
                        .foregroundStyle(Theme.pro)
                    Text(feature.title)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                    Spacer(minLength: 0)
                }
            }
        }
        .padding(.horizontal, 8)
    }

    private var sheetFeatures: [ProFeature] {
        [.personalizedTime, .bodySignals, .weeklyLoad]
    }

    // MARK: - Terms

    /// Everything the purchase decision needs stated beside it, and nothing that
    /// is allowed to sit below the button. Rendered on every state of the page,
    /// so it can grow and shrink freely without touching the CTA's frame.
    private var purchaseTerms: some View {
        VStack(spacing: 10) {
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
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .dynamicTypeSize(...DynamicTypeSize.accessibility3)
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
            HStack(spacing: 6) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(trialLabel.replacingOccurrences(of: " free trial", with: " free")) · Nothing charged today")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.pro)
            .padding(.horizontal, 14)
            .padding(.vertical, 7)
            .background(Theme.pro.opacity(0.15), in: Capsule())
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
        showsIngestProof ? "Your own\nrecharge time" : "Make it yours"
    }

    private var subheadline: String {
        let name = RechargeConversionCopy.proName
        return engine.personalizedPreview.isExample
            ? "Free gives you the standard estimate for your training level. \(name) measures it from your own sessions, sleep, and heart rate."
            : "That's what the standard table says, beside what your own data says. \(name) gives you the second one."
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
                ?? "No active \(RechargeConversionCopy.proName) purchase was found for this Apple ID."
        }
    }
}

/// The same single decision as a half sheet, from a passive trigger later in the
/// app's life. Respects the 14-day cooldown in `RechargeSettings`.
///
/// A **half** sheet, as in Vitals, and that is not a cosmetic choice: the thing
/// the sheet is arguing about is the countdown on the screen behind it, and a
/// full-screen cover hides the one piece of evidence the pitch depends on.
struct TrialOfferSheet: View {
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine
    @Environment(\.dismiss) private var dismiss

    /// Tall enough for the two numbers, three feature lines, the price block and
    /// the buttons, and no taller. A fixed height rather than `.medium` because
    /// `.medium` is half the screen on every device and this content is not.
    static let detentHeight: CGFloat = 600

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
