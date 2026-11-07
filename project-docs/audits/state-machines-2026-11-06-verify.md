VERDICT: FAIL

# Verification of the state machine audit fixes (2026-11-06)

Independent check of `state-machines-2026-11-06-fixes.md` against the review (`state-machines-2026-11-06-review.md`) and the whole change `git diff edf962ed..206ffce` (four fix commits `6ab56eb` B2+P4, `c1fbe95` B1, `f4506f1` B3, `cf22114` B4, plus the fixes doc, two rules files and the README line). This replaces the earlier verify doc on this branch. Every claim was re-read from the code; nothing was taken from the fixes doc on trust. No app code or test was changed.

**Why FAIL:** one test this change added, `RechargeUITests/SeededWalkthroughTests/testDeletedHealthDataStaysDeletedWhenAWorkoutArrives` (B2's only regression test), has no passing result on HEAD. I ran it on GitHub (run 42357050444) and it failed before reaching the code under test: the harness guard at `RechargeUITests/SeededWalkthroughTests.swift:125-129` ("The Health permission sheet never appeared and the app never got past onboarding"). The fixes doc says outright that it was never run. Under the rules an added test must pass on HEAD, with no exemption, so B2's end-to-end behaviour and its fail-without-fix claim are unproven. Every other check passed. The code fix looks correct on a read, and the fix is one local run away from PASS (see Must change).

## Fixes

| id | works | regression check | evidence |
|---|---|---|---|
| B2 | yes from reading the code; **not proven by any executed test** (its UI test fails in the harness on GitHub, run 42357050444) | no regression found | Delete sets `hasDeferredHealthAccess` (`Shared/Services/RecoveryEngine.swift:1043`), and every Health read now stops on it: the `refresh` entry guard (`:119`) covers all eight callers (observer `HealthKitService.swift:773`, BG task `App.swift:135`, scene `App.swift:206/214/236`, the three pull-to-refresh handlers, Settings/Today/History/Onboarding requests). Re-checks after each suspension: top of each pass (`:133`), before rescore (`:138`), before the profile merge (`:169`), before both saves (`:356`, `:459`). The `:356` return comes before `commitWorkoutAnchor` (`:370`), so a delete during a read cannot commit a stale anchor. Delete stops the observer queries and calls `disableAllBackgroundDelivery` (`RecoveryEngine.swift:1051`, `HealthKitService.swift:851-862`; queries recorded at `:843`, `installedObserverTypes` cleared so a reinstall works). Reconnect turns delivery back on through every path: Today and History `.unnecessary` branch (`TodayView.swift:606`, `HistoryView.swift:200`), `requestAuthorization` (`HealthKitService.swift:170`, used by Settings `:345`, Onboarding, Today/History second branch), and `App.init` on the next launch (`App.swift:59-61`). Onboarding and the seeder clear the flag before refreshing (`OnboardingView.swift:177-178`, `App.swift:192`), and screenshot mode returns before the guard (`RecoveryEngine.swift:97-101`). History hides Try again while disconnected (`HistoryView.swift:157`), and Connect Apple Health stays (`:140`, `needsHealthConnection` `:176`). |
| P4 (with B2) | yes from reading the code (no test: `PhoneWatchSession` is outside the unit target) | no regression found | Delete sends `RecoverySnapshot.empty` with no pending effort ID (`RecoveryEngine.swift:1072-1078`, `#if os(iOS)` so the Watch target compiles it out). `sendSnapshot` stamps `sentAt` (`PhoneWatchSession.swift:471`), and the Watch orders on `sentAt`, not `calculatedAt`, so the clearing payload is accepted (`.claude/rules/countdown-and-watch-sync.md`, "A late payload used to win"). Silent if the session is not activated (`:465`), the same as every publish. |
| B1 | yes | no regression found | `awaitingFeedback` drops an estimate that a stacked successor outlasts (`Shared/Utilities/RecoveryResolver.swift:106`, `isSuperseded` `:136-143`). The condition `other.sessionEnd < estimate.readyAt` is the same test as `carriedHours > 0` (`RecoveryCalculator.swift:279-282`), and it also requires `other.producesCountdown`, which matches "only a session that earns a countdown may inherit". Route (i): nothing is asked while B runs. Route (ii): B is asked, then with B answered A is not. Today presents only `engine.awaitingFeedback` (`TodayView.swift:118`, `:674`), set only by `rescore` (`RecoveryEngine.swift:808`) and `handleClockTick` (`:1240`), and both go through the fixed function. A countdown that ran out before the next session is still asked about (control test). Edits and undo (`overrideIntensity`, `recordFeedback`) rescore and recompute, so a session whose edit removes the overlap becomes eligible again inside its 48 h window. Free tier unchanged (`feedbackEligibleFrom` is `.distantFuture`, `:1157`). Fails without the fix (run 42354300059). |
| B3 (onboarding route) | yes | no regression found | `readyMoment` (`RecoveryResolver.swift:118-129`) needs a non-nil `eligibleFrom` and `readyAt >= eligibleFrom`. Both callers use it: `publish()` (`RecoveryEngine.swift:1011-1015`) and `handleClockTick` (`:1246-1249`). It reads the raw `settings.feedbackEligibleFrom`, not the Pro-gated helper, so the review funnel stays on both tiers. Onboarding's import runs before `finish()` stamps the window (`OnboardingView.swift:263`), so it counts nothing. Existing users already hold a stamp (`App.swift:65`, and setup), so the returning-user route the review called intended still counts. One neighbour: Delete clears the stamp (`RecoveryEngine.swift:1044`), so after a delete and reconnect no Ready moment counts until the next launch re-stamps it. That is the onboarding rule applied to a re-import, not a regression. No stored format changed. Fails without the fix (run 42354300059). |
| B4 | yes | no regression found | `entryDates` adds one entry a second past `RecoveryResolver.staleFrom` to running timelines (`CountdownTimeline.swift:70`) and idle ones (`:42`), only when it is still ahead (`:78-83`). `isStale` is now defined through `staleFrom` (`RecoveryResolver.swift:40-51`), with the same `>` boundary, so Today and the face flip at the same second. `reservedFinalEntries` 3 (`:29`) keeps the total within `maximumEntries` (108): a 96 h countdown is about 106 entries. Both providers still build from `entryDates` and `refreshDate` (`RechargeWidget.swift:58-63`, `WatchComplication.swift:67-77`), and `refreshDate` is unchanged. An empty snapshot is still `[now]`. Absolute intervals, so DST and time zone changes do not apply. The two edited `CountdownTimelineTests` were updated to the new shape, not loosened: Ready is still asserted on the first entry after `readyAt`. Fails without the fix (run 42354300059). |

## Disputed

The fixes doc has no "Disputed" section and lists no disputed item, so there is nothing to rule on.

## Must change

1. **Get a passing result for `testDeletedHealthDataStaysDeletedWhenAWorkoutArrives` on HEAD.** It can only run on the local `agent-sim` pool on the Air (GitHub's runner never shows the Health sheet, as with the existing `SeededWalkthroughTests`). Run `xcodebuild test -scheme RechargeUITests -only-testing:RechargeUITests/SeededWalkthroughTests/testDeletedHealthDataStaysDeletedWhenAWorkoutArrives` against a leased UDID, record the result in the fixes doc, and ideally also run it once with `RecoveryEngine.swift:119` removed to show it fails without the fix. This needs no code change unless the test fails.
2. Doc only, does not fail the check by itself: the fixes doc cites commits `0e04212`, `edd5e49`, `ff6d46d`, `da8b4f2` and baseline `825493a`. None of them exists on this branch. The fixes are `6ab56eb`, `c1fbe95`, `f4506f1`, `cf22114` on base `edf962ed`.

## Revert proof (check 1)

Top three by the review's rank are B2, B1, B3. B2 has only the UI test, which cannot run on GitHub (above), so the proof covers B1, B3 and B4. On `scratch-revert` I reverted the behaviour and kept the tests and the APIs they call: removed the `isSuperseded` filter, removed the `eligibleFrom` bound inside `readyMoment`, and took the stale entries out of `entryDates` (with `reservedFinalEntries` back to 2). Diffed against `edf962ed`, the resolver and timeline behaviour matched the base exactly. I confirmed the pushed snapshot's tree was the scratch commit (`77fef0d`), then switched back and deleted the branch.

Run `recovery@20261106-233148-8deb-claude-imace161-1107-000959-15816` (GitHub run 42354300059), 9 tests: 6 failed, 3 passed, exactly as the fixes should predict.

| test | fix reverted | HEAD |
|---|---|---|
| `testTheReadinessQuestionIsNotAskedWhileTheShownCountdownIsStillRunning` (B1) | FAIL "asked about A while B's countdown is on screen" | pass |
| `testAnsweringTheStackedSessionDoesNotRaiseTheQuestionAboutTheOneUnderIt` (B1) | FAIL, A returned mid-countdown and after B answered | pass |
| `testControl_aCountdownThatRanOutBeforeTheNextSessionIsStillAskedAbout` | pass | pass |
| `testTheOnboardingImportDoesNotCountAReadyMoment` (B3) | FAIL, "old" counted with nil and with a later stamp | pass |
| `testACountdownThatRanOutAfterSetupStillCounts` (control) | pass | pass |
| `testTheTimelineCarriesTheReadyToNoWorkoutFlip` (B4) | FAIL, last entry 60 s after `readyAt`, reads Ready | pass |
| `testAnIdleTimelineBuiltAfterReadyStillFlipsAtTheCutoff` (B4) | FAIL, `[.ready]` only | pass |
| `CountdownTimelineTests/testAnExpiredCountdownCarriesOnlyNowAndTheStalenessFlip` (edited) | FAIL, `[now]` only | pass |
| `CountdownTimelineTests/testAnEntryAfterReadyAtRendersAsReady` (edited) | pass (asserts Ready after `readyAt`, true both ways) | pass |

What the unit tests leave open, to check on a device or the pool:
- B1: they assert the resolver, which is the actual source Today presents from. Not exercised: Today re-presenting the sheet on the `awaitingFeedback` change after an answer (`TodayView.swift:118`).
- B3: `testTheOnboardingImportDoesNotCountAReadyMoment` asserts the new `readyMoment` function, not the wiring. The two call sites were read (`RecoveryEngine.swift:1011`, `:1246`), but a fresh install with old Watch history and `reviewPrompt.readyMomentCount` staying 0 after onboarding is a device check.
- B4: the providers' use of `entryDates` is unchanged and was read, not run. A face actually flipping to No recent workout at the cutoff without a reload is a device check.
- B2 and P4: everything (see Must change). The background-task route also needs a device or a `_simulateLaunchForTaskWithIdentifier` call after the delete.

## Regressions (check 2)

Every changed function was traced to all its callers and all readers of the state it writes.
- `refresh` guard: the only users with the flag set are those who deleted local data or whose authorization request threw. The scene paths already skipped refresh for them (`App.swift:204`, `:231`) and `App.init` skipped the observers. What changes is that pull to refresh and the BG task now also do nothing for them. That reaches a user only if they deferred, then granted access from the iOS Health app without tapping Connect, and Today's Health card (`TodayView.swift:206`) still offers Connect, whose `.unnecessary` branch clears the flag and imports. Not a regression.
- Upgrade: no stored key or SwiftData shape changed. `observerQueries` is in memory. `feedbackEligibleFrom` semantics are unchanged.
- Widgets and Watch: B4 adds one entry and no reloads. P4 adds one send on delete.
- Notifications: unchanged (delete still cancels, `RecoveryEngine.swift:1068`).
- Entitlements, trials, paywall, onboarding order: untouched. `readyMoment` deliberately ignores `isPro`, as the old predicate did.
- Localization: no new user-facing string; "Try again" is an existing key. iPhone Duo: History's empty state only loses a button under a flag, no layout change.
- Android: the port keeps the old per-estimate `awaitingFeedback` (`android/.../model/CountdownFormat.kt:56`). It was out of scope, and the parity export covers calculations only, so nothing breaks. iOS and Android now differ on B1.

## Scope (check 4)

Every review claim in scope is in the fixes table: B2, the B2 side effect the review said the audit missed, P4 (the review said to fix it with B2), B1 both routes, B3 onboarding route, B4. The B3 returning-user route (NOT A BUG) and P1 to P3, P5 to P8 (product calls) were correctly left alone. Nothing held or skipped, and the review had no UNVERIFIED claims. No change to trial or onboarding flow, prices, paywall, membership or backend. The only state cleared is on the user's explicit Delete. Hiding History's Try again while disconnected is part of B2, since that button was one of the routes that re-imported. No scope failure.

## Test results (check 3)

| run | GitHub run id | what | result |
|---|---|---|---|
| `recovery@20261106-233148-8deb-claude-imace161-1106-233239-31625` | 42351723520 | `gh-sim all --scheme Recharge` on HEAD `206ffce` (full `RechargeTests` + launch) | **433 passed, 0 failed, 0 skipped**, built in 49 s. Matches the fixes doc's final run (433). All 7 `StateMachineRegressionTests` and both edited `CountdownTimelineTests` passed. |
| `recovery@20261106-233148-8deb-claude-imace161-1107-000959-15816` | 42354300059 | revert proof, 9 tests | 6 failed, 3 passed, as expected (table above) |
| `recovery@20261106-233148-8deb-claude-imace161-1107-004840-6135` | 42357050444 | `--scheme RechargeUITests --only .../testDeletedHealthDataStaysDeletedWhenAWorkoutArrives` on HEAD | **FAIL** at the Health-sheet harness guard, before the code under test (905 s). The screen recording ended (170 s) before the app launched, so it shows nothing more. Rerunning on GitHub would not help: the sheet never appears there. |

No unit test newly fails, so no `edf962ed` comparison was needed.

## Screens (check 5)

Only the History empty state changed visibly (Try again hidden while `hasDeferredHealthAccess`), plus a non-visual reconnect call in Today. Screenshot mode forces `hasDeferredHealthAccess = false` (`RechargeSettings.swift:374`) and seeds fixtures, so it cannot reach the deferred empty state. The launch screenshot from run 42351723520 (`RECHARGE_SCREENSHOT_SCENE=history`) shows History rendering normally with the fixture list and tab bar. The changed state itself is a device check.

## Notes

- Narrow race, pre-existing and not made worse: if the user deletes and then reconnects while a refresh from before the delete is still suspended in a Health read, that refresh passes its guards again (the flag is false by then) and can commit an anchor fetched before the reset. The re-import would then skip the history. It needs both taps inside one in-flight read, and before the fix the same refresh re-imported without any reconnect at all.
- A fetch that fails after a delete sets `lastImportFailed` (`RecoveryEngine.swift:242`) even though the user is now disconnected. That is cosmetic and can only happen mid-refresh.

## Resolved after this check

Both must-change items are closed: the B2 UI test passes on HEAD and fails with `6ab56eb`'s app code reversed, and the fixes doc now cites the real commits. Results are in the fixes doc. The verdict line above records this check as it ran.
