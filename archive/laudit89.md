# Recharge user experience audit 89

Audit date: 2026-08-09

Scope: end-to-end user review of the iPhone app, Watch app, widgets, complications, onboarding, Health access, countdown, history, calibration, notifications, review prompts, subscriptions, accessibility, privacy, and failure states.

Build reviewed: commit `aa98fe1`, iOS 27 simulator, paired watchOS simulator, current source and test suite.

This report records findings only. No product code was changed.

## Audit method and limits

The review used the actual app flows available in simulator screenshot mode, live app navigation, paired phone-to-Watch transport, source inspection, and the existing automated tests.

Flows exercised:

- First launch, onboarding, deferred Health access, and trial offer.
- No-workout, recovering, and Ready Today states.
- History list, no-countdown detail, settings, and Health access controls.
- Paywall before and after scrolling.
- Extra-extra-extra-large Dynamic Type on onboarding and the trial offer.
- Standalone Watch recovering, Ready, and effort-entry states.
- Paired phone-to-Watch snapshot and pending-effort delivery.

Verification results:

- Pure model tests: 112 passed.
- UI tests: 7 passed.
- Generic watchOS simulator build: passed.
- Paired snapshot transport: passed after a noticeable cold-start delay.

Not verified end to end on physical hardware: real HealthKit permission combinations, actual RevenueCat purchases and restores, localized and purchasing-power-parity prices, notification delivery after suspension, background HealthKit delivery, widget refresh timing, and VoiceOver interaction. Findings dependent on those areas are marked as source-level or unverified risks.

## Severity

- P1: can block a core task, present stale or ambiguous health guidance, or undermine informed purchase consent.
- P2: material confusion, repeated friction, or a likely failure for a meaningful persona or edge state.
- P3: polish, consistency, or test coverage issue with a reasonable workaround.

## Executive result

The primary countdown flow is understandable once a current estimate exists, and the current phone-to-Watch snapshot path does work. The largest user-facing problems are concentrated around state freshness, permission ambiguity, purchase visibility, accessibility, and cross-device timing.

The highest priority findings are:

1. A workout older than four days can produce a contradictory Today screen, with a no-workout hero beside an old estimate and old reasons.
2. The Watch effort prompt's `Not now` action does not clear the pending session, so it can return on every launch.
3. The primary paywall purchase button is below or underneath the first phone viewport until the user discovers scrolling.
4. The trial page truncates feature, price, trial, and purchase labels at the largest Dynamic Type size.
5. Health access has no clear connected, denied, partial, or stale state, and query failures can leave old data looking current.
6. The Watch briefly shows `No recent workout` after launch even when the paired phone already has a current countdown.

No P0 blocker was found in the exercised simulator paths. The P1 findings still affect trust and completion of important user journeys.

## Findings

### A89-001, P1: stale estimates create a contradictory Today screen

Affected personas: returning users, people who take several days off, users who rely on the current screen as the authoritative state.

Evidence: confirmed by source inspection. [`RecoveryResolver.swift`](/Users/jackwallner/recovery/Shared/Utilities/RecoveryResolver.swift:22) returns the most recent estimate even when it is old. [`RecoveryResolver.swift`](/Users/jackwallner/recovery/Shared/Utilities/RecoveryResolver.swift:29) changes the phase to `noRecentWorkout` after four days. [`TodayView.swift`](/Users/jackwallner/recovery/Recharge/Views/TodayView.swift:35) still renders estimate content when the estimate produces a countdown.

Reproduction:

1. Have a qualifying workout that is more than four days old and still has a stored countdown estimate.
2. Open Today without importing a newer workout.
3. Observe the no-workout hero and its `Finish a workout` message.
4. Observe that the Why section can still show the old window, confidence, activity, and a relative time such as several days ago.

Impact: the user receives two different answers from the same screen. The hero says there is no recent workout, while the supporting cards imply that an old workout still controls the current state. This is especially risky for users returning from travel, illness, or a rest week. The old estimate should either remain consistently visible as historical context or be excluded from the active Today explanation.

Confidence: confirmed source-level bug. The exact visual combination depends on the stored estimate and its age.

### A89-002, P2: Watch `Not now` does not dismiss the pending effort request permanently

