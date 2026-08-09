import SwiftUI

/// Four pages: what it is, what it needs, what it is not, and one decision.
///
/// The last page is the single-decision trial offer, per the fleet playbook —
/// one thumb-zone button, one skip, no plan grid. The full three-plan paywall
/// stays behind Settings and the feature gates.
struct OnboardingView: View {
    @EnvironmentObject private var settings: RechargeSettings
    @EnvironmentObject private var store: StoreService
    @EnvironmentObject private var engine: RecoveryEngine

    @State private var page = 0
    @State private var isRequestingHealth = false
    @State private var healthError: String?

    private let lastPage = 3

    var body: some View {
        VStack(spacing: 0) {
            TabView(selection: $page) {
                welcome.tag(0)
                healthAccess.tag(1)
                honesty.tag(2)
                trialOffer.tag(3)
            }
            .tabViewStyle(.page(indexDisplayMode: .never))

            pageDots
                .padding(.bottom, 10)
        }
        .background(Theme.background)
        .animation(.easeInOut(duration: 0.25), value: page)
    }

    private var pageDots: some View {
        HStack(spacing: 7) {
            ForEach(0...lastPage, id: \.self) { index in
                Circle()
                    .fill(index == page ? Theme.recovering : Theme.ringTrack)
                    .frame(width: 7, height: 7)
            }
        }
        // Four unlabelled circles tell VoiceOver nothing about where the user is
        // in a four-step flow.
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Page \(page + 1) of \(lastPage + 1)")
    }

    // MARK: - Page 1

    private var welcome: some View {
        OnboardingPage(
            symbol: "hourglass",
            tint: Theme.recovering,
            title: "Recovery time,\non the watch you own",
            message: "Finish a hard session and Recharge starts a countdown. When it runs out, you get a clear Ready — the answer a Garmin gives you, from Apple Health.",
            primaryTitle: "Continue",
            primaryAction: { page = 1 }
        )
    }

    // MARK: - Page 2

    private var healthAccess: some View {
        OnboardingPage(
            symbol: "heart.text.square.fill",
            tint: Theme.recoveringSecondary,
            title: "Recharge reads\nApple Health",
            message: "Your workouts and heart rate build the estimate. Sleep, resting heart rate, and HRV sharpen it. Nothing is written back, and your Health data never leaves your devices.",
            primaryTitle: isRequestingHealth ? "Requesting…" : "Connect Apple Health",
            primaryAction: requestHealthAccess,
            primaryDisabled: isRequestingHealth,
            secondaryTitle: "Not now",
            // Disabled while the sheet is in flight. Otherwise the user taps
            // Not now, the app advances, and the delayed system sheet lands on
            // top of a page that never asked for it.
            secondaryAction: isRequestingHealth ? nil : { deferHealthAccess() },
            footnote: healthError,
            isBusy: isRequestingHealth
        )
    }

    private func requestHealthAccess() {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        healthError = nil
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
                settings.hasDeferredHealthAccess = false
                await engine.refresh(force: true)
                isRequestingHealth = false
                if page == 1 { page = 2 }
            } catch {
                // A refusal is a legitimate choice, not an error state to shout
                // about — but the explanation has to be readable, so stay on the
                // page that shows it rather than advancing out from under it.
                healthError = "Recharge couldn't read Health. You can grant access in the Health app under Sharing › Apps, then pull to refresh."
                isRequestingHealth = false
            }
        }
    }

    private func deferHealthAccess() {
        settings.hasDeferredHealthAccess = true
        page = 2
    }

    // MARK: - Page 3

    private var honesty: some View {
        OnboardingPage(
            symbol: "info.circle.fill",
            tint: Theme.idle,
            title: "What the number\nactually means",
            message: "Recharge estimates when another hard session is likely to be reasonable, based on your recent workout load. It is a cardiovascular training estimate — not a measure of muscle repair, illness, or injury risk, and not medical advice.",
            primaryTitle: "I understand",
            primaryAction: { page = 3 }
        )
    }

    // MARK: - Page 4

    private var trialOffer: some View {
        TrialOfferPage(
            onDecline: finish,
            onPurchased: finish
        )
        .environmentObject(store)
    }

    private func finish() {
        settings.hasCompletedSetup = true
        settings.lastTrialOfferShownDate = .now
    }
}

// MARK: - Reusable page

/// Explanation on top, one decision pinned to the thumb zone underneath.
///
/// The explanation scrolls and the buttons do not. At an accessibility content
/// size the icon, title, and message are several times taller than the screen,
/// and the previous fixed `VStack` with `Spacer()`s simply clipped them — the
/// user reached the Health prompt having been shown a title ending in "on the
/// wat…". Scrolling the top half is what makes the copy reachable; keeping the
/// buttons out of the scroll view is what keeps the decision reachable too.
private struct OnboardingPage: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    var primaryDisabled = false
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var footnote: String?
    var isBusy = false

    /// Below the accessibility sizes the fixed 64pt symbol is the right anchor;
    /// above them it is just a large object competing with the copy for a screen
    /// that has already run out of room.
    @Environment(\.dynamicTypeSize) private var typeSize

    var body: some View {
        VStack(spacing: 0) {
            ScrollView {
                VStack(spacing: 0) {
                    Spacer(minLength: 0)
                    if !typeSize.isAccessibilitySize {
                        Image(systemName: symbol)
                            .font(.system(size: 64))
                            .foregroundStyle(tint)
                            .padding(.bottom, 28)
                            .accessibilityHidden(true)
                    }

                    Text(title)
                        .font(.system(.largeTitle, design: .rounded, weight: .bold))
                        // A largeTitle at the top accessibility sizes runs to
                        // four full-width lines and pushes the explanation off
                        // the screen entirely. Capping the *headline* keeps it
                        // large without letting it crowd out the copy that
                        // actually has to be read before the Health prompt; the
                        // body below scales all the way.
                        .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textPrimary)
                        .fixedSize(horizontal: false, vertical: true)
                        .accessibilityAddTraits(.isHeader)
                        .padding(.bottom, 14)

                    Text(message)
                        .font(.system(.body, design: .rounded))
                        .multilineTextAlignment(.center)
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                        .padding(.horizontal, 8)
                    Spacer(minLength: 0)
                }
                .frame(maxWidth: .infinity, minHeight: 0)
                .padding(.vertical, 12)
            }
            .scrollBounceBehavior(.basedOnSize)

            if let footnote {
                Text(footnote)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .fixedSize(horizontal: false, vertical: true)
                    .padding(.bottom, 10)
            }

            Button(action: primaryAction) {
                HStack(spacing: 8) {
                    if isBusy {
                        ProgressView()
                            .tint(.white)
                    }
                    Text(primaryTitle)
                        .font(.system(.headline, design: .rounded))
                }
                .frame(maxWidth: .infinity)
                .padding(.vertical, 16)
                .background(tint.opacity(primaryDisabled ? 0.6 : 1), in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                .foregroundStyle(.white)
            }
            .buttonStyle(.plain)
            .disabled(primaryDisabled)

            if let secondaryTitle {
                Button(secondaryTitle) { secondaryAction?() }
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(secondaryAction == nil ? Theme.textTertiary : Theme.textSecondary)
                    .disabled(secondaryAction == nil)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }
}
