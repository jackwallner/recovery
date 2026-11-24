import XCTest

/// The star prompt asks only at a good result, from the second launch, at most
/// once every 30 days, and stops for good once the write-review page is opened.
@MainActor
final class ReviewPromptTests: XCTestCase {

    private let now = Date(timeIntervalSince1970: 1_800_000_000)
    private let ready = ReviewMoment.countdownReady(questionPending: false)

    override func setUp() async throws {
        try await super.setUp()
        ReviewPromptTracker.resetForTesting()
    }

    override func tearDown() async throws {
        ReviewPromptTracker.resetForTesting()
        try await super.tearDown()
    }

    private func gate(launches: Int = 2, lastAsked: Date? = nil, opened: Bool = false) -> ReviewPromptGate {
        ReviewPromptGate(launchCount: launches, lastAsked: lastAsked, openedWriteReview: opened)
    }

    // MARK: - The moments

    func testACountdownReachingReadyIsAGoodResultWhenNoQuestionIsOwed() {
        XCTAssertTrue(ReviewMoment.countdownReady(questionPending: false).isGoodResult)
        XCTAssertTrue(gate().allows(ready, now: now))
    }

    func testAReadyWithTheQuestionStillOwedWaitsForTheAnswer() {
        let pending = ReviewMoment.countdownReady(questionPending: true)
        XCTAssertFalse(pending.isGoodResult)
        XCTAssertFalse(gate().allows(pending, now: now))
    }

    func testOnlyFeltReadyIsAGoodAnswer() {
        XCTAssertTrue(ReviewMoment.readinessAnswered(.feltReady).isGoodResult)
        XCTAssertFalse(ReviewMoment.readinessAnswered(.okayNotFresh).isGoodResult)
        XCTAssertFalse(ReviewMoment.readinessAnswered(.notReady).isGoodResult)
        XCTAssertTrue(gate().allows(.readinessAnswered(.feltReady), now: now))
        XCTAssertFalse(gate().allows(.readinessAnswered(.notReady), now: now))
        XCTAssertFalse(gate().allows(.readinessAnswered(.okayNotFresh), now: now))
    }

    // MARK: - The gates

    func testNoAskInTheFirstLaunch() {
        XCTAssertFalse(gate(launches: 0).allows(ready, now: now))
        XCTAssertFalse(gate(launches: 1).allows(ready, now: now))
    }

    func testTheSecondLaunchMayAsk() {
        XCTAssertTrue(gate(launches: 2).allows(ready, now: now))
        XCTAssertTrue(gate(launches: 9).allows(ready, now: now))
    }

    func testThirtyDayCooldownBetweenCalls() {
        let day: TimeInterval = 86_400
        XCTAssertFalse(gate(lastAsked: now.addingTimeInterval(-29 * day)).allows(ready, now: now))
        XCTAssertTrue(gate(lastAsked: now.addingTimeInterval(-30 * day)).allows(ready, now: now))
        XCTAssertTrue(gate(lastAsked: now.addingTimeInterval(-90 * day)).allows(ready, now: now))
    }

    func testAStampFromAClockThatRanAheadDoesNotHoldTheCooldownShut() {
        XCTAssertTrue(gate(lastAsked: now.addingTimeInterval(400 * 86_400)).allows(ready, now: now))
    }

    func testOpeningTheWriteReviewPageEndsTheAsks() {
        XCTAssertFalse(gate(opened: true).allows(ready, now: now))
        XCTAssertFalse(gate(lastAsked: now.addingTimeInterval(-400 * 86_400), opened: true).allows(ready, now: now))
    }

    // MARK: - The tracker, over real defaults

    func testTheTrackerBlocksLaunchOneAndAllowsLaunchTwo() {
        ReviewPromptTracker.recordAppLaunch(now: now)
        XCTAssertFalse(ReviewPromptTracker.shouldRequestReview(for: ready, hasCompletedSetup: true, now: now))
        ReviewPromptTracker.recordAppLaunch(now: now)
        XCTAssertTrue(ReviewPromptTracker.shouldRequestReview(for: ready, hasCompletedSetup: true, now: now))
    }

    func testNeverBeforeSetupFinishes() {
        ReviewPromptTracker.appLaunchCount = 5
        XCTAssertFalse(ReviewPromptTracker.shouldRequestReview(for: ready, hasCompletedSetup: false, now: now))
    }

    func testTheCallIsStampedWhenItIsMade() {
        ReviewPromptTracker.appLaunchCount = 3
        ReviewPromptTracker.markShown(now: now)
        let later = now.addingTimeInterval(10 * 86_400)
        XCTAssertFalse(ReviewPromptTracker.shouldRequestReview(for: ready, hasCompletedSetup: true, now: later))
        let afterCooldown = now.addingTimeInterval(31 * 86_400)
        XCTAssertTrue(ReviewPromptTracker.shouldRequestReview(for: ready, hasCompletedSetup: true, now: afterCooldown))
    }

    func testOpeningWriteReviewStopsTheTrackerForGood() {
        ReviewPromptTracker.appLaunchCount = 3
        ReviewPromptTracker.markOpenedWriteReview()
        let farFuture = Date.now.addingTimeInterval(800 * 86_400)
        XCTAssertFalse(ReviewPromptTracker.shouldRequestReview(for: ready, hasCompletedSetup: true, now: farFuture))
    }

    func testAnOutcomeFromTheOldFeedbackFlowStopsNothing() {
        // Builds before this one wrote `submittedFeedback` and treated it as
        // the end of the asks. Sending feedback never ends them.
        ReviewPromptTracker.appLaunchCount = 3
        ReviewPromptTracker.outcome = .submittedFeedback
        XCTAssertTrue(ReviewPromptTracker.shouldRequestReview(for: ready, hasCompletedSetup: true, now: .now))
    }

    func testOneSessionAnnouncesItsReadyMomentOnce() {
        final class Count: @unchecked Sendable { var value = 0 }
        let posts = Count()
        let token = NotificationCenter.default.addObserver(
            forName: .rechargePositiveMomentForReview, object: nil, queue: nil
        ) { _ in posts.value += 1 }
        defer { NotificationCenter.default.removeObserver(token) }

        ReviewPromptTracker.recordReadyMoment(sessionID: "a", questionPending: false)
        ReviewPromptTracker.recordReadyMoment(sessionID: "a", questionPending: false)
        ReviewPromptTracker.recordReadyMoment(sessionID: "b", questionPending: false)
        XCTAssertEqual(posts.value, 2)
    }
}
