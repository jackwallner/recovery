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
/// Underneath it, on the onboarding page, is one line of receipt: what Recharge
/// just read out of Apple Health, counted. That is the evidence the number on
/// the right came from somewhere, and it is far more persuasive than a feature
/// list because the user recognises their own training in it. It used to be the
/// itemised nine-row table, which is the right shape for the readout page two
/// screens earlier and the wrong one here — on the screen that asks for money,
/// the only thing that should be large is the pair of numbers.
struct TrialOfferPage: View {
    let onDecline: () -> Void
    let onPurchased: () -> Void
    /// "Not now" is right for a sheet that interrupted someone. At the end of
    /// onboarding it is wrong: declining there is not postponing anything, it is
    /// choosing the free tier and starting to use the app.
    var declineTitle: String = "Not now"
    /// Onboarding has just finished reading Health, so it shows the one-line
    /// receipt. The passive sheet appears later in the app's life, when the user
    /// has already seen the app work, and shows three feature lines instead.
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
                    .padding(.vertical, Theme.Space.xs)
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
        .padding(.horizontal, Theme.Space.step(7))
        .padding(.bottom, Theme.Space.md)
        .task {
            store.trackPaywallImpression(id: showsIngestProof ? "onboarding_trial" : "passive_trial")
            if store.products.isEmpty { await store.fetchProducts() }
        }
    }

    /// **One thing on this page is large, and it is the pair of numbers.**
    ///
    /// It used to be a headline, the numbers, a three-line paragraph, a five-row
    /// Health receipt with an "…and 4 more" footnote under it, a trial capsule,
    /// a price, a disclosure, a CTA, a decline, and three legal links. Every one
    /// of those was defensible on its own and together they were a wall: the
    /// last screen of onboarding, the one that asks for money, was the busiest
    /// screen in the app.
    ///
    /// What survived is the argument and the evidence for it. The paragraph is
    /// one line. The receipt is one line — a count, not a table — because the
    /// itemised version was already read two pages ago on the readout, and
    /// repeating it here buried the thing the page is about.
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
                .padding(.bottom, Theme.Space.lg)

            comparison
                .padding(.bottom, Theme.Space.md)

            Text(subheadline)
                .font(.system(.subheadline, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .fixedSize(horizontal: false, vertical: true)
                .padding(.horizontal, Theme.Space.xxs)

            if showsIngestProof, let proof = engine.healthIngest.oneLineReceipt {
                Text(proof)
                    .font(.system(.footnote, design: .rounded))
                    .multilineTextAlignment(.center)
                    .foregroundStyle(Theme.textTertiary)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.top, Theme.Space.md)
            } else if !showsIngestProof {
                features.padding(.top, Theme.Space.lg)
            }
        }
    }

    // MARK: - The two numbers

    /// The whole pitch. Left is what the standard table says for somebody at
    /// this person's training level; right is what their own data says.
    ///
    /// Both are real. `RecoveryEngine.personalizedPreview` computes them on both
    /// tiers precisely so this screen never has to invent one, and it falls back
    /// to a canonical hard session - a genuine point on the genuine curve -
    /// when the user has no qualifying session yet.
    ///
    /// The personalized figure is **blurred until it is bought**, exactly as it
    /// is on Today's card. It used to be printed in full here, on the argument
    /// that hiding half an argument is not an argument, and that reasoning was
    /// wrong in one specific way: this page is the last thing a user sees before
    /// deciding, so printing the number gives away the entire thing being sold.
    /// Somebody who reads it has already got what they came for and has no
    /// reason to pay. The argument the page has to make is that there *is* a
    /// difference and that it was measured from their own data - which the
    /// standard figure, the blurred shape beside it, and the receipt underneath
    /// all still make.
    private var comparison: some View {
        let preview = engine.personalizedPreview
        return VStack(spacing: Theme.Space.sm) {
            HStack(alignment: .center, spacing: Theme.Space.lg) {
                numberColumn(
                    RechargeConversionCopy.standardColumn,
                    CountdownFormat.hours(preview.standardHours),
                    Theme.textSecondary
                )
                Image(systemName: "arrow.right")
                    .font(.system(size: 16, weight: .bold))
                    .foregroundStyle(Theme.textTertiary)
                numberColumn(
                    RechargeConversionCopy.proColumn,
                    CountdownFormat.hours(preview.personalizedHours),
                    Theme.pro,
                    blurred: !store.isPro
                )
            }
            .padding(.vertical, Theme.Space.md)
            .padding(.horizontal, Theme.Space.xl)
            .frame(maxWidth: .infinity)
            .cardShape()

            Text(preview.isExample
                 ? "For a hard 60-minute session. An example on the real curve until you have recorded one."
                 : preview.label)
                .font(.system(.caption, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
                .multilineTextAlignment(.center)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    /// - Parameter blurred: withholds the value while keeping its shape legible
    ///   as a figure, the same treatment and the same radius Today's card uses.
    ///   At a larger radius a number this size disappears completely and the
    ///   column reads as a rendering fault rather than as a withheld value.
    private func numberColumn(
        _ label: String,
        _ value: String,
        _ tint: Color,
        blurred: Bool = false
    ) -> some View {
        VStack(spacing: Theme.Space.hair) {
            Group {
                if blurred {
                    Text(value)
                        .foregroundStyle(tint)
                        .blur(radius: 7)
                        .opacity(0.9)
                        .overlay(alignment: .topTrailing) {
                            Image(systemName: "lock.fill")
                                .font(.system(size: 12, weight: .bold))
                                .foregroundStyle(Theme.pro)
                                .offset(x: 12, y: 2)
                        }
                        .accessibilityLabel("Hidden until you upgrade")
                } else {
                    Text(value).foregroundStyle(tint)
                }
            }
            .countdownNumber(38)
            .lineLimit(1)
            .minimumScaleFactor(0.6)
            Text(label)
                .font(.system(.caption2, design: .rounded, weight: .semibold))
                .textCase(.uppercase)
                .foregroundStyle(Theme.textTertiary)
        }
        .dynamicTypeSize(...DynamicTypeSize.accessibility1)
        .accessibilityElement(children: .combine)
    }

    /// The sheet variant's substitute for the receipt: three lines, because a
    /// half sheet has room for three lines.
    private var features: some View {
        VStack(alignment: .leading, spacing: Theme.Space.sm) {
            ForEach(sheetFeatures, id: \.self) { feature in
                HStack(alignment: .top, spacing: Theme.Space.sm) {
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
        .padding(.horizontal, Theme.Space.xs)
    }

    private var sheetFeatures: [ProFeature] {
        [.personalizedTime, .bodySignals, .weeklyLoad]
    }

    // MARK: - Terms

    /// Everything the purchase decision needs stated beside it, and nothing that
    /// is allowed to sit below the button. Rendered on every state of the page,
    /// so it can grow and shrink freely without touching the CTA's frame.
    private var purchaseTerms: some View {
        VStack(spacing: Theme.Space.sm) {
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
            HStack(spacing: Theme.Space.xs) {
                Image(systemName: "gift.fill")
                    .font(.system(size: 12, weight: .semibold))
                Text("\(trialLabel.replacingOccurrences(of: " free trial", with: " free")) · Nothing charged today")
                    .font(.system(.footnote, design: .rounded, weight: .semibold))
                    .multilineTextAlignment(.center)
            }
            .foregroundStyle(Theme.pro)
            .padding(.horizontal, Theme.Space.md)
            .padding(.vertical, Theme.Space.xs)
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
            VStack(spacing: Theme.Space.xxs) {
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
            VStack(spacing: Theme.Space.xs) {
                ProgressView()
                Text("Loading the offer…")
                    .font(.system(.footnote, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
            }
        } else {
            VStack(spacing: Theme.Space.xs) {
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

    /// One line, and it has one job: say which figure is free and which is paid.
    ///
    /// The two headings above name the tiers, so this names the derivation. It
    /// used to be a three-line paragraph that said the same thing twice and left
    /// the reader no clearer about which side of the paywall either number was
    /// on.
    private var subheadline: String {
        RechargeConversionCopy.comparisonCaption(hasPurchased: store.isPro)
    }

    private func purchase() async {
        guard let package else { return }
        errorMessage = nil
        do {
            switch try await store.purchase(package) {
            case .purchased:
                Haptics.success()
                onPurchased()
            case .cancelled: errorMessage = store.purchaseCancelledMessage(for: package)
            case .pending: errorMessage = "Your purchase is pending approval."
            }
        } catch {
            Haptics.failure()
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
