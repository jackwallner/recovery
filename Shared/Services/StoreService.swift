import Combine
import Foundation
import StoreKit
import WidgetKit
import os
@preconcurrency import RevenueCat

/// Recharge Pro product identifiers. Must match App Store Connect and
/// `Recharge.storekit`.
public enum RechargeProduct {
    /// Bundle-prefixed, matching App Store Connect. StoreKit will not vend bare
    /// identifiers like "yearly", so the local `.storekit` file has to use the
    /// same form the real catalogue does.
    public static let lifetime = "com.jackwallner.recovery.lifetime"
    public static let yearly = "com.jackwallner.recovery.yearly"
    public static let monthly = "com.jackwallner.recovery.monthly"
    public static let all: [String] = [lifetime, yearly, monthly]
}

public enum RevenueCatConfig {
    /// Production public SDK key. Read from `~/.recovery_credentials` at build
    /// time in release automation; the placeholder keeps the repo free of a live
    /// key and simulator runs never reach this path anyway.
    public static let apiKey = "appl_RECHARGE_PLACEHOLDER"
}

public enum PurchaseState {
    case purchased
    case cancelled
    case pending
}

public enum RevenueCatPackageKind: Int {
    case lifetime = 0
    case yearly = 1
    case monthly = 2
    case other = 3

    init(package: Package) {
        switch package.packageType {
        case .lifetime: self = .lifetime
        case .annual: self = .yearly
        case .monthly: self = .monthly
        default:
            let identifiers = [package.identifier, package.storeProduct.productIdentifier].map { $0.lowercased() }
            if identifiers.contains(where: { $0.contains(RechargeProduct.lifetime) }) {
                self = .lifetime
            } else if identifiers.contains(where: { $0.contains(RechargeProduct.yearly) || $0.contains("annual") }) {
                self = .yearly
            } else if identifiers.contains(where: { $0.contains(RechargeProduct.monthly) }) {
                self = .monthly
            } else {
                self = .other
            }
        }
    }
}

public extension Package {
    var rechargePackageKind: RevenueCatPackageKind { RevenueCatPackageKind(package: self) }

    var rechargeDisplayName: String {
        switch rechargePackageKind {
        case .lifetime: "Lifetime"
        case .yearly: "Yearly"
        case .monthly: "Monthly"
        case .other: storeProduct.localizedTitle
        }
    }

    var rechargePriceLabel: String {
        guard let period = storeProduct.subscriptionPeriod else { return storeProduct.localizedPriceString }
        let unit: String
        switch period.unit {
        case .day: unit = period.value == 1 ? "day" : "days"
        case .week: unit = period.value == 1 ? "week" : "weeks"
        case .month: unit = period.value == 1 ? "month" : "months"
        case .year: unit = period.value == 1 ? "year" : "years"
        @unknown default: unit = ""
        }
        return period.value == 1
            ? "\(storeProduct.localizedPriceString) / \(unit)"
            : "\(storeProduct.localizedPriceString) / \(period.value) \(unit)"
    }

    /// Per-month equivalent, e.g. "$1.25". Powers the "just $1.25/month, billed
    /// yearly" framing so the annual figure feels small.
    var rechargePricePerMonthLabel: String? {
        guard storeProduct.subscriptionPeriod != nil else { return nil }
        return storeProduct.localizedPricePerMonth
    }

    var rechargeIntroOfferLabel: String? {
        guard let intro = storeProduct.introductoryDiscount, intro.paymentMode == .freeTrial else { return nil }
        let period = intro.subscriptionPeriod
        if period.unit == .week { return "\(period.value * 7)-day free trial" }
        if period.unit == .day { return "\(period.value)-day free trial" }
        return "\(period.value)-month free trial"
    }
}

public extension CustomerInfo {
    /// Recharge ships one premium tier, so *any* active entitlement unlocks Pro.
    /// Deliberately permissive: it survives a rename or casing drift in the
    /// RevenueCat dashboard, which has already bitten four apps in this fleet.
    var hasRechargeProEntitlement: Bool { !entitlements.active.isEmpty }
}