Affected personas: Watch-first users, users who are busy when the effort prompt appears, users who do not want to rate every workout.

Evidence: confirmed by source inspection and paired App Group state. [`WatchTodayView.swift`](/Users/jackwallner/recovery/RechargeWatch/Views/WatchTodayView.swift:59) sends effort only when the callback contains a value. [`WatchEffortPrompt`](/Users/jackwallner/recovery/RechargeWatch/Views/WatchTodayView.swift:193) calls `onSelect(nil)` for `Not now`. The parent does nothing with that nil value, so the pending session key is not cleared. During the paired run, `pendingEffortSessionID` remained set to `screenshot-0` after the phone delivered the request.

Reproduction:

1. Import a workout that asks for effort on the Watch.
2. Scroll to `Rate effort`, open the prompt, and tap `Not now`.
3. Close and reopen the Watch app.
4. The same effort request remains eligible and can return.

Impact: `Not now` reads as a postponement, but there is no visible explanation of when it will return and no durable dismissal choice. Repeated prompts make the Watch feel nagging and can cause users to disable the workflow instead of answering occasionally. A true skip, a snooze policy, or an explicit `Later` label is needed.

Confidence: confirmed source-level bug. Repetition across a full user session was not run because the current Watch prompt is below the first viewport.

### A89-003, P2: the floating iPhone tab bar covers meaningful content

Affected personas: all iPhone users, especially first-time users reading the disclaimer or users checking lower settings and history content.

Evidence: confirmed in runtime screenshots. The pinned bottom tab bar overlays the lower Today disclaimer, the lower part of the History list, the Training load section, and Settings rows such as calibration, Privacy, and Terms at common scroll positions. The views use fixed bottom padding, for example [`TodayView.swift`](/Users/jackwallner/recovery/Recharge/Views/TodayView.swift:35), but the visible safe area does not provide enough separation from the floating bar.

Impact: text appears cut off or visually hidden behind navigation. A user may assume the disclaimer is incomplete, miss the last history item, or fail to discover settings actions. This is a particularly poor first impression in the no-workout state because the first screen contains both a health explanation and a conversion card beneath the obscured region. Scrolling eventually reveals some content, but the overlay gives no cue that more content is hidden.

Confidence: confirmed runtime UX issue.

### A89-004, P1: Health access has no trustworthy status model

Affected personas: privacy-sensitive users, users who deny one category but allow another, users who defer access during onboarding, and users returning after changing Health permissions.

Evidence: confirmed source and runtime behavior. [`SettingsView.swift`](/Users/jackwallner/recovery/Recharge/Views/SettingsView.swift:86) offers `Connect Apple Health` when access is deferred and `Request Apple Health access` otherwise. There is no visible `Connected`, `Denied`, `Partially available`, or `Open Health Settings` state. [`HealthKitService.swift`](/Users/jackwallner/recovery/Shared/Services/HealthKitService.swift:66) requests read-only access with an empty write set, so the app cannot use the request result as proof that any individual read category was granted. [`SettingsView.swift`](/Users/jackwallner/recovery/Recharge/Views/SettingsView.swift:113) reports `Request complete`, which sounds positive even when useful read data remains unavailable.

Impact: users cannot answer the basic question, “Is Recharge connected and working?” A denial and a successful request can look the same. A user who grants workouts but denies sleep or HRV gets no explanation of which confidence or context features will be missing. The footer points to Health settings, but it does not turn the ambiguous button into an actionable recovery path.

Confidence: confirmed source-level UX gap. Exact HealthKit authorization combinations require a physical device or a working HealthKit test setup.

### A89-005, P1: HealthKit refresh errors can leave old data looking current

Affected personas: users who revoke access, users with HealthKit temporarily unavailable, users whose watch or phone has not finished writing a workout, and users who expect a new workout to appear immediately.

Evidence: source inspection. [`HealthKitService.swift`](/Users/jackwallner/recovery/Shared/Services/HealthKitService.swift:134) returns no workout result when the query fails and logs the error. The refresh path then has no user-visible failure state or freshness timestamp. The Today and Settings screens do not expose `lastRefresh` or a stale-data warning.

Impact: the screen can continue to show the previous countdown and history while the user believes the new refresh succeeded. This is more dangerous than an explicit error because a quiet stale estimate looks authoritative. It also makes support reports difficult: “I opened the app” and “the app successfully imported my workout” are visually indistinguishable.

