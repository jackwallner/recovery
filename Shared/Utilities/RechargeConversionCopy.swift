import Foundation

/// Pure copy helpers for Recharge+ conversion CTAs.
///
/// StoreKit always purchases the same package — trial vs paid is *eligibility*,
/// not a different product — so every pitch surface routes through here and
/// stays honest for users who have already used their free trial.
public enum RechargeConversionCopy {
    public static let proName = "Recharge+"

    /// The two column headings every comparison surface uses, named once.
    ///
    /// They used to read **Usual** and **Optimal**, and that pair was the single
    /// most confusing thing in the app: neither word says which tier it belongs
    /// to, so a user looking at "23h → 8h" had no way to tell which figure was
    /// the thing they already had and which was the thing being sold. Naming the
    /// *tiers* answers that with no ambiguity and no claim about how either
    /// number was derived — that is what the caption underneath is for.
    public static var standardColumn: String { String(localized: "Standard", bundle: .recharge) }
    public static var proColumn: String { proName }

    /// The one line that has to sit under any pair of these figures, because the
    /// headings name the tiers and something still has to name the derivation.
    ///
    /// Both halves are literally true, which matters more here than anywhere
    /// else in the app: the standard figure is the model scored at the user's
    /// training level, and the Recharge+ figure is the same session scored
    /// against their own baseline, their thirty-day pattern, and their sleep.
    public static func comparisonCaption(hasPurchased: Bool) -> String {
        String(localized: "Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate.", bundle: .recharge)
    }

    /// Primary button. Carries no pricing words at all: not the trial, not the
    /// price. Apple 3.1.2(c) weighs pricing elements against each other, and a
    /// bold button reading "Start 7-day free trial" would outshout the calm
    /// price line above it. With a neutral button, the billed amount is the
    /// leading pricing text on the surface.
    ///
    /// The parameters are retained so callers keep passing the real offer, and
    /// so re-introducing price wording stays a one-line change.
    public static func ctaLabel(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        String(localized: "Continue with Recharge+", bundle: .recharge)
    }

    /// Short capsule CTA on locked cards. These sit far from any price and only
    /// route to a purchase surface, so they stay neutral for the same reason.
    public static func shortCTALabel(eligibleForTrial: Bool) -> String {
        String(localized: "Continue with Recharge+", bundle: .recharge)
    }

    /// Subordinate line under the billed amount.
    ///
    /// `isRecurring` is false for the lifetime non-consumable: Apple 3.1.2
    /// requires the terms shown to match what is actually charged, and there is
    /// nothing to bill again or to cancel on a one-time purchase.
    public static func billedNote(
        trialLabel: String?,
        eligibleForTrial: Bool,
        isRecurring: Bool = true
    ) -> String {
        guard isRecurring else { return String(localized: "One-time purchase · No subscription", bundle: .recharge) }
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return String(localized: "\(trialLabel) included · Cancel anytime", bundle: .recharge)
        }
        return String(localized: "Billed automatically · Cancel anytime", bundle: .recharge)
    }

    /// Apple 3.1.2 disclosure adjacent to the purchase button.
    public static func disclosure(
        trialLabel: String?,
        priceLabel: String,
        eligibleForTrial: Bool
    ) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return String(localized: "\(priceLabel) after the \(trialLabel). Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.", bundle: .recharge)
        }
        return String(localized: "\(priceLabel). Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions.", bundle: .recharge)
    }

    /// Compact disclosure for the onboarding trial sheet footer.
    public static func sheetDisclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return String(localized: "\(priceLabel) after the \(trialLabel). Auto-renews unless cancelled at least 24 hours before the trial ends.", bundle: .recharge)
        }
        return String(localized: "\(priceLabel). Auto-renews unless cancelled 24h before the period ends.", bundle: .recharge)
    }

    /// Cancel / failure copy — never blames a "trial" the user wasn't eligible for.
    public static func purchaseCancelledMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? String(localized: "Trial wasn't started. Tap again to continue.", bundle: .recharge)
            : String(localized: "Purchase wasn't completed. Tap again to continue.", bundle: .recharge)
    }

    public static func purchaseFailedMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? String(localized: "Couldn't start your trial. Please try again.", bundle: .recharge)
            : String(localized: "Couldn't complete the purchase. Please try again.", bundle: .recharge)
    }
}