public extension Offering {
    var rechargeSortedPackages: [Package] {
        availablePackages.sorted {
            let lhs = $0.rechargePackageKind.rawValue
            let rhs = $1.rechargePackageKind.rawValue
            if lhs != rhs { return lhs < rhs }
            return $0.storeProduct.productIdentifier < $1.storeProduct.productIdentifier
        }
    }
}

public extension Offerings {
    var rechargePaywallOffering: Offering? { offering(identifier: "default") ?? current }
}

@MainActor
public final class StoreService: NSObject, ObservableObject {
    public static let shared = StoreService()

    @Published public private(set) var products: [Package] = []
    @Published public private(set) var currentOffering: Offering?
    @Published public private(set) var customerInfo: CustomerInfo?
    @Published public private(set) var isPro: Bool = false {
        didSet {
            guard oldValue != isPro else { return }
            // Mirror into the App Group so the complication can gate Pro-only
            // detail without a StoreKit round-trip.
            Self.groupDefaults?.set(isPro, forKey: SettingsKeys.isProCached)
            WidgetCenter.shared.reloadAllTimelines()
        }
    }

    @Published public private(set) var purchaseInFlight = false
    @Published public private(set) var isLoadingProducts = false
    @Published public private(set) var lastError: String?

    /// Per-product intro-offer eligibility. The paywall reads this so it only
    /// advertises a free trial to users who will actually receive one — Apple
    /// 3.1.2 requires the offer shown to match what StoreKit will grant.
    @Published public private(set) var introEligibility: [String: Bool] = [:]
    /// True once the first eligibility check finishes. Until then trial copy
    /// stays off, so a used-trial user is never promised a free week.
    @Published public private(set) var introEligibilityResolved = false

    private static let groupDefaults = UserDefaults(suiteName: rechargeAppGroupID)
    private let logger = Logger(subsystem: "com.jackwallner.recovery", category: "Store")
    private var isConfigured = false
    private var paywallImpressionsThisSession: Set<String> = []

    /// Dev/simulator override so paywall-gated surfaces can be exercised without
    /// a live key.
    private var localProOverride: Bool?

    private override init() {}

    public func start() {
        configureIfNeeded()
        #if DEBUG
        if ScreenshotConfig.wantsPremiumActive { isPro = true }
        #endif
        Task { await updateCustomerProductStatus(fetchPolicy: .fetchCurrent) }
        Task { await fetchProducts() }
    }

    public func setLocalOverride(isPro value: Bool) {
        localProOverride = value
        isPro = value
    }

    // MARK: - Products

