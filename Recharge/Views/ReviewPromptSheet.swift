import SwiftUI

enum ReviewPromptDismissOutcome: Sendable {
    case notNow
    case openedWriteReview
    case requestNativeReview
}

/// The enjoyment gate.
///
/// Ask whether they like it first. A Yes requests Apple's native rating prompt
/// after this sheet closes. A No routes to feedback.
struct ReviewPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    let onFinish: (ReviewPromptDismissOutcome) -> Void

    @State private var stage = Stage.enjoyment
    @State private var feedbackText = ""
    @State private var feedbackError: String?

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
            VStack(spacing: Theme.Space.lg) {
                switch stage {
                case .enjoyment: enjoyment
                case .ratePitch: ratePitch
                case .feedback: feedback
                case .thanks: thanks
                }
            }
            .padding(.horizontal, Theme.Space.xl)
            .padding(.top, Theme.Space.step(7))
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
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: "hourglass")
                .font(.system(size: 42))
                .foregroundStyle(Theme.recovering)
            Text("Enjoying Recharge?")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("It helps to know either way.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)

            VStack(spacing: Theme.Space.sm) {
                primaryButton("Yes, it's useful") { stage = .ratePitch }
                secondaryButton("Not really") { stage = .feedback }
            }
            .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: - Stage 2

    private var ratePitch: some View {
        VStack(spacing: Theme.Space.lg) {
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

            VStack(spacing: Theme.Space.sm) {
                primaryButton("Rate Recharge") {
                    ReviewPromptTracker.markShown()
                    finish(.requestNativeReview)
                }
                secondaryButton("Write a review") {
                    ReviewPromptTracker.markOpenedWriteReview()
                    openURL(AppStoreReviewLinks.writeReviewURL)
                    finish(.openedWriteReview)
                }
                Button("Not now") {
                    ReviewPromptTracker.markSoftDeferred()
                    finish(.notNow)
                }
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textTertiary)
            }
            .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: - Stage 3

    private var feedback: some View {
        VStack(spacing: Theme.Space.md) {
            Text("What's missing?")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            Text("Tell me what would make the countdown more useful. It goes straight to me.")
                .font(.system(.subheadline, design: .rounded))
                .foregroundStyle(Theme.textSecondary)
                .multilineTextAlignment(.center)

            TextEditor(text: $feedbackText)
                .frame(height: 110)
                .padding(Theme.Space.xs)
                .controlShape()
                .font(.system(.body, design: .rounded))

            primaryButton("Send") {
                feedbackError = nil
                openURL(mailURL) { accepted in
                    guard accepted else {
                        feedbackError = "Couldn't open Mail. Email \(AppStoreReviewLinks.supportEmail) directly."
                        return
                    }
                    ReviewPromptTracker.markFeedbackSubmitted()
                    stage = .thanks
                }
            }
            .disabled(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty)
            .opacity(feedbackText.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? 0.5 : 1)

            if let feedbackError {
                Text(feedbackError)
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(.red)
                    .multilineTextAlignment(.center)
            }
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
        VStack(spacing: Theme.Space.lg) {
            Image(systemName: "checkmark.circle.fill")
                .font(.system(size: 42))
                .foregroundStyle(Theme.ready)
            Text("Thank you")
                .font(.system(.title2, design: .rounded, weight: .bold))
                .foregroundStyle(Theme.textPrimary)
            primaryButton("Done") { dismiss() }
                .padding(.top, Theme.Space.xs)
        }
    }

    // MARK: - Buttons

    private func primaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.md)
                .background(Theme.recovering, in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous))
                .foregroundStyle(.white)
        }
        .pressable()
    }

    private func secondaryButton(_ title: String, action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text(title)
                .font(.system(.headline, design: .rounded))
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.md)
                .controlShape()
                .foregroundStyle(Theme.textPrimary)
        }
        .pressable()
    }

    private func finish(_ outcome: ReviewPromptDismissOutcome) {
        onFinish(outcome)
        dismiss()
    }
}