Confidence: confirmed source-level risk. Simulator coverage did not reproduce a real HealthKit query failure.

### A89-006, P1: the trial page is not usable at the largest Dynamic Type size

Affected personas: low-vision users, older users, users who depend on accessibility text sizes, and anyone reviewing a purchase on a small phone.

Evidence: confirmed runtime screenshot at `accessibility-extra-extra-extra-large`. The headline rendered as `Try Rechar...`; feature labels were shortened; the price and trial note were truncated; the primary button rendered as `Continue wit...`. [`TrialOfferPage.swift`](/Users/jackwallner/recovery/Recharge/Views/TrialOfferPage.swift:19) uses a fixed vertical stack without a scroll container or a Dynamic Type layout strategy.

Impact: the user cannot read what is included, the price, the trial duration, or the action that starts the offer. This is an informed-consent failure in the purchase flow, not just a cosmetic layout defect. The page remains tappable, but the user has to buy without being able to inspect the terms or guess which ellipsized control is the purchase action.

Confidence: confirmed runtime issue.

### A89-007, P2: large text also collides with pinned onboarding actions

Affected personas: accessibility users and first-time users reading the Health or honesty explanations.

Evidence: confirmed runtime screenshot. On the welcome page at the largest Dynamic Type size, the explanatory copy extends below and behind the pinned `Continue` button. [`OnboardingView.swift`](/Users/jackwallner/recovery/Recharge/Views/OnboardingView.swift:167) puts the content in a scroll area, but the initial viewport still presents the copy as clipped by the fixed action area.

Impact: a user can scroll, but the first frame makes the explanation look cut off and requires discovering an otherwise invisible interaction before continuing. This is especially confusing when the text explains Health data handling and the app's non-medical positioning.

Confidence: confirmed runtime issue.

### A89-008, P1: the primary paywall action is below the first viewport

Affected personas: free users evaluating Pro, users on smaller phones, and users who reach the paywall from a card rather than onboarding.

Evidence: confirmed runtime screenshot. On first presentation, the hero, feature list, and plan cards occupy the sheet. The blue `Continue with Recharge Pro` button is only visible as a thin sliver beneath the bottom safe area and floating navigation. After an intentional upward swipe, the full button and purchase disclosure become visible. [`PaywallView.swift`](/Users/jackwallner/recovery/Recharge/Views/PaywallView.swift:60) places the CTA after the plans inside one scroll view.

Impact: the user can see prices and plan choices but not the action needed to continue. There is no visible cue that the sheet scrolls, so the paywall initially looks broken or unfinished. A purchase flow should make its next action obvious without requiring trial-and-error scrolling.

Confidence: confirmed runtime issue.

### A89-009, P1: purchase terms are technically present but weak at the decision point

Affected personas: all purchasers, especially users comparing monthly, yearly, and lifetime plans or users who are cautious about recurring billing.

Evidence: confirmed in the paywall. Plan cards use `7-day free trial included` and `Cancel anytime`. The more precise auto-renewal disclosure, including the 24-hour cancellation deadline, is rendered later in small tertiary text in [`PaywallView.swift`](/Users/jackwallner/recovery/Recharge/Views/PaywallView.swift:273). It is below the plan cards and was not visible until scrolling. The CTA says `Continue with Recharge Pro`, not that it starts a trial which converts to a subscription.

Impact: the first scan communicates “cancel anytime” more strongly than it communicates the renewal timing. The copy may be legally sufficient when all of it is read, but it is not well arranged for informed choice. A user can select a recurring plan without seeing the most important billing condition at the point of action.

Confidence: confirmed runtime and source-level UX issue.

### A89-010, P1: the purchase flow has a silent missing-product state

Affected personas: users with slow connectivity, StoreKit or RevenueCat delays, regional catalogue issues, and users opening the trial offer before products finish loading.

Evidence: source inspection. [`TrialOfferPage.swift`](/Users/jackwallner/recovery/Recharge/Views/TrialOfferPage.swift:51) only renders price content when a package exists. When it does not, there is no visible loading label, error, retry action, or explanation. The CTA is disabled in that state in [`TrialOfferPage.swift`](/Users/jackwallner/recovery/Recharge/Views/TrialOfferPage.swift:67).

