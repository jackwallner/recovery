import SwiftUI

/// Static legal destinations, in one place because three surfaces have to agree
/// about them: onboarding, the trial sheet, and Settings.
enum RechargeLinks {
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let privacyPolicy = URL(string: "https://jackwallner.github.io/recovery/privacy-policy.html")!
}

/// The bottom block every onboarding page ends in, and the whole of the reason
/// the primary button lands on the same pixel row on all of them.
///
/// The rule is a layout rule, not a copy rule: **nothing that varies between
/// pages may sit below the primary button.** The button's distance from the
/// bottom of the screen is therefore a constant — twelve points, the legal slot,
/// and the page's bottom padding — so its frame cannot move no matter what a
/// given page puts above it.
///
/// That is what the previous version got wrong. Every explanatory page ended in
/// secondary-then-primary and nothing else, while the trial page appended a
/// subscription disclosure and a Restore/Terms/Privacy row *under* its CTA. Two
/// lines of eleven-point legal text is about forty points, so the one button in
/// the flow that takes money sat forty points higher than the four Continue
/// buttons that trained the thumb to reach for it.
///
/// The legal slot is now laid out on every page and only *shown* on the one that
/// needs it, which is the same trick the reserved secondary row has always used.
struct OnboardingActions: View {
    let primaryTitle: String
    let primaryAction: () -> Void
    var tint: Color = Theme.recovering
    var primaryDisabled = false
    var isBusy = false
    var secondaryTitle: String?
    var secondaryAction: (() -> Void)?

    /// Anything the page wants directly above the secondary row — the price
    /// block, a subscription disclosure, an error. It may be any height at any
    /// content size: nothing above the button can move the button.
    var above: AnyView?

    /// Purchase points have to carry Restore, Terms, and Privacy. Every other
    /// page lays the row out and hides it.
    var showsLegalLinks = false
    var isRestoring = false
    var onRestore: (() -> Void)?

    var body: some View {
        VStack(spacing: 12) {
            above

            // Always present, sometimes invisible, and always *above* the
            // primary. The placeholder text is a real string rather than a space
            // so it reserves the same height at every Dynamic Type size, and
            // sitting above means the primary button is the lowest interactive
            // thing on every page — including the offer, where the way out is
            // "Get Started" and the CTA underneath it has to land in the same
            // slot the thumb has been using all flow.
            Button(secondaryTitle ?? "Not now") { secondaryAction?() }
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(secondaryAction == nil ? Theme.textTertiary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, 8)
                .opacity(secondaryTitle == nil ? 0 : 1)
                .disabled(secondaryTitle == nil || secondaryAction == nil)
                .allowsHitTesting(secondaryTitle != nil && secondaryAction != nil)
                .accessibilityHidden(secondaryTitle == nil)

            OnboardingPrimaryButton(
                title: primaryTitle,
                action: primaryAction,
                tint: tint,
                isDisabled: primaryDisabled,
                isBusy: isBusy
            )

            OnboardingLegalSlot(
                isVisible: showsLegalLinks,
                isRestoring: isRestoring,
                onRestore: onRestore
            )
        }
    }
}

/// The one button the flow is built around.
///
/// The spinner is overlaid rather than inserted, so a page that goes busy — the
/// Health request, a purchase in flight — does not grow the button by the height
/// difference between a `ProgressView` and a headline and shift itself upward
/// mid-tap.
struct OnboardingPrimaryButton: View {
    let title: String
    let action: () -> Void
    var tint: Color = Theme.recovering
    var isDisabled = false
    var isBusy = false

    var body: some View {
        Button(action: action) {
            ZStack {
                Text(title)
                    .font(.system(.headline, design: .rounded))
                    // Capped for the same reason the price below is: at the top
                    // accessibility sizes an uncapped headline on the button
                    // outgrows the billed amount, and Apple 3.1.2(c) weighs
                    // pricing elements against each other.
                    .dynamicTypeSize(...DynamicTypeSize.accessibility2)
                    .opacity(isBusy ? 0 : 1)
                if isBusy {
                    ProgressView()
                        .tint(.white)
                        .controlSize(.small)
                }
            }
            .frame(maxWidth: .infinity)
            .padding(.vertical, 16)
            .background(
                tint.opacity(isDisabled ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: 16, style: .continuous)
            )
            .foregroundStyle(.white)
        }
        .buttonStyle(.plain)
        .disabled(isDisabled)
    }
}

/// Restore, Terms, Privacy — laid out on every onboarding page and shown on the
/// purchase point.
///
/// Hidden rather than absent: this row is the only thing below the primary
/// button, so its height is what makes that button's position a constant. An
/// `if` here would put the bug straight back.
struct OnboardingLegalSlot: View {
    var isVisible: Bool
    var isRestoring = false
    var onRestore: (() -> Void)?

    var body: some View {
        ViewThatFits(in: .horizontal) {
            HStack(spacing: 16) { links }
            VStack(spacing: 8) { links }
        }
        .font(.system(.caption, design: .rounded))
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .foregroundStyle(Theme.textSecondary)
        .opacity(isVisible ? 1 : 0)
        .allowsHitTesting(isVisible)
        .accessibilityHidden(!isVisible)
    }

    @ViewBuilder
    private var links: some View {
        Button(isRestoring ? "Restoring…" : "Restore") { onRestore?() }
            .disabled(isRestoring || onRestore == nil)
        Link("Terms", destination: RechargeLinks.standardEULA)
        Link("Privacy", destination: RechargeLinks.privacyPolicy)
    }
}
