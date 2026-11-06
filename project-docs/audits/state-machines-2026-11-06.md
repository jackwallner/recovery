# State machine audit: Recharge (2026-11-06)

Audit date: 2026-11-06. Committed code only (`git stash -u` found nothing to stash). Scope: iPhone app, `Shared/`, widgets, Watch targets. No backend function exists in the repo; entitlements are RevenueCat's `CustomerInfo` alone. Android is out of scope. Nothing was fixed.

**Summary: 4 bugs. 2 proved by a failing test (B1, B4), 2 code path only, not proved (B2, B3). 8 product calls (not counted).** Test run: `gh-sim test --scheme Recharge --only RechargeTests/StateMachineAuditRepro`, run id `recovery@20261106-114442-3a7f-claude-mbpro3fbc0-1106-115607-4213`, Xcode 27.1, iPhone 17 iOS 27.2: 4 tests, 2 failed (the two bug tests, at their final assertion, all preconditions held), 2 passed (the controls). The repro suite is `state-machines-2026-11-06-repro.swift` (`testBUG1_*` is B1, `testBUG2_*` is B4). Failing tests are expected.

## Bugs, ranked by impact (users reached times cost)

| id | bug | what the user sees | promise | user route | impact | evidence | file:line |
|---|---|---|---|---|---|---|---|
| B1 | The readiness question is raised for an earlier session of a stack while the shown countdown is still running, and the answer retunes every future window | A sheet "How did that feel?" with "Your estimate after that run ran out." over a Today screen whose countdown still has about 32 hours left | `EffortPromptSheet.swift:102` "The one-tap question asked once a countdown expires"; the sheet's own line "Your estimate after that run ran out." (`:131`); `RecoveryResolver.swift:69-70` "Estimates whose countdown has expired" | Recharge+ subscriber. Finish a hard run (A), then a second hard session (B) before A's window ends, so B stacks on A. Open Today (TodayView hero shows B's countdown). Wait until A's own window ends (the 60 second ticker in `TodayView.swift:95-98` calls `handleClockTick`, or open the app after). `presentFeedbackIfNeeded` raises `ReadinessFeedbackSheet`. Tap Felt ready, Okay but not fresh, or Not ready. Needs `isPro` and A's `readyAt` after setup. No special device, zone or duration beyond two sessions inside one window | Every Recharge+ user who trains inside their own countdown (two-a-day or back to back hard days), once per stacked pair, repeatedly for daily trainers. Cost: a question whose premise is false on screen, and the honest answer ("Not ready", the countdown says 32h) multiplies `calibrationFactor` by 1.05 (0.95 for "Felt ready"), bounded 0.80-1.25, which scales every future personalized window. Free tier is not reached (the question is Pro only) | Proved. `testBUG1_readinessQuestionIsNotAskedWhileTheShownCountdownIsStillRunning` failed: "asked about A (own readyAt -1.0h from now) while the shown countdown has 31.913293257686828h left (A hours 33.91329325768321, B hours 33.91329325768321 + carried 1.0)". Preconditions asserted and held: A's `readyAt` is in the past, `B.carriedHours > 0`, B has more than 2h left, `active` is B, phase is `.recovering`. Control `testControl_readinessQuestionIsAskedWhenTheOnlyCountdownHasEnded` passed (A alone, and B after B ends, are asked about) | `RecoveryResolver.swift:80-95` (filters on each estimate's own `readyAt`, never on the shown one); `RecoveryEngine.swift:783-788`, `:1200-1205`; `RecoveryEngine.swift:1116-1118` (`feedbackEligibleFrom` needs `isPro`); `RecoveryCalculator.swift:300-304` (a stacked session always ends later than the one it stacks on) |
| B2 | "Delete local health data" is undone by the next Health wake: observers and the background refresh ignore `hasDeferredHealthAccess` | Settings says "Recharge's local Health cache and estimates were deleted". Within minutes (observer) or about 30 minutes (background refresh) the workouts, countdown, History, Watch figure and Ready notification are back, while Today still shows the Connect Apple Health card | `SettingsView.swift:78` "This removes Recharge's imported workouts, estimates, snapshots, and Health-derived profile values from this device"; `RecoveryEngine.swift:994` "Deletes Recharge's local Health cache and derived estimates"; `RechargeSettings.swift:42-44` the deferred flag "prevents the app from asking again ... gives the main UI a stable state from which to offer reconnection" | Today, gear button, Settings sheet, Delete local health data, Delete. Health permission is left granted (deletion does not revoke it). Leave the app. A workout or heart-rate sample arrives from the Watch: the already-installed `HKObserverQuery` runs `refresh(force: false)`. Or iOS fires the `BGAppRefreshTask` (earliest 30 minutes, `App.swift:118-122`). History fills again. Needs an Apple Watch or any Health writer, and Health read access still on | Reaches only users who tap Delete (a deliberate privacy action, small share), but for them it is near certain whenever they have an Apple Watch writing heart rate (observer type `.immediate`) and costs the whole promise: the data they asked to remove is back with no notice and the deletion message was a false success | Code path, not proved. Seams checked: `RecoveryEngine`, `HealthKitService` and `App.swift` are not in the `RechargeTests` target (`project.yml:154-200`), `HealthKitService` has no injectable store, and the target has no RevenueCat or HealthKit fakes, so no test can drive an observer or a BG task. Settled by: an on-device run (delete, background the app, add a workout in Health, reopen History), or a test target that compiles `RecoveryEngine` with a fake `HealthKitService`, asserting `refresh` is a no-op while `hasDeferredHealthAccess` | No guard on the deferred flag in `RecoveryEngine.refresh` (`:97-139`), `App.handleAppRefresh` (`App.swift:124-136`), or the observer closure (`HealthKitService.swift:811-840`, `enqueueObserverRefresh` `:742-775`); `fetchWorkouts` does not check `isAuthorized` (`HealthKitService.swift:296-308`); `deleteLocalHealthData` sets the flag and resets the anchor (`RecoveryEngine.swift:1016-1020`) but never removes observers or the BG request (`App.swift:44` schedules unconditionally); only the scene handler checks the flag (`App.swift:229-232`) |
| B3 | A Ready moment is counted for a countdown the user never watched, starting at onboarding | Nothing visible; the App Store review ask can arrive after one watched countdown instead of two | `ReviewPromptTracker.swift:19` "Countdowns the user has watched run out"; `AGENTS.md:96` "gated at two Ready moments so the loop has paid off twice before the ask" | New install with Health history. Onboarding: Health page, Continue, grant. `OnboardingView.swift:178` runs `engine.refresh(force: true)`, which ends in `publish()`. `publish` records `current` when its `readyAt <= now`; with no active countdown `current` falls back to the newest session even if weeks old (`RecoveryResolver.swift:24-28`). `readyMomentCount` is 1 before Today is shown. Same predicate fires when a returning user opens the app after a countdown ended while it was closed. Needs a latest session that qualifies for a countdown | Most new installs (people arrive with a Watch history) and every returning user, once per new install and once per background-ended countdown. Cost is small: the review ask lands one cycle early and spends the 120 day cooldown (`ReviewPromptTracker.cooldownDays`). Also leaves `hasPendingReadyMoment` true from install, which blocks `shouldShowForEngagedUse` (`ReviewPromptTracker.swift:197-200`) | Code path, not proved. `ReviewPromptTracker` needs `ScreenshotConfig` (not in the test target) and the call site is the engine. Settled by: reading `reviewPrompt.readyMomentCount` in the App Group defaults on a fresh simulator install with seeded history after onboarding (expected 0; the code path gives 1), or compiling the tracker plus a stub `ScreenshotConfig` into the test target and driving `RecoveryResolver.current` plus the `publish` predicate | `RecoveryEngine.swift:986-988` (and `handleClockTick` `:1199-1214` uses `current` the same way); `ReviewPromptTracker.swift:139-150`; `RecoveryResolver.swift:24-28` |
| B4 | Widgets and complications have no timeline entry at the stale cutoff, so they keep saying Ready after Today says No workout | Today reads "No workout" (empty ring) while the widget or Watch complication still reads Ready with a full ring, until the next refresh | `CountdownTimeline.swift:13` "the timeline must remain correct without any [refresh]: each entry carries the instant it represents"; `.claude/rules/countdown-and-watch-sync.md:225` "`RecoveryResolver.isStale` is the one staleness rule for Today, the snapshot, the widgets and the Watch" | Any user with the iOS widget (`RechargeWidget`) or a Watch complication. Finish a session, let the countdown end, leave the phone alone. At `max(sessionEnd + 4d, readyAt + 1d)` open Today (No workout) and look at the widget (Ready) | Everyone with a widget or complication, once per countdown cycle. Cost is small and bounded: after the flip to Ready the provider asks for a reload 2 minutes later and then every 6 hours (`CountdownTimeline.refreshDate`), so the face is wrong for up to about 6 hours plus WidgetKit budget slack | Proved. `testBUG2_timelineCarriesTheReadyToNoWorkoutFlip` failed: last entry is 2026-02-02 05:41:00Z, 60.0 s after `readyAt`; the cutoff is 2026-02-06 01:40:00Z, 92.0 h after `readyAt`, so the face stays on `ready`. Preconditions held (recovering now, `.ready` after `readyAt`, `.noRecentWorkout` after the cutoff). Control `testControl_timelineCarriesTheRecoveringToReadyFlip` passed (flip to Ready is covered, refresh after Ready is 6 h) | `CountdownTimeline.swift:34-67` (no entry after `readyAt + 60 s`), `:75-83` (6 hour idle refresh); `RecoveryResolver.swift:40-47`; `RechargeWidget.swift:58-63`, `WatchComplication.swift:67-77` |

## Product calls (not counted)

No citation that the code contradicts, or the promise is arguable.

- P1. Per-session edits thaw every record. `rescore`'s doc says a per-session edit passes its own ID in `unfreezing`, but `recordEffort`, `overrideIntensity`, `overrideProfile`, `rescoreAfterModelSettingChange` and `entitlementDidChange` all pass `unfreezeAll: true` (`RecoveryEngine.swift:463` doc, call sites `:1059`, `:1156`, `:1174`, `:1182`, `:1192`). `model-tiers.md` justifies it for `overrideIntensity` (stacked chain), not for an effort answer. An effort answer therefore rewrites expired History rows with the current `calibrationFactor`, which the same doc says must not reach back.
- P2. A delivered "Ready" notification is never removed (no `removeDeliveredNotifications` anywhere). After a new workout the lock screen still says Ready until the user clears it. Pending requests are replaced by identifier, delivered ones are not touched.
- P3. Delete local health data keeps `calibrationFactor`, `manualWindows` and typed profile answers. The calibration was learned from the feedback on the deleted sessions.
- P4. Delete local health data does not send a cleared snapshot to the Watch (no `sendSnapshot` after `RecoverySnapshotStore.clear()`, `RecoveryEngine.swift:1036`), so the Watch app and complication keep the old countdown until the next phone publish. The alert says "from this device", which can be read as the iPhone only.
- P5. Onboarding stamps `lastTrialOfferShownDate = .now` at `finish()` whether or not an offer was visible (`OnboardingView.swift:257`), starting the 14 day passive cooldown even when the plans failed to load.
- P6. The passive trial cooldown is stamped when the offer is decided, not when the sheet is known to have appeared (`RootView.swift:345`, `:361`).
- P7. A pending (Ask to Buy) purchase approved while the onboarding offer page or the half sheet is open leaves a live buy button for a now-Pro user (`PaywallView.swift:139-141` only dismisses when `didPurchase`; `TrialOfferPage.swift:339-366`). Apple blocks a duplicate subscription, a lifetime purchase on top of a yearly one is the open case.
- P8. A force-quit app gets no HealthKit wake, so a pending Ready request set before a new workout still fires "Ready" after the new workout finished. Platform limit, no app-side fix without a wake.

## Related fixes, in order

1. B2 first (privacy, and it also resurrects the notification and Watch figure): check `setup && !deferred` once, inside `RecoveryEngine.refresh`, so the observer, background task and scene paths all obey it; make `deleteLocalHealthData` stop observers and cancel the BG request; then P4 (publish a cleared snapshot) and P2 (remove delivered Ready notifications) in the same change, because they all describe what "deleted" and "no countdown" mean on other surfaces.
2. B1: ask only about the estimate that sets the shown countdown, that is, require no later estimate with a greater `readyAt` that started before this one ended (or key the question on the chain's last link). Decide with P1, since both are about which records an answer is allowed to touch.
3. B3 with B1's predicate: record a Ready moment only from the clock tick that crosses `readyAt` while the app is open (`handleClockTick`), not from `publish`, and never for `readyAt` before `feedbackEligibleFrom`.
4. B4: add an entry (and a refresh date) at the stale cutoff in `CountdownTimeline`, using `RecoveryResolver.isStale`'s own formula so the two cannot drift.

## Test seams checked

Injected clocks: `RecoveryCalculator.estimate(now:)`, `RecoveryResolver.*(now:)`, `CountdownTimeline.entryDates(now:calendar:)`, `RecoverySnapshot.phase(at:)` (used). Defaults parameters: `RecoverySnapshotStore.*(defaults:)`, `KnownEntitlement.*(defaults:)`, `ConversionDiagnostics.defaultsOverride` (no claim needed them). `NSTimeZone.default` is settable and the pure date helpers take a `calendar`, but no time zone or day change claim survived. Constructed `CustomerInfo` fixtures: none exist, and `StoreService` and the RevenueCat package are not in the test target, so entitlement and purchase transitions are read from code only and no claim about them is counted. Notification scheduler: `NotificationService` is in the target but is a static enum over `UNUserNotificationCenter` with no fake; every scheduler call site is listed under M9 (all scheduling goes through `RecoveryEngine.publish()`, the one cancel outside it is `deleteLocalHealthData`). `RecoveryEngine`, `HealthKitService`, `PhoneWatchSession`, `ReviewPromptTracker`, `RechargeSettings` are outside the target.

Entitlement and money, specifically: the gate is `CustomerInfo.entitlements.active` non-empty (`StoreService.swift:125`), scoring falls back to the last recorded answer, conversion is recorded once. Nothing found that grants Pro without an active entitlement or withholds it from one in the shipping path; the only overrides are `#if DEBUG` and simulator.

## State machines

Notation: `I#` is an invariant of that machine. A transition row that breaks one names it and, where it is a counted bug, the bug id.

### M1. Setup and Health access

State lives in `RechargeSettings.hasCompletedSetup`, `hasDeferredHealthAccess` (App Group defaults), onboarding `@State` (`index`, `hasResolvedHealth`, `questions`, `isRequestingHealth`), and the system's own HealthKit prompt status (which the app cannot read for reads).

States: `fresh` (setup false), `onboarding-health-pending`, `onboarding-resolved` (flow frozen), `ready-connected` (setup true, deferred false), `ready-deferred` (setup true, deferred true).

Invariants:
- I1. `deferred == true` means the app is not reading Health (`RechargeSettings.swift:42-44`, "prevents the app from asking again ... offer reconnection").
- I2. Observers and background tasks run only for `setup && !deferred` (`App.swift:59`).
- I3. The step list is frozen once Health is resolved (`OnboardingView.swift:23-25` doc).

| From | Event | To | Notes |
|---|---|---|---|
| fresh | Health Continue, request succeeds | onboarding-resolved | `deferred=false`, import, `resolveHealth()` (`OnboardingView.swift:171-190`) |
| fresh | request throws | onboarding-resolved | `deferred=true` |
| onboarding-resolved | swipe back to Health page, Continue again | onboarding-resolved | `questions` recomputed from `gaps`, breaks I3 (minor, not counted) |
| onboarding-resolved | `finish()` | ready-connected or ready-deferred | `hasCompletedSetup=true`, trial cooldown stamped, notification prompt |
| ready-connected | Settings, Delete local health data | ready-deferred | sets `deferred=true` (`RecoveryEngine.swift:1016`) |
| ready-deferred | any HealthKit observer wake already installed in this process | ready-deferred with data re-imported | **breaks I1 (B2)** |
| ready-deferred | `BGAppRefreshTask` | ready-deferred with data re-imported | **breaks I1, I2 (B2)** `App.swift:124-136` has no guard |
| ready-deferred | Today or History Connect Health | ready-connected | `TodayView.swift:598-618` |

### M2. Health freshness

State: `RecoveryEngine.lastImportFailed`, `lastSuccessfulImport` (mirrored in App Group), `HealthDataState` in the snapshot (`current` or `stale`, 6 hour debounce, `RecoverySnapshot.swift:7-40`).

Invariants: I1. A failed read never blanks a countdown, it annotates. I2. `stale` only after 6 hours since the last success, or immediately when there was never a success. I3. `lastSuccessfulImport` advances only after the workout save and anchor commit.

| From | Event | To | Notes |
|---|---|---|---|
| current | workout query returns nil | current (phone line says failed) | `lastImportFailed=true`, glance surfaces still `current` for 6h |
| current | context import fails after workout import succeeded | current | phone line reads "Couldn't read Apple Health" although workouts imported (copy overstates, not counted) |
| any | delete local data | current, `lastSuccessfulImport=nil` | next failed read is `stale` at once |

### M3. Countdown phase (`RecoveryResolver`, `RecoverySnapshot.phase`)

States: `noRecentWorkout`, `recovering`, `readySoon` (under 2h), `ready`. Derived, never stored, from `readyAt`, `sessionEnd`, `now`.

Invariants:
- I1. The shown countdown is the active estimate with the latest `readyAt` (`RecoveryResolver.active`).
- I2. Past `max(sessionEnd+4d, readyAt+1d)` every surface says `noRecentWorkout` (`isStale`, one rule for Today, snapshot, widgets, Watch).
- I3. An `easy` or sub-threshold session never starts or shortens a countdown.
- I4. A session stacked inside a running countdown has a later `readyAt` than the session it stacks on (`stackedContribution`).

| From | Event | To | Notes |
|---|---|---|---|
| recovering | clock reaches `readyAt - 2h` | readySoon | timeline has a 15 minute entry cadence |
| readySoon | clock reaches `readyAt` | ready | entry at `readyAt` and `readyAt+60s` |
| ready | clock reaches the stale cutoff | noRecentWorkout | timeline has **no entry here**, relies on a 6 hour refresh, breaks I2 for the widget and complication (B4) |
| ready | new qualifying session | recovering | `publish()` reloads timelines |
| recovering (B stacked on A) | clock reaches A's own `readyAt` | recovering | A's estimate is expired while B's is running; `awaitingFeedback` treats A as ended, breaks I1 of M10 (B1) |

### M4. Estimate record freezing (`RecoveryStateRecord`)

States per session: `live` (`readyAt > now`), `frozen` (`readyAt <= now`, current model version, complete tier metadata), `thawed` (rescored because `unfreezeAll`, stale model version, or unresolved entitlement).

Invariants: I1. A frozen record keeps the numbers the user was shown (`RecoveryEngine.swift` rescore doc). I2. A model version bump thaws everything once. I3. Calibration does not reach back ("Calibration is deliberately not in that list").

| From | Event | To | Notes |
|---|---|---|---|
| frozen | `recordEffort`, `overrideIntensity`, `overrideProfile`, `rescoreAfterModelSettingChange`, `entitlementDidChange` | thawed, every record | all five pass `unfreezeAll: true`, including the per-session effort answer whose doc says it passes its own ID (product call P1) |
| frozen | `recordFeedback` | frozen | `rescore()` with no thaw, honours I3 |
| thawed | next rescore | frozen again once expired | thawed rows were rescored with the current `calibrationFactor` |

### M5. Entitlement and scoring tier (`StoreService`, `KnownEntitlement`)

State: `customerInfo` (nil until RevenueCat answers), `isPro`, `localProOverride` (debug and simulator), `KnownEntitlement.lastKnownIsPro` (App Group), `introEligibility`, `introEligibilityResolved`.

Invariants: I1. Screens gate on `isPro`, which RevenueCat alone decides (any active entitlement). I2. Background scoring uses `scoringIsPro`, which falls back to the last recorded answer until the process has its own. I3. Trial copy is shown only after eligibility resolved and only when eligible.

| From | Event | To | Notes |
|---|---|---|---|
| unresolved | RevenueCat answers free | resolved free | `KnownEntitlement.record(false)`, rescore only if build-10 records need it |
| unresolved | answers active | pro | `isPro` didSet runs `entitlementDidChange()` |
| pro | entitlement lapses | free | rescore with thaw, snapshot and Ready alert republished at the free tier |
| any | scene-less launch | `scoringIsPro` = last known | stale for a lapsed user until the app is opened (accepted in AGENTS.md) |
| any | fetch with `.fetchCurrent` fails offline | unchanged | `lastError` only; RevenueCat delegate replays cached info (not verified here) |

### M6. Purchase flow (`PaywallView`, `TrialOfferPage`, `StoreService.purchase`)

States: `idle`, `purchaseInFlight`, `purchased` (dismiss), `cancelled` (message), `pending` (Ask to Buy message), `failed` (message), `restoring`.

Invariants: I1. Conversion is recorded once, on the first entitled purchase. I2. The CTA is disabled while `purchaseInFlight`. I3. The copy never names a trial the user is ineligible for.

| From | Event | To | Notes |
|---|---|---|---|
| pending | approval arrives while the page is open | page stays, `isPro=true` | PaywallView dismisses only if `didPurchase` (`PaywallView.swift:139-141`); the Plus tab swaps itself, the onboarding and half-sheet pages keep showing a buy button (not counted, no double charge path found: Apple blocks a duplicate subscription, lifetime is the open case, see P7) |
| any | simulator | `purchased` | local override, no RevenueCat |

### M7. Interrupt arbitration (`RootView`)

State: `showWhatsNew`, `showTrialOffer`, `showPaywall`, `todayIsPresentingSheet`, `trailingPanel`, `settings.lastTrialOfferShownDate`, `lastWhatsNewVersionShown`.

Invariants: I1. At most one of What's New, review ask, trial offer fires per evaluation, in that order. I2. None fires while another sheet is up (`isPresentingSomething`). I3. Passive trial offer needs the 14 day cooldown, a resolved `customerInfo`, a loaded yearly package, and non-Pro.

| From | Event | To | Notes |
|---|---|---|---|
| idle | `evaluateTrialOffer` passes | offer shown | cooldown stamped **before** the sheet is known to have appeared (P6) |
| idle | Duo split, Settings open in trailing pane | pane open | `trailingPanelSheet` is nil while split so `isPresentingSomething` is false; review ask and trial offer can open over the pane (Duo only, not counted) |
| idle | two concurrent `requestReviewIfEligible` calls (launch task and Ready notification) | `requestReview()` twice | second call does not re-check eligibility after the sleep (`RootView.swift:307-320`); Apple throttles, not counted |

### M8. Review funnel (`ReviewPromptTracker`)

State (App Group): `appLaunchCount`, `firstAppOpenDate`, `readyMomentCount`, `seenReadySessions` (capped 200), `hasPendingReadyMoment`, `lastShownDate`, `softDefer`, `outcome`, `hasSeenEstimate`.

Invariants: I1. A Ready moment is a countdown the user watched run out (`ReviewPromptTracker.swift:19`). I2. Two Ready moments before the ask (`AGENTS.md:96`). I3. A session counts once.

| From | Event | To | Notes |
|---|---|---|---|
| count 0 | onboarding import publishes with history present | count 1, pending | `publish()` records `current` if its `readyAt <= now`, and `current` falls back to an expired estimate from weeks ago; breaks I1, I2 (B3) |
| count n | app opened after a countdown ended while closed | count n+1 | same predicate (`RecoveryEngine.swift:986`), the user did not watch it |
| any | more than 200 sessions seen | set truncated with `prefix(200)` on a `Set` | random members dropped, a later publish can re-count an old session (breaks I3 for heavy trainers, not counted) |
| pending | soft defer or markShown | cleared | `shouldShowForEngagedUse` is blocked while pending is true |

### M9. Ready notification

State: `notifyOnReady`, `hasRequestedReadyNotifications`, iOS authorization, one pending request `recharge.ready`, delivered notifications.

Invariants: I1. At most one pending request, equal to the shown countdown's `readyAt`. I2. No pending request when no countdown, when the toggle is off, or after data deletion. I3. The toggle shows when delivery is impossible (Settings banner).

Every scheduler call site: `RecoveryEngine.publish()` (`:978-981`), `RecoveryEngine.deleteLocalHealthData()` (`:1037` cancel), `RechargeApp.requestReadyNotificationsIfNeeded` and `OnboardingView.finish` and Settings toggle (all via `engine.publish()`).

| From | Event | To | Notes |
|---|---|---|---|
| none | publish with running countdown, toggle on | pending at `readyAt` | `UNTimeIntervalNotificationTrigger`, serial queue so order is preserved |
| pending | new session stacked | pending replaced | same identifier |
| pending | toggle off | none | `publish()` cancels; returns early if the last rescore failed to persist (`RecoveryEngine.swift:926-929`), rare |
| pending | delete local data | none | cancelled |
| none (after delete) | background refresh or observer re-imports | pending again | breaks I2 (B2) |
| pending | permission revoked in iOS Settings | none (iOS drops) | Settings banner reconciles on foreground |
| none | permission granted later | pending after the next `publish()` | foreground refresh is throttled 30 s, observers cover the gap |
| delivered | new workout starts a new countdown | delivered stays | stale "Ready" in Notification Center (P2) |

### M10. Readiness question (`RecoveryResolver.awaitingFeedback`)

State: `RecoveryEngine.awaitingFeedback`, `answeredFeedbackSessions`, `feedbackEligibleFrom`, `TodayView.feedbackTarget`.

Invariants: I1. Asked once a countdown expires, about the countdown the user saw (`EffortPromptSheet.swift:102`, "Your estimate after that run ran out."). I2. Not for sessions before setup. I3. Recharge+ only. I4. Once per session.

| From | Event | To | Notes |
|---|---|---|---|
| none | stacked A's own `readyAt` passes while B runs | A awaiting | **breaks I1 (B1)**; answer moves `calibrationFactor` by 0.95 or 1.05 |
| awaiting | Not now | none | marked answered |
| awaiting | answer | none | `recordFeedback` rescore, no thaw |
| any | delete local data | none, eligibility nil | window reopens at next cold launch |

### M11. Effort question (phone and Watch)

State: `awaitingEffort`, `declinedEffortSessions`, `pendingEffortSessionID` (phone App Group and Watch App Group), Watch `pendingQueue`.

Invariants: I1. Asked only for strength or mixed sessions whose load came from energy or duration, not already answered or overridden, ended under 2 days ago. I2. A decline is an answer on both devices. I3. The phone names the pending session, the Watch never infers it.

| From | Event | To | Notes |
|---|---|---|---|
| pending | Watch decline | local clear, message to phone | local clear can be undone by a snapshot already in flight (transient, not counted) |
| pending | answer on phone | none | `recordEffort` thaws everything (P1) |
| pending | answer for a deleted session | dropped | logged only |

### M12. Phone to Watch snapshot sync (`PhoneWatchSession`)

State: phone `activationState`, application context slot, FIFO `transferUserInfo`; Watch `lastAcceptedSentAt` high water mark, `lastSnapshotReceived`, `RecoverySnapshotStore` presence.

Invariants: I1. Late payloads are dropped by `sentAt` (not for the authoritative reply). I2. Absent key means `neverSynced`, empty snapshot means `noRecentWorkout`. I3. Every phone publish reaches the Watch.

| From | Event | To | Notes |
|---|---|---|---|
| any | `publish()` with Watch unpaired or session inactive | nothing sent | silent returns, republished at activation |
| any | delete local data | phone cleared, Watch unchanged | no `sendSnapshot` call (P4) |
| any | Watch launches and phone reachable | authoritative reply | clears the Watch app, not the complication until timelines reload |

### M13. Widget and complication timeline (`CountdownTimeline`)

Entries carry their own date; refresh policy `.after`. Running: hourly, 15 minute tail, entries at `readyAt` and `readyAt+60s`. Idle: one entry now, refresh in 6 hours. See M3 for the bad transition (B4).

### M14. Refresh coalescing (`RecoveryEngine.refresh`)

State: `runningRefresh`, `refreshAgain`, `isRefreshing`, `lastRefresh` (30 second throttle for non-forced), observer coalescing (`pendingRefreshTask`), `BGAppRefreshTask`, scene `.active` handler.

Invariants: I1. A forced caller is never answered by a refresh whose reads predate it. I2. Every entry point respects M1's I2.

| From | Event | To | Notes |
|---|---|---|---|
| idle | observer wake, BG task, scene active | refresh | only the scene handler checks `deferred` (`App.swift:229-232`); the other two do not (B2) |
| running | delete local data | delete completes, running refresh then re-inserts | in-flight race variant of B2 |

### M15. Duo layout (`RootView`)

State: `split` (derived from width and fold), `selectedTab`, `trailingPanel`, `TodayView.showSettings/showDetail`. Folding only moves frames, all three tabs stay mounted. Sheets move into the pane on unfold (`TodayView.swift:170-179`). No bad transition counted.

### M16. Local data deletion (`deleteLocalHealthData`)

Clears: workouts, states, daily context, Health-derived profile fields, feedback and effort sets, anchor, import stamps, snapshot, pending notification. Keeps: `calibrationFactor`, `manualWindows`, typed profile answers, review and trial state, the Watch's copy, delivered notifications (P3, P4). Sets `deferred=true`. Does not stop observers or the BG task (B2).
