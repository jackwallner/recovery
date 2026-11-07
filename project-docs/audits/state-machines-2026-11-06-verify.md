VERDICT: PASS

# Verification of the state machine audit fixes (2026-11-06)

Independent check of `state-machines-2026-11-06-fixes.md` against the review (`state-machines-2026-11-06-review.md`) and the whole change `git diff 5bcc076..9a1aecb` (13 files: `RecoveryEngine`, `HealthKitService`, `RecoveryResolver`, `CountdownTimeline`, `TodayView`, `HistoryView`, two test files, one UI test, two rules files, the fixes doc and its index line). No claim in the fixes doc was taken on trust. The code was read again, the user routes were walked, and the tests were run on GitHub's Macs. No app code or test was changed. The only commit this pass adds is this file.

## Fixes

| id | works | regression check | evidence |
|---|---|---|---|
| B2 | yes (code walk; the end-to-end UI test cannot run on GitHub's runner, see Test results) | no regression found | Every Health read now stops at `RecoveryEngine.refresh` while the deferred flag is set (`Shared/Services/RecoveryEngine.swift:119`, flag at `:154`), and it is checked again after each suspended read: at the top of each pass (`:133`), before rescore (`:138`), before the profile merge (`:169`), and before both saves (`:356`, `:459`). The early return at `:356` comes before `commitWorkoutAnchor` (`:370`), so a delete made mid read cannot leave an advanced anchor behind, which would have made a later reconnect skip the history. Delete now stops the observers and background delivery (`:1051`, `HealthKitService.swift:851-862`, queries recorded at `:843`), so on the review's observer route there is no wake left. On the `BGAppRefreshTask` route (`App.swift:124-136`) the wake still arrives but returns at the `:119` guard. Reconnecting turns delivery back on through every path: Today and History when the request status is `.unnecessary` (`TodayView.swift:606`, `HistoryView.swift:200`), and Settings, Today and History through `requestAuthorization` (`HealthKitService.swift:170`), plus `App.init` on the next launch (`App.swift:59-61`). Onboarding clears the flag before its refresh (`OnboardingView.swift:177-178`), so the first import still runs. The `HealthSeeder` debug path clears it before the scene refresh (`App.swift:190-193`). The success copy in the Delete alert is now true. |
| P4 (with B2) | yes (code walk) | no regression found | Delete sends `RecoverySnapshot.empty` with no pending effort ID (`RecoveryEngine.swift:1073-1077`). The Watch orders payloads on `sentAt`, not on the snapshot's `distantPast` `calculatedAt`, so it accepts the clearing payload (`.claude/rules/countdown-and-watch-sync.md`, "A late payload used to win"). The App Group key is then present and empty, so the complication reads No recent workout, not "Open Recharge to set up". |
| B1 | yes | no regression found | `awaitingFeedback` drops any estimate that a later countdown outlasts (`Shared/Utilities/RecoveryResolver.swift:106`, `isSuperseded` at `:136-143`). Route (i): while B runs, nothing is asked. Route (ii): after B ends, B is asked, and once B is answered A is not asked. An unstacked earlier countdown is still asked about (control test). On the free tier nothing changes, because `feedbackEligibleFrom` there is `.distantFuture` (`RecoveryEngine.swift:1156-1159`). The filter compares absolute `readyAt` values, as `active` does, so it matches the ring even when frozen records carry mixed tiers. With the fix reverted, both B1 tests fail (run 42340662018). |
| B3 (onboarding route) | yes | no regression found | `readyMoment` requires `eligibleFrom` and `readyAt >= eligibleFrom` (`RecoveryResolver.swift:118-129`). `publish()` and `handleClockTick` both call it (`RecoveryEngine.swift:1011`, `:1246`). It reads the raw `settings.feedbackEligibleFrom` and not the Pro-gated helper, so the review ask keeps working on both tiers. The stamp is set at `finish()` (`OnboardingView.swift:263`) after onboarding's import, so that import counts nothing. `openFeedbackWindowIfNeeded` runs at every launch (`App.swift:65`) and has existed since `a5bdb0c` (2026-08-22), so existing users already have a stamp and keep counting countdowns that end after it, including the returning-user route the review called intended. No stored format changed. With the fix reverted, the test fails (run 42340662018). |
| B4 | yes | no regression found | `entryDates` appends one entry a second past `RecoveryResolver.staleFrom` on running timelines (`CountdownTimeline.swift:70`) and idle ones (`:42`), and only when that instant is still ahead (`:78-83`). `isStale` is now defined through `staleFrom` (`RecoveryResolver.swift:41-50`), so Today and the face cannot drift apart. `reservedFinalEntries` 2 to 3 (`:29`) keeps a 96-hour countdown within `maximumEntries`: 105 loop entries plus `readyAt`, `readyAt + 60 s` and the flip. Both providers (`RechargeWidget.swift:58-63`, `WatchComplication.swift:67-77`) still take `refreshDate`, which is unchanged. An empty snapshot (no `sessionEnd`) still produces one entry. The two edited `CountdownTimelineTests` pinned the old final shape and now assert the flip. They were changed because the shape changed, not loosened: Ready is still asserted on the first entry after `readyAt`. With the fix reverted, both B4 tests fail (run 42340662018). |

## Disputed

The fixes doc has no "Disputed" section and lists no disputed item, so there is nothing to rule on.

## Must change

Nothing in the app.

The fixes doc cites commits `0e04212`, `edd5e49`, `ff6d46d`, `da8b4f2` and the baseline `825493a`. None of them is on this branch: the fixes were replayed onto `5bcc076` as `b700ac8`, `ad36ade`, `8b8d201` and `36f3f41`, with identical diffs. The table is right about what changed, but its hashes do not resolve here. Correct them when the doc is next touched. This does not fail the check.

## Revert proof (check 1)

The review ranks B2, B1, B3, B4. B2's only end-to-end test is a seeded-Health UI test, and that harness does not get past the Health sheet on GitHub's runner. So the revert proof covers the three fixes that unit tests can reach: B1, B3 and B4. On a scratch branch from `9a1aecb` I reverted the behaviour and kept the tests and the APIs they call. That meant three edits: removing the `isSuperseded` filter, removing the `eligibleFrom` bound inside `readyMoment`, and taking the stale entries back out of `entryDates` (with `reservedFinalEntries` back to 2). I confirmed the pushed snapshot carried the revert, then deleted the scratch branch. The branch ends with only this doc's commit on top of `9a1aecb`.

Run `recovery@20261106-195915-06c0-claude-mbpro08a0-1106-205736-8487`, GitHub run 42340662018, all 7 `StateMachineRegressionTests`: **5 failed, 2 passed.**

- Failed without the fix: `testTheReadinessQuestionIsNotAskedWhileTheShownCountdownIsStillRunning` (asked about A), `testAnsweringTheStackedSessionDoesNotRaiseTheQuestionAboutTheOneUnderIt` (asked about A at both of its checks: mid countdown, line 72, and after B was answered, line 77), `testTheOnboardingImportDoesNotCountAReadyMoment` (counted the 30-day-old session), `testTheTimelineCarriesTheReadyToNoWorkoutFlip` (last entry `readyAt + 60 s`, cutoff 92 h later), `testAnIdleTimelineBuiltAfterReadyStillFlipsAtTheCutoff` (only `[.ready]`).
- Passed both ways, as controls should: `testControl_aCountdownThatRanOutBeforeTheNextSessionIsStillAskedAbout`, `testACountdownThatRanOutAfterSetupStillCounts`.

Each test asserts the user-visible behaviour that its review route promises: no question while the shown ring runs, no second question after the stacked one is answered, no Ready moment from the import, and No recent workout on the face at the cutoff.

## Regressions (check 2)

Read for every changed symbol: all callers of `RecoveryEngine.refresh` (`App.swift:135`, `:206`, `:214`, `:236`, `HealthKitService.swift:773`, the Today, History and Recharge+ pull to refresh, Today, History and Settings connect, History Try again, the Settings DEBUG refresh, and onboarding), `awaitingFeedback` readers (`TodayView.swift:118`, `:674`), `publish()`'s Watch, notification and review paths, `CountdownTimeline` (both providers), and `deleteLocalHealthData` (Settings).

- Stored data after an upgrade: no schema, key or format change. `observerQueries` exists only in memory. `recoveryModelVersion` correctly stays at 17, because no figure moved.
- Widgets and Watch: covered above (B4, P4). The phone-to-Watch effort path is not touched.
- Notifications: the Ready alert is still scheduled from the snapshot in `publish()`, and delete still cancels it. Unchanged.
- Entitlements and trials: nothing that reads `isPro`, `scoringIsPro`, an offering or the trial cooldown changed.
- Undo and edit paths: `recordFeedback` and `overrideIntensity` rescore and then recompute `awaitingFeedback` through the same resolver, so a superseded A stays unasked after an edit, as intended. If B is deleted from Health, A is no longer superseded and can be asked within its two days, which is correct because the ring then showed A.
- Day and time zone changes: the new code uses absolute instants only (`staleFrom`, `readyAt`, `sessionEnd`). No calendar arithmetic was added.
- Localized text: no new strings. `HistoryView` only wraps an existing key in a condition. `python3 Tools/Localization/check.py`: 930 keys, 7 languages, 0 problems.
- iPhone Duo: `HistoryView` loses a button in one state and gains no geometry. Nothing in the panes or the tab bar changed.

## Scope (check 4)

No failure found.

- Every in-scope claim is in the table: B2, B1 (both routes), B3 (onboarding route), B4, and P4, which the review said belongs with B2. The review's missed B2 side effect (background delivery never disabled) is fixed. The B3 returning-user route and P1 to P3 and P5 to P8 were left alone, as the review directed.
- Onboarding, trial, paywall, prices and membership logic were not touched. `OnboardingView`, `RootView`, `PaywallView`, `StoreService` and `TrialOfferPage` are all outside the diff.
- Nothing needs a backend, App Store Connect or RevenueCat change.
- No claim was UNVERIFIED, and none was held or skipped.
- No stored setting is cleared on an inferred state. The only clearing is in `deleteLocalHealthData`, which runs on an explicit user action and already cleared those values before this change.
- Hiding History's Try again while disconnected follows from the B2 guard: the button would now do nothing. Connect Apple Health stays visible in that state (`HistoryView.swift:140`, `needsHealthConnection`). This is part of B2, not extra scope.

## Test results

All on GitHub's Macs (Xcode 27.1, iPhone 17, iOS 27.2):

- Full suite on HEAD `9a1aecb`: `recovery@20261106-195915-06c0-claude-mbpro08a0-1106-200151-947`, GitHub run 42336609415, `gh-sim test --scheme Recharge`. **433 passed, 0 failed, 0 skipped.** This matches the fixes doc's final run (433 = 426 baseline + the 7 new tests). No test fails newly, so there was nothing to rerun.
- Revert proof: GitHub run 42340662018, above.
- Screen: `recovery@20261106-195915-06c0-claude-mbpro08a0-1106-214445-5674`, GitHub run 42344020815, `gh-sim launch` with `RECHARGE_SCREENSHOT_MODE=1`, `RECHARGE_SCREENSHOT_SCENE=history`. History rendered normally (day headers, rows, tab bar clear of the last row).
- B2 UI test: `recovery@20261106-195915-06c0-claude-mbpro08a0-1106-224939-31586`, GitHub run 42348689624, `--scheme RechargeUITests --only RechargeUITests/SeededWalkthroughTests/testDeletedHealthDataStaysDeletedWhenAWorkoutArrives`. `RechargeUITests` built (38 s), so the test compiles. The test failed at `SeededWalkthroughTests.swift:126` ("The Health permission sheet never appeared"), before reaching anything B2 touches. That is the known harness limit on GitHub's runner (the review's run 29157 and the existing `SeededWalkthroughTests` fail the same way), not a regression, and it proves nothing about B2 either way. A first attempt never started (GitHub API rate limit at dispatch) and was rerun.

