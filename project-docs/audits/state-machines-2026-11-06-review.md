# Review of the state machine audit (2026-11-06)

Independent review of `state-machines-2026-11-06.md` and its repro suite. Every claim was re-derived from the code; the audit's reasoning was not relied on. Committed code only (the working tree was clean, so there was nothing to stash). Nothing was fixed.

**Summary: 4 claims reviewed. 2 CONFIRMED (B2, B1), 2 CONFIRMED-MINOR (B3, B4), 0 NOT A BUG, 0 UNVERIFIED. No claim is a false positive, but one of B3's two routes is intended behaviour, B4's stated route mostly cannot happen on the iPhone, and the ranking put a calibration nudge above a privacy failure. The audit missed a second, more common route to B1.**

Test runs (GitHub Macs via `gh-sim`, Xcode 27):

- Unit run `recovery@20261106-123652-d85a-claude-mbpro9f08-1106-125522-5224` (iPhone 17, iOS 27.2), `--only RechargeTests/StateMachineAuditRepro --only RechargeTests/StateMachineAuditReview`: 7 tests, 5 passed, 2 failed. The audit's suite reproduced its recorded result exactly: `testBUG1_*` failed at its final assertion with the same figures (asked about A, own `readyAt` 1.0 h ago, shown countdown 31.9 h left), `testBUG2_*` failed with the same figures (last entry 60 s after `readyAt`, cutoff 92 h after it), both controls passed. The review's own suite (`StateMachineAuditReview`, three tests written to pass when the claimed behaviour is present) passed in full.
- UI run `recovery@20261106-123652-d85a-claude-mbpro9f08-1106-133309-29157` (`--scheme RechargeUITests --only RechargeUITests/StateMachineReviewUITests`, the B2 test in the appendix): 1 test, failed before reaching the code under test. The Health permission sheet never appeared and the screen recording shows the app on the onboarding welcome page for the whole run. This is the harness, not the app: the repo's own `SeededWalkthroughTests` fails the same way on GitHub's runner (`shift-bughunt-recovery-1-1793430047-mbpro6bb2-1031-075324-4569`, 2026-10-31). The seeded-Health harness works only on the local `agent-sim` pool, which this headless machine cannot reach.

Both temporary test files were removed from the test targets after the runs.

## Claims

