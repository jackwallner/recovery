import SwiftUI

/// Static legal destinations, in one place because three surfaces have to agree
/// about them: onboarding, the trial sheet, and Settings.
enum RechargeLinks {
    static let standardEULA = URL(string: "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/")!
    static let termsOfUse = URL(string: "https://jackwallner.github.io/recovery/terms.html")!
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
        VStack(spacing: Theme.Space.sm) {
            above

            // Always present, sometimes invisible, and always *above* the
            // primary. The placeholder text is a real string rather than a space
            // so it reserves the same height at every Dynamic Type size, and
            // sitting above means the primary button is the lowest interactive
            // thing on every page — including the offer, where the way out is
            // "Get Started" and the CTA underneath it has to land in the same
            // slot the thumb has been using all flow.
            secondaryRow
                .font(.system(.subheadline, design: .rounded, weight: .semibold))
                .foregroundStyle(secondaryAction == nil ? Theme.textTertiary : Theme.textSecondary)
                .frame(maxWidth: .infinity)
                .padding(.vertical, Theme.Space.xs)

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

    /// A page with no secondary action gets a hidden text of the same size, not
    /// a hidden button. An invisible button is still a button to XCUITest and
    /// to anyone inspecting the page, and on the Health page an invisible
    /// "Not now" reads as a way to skip the permission request, which App
    /// Review rejects under 5.1.1(iv).
    @ViewBuilder
    private var secondaryRow: some View {
        if let secondaryTitle {
            Button(secondaryTitle) { secondaryAction?() }
                .disabled(secondaryAction == nil)
        } else {
            Text(verbatim: "Not now")
                .hidden()
                .accessibilityHidden(true)
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
            .padding(.vertical, Theme.Space.md)
            .background(
                tint.opacity(isDisabled ? 0.6 : 1),
                in: RoundedRectangle(cornerRadius: Theme.Radius.control, style: .continuous)
            )
            .foregroundStyle(.white)
        }
        .pressable()
        .disabled(isDisabled)
    }
}

/// Restore, Terms, Apple EULA, Privacy, laid out on every onboarding page and
/// shown on the purchase point.
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
            HStack(spacing: Theme.Space.md) { row }
            VStack(spacing: Theme.Space.xs) { row }
        }
        .font(.system(.caption, design: .rounded))
        .dynamicTypeSize(...DynamicTypeSize.accessibility3)
        .foregroundStyle(Theme.textSecondary)
    }

    /// Hidden text of the same size off the purchase point, for the same reason
    /// as the secondary row: invisible links are still links to anything that
    /// reads the page.
    @ViewBuilder
    private var row: some View {
        if isVisible {
            links
        } else {
            ForEach(["Restore", "Terms", "Apple EULA", "Privacy"], id: \.self) { title in
                Text(verbatim: title)
                    .frame(minHeight: 44)
                    .hidden()
            }
            .accessibilityHidden(true)
        }
    }

    @ViewBuilder
    private var links: some View {
        Button(isRestoring ? "Restoring…" : "Restore") { onRestore?() }
            .disabled(isRestoring || onRestore == nil)
            .frame(minHeight: 44)
        Link("Terms", destination: RechargeLinks.termsOfUse)
            .frame(minHeight: 44)
        Link("Apple EULA", destination: RechargeLinks.standardEULA)
            .frame(minHeight: 44)
        Link("Privacy", destination: RechargeLinks.privacyPolicy)
            .frame(minHeight: 44)
    }
}
