import XCTest

/// A closed App Store sheet is a cancel, and Ask to Buy is pending.
///
/// RevenueCat's `async` purchase throws both as `NSError`s in its own domain
/// rather than returning `userCancelled`, so the paywall's `.cancelled` and
/// `.pending` branches were unreachable on a device: closing the sheet showed
/// "Couldn't start your trial. Please try again." with a failure haptic.
final class PurchaseOutcomeTests: XCTestCase {

    /// The shape RevenueCat throws: `PurchasesError.asPublicError` is an
    /// `NSError` in `ErrorCode.errorDomain` with the `ErrorCode` raw value.
    private func revenueCatError(_ code: Int) -> Error {
        NSError(
            domain: "RevenueCat.ErrorCode",
            code: code,
            userInfo: [NSLocalizedDescriptionKey: "test"]
        )
    }

    func testAClosedPurchaseSheetIsACancelNotAFailure() {
        XCTAssertEqual(PurchaseErrorOutcome.state(for: revenueCatError(1)), .cancelled)
    }

    func testAskToBuyIsPendingNotAFailure() {
        XCTAssertEqual(PurchaseErrorOutcome.state(for: revenueCatError(20)), .pending)
    }

    func testRealFailuresStillThrow() {
        // storeProblemError, networkError, purchaseNotAllowedError, unknownError.
        for code in [0, 2, 3, 10] {
            XCTAssertNil(PurchaseErrorOutcome.state(for: revenueCatError(code)), "code \(code)")
        }
    }

    func testTheSameCodeFromAnotherDomainIsNotACancel() {
        XCTAssertNil(PurchaseErrorOutcome.state(for: NSError(domain: NSURLErrorDomain, code: 1)))
        XCTAssertNil(PurchaseErrorOutcome.state(for: NSError(domain: "SKErrorDomain", code: 20)))
    }
}
