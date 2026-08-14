import Foundation

/// Pure copy helpers for Recharge+ conversion CTAs.
///
/// StoreKit always purchases the same package — trial vs paid is *eligibility*,
/// not a different product — so every pitch surface routes through here and
/// stays honest for users who have already used their free trial.
public enum RechargeConversionCopy {
    public static let proName = "Recharge+"

    /// Primary button. Carries no pricing words at all: not the trial, not the
    /// price. Apple 3.1.2(c) weighs pricing elements against each other, and a
    /// bold button reading "Start 7-day free trial" would outshout the calm
    /// price line above it. With a neutral button, the billed amount is the
    /// leading pricing text on the surface.
    ///
    /// The parameters are retained so callers keep passing the real offer, and
    /// so re-introducing price wording stays a one-line change.
    public static func ctaLabel(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        "Continue with \(proName)"
    }

    /// Short capsule CTA on locked cards. These sit far from any price and only
    /// route to a purchase surface, so they stay neutral for the same reason.
    public static func shortCTALabel(eligibleForTrial: Bool) -> String {
        "Continue with \(proName)"
    }

    /// Apple 3.1.2(c): the amount the user will actually be billed, phrased as a
    /// commitment rather than a rate. Every purchase surface renders this as its
    /// largest pricing element.
    public static func billedAmount(priceLabel: String) -> String {
        priceLabel.replacingOccurrences(of: " / ", with: " per ")
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
        guard isRecurring else { return "One-time purchase · No subscription" }
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "\(trialLabel.lowercased()) included · Cancel anytime"
        }
        return "Billed automatically · Cancel anytime"
    }

    /// Apple 3.1.2 disclosure adjacent to the purchase button.
    public static func disclosure(
        trialLabel: String?,
        priceLabel: String,
        eligibleForTrial: Bool,
        renewClause: String = "Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in Settings › Apple ID › Subscriptions."
    ) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "\(priceLabel) after the \(trialLabel.lowercased()). \(renewClause)"
        }
        return "\(priceLabel). \(renewClause)"
    }

    /// Compact disclosure for the onboarding trial sheet footer.
    public static func sheetDisclosure(trialLabel: String?, priceLabel: String, eligibleForTrial: Bool) -> String {
        if eligibleForTrial, let trialLabel, !trialLabel.isEmpty {
            return "\(priceLabel) after the \(trialLabel.lowercased()). Auto-renews unless cancelled at least 24 hours before the trial ends."
        }
        return "\(priceLabel). Auto-renews unless cancelled 24h before the period ends."
    }

    /// Cancel / failure copy — never blames a "trial" the user wasn't eligible for.
    public static func purchaseCancelledMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? "Trial wasn't started. Tap again to continue."
            : "Purchase wasn't completed. Tap again to continue."
    }

    public static func purchaseFailedMessage(eligibleForTrial: Bool) -> String {
        eligibleForTrial
            ? "Couldn't start your trial. Please try again."
            : "Couldn't complete the purchase. Please try again."
    }
}
