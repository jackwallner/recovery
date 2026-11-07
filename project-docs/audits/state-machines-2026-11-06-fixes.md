# Fixes for the state machine audit (2026-11-06)

Fixes for the claims `state-machines-2026-11-06-review.md` confirmed, in the review's ranked order, using its corrected routes. No `-verify.md` existed, so this is the first pass.

**Summary: 5 in scope (B2, B1, B3 onboarding route, B4, and P4, which the review said belongs in the B2 fix). 5 fixed, 0 held, 0 skipped. 0 UNVERIFIED claims.** The review's other finding the audit missed (B2's background delivery is never disabled) is fixed with B2; its route (ii) for B1 is fixed with B1.

## Claims

| id | outcome | commit | regression test | what changed |
|---|---|---|---|---|
| B2 | fixed | `6ab56eb` | `RechargeUITests/SeededWalkthroughTests/testDeletedHealthDataStaysDeletedWhenAWorkoutArrives` (the review's appendix test) | `RecoveryEngine.refresh` returns while `hasDeferredHealthAccess` is set, so the observer queries, the background task, the scene and pull to refresh all honour Delete local health data. It re-checks after each suspended Health read (before both saves, before the profile merge, before rescore), so a delete made mid refresh is not written back. `deleteLocalHealthData` now stops the observer queries and calls `disableAllBackgroundDelivery` (the review's missed side effect), and the two reconnect paths that skip `requestAuthorization` (Today, History) turn delivery back on. History hides Try again while disconnected, because it can no longer read anything; Connect Apple Health stays. |
| P4 | fixed with B2 | `6ab56eb` | same as B2 (not separately testable: `PhoneWatchSession` is outside the unit target) | Deletion sends `RecoverySnapshot.empty` to the Watch, which already accepts it (the `sentAt` ordering exists so a clearing snapshot is never refused). |
| B1 | fixed | `c1fbe95` | `StateMachineRegressionTests/testTheReadinessQuestionIsNotAskedWhileTheShownCountdownIsStillRunning` (the audit's `testBUG1_*`), `testAnsweringTheStackedSessionDoesNotRaiseTheQuestionAboutTheOneUnderIt` (route ii, the review's ordinary double day), control `testControl_aCountdownThatRanOutBeforeTheNextSessionIsStillAskedAbout` | `RecoveryResolver.awaitingFeedback` skips an estimate that a stacked successor outlasts (`isSuperseded`: another countdown ended before this one's `readyAt` and ends after it, the same condition as `carriedHours > 0`). An unstacked earlier countdown is still asked about. |
| B3 | fixed (onboarding route) | `f4506f1` | `StateMachineRegressionTests/testTheOnboardingImportDoesNotCountAReadyMoment`, control `testACountdownThatRanOutAfterSetupStillCounts` | New `RecoveryResolver.readyMoment` bounds the Ready moment by `feedbackEligibleFrom` (nil until onboarding's `finish()` stamps it). `publish()` and `handleClockTick` both use it. The returning-user route the review called intended still counts: a countdown that ran out after setup while the app was closed. No stored data changes shape; existing users already have the stamp (set at setup, or at launch by `openFeedbackWindowIfNeeded`). |
| B4 | fixed | `cf22114` | `StateMachineRegressionTests/testTheTimelineCarriesTheReadyToNoWorkoutFlip` (the audit's `testBUG2_*`), `testAnIdleTimelineBuiltAfterReadyStillFlipsAtTheCutoff` | `CountdownTimeline.entryDates` adds an entry one second past `RecoveryResolver.staleFrom` (new, and now the body of `isStale`, so the two cannot drift) for running and idle timelines with a session. `reservedFinalEntries` 2 to 3 so the longest countdown still fits `maximumEntries`. `testAnExpiredCountdownProducesASingleEntry` and `testAnEntryAfterReadyAtRendersAsReady` pinned the old shape and now assert the flip. |

Every unit regression test was also run locally against the fixed code and with each fix reverted (a `swiftc` build of the pure model files and the test files over a small XCTest shim, since this machine has no Xcode): all pass with the fixes; every B1, B3 and B4 test fails without its fix, and the controls pass both ways.

The B2 UI test needs the seeded Health harness, which works only on the local `agent-sim` pool: on GitHub's runner the Health permission sheet never appears. It lives in the `RechargeUITests` scheme, so it does not affect the `Recharge` suite. Results on the Air's pool (`agent-sim-5`, iOS 27), 2026-11-07:

- HEAD: passed in 416 s.
- All of `6ab56eb`'s app code reversed, test kept: failed with "deleted Health data came back with no user action: hero now reads 1d 15h left", the audit's bug.
- Only the `guard mayReadHealth else { return }` lines removed: passed, because the rollback guards remained and deletion also stops the observers. That run does not exercise the bug, so it proves nothing either way.

The first HEAD run failed on a simulator with a denied Health store, cleared by erasing it. The next failed because `waitUntilHittable` read `isHittable` on a cell with no usable frame while the sheet slid in, which fails the test instead of returning false. The helper now checks the frame first.

## Held for Jack

None.

## Skipped

None.

Not in scope, and not changed: B3's returning-user route (the review: intended behaviour), the product calls P1, P2, P3, P5, P6, P7 and P8 (the review agreed each is a product call; P4 was the one it said to fix). The Android port has the same per-estimate `awaitingFeedback` filter (`android/.../model/RecoveryEngine.kt:65`); Android was out of the audit's scope and was not touched.

## Test runs

GitHub Macs via `gh-sim test --scheme Recharge` (full `RechargeTests` suite).

- Baseline, before any change (clean worktree at `825493a`, the base before the rebase onto `edf962e`): `recovery@20261106-165633-1b3f-baseline-mbpro8063-1106-180252-20154`, GitHub run 42327224241, Xcode 27.1, iPhone 17 iOS 27.2. 426 passed, 0 failed, 0 skipped. Nothing failed before the fixes.
- Final, with all fixes (`da8b4f2`, now `cf22114` after the rebase): `recovery@20261106-165633-1b3f-claude-mbpro8063-1106-191204-32136`, GitHub run 42332889141, same device. 433 passed, 0 failed, 0 skipped: the 426 tests from the baseline plus the 7 in `StateMachineRegressionTests`. The app and Watch targets built, so the `RecoveryEngine`, `HealthKitService` and view changes compile. No test newly fails. No repro suite was added to the target, so there was none to remove.
