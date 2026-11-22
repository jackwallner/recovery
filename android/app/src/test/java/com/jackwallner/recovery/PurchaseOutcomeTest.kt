package com.jackwallner.recovery

import org.junit.Assert.*
import org.junit.Test

import com.revenuecat.purchases.PurchasesError
import com.revenuecat.purchases.PurchasesErrorCode
import com.revenuecat.purchases.PurchasesTransactionException

import com.jackwallner.recovery.data.PurchaseOutcome
import com.jackwallner.recovery.data.outcomeOf

/** Port of iOS 14b54a2: a purchase the store holds as pending is pending, never a failure and never an unlock. */
class PurchaseOutcomeTest {
    private fun thrown(code: PurchasesErrorCode,userCancelled: Boolean=false)=PurchasesTransactionException(PurchasesError(code),userCancelled)
    @Test fun aPendingGooglePlayPurchaseIsPendingNotAFailure() = assertEquals(PurchaseOutcome.PENDING,outcomeOf(thrown(PurchasesErrorCode.PaymentPendingError)))
    @Test fun cancellingTheSheetIsACancellation() = assertEquals(PurchaseOutcome.CANCELLED,outcomeOf(thrown(PurchasesErrorCode.PurchaseCancelledError,true)))
    @Test fun otherErrorsStayFailures() {
        assertNull(outcomeOf(thrown(PurchasesErrorCode.StoreProblemError)))
        assertNull(outcomeOf(thrown(PurchasesErrorCode.NetworkError)))
    }
    @Test fun pendingIsNeverReportedAsPurchased() = assertNotEquals(PurchaseOutcome.PURCHASED,outcomeOf(thrown(PurchasesErrorCode.PaymentPendingError)))
}
