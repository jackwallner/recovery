import XCTest
import UserNotifications
import os

/// The Ready alert, which is the only thing that tells a user the countdown ran
/// out while the app was closed.
///
/// Build 39 aborted with SIGABRT on **every** tap on it. The delegate method was
/// spelled `async`, and the compiler-generated `@objc` thunk resumes on a
/// cooperative thread and calls UIKit's completion handler from there; UIKit
/// answers a tap by writing the state-restoration archive, which asserts the
/// main thread. Nothing in the app could see it, because the crash is in code
/// the compiler writes.
final class ReadyNotificationTests: XCTestCase {

    // MARK: - Which thread the tap is answered on

    func testTheTapCompletionHandlerRunsOnTheMainThread() {
        let acknowledged = expectation(description: "completion handler called")
        let wasMainThread = OSAllocatedUnfairLock(initialState: false)

        DispatchQueue.global(qos: .userInitiated).async {
            XCTAssertFalse(Thread.isMainThread, "the point of this test is a background caller")
            RechargeNotificationDelegate.handleTap(route: NotificationService.readyRouteValue) {
                wasMainThread.withLock { $0 = Thread.isMainThread }
                acknowledged.fulfill()
            }
        }

        wait(for: [acknowledged], timeout: 2)
        XCTAssertTrue(wasMainThread.withLock { $0 })
    }

    func testTheTapIsAlwaysAcknowledgedEvenWithNoRoute() {
        // UIKit watchdogs a response that is never acknowledged, so the handler
        // has to be called on the paths that do no routing too.
        let acknowledged = expectation(description: "completion handler called")
        RechargeNotificationDelegate.handleTap(route: nil) { acknowledged.fulfill() }
        wait(for: [acknowledged], timeout: 2)
    }

    // MARK: - Where the tap lands

    func testTheReadyRoutePostsTheRouteRequest() {
        let routed = expectation(description: "route posted")
        let observer = NotificationCenter.default.addObserver(
            forName: NotificationService.routeRequested, object: nil, queue: nil
        ) { note in
            XCTAssertEqual(
                note.userInfo?[NotificationService.routeKey] as? String,
                NotificationService.readyRouteValue
            )
            routed.fulfill()
        }
        defer { NotificationCenter.default.removeObserver(observer) }

        RechargeNotificationDelegate.handleTap(route: NotificationService.readyRouteValue) {}
        wait(for: [routed], timeout: 2)
    }

    func testAnUnknownRouteMovesNothing() {
        let routed = expectation(description: "route posted")
        routed.isInverted = true
        let observer = NotificationCenter.default.addObserver(
            forName: NotificationService.routeRequested, object: nil, queue: nil
        ) { _ in routed.fulfill() }
        defer { NotificationCenter.default.removeObserver(observer) }

        let acknowledged = expectation(description: "completion handler called")
        RechargeNotificationDelegate.handleTap(route: "history") { acknowledged.fulfill() }
        wait(for: [acknowledged], timeout: 2)
        wait(for: [routed], timeout: 0.2)
    }

    // MARK: - What it says

    func testTheBodyNamesTheSessionTheCountdownCameFrom() {
        let snapshot = RecoverySnapshot(readyAt: .now, activityLabel: "run")
        XCTAssertEqual(
            NotificationService.readyBody(for: snapshot),
            "Your countdown from that run has finished."
        )
    }

    func testTheBodyStillReadsWhenThereIsNoActivityLabel() {
        XCTAssertEqual(
            NotificationService.readyBody(for: RecoverySnapshot(readyAt: .now)),
            "Your recovery countdown has finished."
        )
    }

    func testTheAlertNeverSaysTheCountdownIsCompleteAndThenSaysItAgain() {
        // The copy this replaced was "Your recovery countdown is complete. No
        // countdown is active." Two sentences making the same claim reads like
        // two notifications stapled together.
        for label in ["", "run", "strength training"] {
            let body = NotificationService.readyBody(for: RecoverySnapshot(activityLabel: label))
            let sentences = body.split(separator: ".").filter { !$0.trimmingCharacters(in: .whitespaces).isEmpty }
            XCTAssertEqual(sentences.count, 1, "one claim per alert, got: \(body)")
        }
    }

    func testTheAlertMakesNoMedicalClaim() {
        // The same bar `testReasonsNeverMakeAMedicalClaim` holds the reasons to.
        let banned = ["recovered", "safe to train", "injury", "your body", "cure", "diagnos"]
        let copy = ([NotificationService.readyTitle]
            + ["", "run"].map { NotificationService.readyBody(for: RecoverySnapshot(activityLabel: $0)) })
            .joined(separator: " ")
            .lowercased()
        for phrase in banned {
            XCTAssertFalse(copy.contains(phrase), "Ready alert copy contains \"\(phrase)\"")
        }
    }
}
