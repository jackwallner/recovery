import SwiftUI

enum ReviewPromptDismissOutcome: Sendable {
    case notNow
    case openedWriteReview
    case enjoyedMaybeLater
}

/// The enjoyment gate.
///
/// Ask whether they like it first. A Yes reaches the App Store review page; a
/// No routes to feedback. Apple's native prompt is reserved for "Maybe later."
struct ReviewPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let onFinish: (ReviewPromptDismissOutcome) -> Void

    @State private var stage = Stage.enjoyment
    @State private var feedbackText = ""

    private enum Stage {
        case enjoyment
        case ratePitch
        case feedback
        case thanks
    }

    init(onFinish: @escaping (ReviewPromptDismissOutcome) -> Void = { _ in }) {
        self.onFinish = onFinish
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                switch stage {
                case .enjoyment: enjoyment
                case .ratePitch: ratePitch
                case .feedback: feedback
                case .thanks: thanks
                }
            }
            .padding(.horizontal, 24)
            .padding(.top, 28)
            .frame(maxHeight: .infinity, alignment: .top)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") {
                        if stage == .enjoyment { ReviewPromptTracker.markShown() }
                        finish(.notNow)
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }

    // MARK: - Stage 1

    private var enjoyment: some View {
        VStack(spacing: 18) {
            Image(systemName: "hourglass")
                .font(.system(size: 42))
                .foregroundStyle(Theme.recovering)
            Text("Enjoying Recharge?")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("It helps to know either way.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: 10) {
                primaryButton("Yes, it's useful") { stage = .ratePitch }
                secondaryButton("Not really") { stage = .feedback }
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Stage 2

    private var ratePitch: some View {
        VStack(spacing: 18) {
            Image(systemName: "star.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.readySoon)
            Text("Mind rating it?")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("A rating is the whole reason anyone else finds an app like this.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            VStack(spacing: 10) {
                primaryButton("Rate Recharge") {
                    ReviewPromptTracker.markOpenedWriteReview()
                    openURL(AppStoreReviewLinks.writeReviewURL)
                    finish(.openedWriteReview)
                }
                Button("Maybe later") {
                    ReviewPromptTracker.markSoftDeferred()
                    finish(.enjoyedMaybeLater)
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, 6)
        }
    }

    // MARK: - Stage 3

    private var feedback: some View {
        VStack(spacing: 16) {
            Text("What's missing?")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Tell me what would make the countdown more useful. It goes straight to me.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            TextEditor(text: $feedbackText)
                .frame(height: 110)
                .padding(8)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                .font(.system(.body, design: .rounded))

            primaryButton("Send") {
                openURL(mailURL)
                ReviewPromptTracker.markFeedbackSubmitted()
                stage = .thanks
            }
            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)
        }
    }

    private var mailURL: URL {
        var components = URLComponents(string: "mailto:\(AppStoreReviewLinks.supportEmail)")!
        components.queryItems = [
            URLQueryItem(name: "subject", value: "Recharge feedback"),
            URLQueryItem(name: "body", value: feedbackText)
        ]
        return components.url ?? URL(string: "mailto:\(AppStoreReviewLinks.supportEmail)")!
    }

    // MARK: - Stage 4

    private var thanks: some View {
        VStack(spacing: 18) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.ready)
            Text("Thank you")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            primaryButton("Done") { dismiss() }
                .padding(.top, 6)
        }
    }

    // MARK: - Buttons

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.recovering, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 15)
                .background(Theme.cardSurface, in: RoundedRectangle(cornerRadius: 14, style: .continuous))
                .foregroundStyle(Theme.textPrimary)
        }
        .buttonStyle(.plain)
    }

    private func finish(_ outcome: ReviewPromptDismissOutcome) {
        onFinish(outcome)
        dismiss()
    }
}