Impact: the user sees an incomplete offer and a dead button, with no indication whether to wait, retry, check connectivity, or leave the screen. This is likely to be reported as “the app does not work” and can strand a user who has already decided to subscribe.

Confidence: confirmed source-level issue. The screenshot fixture masks this state, and real catalogue timing was not available in simulator.

### A89-011, P2: no-countdown history rows look like missing data

Affected personas: runners, walkers, lifting users, and free users reviewing why a workout did not start a countdown.

Evidence: confirmed runtime on the Walk row. The list displays the workout category and a dash in the recovery column. The detail sheet later explains `No countdown`, the `Easy` classification, and the reasons. [`HistoryView.swift`](/Users/jackwallner/recovery/Recharge/Views/HistoryView.swift:134) does not expose that explanation in the list row.

Impact: a dash commonly means unavailable, not applicable, or failed calculation. The user has to guess that it means “this session intentionally had no countdown” and open the row to learn why. This is particularly confusing after a user deliberately checks a walk or easy session to see whether it was imported.

Confidence: confirmed runtime issue.

### A89-012, P2: the model's no-countdown threshold is not explained to strength and hybrid users

Affected personas: lifters, HYROX and CrossFit users, interval users with sparse heart-rate coverage, and users whose perceived effort is high but whose measured load is below the countdown floor.

Evidence: source inspection. [`RecoveryCalculator.swift`](/Users/jackwallner/recovery/Shared/Utilities/RecoveryCalculator.swift:16) applies an absolute load floor. Easy or non-qualifying sessions can return zero hours in [`RecoveryCalculator.swift`](/Users/jackwallner/recovery/Shared/Utilities/RecoveryCalculator.swift:74). The visible fallback is generally a Ready state or a no-countdown history value, with the explanation available only after navigating into detail.

Impact: a user can complete a long lift or mixed session and reasonably expect a countdown, then see Ready or a dash. The app does not explain that heart-rate coverage, energy, effort, duration, and the personal baseline interact, so the user may conclude that the workout was lost or misclassified. This is a product-model expectation problem, not necessarily a calculation defect.

Confidence: confirmed source-level UX gap. The exact session classification varies with fixture data.

### A89-013, P1: Ready language can be read as training clearance

Affected personas: users who interpret health products literally, users returning from injury or illness, older users, and users viewing only a widget, complication, or notification.

Evidence: the iPhone and Watch Today views use `Ready for another hard session`. The notification body uses the same style of wording in [`NotificationService.swift`](/Users/jackwallner/recovery/Shared/Services/NotificationService.swift:57). The Watch complication separately uses `Ready to train` in [`WatchComplication.swift`](/Users/jackwallner/recovery/RechargeWatchWidget/WatchComplication.swift:110). The app describes the output as a training estimate, but the shortest surfaces omit that qualifier.

Impact: the word Ready is stronger than the underlying estimate. A glance user may treat it as a clearance to train hard, even though the model is based on available cardiovascular and context data and does not assess injury, illness, or overall safety. The copy is also inconsistent across Today, notification, widget, and complication surfaces.

Confidence: confirmed copy inconsistency and interpretation risk. This is not a claim that the current strings violate the existing compliance tests.

### A89-014, P2: Watch cold start shows a false empty state before syncing

Affected personas: Watch-first users, users checking a complication immediately after waking, and users who leave the phone at home.

Evidence: confirmed in the paired simulator. After launching the current phone and Watch apps, the Watch initially showed `No recent workout` and `Open Recharge on your iPhone to sync`. Roughly 30 seconds later it updated to the current countdown and Ready time from the phone. The phone already had the current snapshot during the initial Watch state.

Impact: the first screen looks like the app has lost its data, even though transport is working. A user may open the phone, repeat a workout, or assume the Watch app is unreliable. The connection note helps, but it is shown alongside an empty state rather than a clear syncing state.

Confidence: confirmed paired runtime issue. The delay depends on simulator scheduling and may differ on hardware.

### A89-015, P2: the Watch effort action is hidden below the first viewport

Affected personas: users who receive an effort request, users with smaller Watch screens, and users who expect a prompt to appear automatically.

