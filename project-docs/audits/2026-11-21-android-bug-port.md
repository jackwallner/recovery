# Android port of the 2026-11-20 bug fixes

Checked 2026-11-22 on `main`. Each row of
[2026-11-20-bug-fixes.md](2026-11-20-bug-fixes.md) was checked against the
`android/` port by reading the code. Bugs that exist there were fixed with the
smallest change that matches the iOS behavior.

The fix commits came from a fleet run (`recovery-port1122`) that ported the
same iOS commits; they were fast-forwarded onto `main` in place of a second,
overlapping set of edits. That run also ported three iOS fixes from outside the
catalog, listed under the table.

Unit run (`fm-gradle testDebugUnitTest`, GitHub Linux) at HEAD `3730779`:
`recovery-mbairfcc1-1122-103204-25802`, **4441 passed, 0 failed.**

No run before the fixes. No emulator run; the Compose wiring was checked by
reading the code.

| iOS bug | Android verdict | Commit | Test | Notes |
|---|---|---|---|---|
| B1 "Correct this session" on a free account closes the detail and shows no offer | already fine | | | The card's tap is `upgrade`, which pushes `Route.Paywall` on top of the detail (`RootScreen.kt`); the detail is not closed first |
| B2 Watch effort question names one session and saves the answer to another | not applicable | | | No Wear OS app |
| B3 A quarantined store keeps the Health anchor, so history never re-imports | not applicable | | | Android keeps no Health anchor and no quarantined store; every refresh reads the Health Connect window again |
| B4 At the largest text sizes the offer loses its pitch and clips its buttons | not applicable | | | iOS Dynamic Type accessibility sizes. Android font scale stops at 2x |
| B5 Ask to Buy shows "Couldn't start your trial" | ported | 473ae90 | `PurchaseOutcomeTest` (4 tests) | RevenueCat's `PaymentPendingError` returns `PurchaseOutcome.PENDING`, so the offer shows the existing pending message instead of a failure |
| B6 A hard session's Ready moment is lost behind a later easy session | ported | 850550d | `ReadyMomentTest.aHardSessionsReadyMomentCountsEvenWhenAnEasySessionEndedInsideItsCountdown` | `readyMoment` takes the countdown that ran out last once none is running |
| B7 Background relaunches count as app launches for the review ask | already fine | | | `recordForegroundOpen` is called only from `MainActivity.onCreate`. Background work (`WorkManager`, the alert receiver) starts the process without an activity and never reaches it |
| B8 After deleting local data, the readiness question stays off until a cold launch | ported | 6fadf34 | `LocalDataDeletionTest.deletingClosesTheReadinessWindowAndReconnectingReopensItFromNow`, `reconnectingBeforeSetupLeavesTheWindowToSetup`, `anOrdinaryReconnectKeepsTheWindowThatIsAlreadyOpen` | `Settings.reconnectHealth` reopens the readiness window when Health Connect is connected again. The same commit stops the next refresh from re-importing deleted data |
| B9 The effort sheet on Today renders empty while it closes | not applicable | | | A SwiftUI `sheet(item:)` teardown problem. The Compose sheet is drawn from a plain `sheet` string and has no item to lose |
| B10 Max heart rate rejects Arabic-Indic or Persian digits | ported | 6500714 | `TypedNumberTest` (4 tests) | `TypedNumber.value` reads local digits; ASCII input reads as before |
| B11 A Ready alert or widget tap leaves a sheet in front of Today | already fine | | | `RootScreen` handles `openToday` with `sheet=null;tab=0;popToRoot()` |

Counts: 4 ported, 3 already fine, 4 not applicable.

## Also ported, from outside the catalog

| Commit | What | Test |
|---|---|---|
| 1e1bdae | No "how did it feel" question about a countdown while a later session's countdown is still running (iOS c1fbe95) | `StateMachineRegressionTest` (3 cases) |
| 850550d | The review ask does not count Ready moments from before setup (iOS f4506f1) | `ReadyMomentTest.theOnboardingImportDoesNotCountAReadyMoment` |
| 20c2ced | The session detail's Ready line reads the clock once when it opens (iOS 6b5da5c) | none (one line of screen state) |
| 3730779 | Test only: the functional and hybrid setting reaches sessions already imported | `ReclassificationTest` |

## Needs Jack

Nothing blocking. Not uploaded to Play; the fixes ship with the next Android
build when you ask for one.