| id | verdict | user route (shipping UI) | impact | evidence |
|---|---|---|---|---|
| B2 | CONFIRMED (from code; the end-to-end test could not run headless) | Recharge+ not needed. Today, gear (`TodayView.swift:246`), Settings sheet, scroll to the About section, Delete local health data (`SettingsView.swift:790`, not behind `#if DEBUG`; the DEBUG section is `:46-48`), Delete in the alert (`:70-79`). Leave Health access granted (deletion never revokes it). Then do nothing: either the observer queries already installed in that process fire on the next Watch heart-rate or workout sample, or iOS runs the `BGAppRefreshTask` that every launch schedules. Any iPhone; an Apple Watch (or any Health writer) makes the observer route immediate, the background task route needs only time. | Few users tap Delete, but for those who do and keep Health access on, the data returns with certainty and without notice: the full 120-day history is re-imported because the anchor was reset, the countdown, History, Watch figure and Ready alert come back, and the success message they read was false. A privacy control that does not hold is the most expensive kind of bug this app can ship, so it ranks first despite the small audience. Users who also revoke Health access in iOS Settings are not affected (the reads return nothing). | Delete sets `hasDeferredHealthAccess = true` and resets the anchor (`RecoveryEngine.swift:1016-1020`) but stops nothing. The observer queries are never stopped (`HealthKitService.swift:811-842`, no `stop` anywhere) and route to `enqueueObserverRefresh`, which calls `RecoveryEngine.refresh` (`:772`). The background task is registered and submitted on every launch with no guard (`App.swift:40-44`), and its handler calls `refresh(force: true)` unguarded (`:124-136`). `refresh` (`RecoveryEngine.swift:96-135`) and `importWorkouts` (`:220-227`) never read the flag, and `fetchWorkouts` does not check authorization (`HealthKitService.swift:296-310`). Only the scene paths check it (`App.swift:59`, `:204`, `:229-232`). Every function on both routes was read and none checks the flag, so the only conditions outside the app are that iOS eventually runs the background task (or Health delivers a sample to a live process) and that read access is still on. Settled on a device or the local pool by the appendix test, which fails with "deleted Health data came back with no user action" if the claim holds. |
| B1 | CONFIRMED | Recharge+ subscriber. Finish a session that earns a countdown (A). Finish a second one (B) before A's countdown ends, so B stacks on A and the ring shows B. Then either (i) open Today after A's own `readyAt` while B is still running: `TodayView` raises "How did that feel?" with "Your estimate after that run ran out." over a ring that is still counting down; or (ii) open Today after B ends, answer B's question, and the question about A is raised next: `recordFeedback` rescores (`RecoveryEngine.swift:1079-1095`), A is still unanswered and inside its two-day window, and Today re-presents on the change of `awaitingFeedback` (`TodayView.swift:118-120`). The resolver half of (ii) is tested below; the re-presentation is read from code, not run. Any iPhone; no Watch needed beyond whatever records the workouts. | Recharge+ only (`RecoveryEngine.swift:1116-1118`), so a minority of users, but among them it reaches anyone who trains inside their own countdown (back-to-back days, doubles), repeatedly. The audit's route (i) needs the app opened between the two `readyAt`s; route (ii), which the audit missed, needs only that B's countdown ends within two days of A's and that A was not answered in between, which is true of almost every stacked pair (7.9 h apart in the review's example). Cost: a question whose premise is false on screen, a duplicate question for one countdown, and an answer that moves `calibrationFactor` (0.95 or 1.05 per answer, bounded 0.80-1.25, `RecoveryModels.swift:1101-1120`) while the user is still under B's load, so "Not ready" lengthens every future Recharge+ window. | `awaitingFeedback` filters on each estimate's own `readyAt` and never on the shown countdown (`RecoveryResolver.swift:80-95`); it is recomputed on every rescore (`RecoveryEngine.swift:783-788`) and every minute while Today is open (`:1199-1205`, ticker `TodayView.swift:67`, `:95-98`); Today presents it on settle and on change (`TodayView.swift:101-120`, `:670-673`). A stacked B always ends after A (`RecoveryCalculator.swift:279-282` plus `stackedContribution`). The promise is real and cited correctly: `.claude/rules/model-tiers.md:248` "The readiness question only asks about countdowns the user watched", the sheet's own doc "asked once a countdown expires" (`EffortPromptSheet.swift:102`) and its copy "Your estimate after that run ran out." (`ActivityPhrases.swift:381`). The doc on `awaitingFeedback` ("Estimates whose countdown has expired", `RecoveryResolver.swift:69`) describes per-estimate behaviour literally, but no comment or test chooses the stacked case on purpose: every existing `awaitingFeedback` test uses a single estimate (`RecoveryResolverTests.swift:150-172`, `ClockBoundaryTests.swift:159-172`, `UserCorrectionTests.swift:243-275`). The audit's test is sound: its preconditions are asserted and held, and it asserts the user-visible claim (nothing is awaiting an answer while the shown countdown runs). Its stacked pair is an edge case, though (B carries only 1 h of A's residual), so the review re-ran B1 on an ordinary double day (`testB1_ordinaryBackToBackDayRaisesTheQuestionMidCountdown`, passed): a hard 60-minute run (A, 36.9 h) and a moderate 45-minute run 14 h later (B, 15.8 h plus 15.1 h carried). At A's `readyAt` plus one minute the question is about A while B's countdown has 7.9 h left; at B's `readyAt` the question is about B, and with B answered it is about A again. One "Not ready" moves the next identical hard hour from 36.9 h to 38.8 h. |
| B3 | CONFIRMED-MINOR (onboarding half only); the returning-user half is NOT A BUG | New install with any Health history whose newest session earned a countdown that has already ended. Onboarding, Health page, Continue, grant (`OnboardingView.swift:171-178`). The import ends in `publish()`, which records a Ready moment for that session before Today has ever been shown. Any iPhone. | Most new installs that arrive with Watch history, once per install. The review ask then fires at the first real Ready moment instead of the second (the 3-launch and 3-day gates in `ReviewPromptTracker.swift:31-35` still apply), so it arrives one countdown early. No visible symptom and no data cost; the audit's "small" is right. The audit's second route, a returning user opening the app after a countdown ended while it was closed, is the intended trigger: the user watched that countdown, the Ready alert told them, and `handleClockTick` was added only to record the moment sooner when the app is open ("not on the next launch", `RecoveryEngine.swift:1196-1198`), not to stop the launch path. So "every returning user" in the audit's impact is wrong. | `publish()` records `current` whenever `producesCountdown && readyAt <= .now` (`RecoveryEngine.swift:984-988`), with no staleness or setup bound; `current` falls back to the newest session however old (`RecoveryResolver.swift:24-27`, set at `RecoveryEngine.swift:782`); onboarding's `refresh(force: true)` reaches `publish()` (`RecoveryEngine.swift:130-131`) before `finish()` sets up anything (`OnboardingView.swift:254-262`). The promise is the doc on the counter, "Countdowns the user has watched run out" (`ReviewPromptTracker.swift:19`), and `AGENTS.md:95-97`. The readiness question already has the bound this lacks (`feedbackEligibleFrom`). Test: `testB3_onboardingImportSatisfiesThePublishReadyMomentPredicate` (passed) shows a single session from 30 days ago is `current`, satisfies the `publish()` predicate, and is simultaneously `noRecentWorkout` with no explanation, so the funnel counts a session Today will not even name. The engine wiring itself is not in the test target; the three lines cited leave no doubt about it. |
| B4 | CONFIRMED-MINOR | Have the iOS widget or a Watch complication. Finish a session, let it reach Ready, then record nothing for four days (or a day past `readyAt`, whichever is later). Between the staleness cutoff and the provider's next six-hour refresh the face says Ready with a full ring while the model says No recent workout. Watch complication: any Apple Watch. | Far narrower than the audit's "everyone with a widget, once per countdown cycle": it needs four idle days, which a regular trainer never reaches, and lasts at most about six hours. The audit's route (open Today, see No workout, look at the widget, see Ready) mostly cannot happen on the iPhone: opening Today runs a refresh that ends in `publish()`, and `publish()` reloads every timeline (`App.swift:228-237`, `RecoveryEngine.swift:959`). The Watch complication does keep Ready, because the republished snapshot is identical and the Watch skips the reload (`PhoneWatchSession.swift:376-401`). Cost is cosmetic: both Ready and No recent workout tell the user there is nothing to wait out. | The running timeline ends at `readyAt + 60 s` (`CountdownTimeline.swift:63-68`); the idle timeline is one entry plus a six-hour refresh (`:35-40`, `:76-79`); both providers render `snapshot.phase(at: entry.date)` (`RechargeWidget.swift:18`, `:54-63`; `WatchComplication.swift:21`, `:63-77`), which applies `isStale` (`RecoverySnapshot.swift:223-225`). The citation holds: "`RecoveryResolver.isStale` is the one staleness rule for Today, the snapshot, the widgets and the Watch" (`.claude/rules/countdown-and-watch-sync.md:224-227`); the widgets apply the rule but only at entry instants. The audit's `testBUG2_*` reproduced (above). The review's `testB4_worstCaseWrongFaceIsBoundedBySixHours` (passed) bounds it: an idle timeline built one minute before the cutoff is one entry reading Ready with a refresh 5.98 h after the cutoff, so six hours is the worst case before WidgetKit budget slack. |