Evidence: confirmed source and runtime layout. [`WatchTodayView.swift`](/Users/jackwallner/recovery/RechargeWatch/Views/WatchTodayView.swift:128) places `Rate effort` after the ring and recovery details in a scroll view. The initial Watch viewport showed only the countdown or Ready content. The `watchEffort` screenshot scene also did not present a modal automatically; the user must find and tap the button.

Impact: the most important Watch-to-phone action is discoverable only by scrolling. A user can open the Watch specifically to answer the request, see a normal countdown, and leave without realizing an action is waiting below. The app should surface a pending request as a prominent state or present it when appropriate.

Confidence: confirmed source and runtime issue.

### A89-016, P2: Watch pairing and sync health are not visible on the phone

Affected personas: users who install the iPhone app but not the Watch app, users with an unpaired Watch, users with a disabled WatchConnectivity session, and users relying on complications.

Evidence: [`PhoneWatchSession.swift`](/Users/jackwallner/recovery/Shared/Services/PhoneWatchSession.swift:262) silently returns when WatchConnectivity is unsupported, inactive, unpaired, or missing the Watch app. The phone UI has no Watch status row, last-sent timestamp, or action to diagnose the connection. The Watch has a connection note, but the phone is the source of truth and gives no indication that the Watch may be stale.

Impact: the iPhone can look healthy while the wrist surface is outdated. Users cannot tell whether they need to install the Watch app, open it, keep the phone nearby, or wait for transport. This is also a supportability gap because the app cannot distinguish “no workout” from “no Watch sync.”

Confidence: confirmed source-level UX gap.

### A89-017, P2: notification enablement has no explanation when there is nothing to schedule

Affected personas: users enabling notifications close to the Ready time, users who have already become Ready, and users troubleshooting why no alert arrived.

Evidence: [`NotificationService.swift`](/Users/jackwallner/recovery/Shared/Services/NotificationService.swift:48) cancels the pending notification when the Ready time is less than about one minute away. The Settings toggle does not explain that the request was intentionally not scheduled.

Impact: the toggle can appear enabled while no notification exists. The user has no way to distinguish “notification permission denied,” “the notification was scheduled,” and “the estimate was too close to Ready to schedule.” The next estimate may work, but the current action feels unreliable.

Confidence: confirmed source-level UX gap.

### A89-018, P2: readiness feedback and review prompts can compete

Affected personas: engaged users who reach Ready repeatedly and users who are asked for feedback while also seeing a review request.

Evidence: [`TodayView.swift`] triggers a readiness feedback sheet when an expired estimate is awaiting feedback. [`ReviewPromptTracker.swift`] posts a positive Ready moment, and [`RootView.swift`] can show a review prompt after the second Ready moment. These flows have separate presentation state and no explicit arbitration.

Impact: at the same transition, the user may receive two competing sheets or see the review request before answering the product feedback question. Either outcome interrupts the meaning of Ready and makes the review ask feel opportunistic. This was not reproduced in the current seeded scene, so the finding is a source-level risk.

Confidence: unverified source-level risk.

### A89-019, P2: skipped onboarding trial has no visible passive re-entry path

Affected personas: users who tap `Not now` during onboarding, users who want to use the free countdown before deciding, and users who later want to reconsider Pro.

Evidence: [`TrialOfferPage.swift`](/Users/jackwallner/recovery/Recharge/Views/TrialOfferPage.swift:134) defines a passive trial sheet, and [`RechargeSettings.swift`](/Users/jackwallner/recovery/Shared/Services/RechargeSettings.swift:132) defines a cooldown helper. A source search found no active call site presenting that sheet. The later route is the full paywall from Pro cards or settings.

Impact: `Not now` appears to mean “I will decide later,” but the app does not visibly offer the same simple trial again. Users may forget where the offer went, or interpret the later Pro card as a different or more expensive proposition. The free core countdown should remain clearly available while the trial offer has a deliberate, discoverable re-entry path.

Confidence: confirmed source-level product-flow gap.

### A89-020, P2: no-workout users see monetization before they see a working result

Affected personas: new users who defer Health access, users who have not completed a qualifying workout, and privacy-sensitive users deciding whether the app is worth connecting.

