import Foundation

/// How a purchase attempt ended, as far as the paywall copy is concerned.
public enum PurchaseState: Equatable, Sendable {
    case purchased
    case cancelled
    case pending
}

/// Reads RevenueCat's purchase errors as the outcomes they really are.
///
/// RevenueCat's `async` `purchase(package:)` and `purchase(product:)` **throw**
/// when the user cancels the App Store sheet (`purchaseCancelledError`) and
/// when Ask to Buy defers the payment (`paymentPendingError`): its continuation
/// resumes with the error whenever one is set, so `userCancelled` on the
/// returned result is never seen for a cancel. Treated as failures, both put
/// "Couldn't start your trial" and a failure haptic in front of somebody who
/// simply closed the sheet, and told a child whose parent has the request that
/// the purchase broke.
///
/// Kept free of the RevenueCat import so the logic suite can pin it.
/// `StoreService` asserts the constants against the SDK's own `ErrorCode`.
public enum PurchaseErrorOutcome {
    /// `ErrorCode.errorDomain`: the module-qualified type name.
    public static let revenueCatDomain = "RevenueCat.ErrorCode"
    /// `ErrorCode.purchaseCancelledError.rawValue`.
    public static let cancelledCode = 1
    /// `ErrorCode.paymentPendingError.rawValue`.
    public static let pendingCode = 20

    /// The outcome a thrown purchase error stands for, or `nil` when it is a
    /// real failure.
    public static func state(for error: Error) -> PurchaseState? {
        let error = error as NSError
        guard error.domain == revenueCatDomain else { return nil }
        switch error.code {
        case cancelledCode: return .cancelled
        case pendingCode: return .pending
        default: return nil
        }
    }
}