    public func fetchProducts() async {
        configureIfNeeded()
        isLoadingProducts = true
        defer { isLoadingProducts = false }
        #if DEBUG
        // Screenshot mode already replaces HealthKit with fixtures; the store is
        // the last real dependency the paywall has. Without this, every headless
        // paywall render is the "couldn't load plans" empty state — see
        // `screenshotPackages` for why StoreKit Testing cannot fill the gap.
        if ScreenshotConfig.isEnabled {
            products = Self.screenshotPackages()
            currentOffering = nil
            lastError = nil
            await refreshIntroEligibility()
            return
        }
        #endif
        #if targetEnvironment(simulator)
        // RevenueCat is never configured on simulator (see `configureIfNeeded`),
        // so ask StoreKit Testing directly. Under `xcodebuild test` the scheme's
        // .storekit file is active and this renders the real paywall without
        // creating a customer in the production project.
        await hydrateFromStoreKitTesting()
        return
        #else
        do {
            let offerings = try await Purchases.shared.offerings()
            let offering = offerings.rechargePaywallOffering
            currentOffering = offering
            products = offering?.rechargeSortedPackages ?? []
            lastError = nil
            await refreshIntroEligibility()
        } catch {
            logger.error("Product fetch failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't load subscription options. Check your connection and try again."
        }
        #endif
    }

    public func refreshIntroEligibility() async {
        #if DEBUG
        if ScreenshotConfig.forceIntroIneligible {
            let ids = products
                .filter { $0.storeProduct.introductoryDiscount != nil }
                .map(\.storeProduct.productIdentifier)
            introEligibility = Dictionary(uniqueKeysWithValues: ids.map { ($0, false) })
            introEligibilityResolved = true
            return
        }
        #endif
        let identifiers = products
            .filter { $0.storeProduct.introductoryDiscount != nil }
            .map(\.storeProduct.productIdentifier)
        guard !identifiers.isEmpty else {
            introEligibility = [:]
            introEligibilityResolved = true
            return
        }
        #if targetEnvironment(simulator)
        // StoreKit Testing grants the intro offer to every fresh test account.
        introEligibility = Dictionary(uniqueKeysWithValues: identifiers.map { ($0, true) })
        introEligibilityResolved = true
        #else
        let result = await Purchases.shared.checkTrialOrIntroDiscountEligibility(productIdentifiers: identifiers)
        introEligibility = result.mapValues { $0.status == .eligible }
        introEligibilityResolved = true
        #endif
    }

    public func isEligibleForIntroOffer(_ package: Package) -> Bool {
        guard package.rechargeIntroOfferLabel != nil else { return false }
        #if DEBUG
        if ScreenshotConfig.forceIntroIneligible { return false }
        #endif
        guard introEligibilityResolved else { return false }
        return introEligibility[package.storeProduct.productIdentifier] ?? false
    }

    public func eligibleIntroLabel(for package: Package) -> String? {
        isEligibleForIntroOffer(package) ? package.rechargeIntroOfferLabel : nil
    }

    public var canPitchFreeTrial: Bool {
        guard let yearly = yearlyPackage else { return false }
        return isEligibleForIntroOffer(yearly)
    }

    /// The one-tap conversion target. StoreKit applies the trial automatically
    /// when eligible; ineligible users pay the yearly price on the same product.
    public var yearlyPackage: Package? {
        products.first { $0.rechargePackageKind == .yearly }
    }

    public var onboardingTrialCTALabel: String {
        guard let yearly = yearlyPackage else { return "Continue with \(RechargeConversionCopy.proName)" }
        return RechargeConversionCopy.ctaLabel(
            trialLabel: yearly.rechargeIntroOfferLabel,
            priceLabel: yearly.rechargePriceLabel,
            eligibleForTrial: isEligibleForIntroOffer(yearly)
        )
    }

    public var yearlyCTADisclosureText: String? {
        guard let yearly = yearlyPackage else { return nil }
        return RechargeConversionCopy.disclosure(
            trialLabel: yearly.rechargeIntroOfferLabel,
            priceLabel: yearly.rechargePriceLabel,
            eligibleForTrial: isEligibleForIntroOffer(yearly)
        )
    }

    public var yearlySheetDisclosureText: String? {
        guard let yearly = yearlyPackage else { return nil }
        return RechargeConversionCopy.sheetDisclosure(
            trialLabel: yearly.rechargeIntroOfferLabel,
            priceLabel: yearly.rechargePriceLabel,
            eligibleForTrial: isEligibleForIntroOffer(yearly)
        )
    }

    public func purchaseCancelledMessage(for package: Package) -> String {
        RechargeConversionCopy.purchaseCancelledMessage(eligibleForTrial: isEligibleForIntroOffer(package))
    }

    public func purchaseFailedMessage(for package: Package) -> String {
        RechargeConversionCopy.purchaseFailedMessage(eligibleForTrial: isEligibleForIntroOffer(package))
    }

    // MARK: - Purchase

    public func trackPaywallImpression(id: String, oncePerSession: Bool = false) {
        configureIfNeeded()
        #if DEBUG
        if ScreenshotConfig.isEnabled { return }
        #endif
        #if targetEnvironment(simulator)
        return
        #else
        if oncePerSession {
            guard !paywallImpressionsThisSession.contains(id) else { return }
            paywallImpressionsThisSession.insert(id)
        }
        Purchases.shared.trackCustomPaywallImpression(CustomPaywallImpressionParams(paywallId: id))
        #endif
    }

    @discardableResult
    public func purchase(_ product: Package) async throws -> PurchaseState {
        configureIfNeeded()
        purchaseInFlight = true
        defer { purchaseInFlight = false }
        #if targetEnvironment(simulator)
        // No RevenueCat on simulator. Flip the local override so the post-purchase
        // UI can be exercised; no customer is created anywhere.
        setLocalOverride(isPro: true)
        return .purchased
        #else
        let result = try await Purchases.shared.purchase(package: product)
        apply(customerInfo: result.customerInfo)
        if result.userCancelled { return .cancelled }
        return result.customerInfo.hasRechargeProEntitlement ? .purchased : .pending
        #endif
    }

    public func updateCustomerProductStatus(fetchPolicy: CacheFetchPolicy = .default) async {
        configureIfNeeded()
        #if DEBUG
        if ScreenshotConfig.wantsPremiumActive {
            isPro = true
            return
        }
        #endif
        if let localProOverride {
            isPro = localProOverride
            return
        }
        #if targetEnvironment(simulator)
        return
        #else
        do {
            apply(customerInfo: try await Purchases.shared.customerInfo(fetchPolicy: fetchPolicy))
            lastError = nil
        } catch {
            logger.error("Customer info refresh failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't refresh your subscription status. Check your connection and try again."
        }
        #endif
    }

    public func restorePurchases() async {
        configureIfNeeded()
        lastError = nil
        #if targetEnvironment(simulator)
        lastError = "Restore is unavailable in the simulator."
        return
        #else
        do {
            apply(customerInfo: try await Purchases.shared.restorePurchases())
            lastError = isPro ? nil : "No active \(RechargeConversionCopy.proName) purchase was found for this Apple ID."
        } catch {
            logger.error("Restore failed: \(String(describing: error), privacy: .public)")
            lastError = "Couldn't restore purchases. Try again."
        }
        #endif
    }

    public func apply(customerInfo: CustomerInfo) {
        self.customerInfo = customerInfo
        let active = customerInfo.entitlements.active.keys.sorted().joined(separator: ", ")
        logger.info("Applied customerInfo — active: [\(active, privacy: .public)]")
        let hasActive = customerInfo.hasRechargeProEntitlement
        if isPro != hasActive { isPro = hasActive }
    }

    // MARK: - Private

    private func configureIfNeeded() {
        guard !isConfigured else { return }
        #if targetEnvironment(simulator)
        // Agent and simulator runs must never create customers in the production
        // RevenueCat project. Use StoreKit Testing and the local Pro override.
        return
        #else
        #if DEBUG
        Purchases.logLevel = .debug
        #endif
        Purchases.configure(withAPIKey: RevenueCatConfig.apiKey)
        Purchases.shared.delegate = self
        isConfigured = true
        #endif
    }

    #if DEBUG
    /// The paywall catalogue used under `RECHARGE_SCREENSHOT_MODE`.
    ///
    /// StoreKit Testing was the intended source and does not work here: with the
    /// `.storekit` file referenced from the scheme's Test action *and* from a
    /// test plan (every relative-path spelling tried, plus `SKTestSession` from
    /// the UI-test runner), the app under test still reaches the live
    /// `storekitd` and `Product.products(for:)` returns an empty array. So a
    /// headless run could only ever render the empty state, which exercises
    /// none of the plan-card layout the screenshot and the UI test exist to
    /// check.
    ///
    /// Prices, periods, and the one-week trial mirror `Recharge.storekit` and
    /// App Store Connect. Keep them in step: this is what `RechargeUITests` and
    /// the App Store paywall screenshot both render.
    private static func screenshotPackages() -> [Package] {
        let locale = Locale(identifier: "en_US")
        let freeWeek = TestStoreProductDiscount(
            identifier: "trial",
            price: 0,
            localizedPriceString: "$0.00",
            paymentMode: .freeTrial,
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .week),
            numberOfPeriods: 1,
            type: .introductory
        )
        let lifetime = TestStoreProduct(
            localizedTitle: "Recharge Pro Lifetime",
            price: 29.99,
            currencyCode: "USD",
            localizedPriceString: "$29.99",
            productIdentifier: RechargeProduct.lifetime,
            productType: .nonConsumable,
            localizedDescription: "Unlock Recharge Pro forever",
            locale: locale
        )
        let yearly = TestStoreProduct(
            localizedTitle: "Recharge Pro Yearly",
            price: 14.99,
            currencyCode: "USD",
            localizedPriceString: "$14.99",
            productIdentifier: RechargeProduct.yearly,
            productType: .autoRenewableSubscription,
            localizedDescription: "Unlock Recharge Pro yearly — save 37%",
            subscriptionGroupIdentifier: "RechargePro",
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .year),
            introductoryDiscount: freeWeek,
            locale: locale
        )
        let monthly = TestStoreProduct(
            localizedTitle: "Recharge Pro Monthly",
            price: 1.99,
            currencyCode: "USD",
            localizedPriceString: "$1.99",
            productIdentifier: RechargeProduct.monthly,
            productType: .autoRenewableSubscription,
            localizedDescription: "Unlock Recharge Pro monthly",
            subscriptionGroupIdentifier: "RechargePro",
            subscriptionPeriod: SubscriptionPeriod(value: 1, unit: .month),
            introductoryDiscount: freeWeek,
            locale: locale
        )
        return [lifetime, yearly, monthly]
            .map { product in
                Package(
                    identifier: product.productIdentifier,
                    packageType: Self.packageType(for: product.productIdentifier),
                    storeProduct: product.toStoreProduct(),
                    offeringIdentifier: "default",
                    webCheckoutUrl: nil
                )
            }
            .sorted { $0.rechargePackageKind.rawValue < $1.rechargePackageKind.rawValue }
    }
    #endif