Evidence: the no-workout Today state shows both the Health connection card and the Body signals Pro card. The runtime screenshot showed `Connect Apple Health` followed by the Pro conversion card while the core area still said `No workout yet`. The onboarding and trial copy do not prominently state that the basic countdown remains usable without Pro.

Impact: the user has not yet experienced the core value but is already asked to connect data and consider a subscription. This creates a paywall impression and can make a deferred-permission user believe the app is unusable without purchase. The sequence is especially weak for a privacy-sensitive user who needs a reason to grant access first.

Confidence: confirmed runtime and source-level UX issue.

### A89-021, P2: Health permission copy implies write access in a read-only app

Affected personas: privacy-sensitive users and users who inspect the system authorization prompt before granting access.

Evidence: [`Info.plist`](/Users/jackwallner/recovery/Recharge/Info.plist:38) includes `NSHealthUpdateUsageDescription` with text explaining that the app does not write data. The app service requests an empty write set in [`HealthKitService.swift`](/Users/jackwallner/recovery/Shared/Services/HealthKitService.swift:66). The system HealthKit prompt can therefore present access and update wording even though the product's architecture is read-only.

Impact: the user may think Recharge can modify Health data, which conflicts with the in-app privacy explanation and undermines trust at the exact moment consent is requested. The explanatory text attempts to correct this, but the permission surface itself should not raise the concern.

Confidence: source-confirmed. The exact system prompt wording varies by OS version; the prior audit observed the access-and-update wording and the current plist still contains the condition.

### A89-022, P2: the privacy policy and current HealthKit read set do not match

Affected personas: privacy-conscious users, reviewers, and users comparing the app's stated data practices with the Health permission sheet.

Evidence: [`docs/privacy-policy.html`](/Users/jackwallner/recovery/docs/privacy-policy.html:12) says the app reads cardio fitness. The current [`HealthKitService.swift`](/Users/jackwallner/recovery/Shared/Services/HealthKitService.swift:31) read set covers workouts, heart rate, resting heart rate, HRV, active energy, and sleep, but not cardio fitness/VO2 max.

Impact: the policy appears broader than the current implementation. Even if the data is not actually requested, the mismatch makes it harder for users to understand what they are consenting to and can create review or support questions.

Confidence: confirmed source mismatch.

### A89-023, P2: fixed-height sheets have an unverified Dynamic Type risk

Affected personas: accessibility users who receive an effort prompt, readiness feedback, or review request.

Evidence: [`EffortPromptSheet.swift`](/Users/jackwallner/recovery/Recharge/Views/EffortPromptSheet.swift:1), the readiness feedback sheet, and [`ReviewPromptSheet.swift`](/Users/jackwallner/recovery/Recharge/Views/ReviewPromptSheet.swift:1) use compact fixed vertical layouts and medium presentation detents without an equivalent scroll strategy. The trial page confirmed that this layout pattern truncates important text at the largest text size.

Impact: prompt actions, explanatory text, or the dismiss control may collide or fall below the detent for users who need larger text. Because these sheets are event-driven, a user can be interrupted by a screen they cannot comfortably read or dismiss. The exact clipping needs a device-level accessibility pass.

Confidence: unverified runtime risk, supported by the confirmed trial-page failure.

### A89-024, P2: the app has no visible import freshness feedback after a workout

Affected personas: runners and lifters who finish a workout and immediately open Recharge, and users whose phone and Watch are not nearby.

Evidence: the phone refreshes in the app lifecycle and exposes pull-to-refresh, but `RecoveryEngine.lastRefresh` is not shown in Today or Settings. There is no `Importing`, `Last updated`, or `Waiting for Health` state. The paired Watch also relies on the same snapshot without exposing its age on the phone.

Impact: after a workout, users cannot tell whether they should wait, pull to refresh, reopen the Health app, or troubleshoot permissions. The lack of a timestamp makes the stale-data risk in A89-005 harder to detect and makes a successful import feel random.

Confidence: confirmed source-level UX gap.

### A89-025, P3: the same readiness concept has too many short labels

Affected personas: glance users who move between iPhone, Watch, widgets, complications, notifications, and history.

Evidence: current surfaces use `Ready`, `Ready for another hard session`, `Ready to train`, `No countdown`, a dash in History, and `After your ...` in the complication. These labels represent related states but do not share a clear hierarchy between estimate expiry, no-countdown classification, and permission/data absence.

