import SwiftUI

/// The comparison that makes the countdown mean something.
///
/// A lone "18h" gives the user no way to tell whether that is a lot, a little,
/// or roughly what they were going to do anyway. Three columns per intensity
/// band answer it:
///
/// - **You** — the gap they actually leave. Measured, not modelled, and shown on
///   both tiers because it is a description of their own training rather than a
///   personalised estimate.
/// - **Similar** — what the standard table gives someone with their answers.
/// - **Yours** — what Recharge+ makes of it, blurred until they have it.
///
/// The third column is the pitch and it is deliberately a real number under the
/// blur, computed the same way a subscriber's would be. A mocked-up figure there
/// is a figure someone will hold the app to.
struct RestPatternCard: View {
    let rows: [RestPattern.Row]
    let isPro: Bool
    var onUpgrade: (() -> Void)?

    /// The onboarding pitch shows the same table with none of the furniture: no
    /// upgrade button (the page has one), no explanatory footnote (the page is
    /// the explanation). Same numbers, same blur, so what the user is shown
    /// before paying is exactly what they get after.
    var isCompact = false

    /// The band the sentence talks about: the hardest one with a real measured
    /// gap, because that is where the difference between habit and estimate is
    /// largest and where the user has the most to gain from looking.
    private var narratedRow: RestPattern.Row? {
        rows.last { $0.observedRestHours != nil }
    }

    var body: some View {
        Card {
            VStack(alignment: .leading, spacing: 14) {
                header
                table
                if let narratedRow, let sentence = RestPattern.observedSentence(narratedRow) {
                    Text(sentence)
                        .font(.system(.footnote, design: .rounded))
                        .foregroundStyle(Theme.textSecondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
                if !isCompact {
                    if !isPro, let onUpgrade { upgradeButton(onUpgrade) }
                    footnote
                }
            }
        }
    }

    private var header: some View {
        HStack(alignment: .firstTextBaseline) {
            VStack(alignment: .leading, spacing: 3) {
                Text("Your rest pattern")
                    .font(.system(.subheadline, design: .rounded, weight: .semibold))
                    .foregroundStyle(Theme.textPrimary)
                Text("Hours between sessions, by how hard the last one was.")
                    .font(.system(.caption, design: .rounded))
                    .foregroundStyle(Theme.textSecondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
            Spacer(minLength: 8)
            if !isPro, !isCompact { ProBadge() }
        }
    }

    private var table: some View {
        VStack(spacing: 0) {
            HStack(spacing: 0) {
                Text("")
                    .frame(maxWidth: .infinity, alignment: .leading)
                columnHeading("You")
                columnHeading("Similar")
                columnHeading("Yours")
            }
            .padding(.bottom, 6)
            .accessibilityHidden(true)

            ForEach(Array(rows.enumerated()), id: \.element.id) { index, row in
                if index > 0 {
                    Divider().overlay(Theme.ringTrack)
                }
                bandRow(row)
            }
        }
    }

    private func columnHeading(_ text: String) -> some View {
        Text(text)
            .font(.system(.caption2, design: .rounded, weight: .semibold))
            .foregroundStyle(Theme.textTertiary)
            .textCase(.uppercase)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    private func bandRow(_ row: RestPattern.Row) -> some View {
        HStack(spacing: 0) {
            Text(row.band.shortLabel)
                .font(.system(.footnote, design: .rounded, weight: .medium))
                .foregroundStyle(Theme.textPrimary)
                .lineLimit(1)
                .minimumScaleFactor(0.7)
                .frame(maxWidth: .infinity, alignment: .leading)

            // An em dash rather than a zero: a band with fewer than two measured
            // gaps has no figure, and printing one anyway would be inventing the
            // only column on this card that is a measurement.
            figure(
                row.observedRestHours.map(CountdownFormat.hours) ?? "—",
                tint: Theme.textPrimary
            )
            figure(CountdownFormat.hours(row.similarProfilesHours), tint: Theme.textSecondary)
            personalizedFigure(row)
        }
        .padding(.vertical, 9)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(accessibilityLabel(for: row))
    }

    private func figure(_ text: String, tint: Color) -> some View {
        Text(text)
            .font(.system(.subheadline, design: .rounded, weight: .semibold))
            .monospacedDigit()
            .foregroundStyle(tint)
            .lineLimit(1)
            .minimumScaleFactor(0.7)
            .frame(maxWidth: .infinity)
    }

    /// The real personalized figure, blurred rather than replaced.
    ///
    /// Replacing it with a lock glyph would make the card an advertisement;
    /// blurring the number the subscriber would actually see makes it a preview
    /// of arithmetic that already exists. `RecoveryEngine` computes it on both
    /// tiers for exactly this reason.
    @ViewBuilder
    private func personalizedFigure(_ row: RestPattern.Row) -> some View {
        let text = CountdownFormat.hours(row.personalizedHours)
        if isPro {
            figure(text, tint: Theme.pro)
        } else {
            // Blurred *just* enough that the shape of a two-character figure is
            // still legible as a figure. At radius 6 with a small lock centred on
            // top, a 17-point number disappeared completely and the cell read as
            // a rendering fault rather than as a withheld value — which defeats
            // the reason the real number is computed on this tier at all.
            figure(text, tint: Theme.pro)
                .blur(radius: 3.5)
                .opacity(0.85)
                .overlay(alignment: .topTrailing) {
                    Image(systemName: "lock.fill")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(Theme.pro)
                        .padding(.trailing, 2)
                }
        }
    }

    private func upgradeButton(_ action: @escaping () -> Void) -> some View {
        Button(action: action) {
            Text("See your own numbers")
                .font(.system(.footnote, design: .rounded, weight: .semibold))
                .frame(maxWidth: .infinity)
                .padding(.vertical, 10)
                .background(Theme.pro, in: Capsule())
                .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
    }

    /// Says which figures are measurements and which are estimates, because the
    /// three columns look alike and only one of them is something that happened.
    private var footnote: some View {
        Text(
            rows.contains(where: \.isExample)
                ? "Measured from your own sessions where there are enough of them, and from the standard curve where there are not. Estimates, not targets."
                : "Measured from your own sessions. The last two columns are estimates, not targets."
        )
        .font(.system(.caption2, design: .rounded))
        .foregroundStyle(Theme.textTertiary)
        .fixedSize(horizontal: false, vertical: true)
    }

    private func accessibilityLabel(for row: RestPattern.Row) -> String {
        var parts = ["\(row.band.shortLabel) sessions."]
        if let observed = row.observedRestHours {
            parts.append("You usually leave \(CountdownFormat.hours(observed)).")
        } else {
            parts.append("Not enough gaps measured yet.")
        }
        parts.append("Similar profiles, \(CountdownFormat.hours(row.similarProfilesHours)).")
        parts.append(
            isPro
                ? "Yours, \(CountdownFormat.hours(row.personalizedHours))."
                : "Your own estimate is a Recharge+ feature."
        )
        return parts.joined(separator: " ")
    }
}