## Notes

- **Screens (check 5).** The only visible change is History's empty state while disconnected, where Try again is now hidden. Screenshot mode always seeds fixtures and a fresh launch stops at onboarding, so `gh-sim` cannot reach that state. The launch confirms History still renders. The hidden button was checked from code only.
- **B2's UI test** compiles in `RechargeUITests` (run 42348689624; it is outside the `Recharge` scheme, so the full run does not build it). It uses helpers that exist in the same file (`sleepForImport` `:447`, `waitUntilHittable` `:276`, `allowHealthAccess` `:122`, `dismissInterrupts` `:238`, `attach` `:283`). It still needs a run on the local `agent-sim` pool to prove the observer route end to end: `--scheme RechargeUITests -only-testing:RechargeUITests/SeededWalkthroughTests/testDeletedHealthDataStaysDeletedWhenAWorkoutArrives`.
- **Side effect of the B2 guard, judged intended.** `hasDeferredHealthAccess` is also set when an authorization request throws (onboarding, Today, History, Settings). Before this change, the background task (and pull to refresh) still imported for such a user if Health happened to answer. Now nothing reads Health until they tap Connect, which every one of those screens offers. That matches what the flag already meant to the scene path (`App.swift:204-212`) and how Today's Health card describes it, so it is not counted as a regression.
- **Delete, then reconnect in the same process.** `feedbackEligibleFrom` stays nil until the next launch stamps it, so no Ready moment counts until then. The readiness question was already suppressed in this window before this change. The review ask is now held for one session too, which is harmless and errs toward not asking.
- The Android port has the same per-estimate `awaitingFeedback` filter (`android/.../RecoveryEngine.kt`). It is outside this audit, as the fixes doc says.