Impact: users can interpret `Ready` as a completed countdown, a no-countdown session, or a health clearance depending on the surface. The full Today screen explains more, but a widget or complication has no room to resolve the ambiguity. A compact state vocabulary would reduce cross-surface confusion.

Confidence: confirmed copy inconsistency.

## Persona and journey coverage

### New user

The onboarding sequence is understandable at normal text size and the Health request race appears guarded in the current source. The major new-user risks are the clipped large-text welcome page, the immediate Pro card before a first result, ambiguous Health status, and the dead-product state if the catalogue is still loading.

### Deferred or privacy-sensitive user

The app gives a clear way to defer Health access, but after deferral it does not explain what works without Health data, does not show a durable connection state, and still places conversion content near the empty core state. The permission copy and privacy-policy mismatch further weaken trust.

### Runner or cyclist

The current countdown and Why card are easy to understand when data is current. The main risks are stale estimates, no import freshness indicator, and Ready wording that can sound like clearance rather than an estimate.

### Strength, HYROX, or CrossFit user

The model has explicit profiles and fallbacks, but the UI does not explain sparse heart-rate coverage, effort fallback, or the no-countdown floor. These users are more likely to perceive a mismatch between how hard a session felt and the displayed result.

### Easy-day or active-recovery user

The model intentionally avoids starting a countdown for easy sessions. The UI should make that an affirmative classification rather than a missing value. The current History dash and Ready state require the user to open detail to understand the decision.

### Returning user after several days away

This persona is exposed to A89-001. The phase logic correctly identifies no recent activity in one place, but the supporting estimate logic can continue showing old active context.

### Free user considering Pro

The core Pro value is visible, but the first paywall viewport hides the primary action and the terms are low prominence. A user who skips the onboarding trial has no obvious passive re-entry path.

### Existing subscriber

The app has a visible restore action and entitlement changes trigger a rescore path in the current source. Real device restore, entitlement timing, and localized pricing were not verified. The user-facing risk is still that a catalogue or connectivity failure presents as a dead button without recovery instructions.

### Watch-first user

The current phone-to-Watch path eventually delivers the snapshot, but the cold-start empty state is misleading. The effort action is below the first viewport, `Not now` does not clear the pending request, and the phone offers no pairing or last-sync diagnosis.

### Widget and complication user

These surfaces are concise and useful for a current snapshot, but they have the highest risk of the Ready wording being read as clearance. They also cannot explain stale data, no-countdown classification, or a permission problem without a compact freshness/status cue.

### Accessibility user

The largest Dynamic Type test found a confirmed purchase-flow failure. Fixed sheets and pinned actions are additional risks. VoiceOver, Switch Control, reduced motion, contrast, and hardware accessibility interaction remain unverified.

### Offline or service-failure user

The purchase path has a silent missing-product state. Health refresh failures have no user-facing error or timestamp. Notification scheduling has no explanation when a notification is intentionally not created. These states need explicit recovery language rather than an unchanged screen.

## Existing coverage gaps

The passing tests provide useful model and basic screen coverage, but they do not currently assert the highest-risk user behaviors:

- No test for an estimate older than four days alongside the Today phase.
- No test for Health access denied, partial access, revoked access, or HealthKit query failure.
- No test for import freshness, delayed Health delivery, or a stale snapshot.
- No test for Watch cold start, pending effort, `Not now`, or pairing failure.
- No test for widgets or complications under stale, no-countdown, or no-workout states.
- No test at any Dynamic Type size.
- No test that the paywall CTA is visible without scrolling or that purchase terms are legible at the action point.
- No test for product loading, missing products, purchase failure, or restore failure on device.
- No test for notification scheduling near the Ready boundary.
- No test for competing readiness feedback and review sheets.

## Prior audit recheck

The earlier audit's major phone-to-Watch delivery blocker is not present in the current paired run. The snapshot arrived and the Watch eventually showed the phone's countdown. The remaining issue is the cold-start delay and the absence of a visible sync state.

The current build also shows that the history list contains persisted past sessions and that the Walk detail explains a no-countdown decision. Those improvements reduce, but do not remove, the list-level ambiguity and the stale Today inconsistency documented above.
