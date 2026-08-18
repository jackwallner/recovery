import SwiftUI

/// The session-RPE question, on the phone.
///
/// It exists because a lifting session produces garbage heart-rate data: the
/// optical sensor loses the signal under grip and bar contact, so TRIMP has
/// nothing reliable to work from. Without this, a heavy hour of squats and an
/// easy hour of walking look the same to the model.
///
/// One tap, three bands. A ten-point slider would be more precise and far less
/// likely to be answered.
struct EffortPromptSheet: View {
    let activityLabel: String
    let durationMinutes: Double
    /// `nil` means Skip: a decline, which retires the request rather than
    /// leaving it to be asked again on the next launch.
    let onSelect: (Double?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// Borg CR10 anchors, collapsed to the three bands people can actually
    /// distinguish after the fact.
    static let options: [(effort: Double, title: String, detail: String)] = [
        (4, "Easy", "Could have kept going for a long time."),
        (7, "Moderate", "Working, but in control throughout."),
        (9, "Hard", "Near the limit. Little left at the end.")
    ]

    var body: some View {
        NavigationStack {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "hand.raised.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.recovering)
                    Text("How hard was it?")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                    // Same correction as the card that opens this sheet: the
                    // rating joins the other signals and the highest one wins,
                    // so it can only ever lengthen the window, never shorten it.
                    Text("Your \(Int(durationMinutes.rounded()))-minute \(activityLabel) didn't have usable heart-rate data. Your rating counts whenever it reads harder than the other signals.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                }
                .padding(.top, 24)

                VStack(spacing: 10) {
                    ForEach(Self.options, id: \.effort) { option in
                        Button {
                            onSelect(option.effort)
                            dismiss()
                        } label: {
                            HStack(spacing: 12) {
                                VStack(alignment: .leading, spacing: 3) {
                                    Text(option.title)
                                        .font(.system(.headline, design: .rounded))
                                        .foregroundStyle(Theme.textPrimary)
                                    Text(option.detail)
                                        .font(.system(.caption, design: .rounded))
                                        .foregroundStyle(Theme.textSecondary)
                                }
                                Spacer()
                                Image(systemName: "chevron.right")
                                    .font(.caption)
                                    .foregroundStyle(Theme.textTertiary)
                            }
                            .padding(16)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .background(
                                Theme.cardSurface,
                                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                            )
                        }
                        .buttonStyle(.plain)
                    }
                }

                Spacer()
            }
            .padding(.horizontal, 20)
            .background(Theme.background)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("Skip") {
                        onSelect(nil)
                        dismiss()
                    }
                }
            }
        }
        .presentationDetents([.medium])
    }
}

/// The one-tap question asked once a countdown expires. Local only — it
/// calibrates the user's own duration bands and never leaves the device.
struct ReadinessFeedbackSheet: View {
    let estimate: RecoveryEstimate
    /// `nil` means dismissed without answering.
    let onAnswer: (ReadinessFeedback?) -> Void

    @Environment(\.dismiss) private var dismiss

    /// No `NavigationStack`, and no fixed detent.
    ///
    /// The three answers are the entire point of this sheet, and at a `.medium`
    /// detent the content ran past the bottom of it: on a smaller phone, or at a
    /// larger text size, the last answer sat below the fold with nothing to
    /// scroll and a navigation bar eating the top. That is the "blocked off"
    /// half of the report. It scrolls now, sized to its own content, with
    /// `.large` underneath for accessibility text sizes and the escape as a
    /// plain button in the flow rather than a toolbar item.
    var body: some View {
        ScrollView {
            VStack(spacing: 20) {
                VStack(spacing: 8) {
                    Image(systemName: "checkmark.circle.fill")
                        .font(.system(size: 40))
                        .foregroundStyle(Theme.ready)
                    Text("How did that feel?")
                        .font(.system(.title2, design: .rounded, weight: .bold))
                        .foregroundStyle(Theme.textPrimary)
                        .multilineTextAlignment(.center)
                    Text("Your estimate after that \(estimate.activityLabel) ran out. Telling Recharge how it went tunes your own bands.")
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .multilineTextAlignment(.center)
                        .fixedSize(horizontal: false, vertical: true)
                }
                .padding(.top, 28)

                VStack(spacing: 10) {
                    ForEach(ReadinessFeedback.allCases, id: \.self) { feedback in
                        Button {
                            onAnswer(feedback)
                            dismiss()
                        } label: {
                            Text(feedback.label)
                                .font(.system(.headline, design: .rounded))
                                .multilineTextAlignment(.center)
                                .fixedSize(horizontal: false, vertical: true)
                                .frame(maxWidth: .infinity)
                                .padding(.vertical, 15)
                                .background(
                                    Theme.cardSurface,
                                    in: RoundedRectangle(cornerRadius: 16, style: .continuous)
                                )
                                .foregroundStyle(Theme.textPrimary)
                        }
                        .buttonStyle(.plain)
                    }
                }

                Button("Not now") {
                    onAnswer(nil)
                    dismiss()
                }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(Theme.textSecondary)
                .padding(.vertical, 4)

                Text("Stored on this device only.")
                    .font(.system(.caption2, design: .rounded))
                    .foregroundStyle(Theme.textTertiary)
            }
            .frame(maxWidth: .infinity)
            .padding(.horizontal, 20)
            .padding(.bottom, 28)
        }
        .scrollBounceBehavior(.basedOnSize)
        .background(Theme.background)
        .presentationDetents([.height(Self.preferredHeight), .large])
        .presentationDragIndicator(.visible)
    }

    /// Tall enough for the icon, the explanation, all three answers and the way
    /// out, with `.large` available underneath for accessibility text sizes.
    private static let preferredHeight: CGFloat = 470
}