## What survived, ranked

1. **B2, Delete local health data is undone by the next Health wake.** Privacy promise, certain for everyone who deletes without revoking access. The audit ranked it second.
2. **B1, the readiness question about a stacked session.** Recharge+ only, frequent for people who train inside their countdown, and it moves a persistent model parameter. The audit ranked it first, and missed the back-to-back variant (route ii) that makes it nearly certain for every stacked pair.
3. **B3, the onboarding import counts a Ready moment.** Onboarding only; the review ask arrives one countdown early.
4. **B4, widget and complication have no entry at the staleness cutoff.** Watch complication and unopened iOS widget only, after four idle days, at most about six hours, cosmetic.

## Product calls

- P1, per-session edits thaw every record. The facts are right. The reading is not quite: an effort answer changes that session's load and therefore every stacked window after it, which is exactly the reason `overrideIntensity` gives for `unfreezeAll` (`RecoveryEngine.swift:1152-1157`). So the code is consistent and the `rescore` doc (`:460-468`) is stale. The calibration side effect (thawed rows rescored with today's `calibrationFactor`) is real and Recharge+ only. Agree it is a product call; the cheap fix is the doc.
- P2, a delivered Ready notification is never removed. Confirmed: only `removePendingNotificationRequests` exists (`NotificationService.swift:80`, `:108`). Agree, minor.
- P3, deletion keeps `calibrationFactor`, `manualWindows` and typed answers. Confirmed. Those are the user's own answers, and the alert promises only "Health-derived profile values" (`SettingsView.swift:78`), so this is not contradicted by any copy. Agree.
- P4, deletion does not clear the Watch. Confirmed (no `sendSnapshot` in `deleteLocalHealthData`, `RecoveryEngine.swift:997-1040`). Agree it is a product call, and it belongs in the B2 fix.
- P5, onboarding stamps the trial cooldown even when the plans failed to load. Confirmed: `finish()` stamps unconditionally (`OnboardingView.swift:257`) and the offer page has a "Couldn't load the offer" state (`TrialOfferPage.swift:309-320`) whose Get Started still calls `finish`. Agree.
- P6, the passive cooldown is stamped when the offer is decided. Confirmed (`RootView.swift:345`, `:361`), but both sites are behind `!isPresentingSomething`, so the sheet nearly always appears. Agree, negligible.
- P7, an Ask to Buy approval leaves a live buy button. `PaywallView` dismisses only when `didPurchase` (`PaywallView.swift:139-141`). Not verified further: it needs a StoreKit sandbox Ask to Buy flow. Plausible.
- P8, a force-quit app gets no HealthKit wake. Platform behaviour, not checked here. Agree it is not counted.

