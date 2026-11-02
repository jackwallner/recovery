import XCTest

/// Which tier a rescore scores under when RevenueCat has not answered yet.
///
/// `StoreService.isPro` is false at the start of every process and RevenueCat is
/// only configured from the scene. A Health wake or a background refresh starts
/// a process with no scene, so for a subscriber the engine used to score the
/// session, publish the snapshot to the Watch and schedule the Ready alert as
/// the free tier, until the app was next opened by hand.
final class KnownEntitlementTests: XCTestCase {

    private var suiteName = ""
    private var defaults: UserDefaults!

    override func setUp() {
        super.setUp()
        suiteName = "recharge.tests.entitlement.\(UUID().uuidString)"
        defaults = UserDefaults(suiteName: suiteName)
    }

    override func tearDown() {
        defaults.removePersistentDomain(forName: suiteName)
        defaults = nil
        super.tearDown()
    }

    private func scoring(resolved: Bool, isPro: Bool) -> Bool {
        KnownEntitlement.scoringIsPro(entitlementResolved: resolved, isPro: isPro, defaults: defaults)
    }

    // MARK: - A process that has not asked yet

    func testASubscriberIsScoredAsOneInAProcessThatHasNotAskedRevenueCat() {
        KnownEntitlement.record(true, defaults: defaults)

        XCTAssertTrue(
            scoring(resolved: false, isPro: false),
            "a background wake must not publish the free figure to a subscriber's wrist"
        )
    }

    func testAFreeCustomerStaysFreeInAProcessThatHasNotAsked() {
        KnownEntitlement.record(false, defaults: defaults)

        XCTAssertFalse(scoring(resolved: false, isPro: false))
    }

    func testNothingIsAssumedBeforeRevenueCatHasEverAnswered() {
        XCTAssertFalse(KnownEntitlement.lastKnownIsPro(defaults: defaults))
        XCTAssertFalse(scoring(resolved: false, isPro: false))
    }

    // MARK: - Once it has asked

    func testRevenueCatsAnswerBeatsTheRememberedOneAsSoonAsThereIsOne() {
        KnownEntitlement.record(true, defaults: defaults)

        XCTAssertFalse(
            scoring(resolved: true, isPro: false),
            "a lapsed subscription must stop being scored as Recharge+ once RevenueCat says so"
        )
    }

    func testAnAnswerAlreadyHeldByThisProcessIsNeverOverruledByMemory() {
        KnownEntitlement.record(false, defaults: defaults)

        XCTAssertTrue(
            scoring(resolved: false, isPro: true),
            "a local override or a purchase in flight is newer than anything remembered"
        )
        XCTAssertTrue(scoring(resolved: true, isPro: true))
    }

    // MARK: - It outlives the process

    func testTheAnswerIsStillThereForTheNextProcess() throws {
        KnownEntitlement.record(true, defaults: defaults)

        let nextProcess = try XCTUnwrap(UserDefaults(suiteName: suiteName))

        XCTAssertTrue(KnownEntitlement.lastKnownIsPro(defaults: nextProcess))
        XCTAssertTrue(
            KnownEntitlement.scoringIsPro(entitlementResolved: false, isPro: false, defaults: nextProcess)
        )
    }

    func testTheLatestAnswerReplacesTheEarlierOne() {
        KnownEntitlement.record(true, defaults: defaults)
        KnownEntitlement.record(false, defaults: defaults)

        XCTAssertFalse(scoring(resolved: false, isPro: false))
    }
}
