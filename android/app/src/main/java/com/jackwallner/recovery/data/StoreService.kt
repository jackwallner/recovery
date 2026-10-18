package com.jackwallner.recovery.data

import android.app.Activity
import android.content.Context

import com.revenuecat.purchases.CacheFetchPolicy
import com.revenuecat.purchases.CustomerInfo
import com.revenuecat.purchases.LogLevel
import com.revenuecat.purchases.Offering
import com.revenuecat.purchases.Package
import com.revenuecat.purchases.PackageType
import com.revenuecat.purchases.PurchaseParams
import com.revenuecat.purchases.Purchases
import com.revenuecat.purchases.PurchasesConfiguration
import com.revenuecat.purchases.PurchasesTransactionException
import com.revenuecat.purchases.awaitCustomerInfo
import com.revenuecat.purchases.awaitOfferings
import com.revenuecat.purchases.awaitPurchase
import com.revenuecat.purchases.awaitRestore
import com.revenuecat.purchases.interfaces.UpdatedCustomerInfoListener
import com.revenuecat.purchases.paywalls.events.CustomPaywallImpressionParams
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

import com.jackwallner.recovery.BuildConfig
import com.jackwallner.recovery.model.ConversionDiagnostics

object Legal {
    const val TERMS_URL = "https://jackwallner.github.io/recovery/android/terms.html"
    const val PRIVACY_URL = "https://jackwallner.github.io/recovery/android/privacy-policy.html"
    const val SUPPORT_URL = "https://jackwallner.github.io/recovery/support.html"
    const val FEEDBACK_EMAIL = "jackwallner@gmail.com"
    const val PLAY_LISTING_URL = "https://play.google.com/store/apps/details?id=com.jackwallner.recovery"
}

data class PlanOption(val id: String, val displayName: String, val priceLabel: String, val pkg: Package?, val trialLabel: String? = null, val recurring: Boolean = true) {
    val isPurchasable: Boolean get() = pkg != null
}

enum class PurchaseOutcome { PURCHASED, PENDING, CANCELLED }

data class StoreState(
    val isPro: Boolean = false,
    val isResolved: Boolean = false,
    val planOptions: List<PlanOption> = emptyList(),
    val isLoadingProducts: Boolean = false,
    val lastError: String? = null,
    val restoreError: String? = null,
    val offeringId: String? = null,
)

/**
 * RevenueCat, behind the single Recharge+ gate. Debug builds use the Test
 * Store key; release builds use the Play key. Neither ever runs on the other.
 */
class StoreService(private val context: Context, private val diagnostics: ConversionDiagnostics) {
    private val preferences=context.getSharedPreferences("recovery-billing",Context.MODE_PRIVATE)
    private val _state = MutableStateFlow(StoreState(isPro=preferences.getBoolean("recoveryProCached",false)))
    val state: StateFlow<StoreState> = _state.asStateFlow()
    private var isConfigured = false
    private var forcePro = false
    private var paywallImpressionsThisSession = mutableSetOf<String>()

    val current: StoreState get() = _state.value

    /** Debug-only hook: open the paid boundary for local screenshots and tests. */
    fun forceProForDebug() {
        if (!BuildConfig.DEBUG) return
        forcePro = true
        _state.update { it.copy(isPro = true, isResolved = true) }
    }

    suspend fun start() {
        if (forcePro) return
        if (!configureIfNeeded()) return
        updateCustomerStatus(CacheFetchPolicy.FETCH_CURRENT)
        fetchProducts()
    }

