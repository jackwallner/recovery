import SwiftUI

/// Feedback is its own path, never a branch of a rating question. Guideline
/// 5.6.1 rejects asking "Enjoying it?" and sending only the yes answers to the
/// App Store, so ratings go straight to Apple's own prompt and this sheet only
/// collects feedback, opened from Settings.
struct ReviewPromptSheet: View {
    @Environment(\.dismiss) private var dismiss
    @Environment(\.openURL) private var openURL

    @State private var stage = Stage.feedback
    @State private var feedbackText = ""
    @State private var feedbackError: String?

    private enum Stage {
        case feedback
        case thanks
    }

    var body: some View {
        NavigationStack {
            ScrollView {
                VStack(spacing: Theme.Space.lg) {
                    switch stage {
                    case .feedback: feedback
                    case .thanks: thanks
                    }
                }
                .padding(.horizontal, Theme.Space.xl)
                .padding(.top, Theme.Space.step(7))
                .padding(.bottom, Theme.Space.xl)
                .frame(maxWidth: .infinity, alignment: .top)
            }
            .scrollBounceBehavior(.basedOnSize)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Close") { dismiss() }
                }
            }
        }
        .presentationDetents([.large])
        .presentationDragIndicator(.visible)
    }

    // MARK: - Feedback

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
                .accessibilityLabel("Feedback")
                .accessibilityHint("Describe what would make the countdown more useful.")

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

    // MARK: - Thanks

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
}
