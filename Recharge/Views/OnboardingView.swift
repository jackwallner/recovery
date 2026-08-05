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
            message: "Your workouts and heart rate build the estimate. Sleep, resting heart rate, and HRV sharpen it. Nothing is written back, and nothing leaves your devices.",
            primaryTitle: isRequestingHealth ? "Requesting…" : "Connect Apple Health",
            primaryAction: requestHealthAccess,
            secondaryTitle: "Not now",
            secondaryAction: { page = 2 },
            footnote: healthError
        )
    }

    private func requestHealthAccess() {
        guard !isRequestingHealth else { return }
        isRequestingHealth = true
        Task {
            do {
                try await HealthKitService.shared.requestAuthorization()
                await engine.refresh(force: true)
                healthError = nil
            } catch {
                // A refusal is a legitimate choice, not an error state to shout
                // about — the app still works from whatever it can read later.
                healthError = "You can grant access later in Settings › Health."
            }
            isRequestingHealth = false
            page = 2
        }
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

private struct OnboardingPage: View {
    let symbol: String
    let tint: Color
    let title: String
    let message: String
    let primaryTitle: String
    let primaryAction: () -> Void
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?
    var footnote: String?

    var body: some View {
        VStack(spacing: 0) {
            Spacer()
            Image(systemName: symbol)
                .font(.system(size: 64))
                .foregroundStyle(tint)
                .padding(.bottom, 28)

            Text(title)
                .font(.system(.largeTitle, design: .rounded, weight: .bold))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textPrimary)
                .padding(.bottom, 14)

            Text(message)
                .font(.system(.body, design: .rounded))
                .multilineTextAlignment(.center)
                .foregroundStyle(Theme.textSecondary)
                .padding(.horizontal, 8)

            Spacer()

            if let footnote {
                Text(footnote)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
                    .multilineTextAlignment(.center)
                    .padding(.bottom, 10)
            }

            Button(action: primaryAction) {
                Text(primaryTitle)
                    .font(.system(.headline, design: .rounded))
                    .frame(maxWidth: .infinity)
                    .padding(.vertical, 16)
                    .background(tint, in: RoundedRectangle(cornerRadius: 16, style: .continuous))
                    .foregroundStyle(.white)
            }
            .buttonStyle(.plain)

            if let secondaryTitle, let secondaryAction {
                Button(secondaryTitle, action: secondaryAction)
                    .font(.system(.subheadline, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .padding(.top, 12)
            }
        }
        .padding(.horizontal, 28)
        .padding(.bottom, 16)
    }
}