    suspend fun fetchProducts() {
        if (!configureIfNeeded()) {
            _state.update { it.copy(lastError = "Purchases aren't available in this build.") }
            return
        }
        _state.update { it.copy(isLoadingProducts = true) }
        try {
            val offerings = Purchases.sharedInstance.awaitOfferings()
            val offering: Offering? = offerings.getOffering("default") ?: offerings.current
            val plans = offering?.availablePackages.orEmpty().sortedBy { when(it.packageType) { PackageType.LIFETIME -> 0; PackageType.ANNUAL -> 1; PackageType.MONTHLY -> 2; else -> 3 } }
            _state.update {
                it.copy(
                    planOptions = plans.map { pkg ->
                        val name = when(pkg.packageType) { PackageType.LIFETIME -> "Lifetime"; PackageType.ANNUAL -> "Yearly"; PackageType.MONTHLY -> "Monthly"; else -> pkg.product.title }
                        val suffix = when(pkg.packageType) { PackageType.ANNUAL -> " / year"; PackageType.MONTHLY -> " / month"; PackageType.LIFETIME -> " once"; else -> pkg.product.period?.iso8601?.let { " / $it" }.orEmpty() }
                        val trial = pkg.product.defaultOption?.freePhase?.billingPeriod?.iso8601?.let(com.jackwallner.recovery.model.ConversionCopy::trialLabel)
                        PlanOption(pkg.product.id, name, pkg.product.price.formatted + suffix, pkg, trial, pkg.packageType != PackageType.LIFETIME)
                    },
                    offeringId = offering?.identifier,
                    lastError = null,
                    isLoadingProducts = false,
                )
            }
        } catch (error: Throwable) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            _state.update {
                it.copy(
                    isLoadingProducts = false,
                    lastError = "Couldn't load the Recharge+ unlock. Check your connection and try again.",
                )
            }
        }
    }

    val proPrice: String? get() = current.planOptions.firstOrNull()?.priceLabel

    fun directCtaLabel(): String = proPrice?.let { "Unlock Recharge+ for $it" } ?: "Unlock Recharge+"

    fun trackPaywallImpression(id: String) {
        if (forcePro || !configureIfNeeded()) return
        diagnostics.recordPitchView(id)
        syncConversionAttributes()
        runCatching {
            Purchases.sharedInstance.trackCustomPaywallImpression(CustomPaywallImpressionParams(id))
        }
    }

    private fun syncConversionAttributes() {
        if (!configureIfNeeded()) return
        val attributes = diagnostics.subscriberAttributes.toMutableMap()
        if (attributes.isEmpty()) return
        current.offeringId?.let { attributes["offering_id"] = it }
        runCatching { Purchases.sharedInstance.setAttributes(attributes) }
    }

    /** Throws with a user-facing message; cancellation is an outcome, not an error. */
    suspend fun purchase(activity: Activity, plan: PlanOption): PurchaseOutcome {
        val pkg = plan.pkg ?: throw IllegalStateException("Recharge+ isn't available to purchase right now.")
        if (!configureIfNeeded()) throw IllegalStateException("Purchases aren't available in this build.")
        return try {
            val result = Purchases.sharedInstance.awaitPurchase(PurchaseParams.Builder(activity, pkg).build())
            apply(result.customerInfo)
            if (result.customerInfo.hasProEntitlement) {
                diagnostics.recordConversion(plan.displayName.lowercase(), plan.trialLabel != null, current.offeringId)
                syncConversionAttributes()
                PurchaseOutcome.PURCHASED
            } else {
                PurchaseOutcome.PENDING
            }
        } catch (error: PurchasesTransactionException) {
            if (error.userCancelled) return PurchaseOutcome.CANCELLED
            val message = "Couldn't complete the purchase. Please try again."
            _state.update { it.copy(lastError = message) }
            throw IllegalStateException(message)
        }
    }

    suspend fun restorePurchases() {
        _state.update { it.copy(restoreError = null) }
        if (!configureIfNeeded()) {
            _state.update { it.copy(restoreError = "Purchases aren't available in this build.") }
            return
        }
        try {
            val info = Purchases.sharedInstance.awaitRestore()
            apply(info)
            _state.update {
                it.copy(restoreError = if (it.isPro) null else "No active Recharge+ purchase was found for this Google account.")
            }
        } catch (error: Throwable) {
            if (error is kotlinx.coroutines.CancellationException) throw error
            _state.update { it.copy(restoreError = "Couldn't restore purchases. Try again.") }
        }
    }

    private suspend fun updateCustomerStatus(policy: CacheFetchPolicy) {
        runCatching { Purchases.sharedInstance.awaitCustomerInfo(policy) }
            .onSuccess(::apply)
            .onFailure { error ->
                if (error is kotlinx.coroutines.CancellationException) throw error
                _state.update {
                    it.copy(lastError = "Couldn't refresh your Recharge+ purchase status. Check your connection and try again.")
                }
            }
    }

    private fun apply(info: CustomerInfo) {
        if (forcePro) return
        preferences.edit().putBoolean("recoveryProCached",info.hasProEntitlement).apply()
        _state.update { it.copy(isPro = info.hasProEntitlement, isResolved = true) }
    }

    private fun configureIfNeeded(): Boolean {
        if (isConfigured) return true
        val key = BuildConfig.REVENUECAT_API_KEY
        if (key.isBlank()) return false
        // Never the production Play key in a debug build, and never a test key in release.
        if (BuildConfig.DEBUG && key.startsWith("goog_")) return false
        if (!BuildConfig.DEBUG && !key.startsWith("goog_")) return false
        Purchases.logLevel = if (BuildConfig.DEBUG) LogLevel.DEBUG else LogLevel.ERROR
        Purchases.configure(PurchasesConfiguration.Builder(context, key).build())
        Purchases.sharedInstance.updatedCustomerInfoListener = UpdatedCustomerInfoListener { apply(it) }
        isConfigured = true
        return true
    }

    private val CustomerInfo.hasProEntitlement: Boolean
        get() = entitlements.active.isNotEmpty()
}