No product call should have been counted as a bug. P4 should be fixed with B2.

## Missed by the audit

- **B1 route (ii)**, described above: answering the question about B immediately re-raises the question about A. It is the more common way B1 reaches users, because it needs no app open during B's countdown.
- **B2 side effect**: deletion never calls `disableBackgroundDelivery`, so HealthKit keeps waking the app on every heart-rate sample (`.immediate`, `HealthKitService.swift:788-796`) in later processes that then do nothing, because `init` skips the observers while deferred. Wasted wakes rather than a data bug; fix it with B2.

No other serious state bug was found in the paths read for this review.

## False positives and method

**False positive rate: 0 of 4 claims are wrong outright. 2 of 4 overstate reach (B3's returning-user route is intended behaviour; B4's side-by-side route self-heals on iPhone and needs four idle days), and the ranking put B1 above a privacy failure.** The audit's two "code path, not proved" claims (B2, B3) both hold on the code. B2 could not be executed headless in this review either.

Method changes that would have prevented the errors:

1. **Walk the route's own side effects.** B4's route opens Today, and opening Today reloads every widget timeline. Following each step of a route through to what it triggers would have shown the iPhone half cannot be observed that way.
2. **Split a claim into its routes and judge each.** B3 bundled a real defect (onboarding) with the documented design (a returning user's launch), and the impact line was computed from the bundle. Each route needs its own promise check against nearby doc comments.
3. **State the conditions behind every reach estimate.** "Everyone with a widget, once per cycle" hid the four-day idle condition. Write the condition, then estimate who meets it.
4. **Look for an end-to-end harness before writing "no seam".** The audit said nothing could drive an observer. The repo has one: `RECHARGE_SEED_HEALTH=1` with `RECHARGE_SEED_FOLLOWUP_SECONDS` writes a workout that only the observer can carry in (`Recharge/Debug/HealthSeeder.swift:43-52`), and `SeededWalkthroughTests` already drives the Health sheet. It only runs on the local simulator pool (on GitHub's runner the Health sheet never appears), but it is the seam, and the appendix test uses it.
5. **Model the full user sequence in the repro, not one instant.** The B1 test checked only the mid-countdown instant and missed that answering B re-arms A.
6. **Rank by the class of promise as well as by reach.** A false success message on a privacy control outranks a calibration nudge for a subset of subscribers, whatever the head count.

## Appendix: the B2 end-to-end test

Run on the local pool with `--scheme RechargeUITests`. It was removed from the target after the run, as required. The Health sheet helpers (`allowHealthAccess`, `dismissInterrupts`, `waitUntilHittable`, `attach`) are the private ones in `SeededWalkthroughTests.swift`, copied verbatim.

```swift
func testB2_deletedDataStaysDeletedWhenAWorkoutArrives() throws {
    let app = XCUIApplication()
    app.launchEnvironment["RECHARGE_SEED_HEALTH"] = "1"
    app.launchEnvironment["RECHARGE_SEED_DAYS"] = "30"
    // One hard run, written 180 s after the launch import finishes.
    app.launchEnvironment["RECHARGE_SEED_FOLLOWUP_SECONDS"] = "180"
    app.launch()
    allowHealthAccess()

    let today = app.buttons["Today"]
    XCTAssertTrue(today.waitForExistence(timeout: 300), "the tab bar never appeared")
    dismissInterrupts(in: app)
    Thread.sleep(forTimeInterval: 12)
    dismissInterrupts(in: app)
    let hero = app.descendants(matching: .any).matching(identifier: "today.hero").firstMatch
    XCTAssertTrue(hero.waitForExistence(timeout: 30))

    let gear = app.buttons["Settings"]
    waitUntilHittable(gear, timeout: 30)
    gear.tap()
    let delete = app.buttons["Delete local health data"]
    for _ in 0..<25 where !(delete.exists && delete.isHittable) { app.swipeUp() }
    delete.tap()
    app.alerts.buttons["Delete"].tap()
    XCTAssertTrue(app.staticTexts.containing(NSPredicate(format: "label CONTAINS 'were deleted'")).firstMatch.waitForExistence(timeout: 10))
    app.buttons["Done"].firstMatch.tap()
    XCTAssertTrue(hero.label.hasPrefix("No recent workout"))

    // The follow-up workout reaches the app only through the observer query.
    let deadline = Date().addingTimeInterval(330)
    var latest = hero.label
    while Date() < deadline, latest.hasPrefix("No recent workout") {
        Thread.sleep(forTimeInterval: 5)
        dismissInterrupts(in: app)
        latest = hero.label
    }
    XCTAssertTrue(latest.hasPrefix("No recent workout"),
                  "deleted Health data came back with no user action: hero now reads \(latest)")
}
```

It covers the observer route only. The background task route needs a device left alone for 30 minutes or more, or `e -l objc -- (void)[[BGTaskScheduler sharedScheduler] _simulateLaunchForTaskWithIdentifier:@"com.jackwallner.recovery.refresh"]` in the debugger after the delete.