    #if targetEnvironment(simulator)
    /// Hydrates `products` from StoreKit Testing so the *real* paywall view
    /// renders under `xcodebuild test`, rather than the "couldn't load plans"
    /// empty state that exercises none of the layout.
    ///
    /// Goes to StoreKit directly rather than through `Purchases.shared`:
    /// `configureIfNeeded` deliberately never configures RevenueCat on
    /// simulator, and touching `Purchases.shared` before `configure` is a hard
    /// trap in the SDK. `StoreProduct(sk2Product:)` gets the StoreKit 2 product
    /// into the shape the paywall already reads.
    private func hydrateFromStoreKitTesting() async {
        do {
            let storeKitProducts = try await StoreKit.Product.products(for: RechargeProduct.all)
            logger.info("StoreKit Testing returned \(storeKitProducts.count, privacy: .public) products")
            guard !storeKitProducts.isEmpty else {
                // No StoreKit configuration active (plain `simctl launch`), so
                // the paywall shows its empty state. Expected there, and a real
                // failure under `xcodebuild test` — say which so the UI test
                // failure is diagnosable from the screenshot alone.
                lastError = "StoreKit Testing returned no products. Run this from the Recharge or RechargeUITests scheme."
                return
            }
            products = storeKitProducts
                .map { product in
                    Package(
                        identifier: product.id,
                        packageType: Self.packageType(for: product.id),
                        storeProduct: StoreProduct(sk2Product: product),
                        offeringIdentifier: "default",
                        webCheckoutUrl: nil
                    )
                }
                .sorted { $0.rechargePackageKind.rawValue < $1.rechargePackageKind.rawValue }
            lastError = nil
            await refreshIntroEligibility()
        } catch {
            logger.error("StoreKit Testing product fetch failed: \(String(describing: error), privacy: .public)")
            lastError = nil
        }
    }

    #endif

    private static func packageType(for identifier: String) -> PackageType {
        switch identifier {
        case RechargeProduct.lifetime: .lifetime
        case RechargeProduct.yearly: .annual
        case RechargeProduct.monthly: .monthly
        default: .custom
        }
    }
}

extension StoreService: PurchasesDelegate {
    public nonisolated func purchases(_ purchases: Purchases, receivedUpdated customerInfo: CustomerInfo) {
        Task { @MainActor in
            StoreService.shared.apply(customerInfo: customerInfo)
        }
    }
}
