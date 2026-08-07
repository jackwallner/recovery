# Recharge super audit 86

Audit date: 2026-08-06, America/Los_Angeles
Audit mode: user-perspective review only. No app code was changed.

## Executive result

The iPhone experience is visually coherent at the default text size, and the
core countdown, history, paywall, settings, and onboarding surfaces are
present. The Watch experience has a release-blocking data path failure in the
headless paired run: the phone showed a live 18h 43m countdown, while the Watch
launched without screenshot fixtures and showed No recent workout. There is no
phone-to-Watch snapshot transport in the source. The only WatchConnectivity
write path is Watch effort input going back to the phone.

The other immediate release risks are:

1. The Watch and Watch complication cannot reliably receive the phone-owned
   model.
2. Accessibility Dynamic Type at the largest available size truncates
   onboarding copy and overflows the Today hero.
3. A Health permission request can remain on Requesting, while Not now remains
   active and a delayed system sheet appears after the user has moved on.
4. The floating tab bar covers the initial Today and History content, including
   the Pro CTA and safety disclaimer.
5. Pro activation, Restore, and several settings changes do not trigger a
   rescore and republish.
6. Historical estimates are silently recomputed, so the app does not preserve
   what it previously told the user.
7. The documented watchEffort screenshot scene does not expose Rate effort.
8. The medium iOS widget renders the word “Ready” inside the ring for the
   no-workout state, which is misleading empty-state behavior.

## Scope and evidence

I reviewed the repository, the app guide, every SwiftUI screen, the shared
model and data services, widgets, Watch complication families, notification
and purchase paths, privacy and support copy, and the existing tests.

Runtime inspection used only the leased headless simulator pair:

- iPhone: agent-sim-7, iOS 26.5, UDID
  978FE567-2056-428F-965D-D9F6A90F04B6.
- Watch: agent-sim-8, watchOS 26.5, Apple Watch Series 11 46 mm, UDID
  BCDBFB27-A122-4644-9878-D8451BA793F6.
- Simulator UI was kept closed. Screenshots came from the headless bridge or
  simctl image output. Accessibility inspection used the headless accessibility
  tree and the axe fallback when the bridge snapshot was unavailable.
- iPhone scenes inspected: recovering, ready, history, settings, paywall,
  premiumActive, onboarding, and the normal no-workout state.
- Watch scenes inspected: watchRecovering, watchReady, watchEffort, and a
  normal Watch launch after the phone had a live screenshot fixture.
- The paired data-path check was done without Watch screenshot mode. The phone
  had a real screenshot-mode snapshot, but the Watch still showed No recent
  workout.
- Default light mode, dark mode, and the largest available Dynamic Type size
  were inspected.

Verification completed:

- 110 of 110 pure logic tests passed.
- 7 of 7 iOS UI tests passed.
- The UI test build emitted 51 Swift 6 main-actor warnings in
  RechargeUITests. These do not fail today, but the test suite is warning
  rather than clean.
- No Watch UI tests, widget render tests, notification tests, deletion tests,
  permission-denial tests, or accessibility-size tests exist.
- The working tree was clean before this audit and the only intended change is
  this report.

This audit does not claim real-device verification of HealthKit, RevenueCat,
localized price formatting, Apple notification delivery, WatchConnectivity
delivery, App Store links, or subscription renewal behavior. Those are called
out explicitly where they matter.

## Severity

- P0: release blocker or core promise is unavailable.
- P1: high-impact correctness, trust, accessibility, purchase, or recovery
  path issue.
- P2: meaningful friction, ambiguity, polish, or coverage gap.
- P3: minor inconsistency or future hardening.

## Release-blocking findings

### A86-001, P0: the Watch has no verified phone-to-Watch model transport

Affected users: every Watch-first user, every Watch face user, every user who
expects the countdown on the wrist.

Reproduction:

1. Launch the iPhone with screenshot scene recovering. The phone shows a live
   countdown and writes its snapshot through RecoverySnapshotStore.
2. Launch the Watch without screenshot mode.
3. The Watch shows a gray empty ring and No recent workout.

The source confirms the mismatch:

- RecoveryEngine.publish writes RecoverySnapshot to the phone App Group and
  reloads WidgetKit timelines.
- WatchTodayView.currentSnapshot reads the same suite locally on the Watch.
- PhoneWatchSession only sends effort answers from Watch to phone.
- There is no updateApplicationContext, phone-to-Watch sendMessage,
  phone-to-Watch transferUserInfo, or other snapshot handoff.
- RechargeWatchWidget reads the Watch-side snapshot as well.

The headless paired run observed the failure directly. This is not just a
screenshot fixture limitation. A real user can finish a workout on the phone
and still see an empty Watch. The Watch complication will have the same
problem, because it reads the same local snapshot and has no phone refresh
channel.

The effort path is implemented in the reverse direction, but the user cannot
reach a useful effort prompt on a Watch that does not know the current workout
or pending effort session. Treat the entire Watch product surface as
unverified until a real phone-to-Watch synchronization path is demonstrated on
the paired devices.

Relevant source: Shared/Services/RecoveryEngine.swift around publish,
Shared/Services/PhoneWatchSession.swift, RechargeWatch/Views/WatchTodayView.swift,
and RechargeWatchWidget/WatchComplication.swift.

### A86-002, P0: largest Dynamic Type size breaks onboarding and Today

Affected users: low-vision users, older users, anyone with accessibility text
enabled.

Runtime evidence at accessibility-extra-extra-extra-large:

- Onboarding page 1 changed the title to a clipped phrase ending in
  “on the wat...”.
- The body message was clipped with ellipses after several lines.
- The button remained very large, but the explanatory content was not
  scrollable and could not be read.
- Today expanded the remaining number, Ready line, confidence line, and Why
  card beyond the initial viewport. The Why content was visibly under the
  tab bar and the hero/card composition no longer read as a finished frame.

The onboarding pages use fixed vertical spacers and a non-scrolling VStack.
Today uses a ScrollView, but its hero has a fixed ring frame with large text
inside and the overall composition is not designed for the largest content
category. Text does not have a deliberate accessibility layout variant.

This is a functional accessibility failure, not merely a screenshot
difference. The primary onboarding explanation can be lost before the user
connects Health, and the Today answer becomes difficult to read or operate.

Relevant source: Recharge/Views/OnboardingView.swift and
Recharge/Views/TodayView.swift.

### A86-003, P1: Health permission request can race with Not now

Affected users: new users on a fresh install, especially users on a slow
HealthKit or simulator prompt.

Observed sequence:

1. Tap Connect Apple Health.
2. The screen stayed on Requesting for more than eight seconds.
3. Not now remained active.
4. Tap Not now. The app advanced to the honesty page.
5. The delayed Health Access sheet appeared over the next page.
6. The system sheet said the app wanted to access and update Health data,
   despite the app requesting read-only access.
7. After dismissal, the app continued with onboarding.

Problems:

- The request state has no cancellation or timeout.
- The secondary Not now action is not disabled while the request is pending.
- The async completion always sets page = 2, even if the user has navigated
  away by another action.
- A refusal sets healthError, then immediately advances away from the page
  containing that footnote. The user does not reliably see the explanation.
- After onboarding, Settings has no in-app Health access status or Connect
  Apple Health action.
- On subsequent launches App.swift calls synchronizeAuthorization, which can
  prompt again when the user thought Not now was a deferral.

The generic system wording also weakens the trust promise that the app never
writes Health data. The app requests toShare: [], but the visible system
phrase says access and update.

Relevant source: Recharge/Views/OnboardingView.swift,
Recharge/App.swift, Shared/Services/HealthKitService.swift, and
Recharge/Info.plist.

### A86-004, P1: floating tab bar covers content at the first scroll position

Affected users: every iPhone user, most visibly free users and Pro users on
Today and History.

The content adds 72 points of bottom padding, but the floating tab bar and blur
still overlap the initial frame. In the recovering and ready screenshots:

- The blue Continue with Recharge Pro button sits partly under the tab bar.
- The bottom of the Body signals card is obscured.
- The compliance disclaimer is almost invisible under the tab bar at the
  initial scroll position.
- In History, the first lower row is clipped by the tab bar.
- In Pro Today, the Training load card is initially covered.

Scrolling to the bottom exposes the content, so this is easy to miss in a
manual happy-path pass. A user should not have to discover a scroll gesture to
read a purchase CTA or the safety disclaimer. The UI test only asserts that
the disclaimer exists in the accessibility tree, not that it is visible and
uncovered in the initial state.

Relevant source: Recharge/Views/TodayView.swift and
Recharge/Views/HistoryView.swift.

### A86-005, P1: Pro activation does not rescore and republish

Affected users: new subscribers, restored subscribers, and users whose
entitlement arrives after the first launch refresh.

App startup starts StoreService tasks and RecoveryEngine.refresh separately.
RecoveryEngine.rescore includes sleep, HRV, and resting heart rate only when
StoreService.shared.isPro is already true. A later entitlement update changes
StoreService.isPro, but there is no automatic engine rescore and publish from
that state change.

The same gap exists after:

- a simulator or real purchase,
- a RevenueCat entitlement callback,
- Restore purchases,
- a subscription becoming active after startup.

The phone may show the Pro Body signals UI immediately while the estimate and
the App Group snapshot were calculated as free. The Watch and widgets can
therefore retain a free snapshot after a successful purchase. The user has no
explanation for why the paid signal is not reflected until a manual refresh or
another lifecycle event.

Relevant source: Shared/Services/StoreService.swift,
Shared/Services/RecoveryEngine.swift, and Recharge/App.swift.

### A86-006, P1: settings changes silently leave the model stale

Affected users: HYROX and CrossFit users, users with a known maximum heart
rate, and anyone correcting a model assumption.

The Model settings expose:

- HYROX and CrossFit profile: Mixed, Strength, or Endurance.
- Max heart rate: Auto or a number.

The setters persist values, but SettingsView does not rescore and publish when
either value changes. Existing WorkoutRecord values are not reclassified by
the ambiguous profile setting during a settings edit. The max heart rate is
also not applied to the current estimate until some later rescore.

The max heart rate field has an additional silent failure:

- The field accepts visible text such as 119 or 250.
- The setter stores zero unless the parsed value is between 120 and 230.
- The UI leaves the rejected number visible and gives no error or “using Auto”
  indication.

A user can therefore read 250 bpm in Settings while the model quietly uses its
default maximum. The visible preference and actual calculation disagree.

Relevant source: Recharge/Views/SettingsView.swift and
Shared/Services/RechargeSettings.swift.

### A86-007, P1: history is rewritten instead of preserving what was told

Affected users: anyone reviewing an old estimate, giving readiness feedback,
changing settings, receiving new context data, or installing a new model
version.

RecoveryStateRecord comments say it preserves the estimate the app actually
told the user. RecoveryEngine.rescore instead fetches every stored workout and
updates every state record:

- calculatedAt becomes the current rescore time.
- readyAt, hours, window, category, confidence, reasons, load, and relative
  load are recalculated.
- modelVersion is replaced with the current version.
- Current calibration and current context are applied to old sessions.

The history screen can therefore change yesterday's estimate after today's
feedback or after a new Health context import. A future model version cannot
explain a prior result because the old result has already been overwritten.
The product promise of transparent history and model versioning is not met.

This also makes readiness feedback look more powerful than the UI explains:
one answer can rewrite all historical windows, not only future personal bands.

Relevant source: Shared/Services/RecoveryEngine.swift and
Shared/Models/RecoveryRecords.swift.

### A86-008, P1: the documented watchEffort scene is not wired

Affected users: Watch effort users, App Store screenshot reviewers, and anyone
trying to QA the Watch write-back flow.

ScreenshotConfig defines watchEffort and wantsEffortPrompt. WatchTodayView
does not use wantsEffortPrompt. It renders Rate effort only when the App Group
contains pendingEffortSessionID.

The headless watchEffort launch showed the normal recovering screen with no
Rate effort button. This scene therefore cannot prove the feature it was
created to capture. A manually seeded pending ID also did not appear in the
paired Watch simulator, reinforcing the broader snapshot and App Group
transport concern.

The actual WatchEffortPrompt has only Easy, Moderate, and Hard. It has no
visible Skip or Cancel action, unlike the phone sheet. Dismissing by gesture
is not discoverable, and leaving the sheet without answering leaves the
pending session in place.

Relevant source: Shared/Utilities/ScreenshotConfig.swift and
RechargeWatch/Views/WatchTodayView.swift.

### A86-009, P1: medium iOS widget renders “Ready” for no workout

Affected users: users adding the medium home-screen widget before their first
workout, or after the app has no recent session.

RechargeMediumWidgetView displays a checkmark only for .ready. Every other
phase, including .noRecentWorkout, renders
CountdownFormat.compactRemaining(entry.remaining). A no-workout snapshot has
no readyAt and a zero remaining value, and compactRemaining returns “Ready”
for zero, so the medium widget shows Ready inside the ring instead of No
workout or Finish a workout.

The small widget has a separate headline path and avoids this exact rendering,
which makes the problem family-specific and easy to miss.

Relevant source: RechargeWidget/RechargeWidget.swift.

### A86-010, P1: notification tap does not route to Today

Affected users: Pro users who enable Notify me at Ready and then tap the local
notification while viewing History or Settings.

The notification stores a route value of today. The delegate's
didReceive response only calls RecoveryEngine.shared.publish(). RootView has no
notification handler that changes selectedTab to Today. A notification tap can
therefore leave the user on the current tab, with no visible navigation to the
Ready answer that the alert promised.

There is a second notification problem. Enabling Notify me at Ready requests
authorization but ignores the returned Bool. The toggle stays enabled when the
user denies notifications, and scheduling errors are only logged. There is no
inline explanation, settings link, or state correction.

Relevant source: Shared/Services/NotificationService.swift and
Recharge/Views/SettingsView.swift.

### A86-011, P1: VO2 max is requested but never used

Affected users: privacy-sensitive users and anyone reviewing the Health
permission sheet.

HealthKit readTypes and NSHealthShareUsageDescription request Cardio Fitness /
VO2 max. HealthKitService has fetchVO2Max, but no production code calls it.
The onboarding explanation does not mention VO2 max, while the system permission
sheet exposes it as an extra category.

This violates least-privilege expectations and makes the read-only permission
request broader than the feature currently uses. Either the signal needs a
visible, tested product role or the permission and usage copy need to be
narrower.

Relevant source: Shared/Services/HealthKitService.swift and
Recharge/Info.plist.

## iPhone surface audit

### First launch and onboarding

### Page 1, welcome

Observed frame at 402 x 874:

- White system background.
- Orange hourglass around the visual center.
- Large two-line title: Recovery time, on the watch you own.
- Gray explanatory copy that compares the answer to Garmin.
- Orange Continue button in the bottom thumb zone.
- Four small dots, with no text or accessible progress label.

What works:

- The value proposition is immediately understandable.
- The primary action is large and easy to hit.
- The page uses a calm single decision layout.
- The orange state is consistent with the recovering state.

Issues:

- The direct Garmin reference is a competitor comparison in the first frame.
  It may create trademark, review, or expectation risk and makes the product
  sound like a substitute for Garmin rather than an independent training
  estimate.
- The word recovery can be read as a health or medical promise before the
  disclaimer appears.
- The page is a TabView page with horizontal swipe navigation. A user can move
  through the onboarding pages without pressing Continue, which bypasses the
  sequencing intent and can skip the Health explanation and honesty copy.
- Accessibility sees the hourglass as the generic image label Duration, not as
  a decorative image or an explanation of the page.
- Accessibility sees the title as static text rather than a heading.
- The page dots are decorative circles with no “page 1 of 4” announcement.
- At the largest Dynamic Type size, the title and message truncate and the
  page is not scrollable.

### Page 2, Apple Health

Observed frame:

- Coral heart text icon.
- Title Recharge reads Apple Health.
- Copy names workouts, heart rate, sleep, resting heart rate, and HRV.
- Connect Apple Health is the primary button.
- Not now is a secondary action.

What works:

- The app explains the reason for Health access before the system prompt.
- The read-only promise is clear in the app's own copy.
- Not now offers a non-blocking path.

Issues:

- The Health system sheet is broader and more alarming than the app copy:
  it says access and update, even though the app requests no writes.
- The system sheet exposes Cardio Fitness because of the unused VO2 max read.
- Connect can enter an indeterminate Requesting state.
- Not now is still actionable while the request is pending.
- A delayed prompt can land on another onboarding page.
- A denied request error is stored on the page that the app immediately leaves.
- There is no settings surface later to reconnect or review which categories
  were granted.
- If the user taps Not now, a later completed-setup launch may request Health
  again automatically.

### Page 3, honesty

Observed frame:

- Gray info icon.
- Title What the number actually means.
- Long centered paragraph explaining that the output is a cardiovascular
  training estimate, not a measure of muscle repair, illness, or injury risk.
- Gray I understand button.

What works:

- This is the strongest compliance and expectation-setting frame.
- It clearly limits the output to a cardiovascular training estimate.
- The button remains obvious.

Issues:

- The copy still says when another hard session is likely to be reasonable,
  which is a recommendation-like phrase. The surrounding disclaimer helps but
  does not remove the user's likely interpretation.
- The paragraph uses a long line of exclusions and is difficult to scan.
- The title is not exposed as an accessibility heading.
- The page can be skipped by swipe navigation.
- The info icon is exposed to VoiceOver as a generic Info image rather than
  being hidden or given a meaningful page label.

### Page 4, annual trial offer

Eligible screenshot state:

- Headline Try Recharge Pro free.
- Three benefits: sleep, HRV, and resting heart rate; bands tuned to history;
  weekly load against a four-week average.
- Annual billed amount of $14.99.
- Seven-day free trial and cancel anytime line.
- Continue with Recharge Pro button.
- Auto-renew disclosure.
- Not now.

Ineligible screenshot state:

- Headline changes to Go further with Recharge Pro.
- The annual amount remains visible.
- Billed automatically and cancel anytime replaces the free-trial line.
- Disclosure changes to a paid annual renewal statement.

What works:

- Trial eligibility changes the headline and disclosure.
- The amount billed is visible before the purchase action.
- The purchase button is neutral rather than saying Start trial.
- The user can decline without a dead end.

Issues:

- The user is asked to buy before seeing a Health-derived result, a countdown,
  or the main Today screen. This is a high-friction first-run sequence for a
  product whose value depends on personal data.
- While products are loading, the Continue button is disabled, there is no
  ProgressView, no loading label, and no retry action. A plain simulator launch
  showed the button disabled with no price or explanation.
- If the product fetch fails, the onboarding offer has no Try again, Restore,
  Terms, or Privacy action. The user can only choose Not now and find the full
  paywall later.
- The annual-only offer hides the monthly and lifetime choices until later.
  That may be intentional conversion design, but it is not transparent that
  the full plan set exists.
- The small disclosure text is very low contrast at the default size.
- There is no explicit statement that trial eligibility is determined by the
  Apple ID, beyond the changing copy.
- Not now records lastTrialOfferShownDate even when the catalogue did not load.
- TrialOfferSheet and passiveTrialOfferAllowed exist in source but are not
  referenced by any current surface. The intended 14-day passive offer is dead
  code, not a discoverable feature.

### Completion and permission denial

Tapping Not now finishes setup and sends the user to Today. If Health was
denied or skipped, Today looks like a normal no-workout state:

- gray empty ring,
- No workout yet,
- Finish a workout and your estimate appears here,
- a Pro Body signals pitch.

There is no “Health access is off” state, last sync time, permission status, or
in-app reconnect action. The user cannot distinguish no workouts from denied
reads, failed Health queries, a stale store, or an app that has not refreshed.

## Today

### No recent workout

Observed normal frame:

- Ring with a running figure.
- No workout yet.
- Finish a workout and your estimate appears here.
- Free Body signals card and Pro CTA.
- Compliance disclaimer.
- Floating Today, History, Settings tab bar.

What works:

- The empty state is explicit rather than inventing a number.
- The next action is understandable.
- The Pro pitch is localized to the locked card.

Issues:

- There is no indication whether HealthKit was denied, empty, stale, or still
  importing.
- The Body signals pitch appears even when the app has not received any Health
  data, which can make a new user think a subscription will solve setup.
- The disclaimer is very light and close to the tab bar.
- The Today tab image is announced to VoiceOver as Duration, which is not the
  same concept as Today.

### Recovering

Observed fixture frame:

- Large orange ring with 18h 43m and left.
- Ready tomorrow at a precise clock time.
- Window 18 to 25h.
- Three green confidence pips and High confidence.
- Why card with Run / Hard chip, load source, and context adjustment.
- Pro Body signals card with locked CTA for free users.
- Floating tab bar.

What works:

- The primary answer is prominent.
- The Why card exposes activity, category, source, and context.
- The confidence label is visible, not hidden in History.
- The lower Today content can be reached by scrolling.

Issues:

- The initial tab bar covers the lower Pro card and disclaimer.
- The precise Ready clock visually suggests more certainty than a window of
  18 to 25 hours. Low confidence softens the copy, but high confidence is not
  defined anywhere in the frame.
- “Hard for you” depends on a personal baseline that is not explained. A new
  user can see a personal-sounding label before the app has eight samples.
- The Why card calls the context adjustment “short sleep” and “HRV below your
  usual range” without showing the baseline or data freshness.
- There is no last Health sync timestamp and no way to identify which source
  app supplied the workout in the normal UI.
- The disclaimer is below the main answer and obscured in the first frame.

### Ready soon

The phase is entered when less than two hours remain. The source uses the same
hero and changes the color toward yellow. This state was covered in code and
logic tests but is not represented by a dedicated screenshot scene or UI test.

Risks:

- The user gets a color change and a clock but no explicit “less than two hours”
  explanation on Today.
- The system may continue showing a stale state if a background refresh or app
  foreground transition is delayed.
- A precise clock is used for medium and high confidence, but there is no
  visible explanation of how the displayed window relates to the point time.

### Ready

Observed fixture frame:

- Green ring with checkmark and Ready.
- Ready for another hard session.
- Estimate was 18 to 25h.
- Why card remains visible.
- Free users still see the Body signals paywall card.

What works:

- The state change is visually unmistakable.
- The past-tense estimate line avoids presenting the old window as current.
- The Ready result is also represented on Watch and complication code.

Issues:

- Ready for another hard session is easy to interpret as permission or fitness
  clearance even though the disclaimer says it is not medical advice.
- The app does not repeat the limitation about illness, injury, soreness, or
  non-cardiovascular fatigue near the Ready answer.
- The automatic readiness feedback sheet and the review prompt can be eligible
  at the same moment. RootView does not coordinate the review sheet with
  TodayView's ReadinessFeedbackSheet, so two modal flows can compete.
- The lower disclaimer and Pro CTA remain covered at the initial position.

### Easy or non-qualifying latest session

The model intentionally returns zero hours for easy profiles and for sessions
below the quiet threshold. RecoveryResolver then treats the latest non-countdown
session as current when no active window exists. The user sees Ready, not a
special “active recovery” explanation on Today. History can show an em dash for
the estimate.

This is technically consistent with the model, but the UI does not explain why
a walk can appear in History with no countdown while the Today answer reads
Ready.

### Body signals and weekly load

Free:

- The Body signals card is locked.
- The card pitches sleep, resting heart rate, HRV, and personal bands.
- The card's blue CTA opens the full paywall.

Pro:

- The card says sleep, resting heart rate, and HRV are folded into the estimate,
  or says body signals are off in Settings.
- Training load shows This week and 4-week average.
- A small note says load is a proxy, not a measurement.

Issues:

- Pro activation can switch the UI to the Pro card before the estimate and
  snapshot have been recalculated.
- In the premiumActive screenshot fixture, Training load shows 0 and 0 even
  though the History fixture shows eight sessions with nonzero loads. The
  screenshot fixture seeds estimates but not WorkoutRecord objects, so the
  Pro frame is internally inconsistent. This is a QA/signoff failure even if
  production storage is different.
- Training load is a raw number with no unit, scale, range, or explanation of
  how to act on it. “Load” is not obvious to a new user.
- The 4-week average is a weekly average of 28 days, but that definition is
  only implicit in the label.
- The load card and disclaimer are both covered at the initial scroll position.

### Effort card and phone effort sheet

The code displays an effort card for strength or mixed sessions when HR data is
unreliable and the fallback is energy or duration. The sheet has:

- title How hard was it?,
- activity and rounded duration,
- Easy with a keep-going explanation,
- Moderate with a controlled explanation,
- Hard with a near-limit explanation,
- Skip.

What works:

- Three options are easier to answer after a workout than a ten-point slider.
- The copy explains why the app is asking.
- The answer recalculates the session immediately in the normal engine path.

Issues:

- Skip does not answer the pending session. The card can return on future
  launches for up to two days.
- There is no visible confirmation that the answer was saved.
- The model's fallback priority is not exposed. A user cannot tell whether
  effort, energy, or duration is currently driving the estimate after skipping.
- The sheet is only observed from source in this audit because no deterministic
  iPhone screenshot scene seeds awaitingEffort.

### Readiness feedback sheet

The code presents this automatically after a countdown expires and offers:

- Felt ready,
- Okay but not fresh,
- Not ready,
- Not now,
- Stored on this device only.

What works:

- The answer set is short and understandable.
- Local-only storage is stated.
- The user can decline.

Issues:

- The sheet says the answer tunes personal bands but does not say whether it
  changes the current estimate, future estimates, or old History rows. In fact,
  the current rescore rewrites old state records too.
- It can compete with the review prompt after a Ready moment.
- The medium detent leaves little space at larger content sizes.
- There is no accessible scene fixture or UI test for this high-value feedback
  loop.

## History

### Empty state

The source provides a centered list icon, No estimates yet, and Finish a
workout and Recharge will score it here. This is clear, but it has the same
permission ambiguity as Today. It does not say whether the app is waiting for
Health authorization, an import, or an actual workout.

### Free history list

Observed fixture:

- History title.
- Free Weekly load and accuracy card with Pro badge.
- Group headings Today, Yesterday, and localized calendar dates.
- Rows for Run, Ride, Walk, Functional Session, Lifting Session, and more.
- Each row exposes category, time, hours or no-countdown marker, and confidence
  pips.
- The first lower row is covered by the floating tab bar.

What works:

- History remains usable for free users, which supports trust.
- Rows are buttons with combined labels in the accessibility tree.
- Easy activity remains visible without starting a countdown.
- Grouping is understandable.

Issues:

- The no-countdown marker is only a dash. There is no “active recovery” or
  “below threshold” explanation in the row.
- Confidence is shown as pips without a legend in the list.
- “Typical” and “Hard” are relative to personal history, but the list has no
  explanation of the comparison set.
- Date headings use current locale formatting, while activity and reason copy
  is hard-coded English. The product is not localized.
- The free Pro teaser says “Every estimate, and how it landed” in the paywall,
  even though free users already see every estimate. The distinction between
  free History access and Pro detail is not stated precisely.
- The list has no source app, duration, energy, or actual workout date beyond
  the time label.
- Deleted or duplicate Health workouts can create stale or repeated rows due
  to the import behavior described below.

### Estimate detail sheet

Observed free detail:

- Large sheet with Run title and Done.
- Window 18 to 25h.
- Ready time, profile/category chip, and High confidence.
- Why card.
- Numbers card with session load, compared to usual, load source, HR coverage,
  and model version.
- Pro Correct this session teaser.

Observed Pro detail:

- Same header and numbers.
- Session type card with Endurance, Strength, Mixed, and Easy segmented
  controls.

What works:

- The app exposes the actual load source and HR coverage instead of hiding the
  model.
- Model version is visible.
- The Pro override is placed after the explanation rather than as the first
  action.

Issues:

- After selecting a different session type, the visible header, numbers,
  reasons, and explanatory sentence continue to describe the captured original
  estimate. The detail receives a value-type estimate and the local picker
  mirror only changes the selected segment. The sheet does not visibly refresh
  its estimate in the fixture run. In production, even if the engine updates,
  the selected sheet value is still captured and likely requires closing and
  reopening to show the new result.
- The copy “Recharge scored this as endurance” remains stale after selecting
  Strength in the live fixture interaction.
- There is no confirmation, changed-value summary, or undo after a profile
  override.
- The app does not say whether an override changes only this session or the
  user's default classification. The source intends per-session, but the UI
  should make that explicit.
- Accessibility sees the underlying History elements in the sheet tree as well
  as the modal content. Verify with VoiceOver, because background row
  navigation can confuse the modal interaction order.
- Numbers such as 0.50x and 40 have no units or scale legend. A user cannot
  tell whether 40 is minutes, points, or a normalized score.
- HR coverage is shown only when the load source is heart rate. There is no
  equivalent confidence reason for energy or duration fallback beyond the
  confidence label.

## Settings

### Free settings frame

Observed top:

- Settings title.
- Recharge Pro conversion row.
- Watch complication section with Style set to Countdown.
- Model section with HYROX and CrossFit set to Mixed.
- Max heart rate set to Auto bpm.
- Personal calibration Neutral.
- About heading just above the tab bar.

Observed bottom:

- About buttons: Rate or send feedback, Restore purchases, Privacy policy, and
  Terms of use.
- Version 1.0.0 (5).
- Compliance footer.
- Debug section in the Debug build with local Pro override, Force refresh, and
  Model version v1.

The Debug section is compiled out of release, so it is not a production user
surface. It is still visible in every debug simulator audit and can make a
reviewer mistake test controls for product controls if a debug build is used
for screenshots.

### Watch complication style picker

The picker exposes:

- Countdown: hours left with a ring, described as closest to Garmin.
- Ready at: estimated clock time.
- State: Recovering, Ready soon, or Ready.

What works:

- All three choices are understandable.
- The picker detail changes immediately.
- The setting is stored in the App Group for extensions.

Issues:

- The wording closest to Garmin repeats the competitor framing in Settings.
- The footer says all four families use the choice, but there is no preview of
  the four family layouts.
- The Watch complication itself is not receiving the phone snapshot in the
  paired test, so changing this setting may change an empty complication rather
  than the user's actual countdown.
- The picker accessibility tree exposes options as menu buttons but does not
  announce the detail text as part of the selected value.

### Model picker

The picker exposes Mixed, Strength, and Endurance for the HealthKit activity
types labeled HYROX and CrossFit. This is a good escape hatch for ambiguous
HealthKit activity codes.

Issues:

- Changing it only persists the preference. It does not rescore existing
  workouts, republish the snapshot, or tell the user when the new choice takes
  effect.
- The label is “HYROX and CrossFit,” but the app cannot identify either brand
  from HealthKit. The explanation should make the code ambiguity more explicit
  and less like a direct classifier.
- The selected profile is not shown in the History list until a future
  rescore.

### Max heart rate

What works:

- Auto is a simple default.
- Number pad is appropriate for the field.
- The range is intentionally bounded.

Issues:

- Invalid values are silently normalized to Auto in the model while staying
  visible in the field.
- No helper text states the accepted 120 to 230 bpm range.
- No save or recalculation confirmation exists.
- Existing estimates do not update immediately.
- The user cannot see whether HealthKit supplied a max heart rate or the model
  default is active.

### Personal calibration

The UI shows Neutral, or a percentage longer/shorter after readiness answers.
Reset calibration appears only when non-neutral.

Issues:

- Calibration changes after every readiness answer, but the user never sees
  the new factor's effect on a specific session.
- Reset rescores and publishes, so old History can change.
- Calibration does not distinguish “your bands changed” from “this estimate
  changed,” which makes the model harder to trust.

### Pro toggles

Pro exposes:

- Use body signals.
- Notify me at Ready.

The body signals footer says the adjustment is bounded and one reading cannot
move the countdown by itself. This is good expectation setting.

Issues:

- Notification authorization denial leaves the toggle on with no warning.
- There is no current notification authorization status.
- Body signal changes rescore and publish, but a purchase or entitlement
  activation does not.
- The setting does not show which days have usable sleep, HRV, or resting heart
  rate data.

### About

Issues:

- Restore purchases has no visible success, failure, or “nothing found” state
  in Settings. On the simulator, tapping it produced no UI change even though
  StoreService stored “Restore is unavailable in the simulator.”
- The Settings footer says data stays on the user's devices. The privacy policy
  qualifies that Apple and RevenueCat process purchase information, but the
  in-app footer does not. The shorter statement can be read as “nothing leaves
  the device.”
- Privacy policy uses jackwallner@gmail.com as contact, while the in-app review
  email path uses support@jackwallner.com. The user may send feedback to a
  different address from the one listed in the public support and privacy
  pages.
- Terms links directly to Apple's EULA. The app has no app-specific subscription
  details beyond the short purchase disclosure.
- No Health access row, export, local data reset, import status, or delete-data
  action exists.

## Paywall and purchase flow

### Full paywall frame

Observed top:

- Pro icon and Recharge Pro title.
- One-line promise about personal sleep, heart data, and recovery bands.
- Six feature rows:
  sleep/HRV/resting heart rate, personal bands, every estimate and how it
  landed, weekly load, per-workout-type curves, and Ready notification.
- Lifetime, Yearly, and Monthly plan cards.

Observed bottom:

- Annual card selected by default.
- BEST VALUE label.
- $14.99 per year and $1.24 per month equivalent.
- Monthly $1.99 per month.
- Continue with Recharge Pro.
- Disclosure adjacent to CTA.
- Restore, Terms, Privacy.
- Small cardiovascular-estimate disclaimer.

What works:

- All three plans render in screenshot mode.
- The selected plan changes the price and disclosure.
- The CTA is neutral.
- Lifetime explicitly says one-time and no subscription.
- Yearly and monthly show the free trial only when eligibility says it applies.
- Purchase returns to the underlying screen in the simulator.

Issues:

- Feature and disclosure text is low contrast and small at the bottom. The
  compliance disclaimer is especially easy to miss.
- The close button floats over content as the paywall scrolls. It remains
  usable, but at the bottom it sits over the feature area rather than in a
  stable navigation bar.
- The paywall accessibility tree still included the underlying History rows
  while the sheet was open. Verify modal isolation with VoiceOver.
- Restore errors appear only below the purchase CTA in the paywall. Settings
  does not show them at all.
- The product list is not localized in the screenshot fixtures. The existing
  UI test only verifies hand-built English prices. Localized currency,
  regional price formatting, PPP prices, and real eligibility remain untested.
- The simulator purchase path flips a local Pro override and is not a real
  StoreKit or RevenueCat customer path.
- StoreKit Testing did not return products under xcodebuild test, so the UI test
  uses screenshot packages. This validates layout only, not StoreKit behavior.
- A product fetch failure shows an empty state with Try again, but a slow initial
  load can leave the user looking at the feature list before the plan area
  resolves.
- The paywall is accessible from several free cards, but there is no way to
  compare the full plans from the onboarding offer without finishing onboarding.

### Plan selection behavior

The plan cards are large buttons and selection is clear. The annual plan
disclosure correctly changed to the monthly disclosure when Monthly was
selected in the headless run.

Check carefully on device:

- Long localized product names can wrap the plan card and move the CTA below
  the fold.
- A currency with a long symbol or right-to-left layout can collide with the
  annual per-month equivalent.
- Trial eligibility can resolve after the plan is selected, changing the
  disclosure under the user.
- Pending and cancelled purchase messages are source-only and were not
  exercised with real StoreKit.

## Secondary sheets and launch surfaces

### What's New

WhatsNewSheet lists:

- Recovery time on the wrist.
- Four complication families.
- Hybrid training curves.

Free users get a Pro CTA, followed by Continue. Pro users only get Continue.

Issues:

- There is no version, release date, or “why am I seeing this?” context.
- Continue is at the end of a scroll and there is no visible close action.
- The sheet can present at launch before a user has chosen a tab, but RootView
  only coordinates it with the review sheet, not with Today effort or feedback
  sheets.
- The Pro CTA uses a passive marketing surface but the intended passive Trial
  Offer sheet is not wired elsewhere.
- The list icons are decorative but exposed to accessibility without custom
  descriptions.

### Review and feedback funnel

The source implements:

1. Enjoying Recharge? with Yes, useful and Not really.
2. Mind rating it? with Rate Recharge, Write a review, and Maybe later.
3. What's missing? with a TextEditor and Send.
4. Thank you.

What works:

- The user is asked for sentiment before a review.
- Negative feedback is routed to email rather than forced into a rating.
- Send is disabled for an empty message.
- Maybe later has a shorter cooldown than a hard review outcome.

Issues:

- The TextEditor has no placeholder inside the input, so the empty state is
  visually ambiguous.
- The feedback copy says it goes straight to me, but the support address differs
  from the public privacy/support contact.
- Email composition and App Store review links were not exercised on a real
  device.
- The App Store ID currently points at an ASC record described in the project
  guide as Recovery App Placeholder. The external write-review route needs a
  live listing check before release.
- A pending Ready review token is ignored by the launch-time engaged-use path.
  If the app was not alive when the second Ready moment occurred, the pending
  token can remain without producing the review sheet on the next launch.
- Review prompting can compete with the readiness feedback sheet.

### Phone effort and readiness sheets

The phone effort sheet is medium-height with three large card-like choices and
Skip. The readiness sheet is also medium-height with three large choices,
Not now, and a local-storage note.

Specific concerns:

- Medium detents are not designed for the largest text sizes.
- There is no asynchronous save state or failure state.
- The effort Skip behavior does not clear the pending request.
- The readiness answer changes the calibration and can rewrite history.
- Underlying screen accessibility elements remain visible in modal snapshots.

### System surfaces

Health permission, notification permission, StoreKit purchase confirmation,
external privacy/terms links, email composition, and App Store review pages are
all external surfaces. They need real-device checks because the headless
simulator cannot validate:

- Health category read behavior after partial permission.
- Repeated permission prompts after denial.
- Notification denial and Settings handoff.
- localized StoreKit price and trial eligibility.
- RevenueCat customer status and restore.
- email and App Store routing.

## Watch app and complication audit

### Watch app, recovering

Observed on the 46 mm headless Watch:

- Black background.
- Gray Recharge title.
- Orange countdown ring.
- 18h and left inside the ring.
- Ready tomorrow at a precise clock time.
- Hard and run below the ring.

The frame is visually readable and appropriately sparse. It has no visible
connection status when the snapshot is empty or stale, so the user cannot tell
whether the Watch is current.

### Watch app, Ready

Observed:

- Green ring.
- Green checkmark and Ready.
- Ready for another hard session.
- Hard and run below.

The state is clear, but the same recommendation-like interpretation risk from
iPhone applies. The checkmark image is announced as Selected rather than a
combined Ready state. The ring is not one combined accessibility element, so
VoiceOver receives separate pieces rather than the complete answer.

### Watch app, no recent workout

Observed in the paired no-fixture run:

- Gray empty ring.
- Running figure.
- No recent workout.

This was the result after the phone had a live recovering snapshot, so it is
the central A86-001 failure, not a valid post-workout empty state.

### Watch effort

The intended flow is Rate effort, followed by a scrollable prompt with Easy,
Moderate, and Hard. The actual screenshot scene did not show Rate effort. The
button depends only on pendingEffortSessionID in the Watch-side App Group.

Additional risks:

- No visible Skip or Not now.
- No text explaining that the answer will travel to the iPhone.
- No status if the phone is unreachable other than a transient status message
  after a tap.
- statusMessage clears after three seconds and is not persisted.
- A new pending effort request can take up to the 60-second ticker interval to
  appear if the app stays open.

### WatchConnectivity

The effort send path has good defensive intent:

- sendMessage when reachable,
- transferUserInfo when not reachable,
- local queue as a backstop.

But:

- There is no symmetric phone-to-Watch snapshot path.
- sendMessage failure enqueues transferUserInfo and the local queue after
  already telling the user Saved. The answer is durable in intent, but duplicate
  delivery and duplicate engine handling should be tested.
- The phone applies any correctly shaped inbound session ID without a visible
  user confirmation.
- No WatchConnectivity test exists.

### Watch complication families

The source covers:

- Circular: gauge while recovering, symbol and state when ready or empty.
- Rectangular: icon, state/countdown, and secondary text.
- Inline: compact one-line text.
- Corner: primary state or countdown plus widget label gauge.

The three styles are:

- Countdown.
- Ready at.
- State.

This is a good source-level matrix, but the runtime data path blocks trust in
all four families. Additional copy risks:

- Empty corner uses -- as the widget label.
- State style abbreviates to REC and SOON, which may be unclear without the
  Watch app.
- Ready at style shows a clock without the window or confidence.
- Inline countdown strings can be localized or clipped differently from the
  English test assumptions.

## iOS widget audit

### Small widget

The small widget shows an icon, optional compact progress ring, headline, and
caption. It supports:

- No workout.
- Ready.
- Recovering.
- Ready soon.

The small layout is compact but sensible. The caption can become two lines
with a longer localized activity or date phrase. There is no widget-specific
confidence or data freshness signal.

### Medium widget

The medium widget shows a 74 point ring, countdown/checkmark, headline, caption,
and category/activity.

Confirmed bug: no recent workout falls through to the countdown text path and
renders “Ready” inside the ring because the zero remaining value is formatted
as Ready. It should have an explicit empty-state branch.

Both families deep-link to recharge://today. The app does not visibly route the
deep link to a specific tab or state in RootView. A widget tap should be tested
from History and Settings contexts.

## Model, data, and HealthKit audit

### Workout classification

The classifier covers many HealthKit activity codes and has sensible broad
profiles:

- endurance,
- strength,
- mixed,
- easy.

It handles unknown codes by falling back to endurance, which avoids a crash.

Risks:

- Unknown activities silently become endurance with a generic workout label.
- Several activities that can be strength or mixed are hard-coded to one
  profile.
- Functional Strength Training and HIIT are both exposed as the HYROX and
  CrossFit ambiguity, but the product cannot know the user's intended sport.
- Third-party apps may write duplicate overlapping workouts. Import deduplicates
  only by HealthKit UUID, not by time, source, or overlap.
- Existing workout dates, duration, activity code, and source name are not
  updated on re-import when Health revises a workout. Only energy, HR, coverage,
  profile, and label are updated.

### Load source and confidence

The fallback ladder is heart-rate TRIMP, effort, energy, then duration. The
heart-rate coverage check is a good honesty guard for lifting.

User-facing risks:

- Coverage is estimated as sample count times five seconds. Multiple sources,
  irregular intervals, overlapping samples, and sparse bursts can make that
 percentage inaccurate.
- A default max heart rate of 185 is used when no max exists. The user is not
 shown this assumption in Today or History.
- Energy and duration fallback can produce a countdown for a session with very
 weak evidence. The low confidence label is present, but the user is not told
 how much of the result is inferred.
- Mixed sessions use the higher of heart-rate and effort load, which is
 defensible but not exposed in the detail UI.

### Personal baseline

The model uses a median and a 25th percentile, pools profiles when a profile is
sparse, and labels the first eight samples as building baseline.

Risks:

- A median dominated by easy days can make a hard session appear unusually
  large. The project guide acknowledges this open tuning question.
- New users see a personal comparison label even while the baseline is sparse.
- The absolute floor of 18 load units and the quiet threshold are first-pass
  tuning constants, but the UI does not identify them as provisional.
- The bounded 18 to 72 hour result can feel authoritative even though the
  model is not clinically validated.

### Context signals

Sleep, HRV, and resting heart rate move the countdown within bounded
adjustments. This is clear in source and in the Why card.

Risks:

- Sleep samples can overlap or come from multiple sources and are summed
  without overlap resolution.
- Context records are updated only when a positive value is returned. If a user
  deletes data or revokes a category, old sleep, HRV, or resting-heart-rate
  values can remain in SwiftData and continue influencing estimates.
- A single current context import can rewrite historical estimates.
- There is no visible timestamp or source for the context values.

### Empty HealthKit result and deleted workouts

RecoveryEngine.importWorkouts returns immediately when HealthKit returns an
empty array. The deletion pass is therefore skipped when:

- the user deletes all workouts,
- the user revokes read access,
- a query fails,
- HealthKit temporarily returns no data.

Old WorkoutRecord and RecoveryStateRecord objects can remain, keeping a stale
countdown and stale History. This is especially dangerous because the UI
renders the stale result as if it were current and has no last-sync indicator.

### Local store failure

DataService deletes the SwiftData store and its WAL/SHM files whenever the
container fails to open, then re-imports from HealthKit. The app has no
visible warning, backup, or explanation that local History, profile overrides,
effort answers, and calibration may have been discarded.

The fallback to an in-memory store can also make data appear to vanish after a
launch without a user-facing state.

### Snapshot and timing

RecoverySnapshot is compact and appropriate for extensions. CountdownTimeline
precomputes hourly entries and 15-minute entries through the final two hours,
then Ready and a post-Ready entry. The pure tests cover this well.

User-facing timing risks:

- The iPhone view ticks once per minute and can be stale until the next tick
  after a background/foreground transition.
- WidgetKit and watchOS can delay timeline delivery. Support copy admits a lag,
  but the main UI does not show last updated time.
- DateFormatter instances are static while Calendar.current can change during a
  time-zone or locale change. A running app may format a Ready time using old
  formatter settings until relaunch.
- The user sees exact minutes for many states despite a wide underlying window.

## Privacy, trust, and compliance

What works:

- Health data is read-only in the request call.
- The app has an explicit cardiovascular estimate disclaimer.
- Privacy policy says health data is local and no health data is sent to
  RevenueCat.
- The app does not claim to diagnose, treat, cure, or prevent a condition in
  the tested copy.

Risks:

- The Health permission sheet's access and update wording conflicts with the
  in-app read-only promise.
- VO2/Cardio Fitness is requested but unused.
- Settings says data stays on devices without qualifying purchase processing.
- “Ready for another hard session” and “likely to be reasonable” are
  recommendation-like phrases. The user can reasonably interpret Ready as a
  fitness or safety clearance.
- The disclaimer is too low contrast and too close to the tab-bar overlay in
  the default Today frame. Compliance copy needs to be readable without
  scrolling.
- The first onboarding page references Garmin directly. Terms disclaims
  affiliation, but the product should not rely on a legal page to reduce a
  first-frame brand risk.
- There is no in-app explanation of how to remove stored local data or clear
  calibration.

## Personas and end-to-end walkthroughs

### Persona 1: Garmin convert, endurance runner

Goal: finish a run and see a familiar countdown on the Watch face.

Path: onboarding, Health permission, run import, Today, Watch app, circular
complication.

Result:

- iPhone Today is the strongest path. The ring, Ready clock, window, source,
  and confidence all answer the job.
- Competitor copy makes the conversion promise explicit but over-dependent on
  Garmin comparison.
- The Watch path fails in the paired headless run because the phone snapshot
  does not reach the Watch.
- The iPhone disclaimer is obscured at first view.

Priority: P0 Watch sync, P1 initial layout and trust copy.

### Persona 2: strength lifter with unreliable optical HR

Goal: report effort once and get a meaningful estimate.

Path: lifting workout, phone effort card or Watch Rate effort, Easy/Moderate/Hard,
updated Today, later readiness feedback.

Result:

- The model has the right fallback concept.
- The phone prompt is clear and compact.
- The Watch prompt cannot be reached in the deterministic scene and depends on
  the broken snapshot/pending-session path.
- Skip leaves the prompt pending.
- There is no save confirmation.
- The current estimate may not update after a later Pro activation or setting
  change.

Priority: P0 Watch data transport, P1 prompt state and confirmation.

### Persona 3: HYROX or CrossFit athlete

Goal: choose the right curve for ambiguous HealthKit activity codes.

Path: Settings, Model, HYROX and CrossFit, Mixed/Strength/Endurance, History
session override.

Result:

- The concept is discoverable.
- Changing the global setting does not rescore and publish.
- Changing a History session leaves the visible detail stale until the surface
  is refreshed.
- The product does not explain whether the setting applies to old workouts,
  future workouts, or both.

Priority: P1.

### Persona 4: active-recovery walker or yoga user

Goal: walk without starting or shortening a countdown.

Path: walking workout, Today, History.

Result:

- The model correctly avoids a countdown and does not shorten an active window.
- History displays a dash with no explanation.
- If the walk is the latest activity after all hard windows expire, Today reads
  Ready, which is logically acceptable but not explicit about active recovery.

Priority: P2 explanation.

### Persona 5: first-time user with no workout

Goal: understand what to do next without being forced to buy.

Path: onboarding, skip Health, decline annual offer, Today, History.

Result:

- Empty Today and History are understandable.
- The user is asked for Pro before seeing a personalized result.
- There is no Health permission status after skipping.
- The Pro card remains prominent when there is no data.
- Restore/Health/legal recovery paths are not visible from onboarding.

Priority: P1.

### Persona 6: privacy-sensitive user

Goal: grant only necessary access and keep health data local.

Path: Health explanation, system permission sheet, Privacy policy, Settings.

Result:

- Local processing and no write-back are strong promises.
- The system sheet asks for Cardio Fitness/VO2 max that is unused.
- Access and update wording conflicts with read-only copy.
- Settings says data stays on devices without purchase-processing qualification.
- There is no per-category permission status or reset path.

Priority: P1.

### Persona 7: user who denies Health access

Goal: use the app later after changing their mind.

Result:

- There is no in-app Health access row or reconnect button.
- The app silently resembles a no-workout state.
- SynchronizeAuthorization can prompt again at a later launch without a clear
  explanation.

Priority: P1.

### Persona 8: Pro subscriber or restored purchaser

Goal: see paid context signals and history immediately after purchase.

Result:

- Paywall selection and simulator purchase UI are clear.
- Entitlement changes do not guarantee an immediate rescore and snapshot
  publish.
- Restore in Settings has no visible result.
- The Watch may remain on an old/free/empty snapshot.

Priority: P1, with the Watch path P0.

### Persona 9: user who gives readiness feedback

Goal: say whether the estimate felt right and see future bands improve.

Result:

- Three labels are easy to answer.
- The app says local only.
- Calibration can rewrite old History, which violates historical trust.
- Review prompting can collide with the feedback sheet.
- No test fixture proves the sheet or its keyboard behavior.

Priority: P1.

### Persona 10: low-vision or large-text user

Goal: read and operate the same onboarding and Today answer.

Result:

- Largest Dynamic Type size truncates onboarding and overflows Today.
- Fixed ring and fixed spacing do not adapt.
- Safety copy is small and low contrast even at default size.

Priority: P0.

### Persona 11: VoiceOver user

Goal: navigate pages, identify the countdown, and operate sheets.

Result:

- Page titles are static text, not headings.
- Page dots have no page number or progress label.
- Decorative SF Symbols are exposed with generic labels such as Duration.
- Ring state is split into separate image and text nodes.
- Modal snapshots expose underlying content.
- Pickers and segmented controls need device VoiceOver verification.

Priority: P1.

### Persona 12: international user

Goal: see understandable dates and prices in their locale.

Result:

- Product prices are localized only on the real StoreKit/RevenueCat path, not
  the screenshot packages.
- Most copy is hard-coded English.
- Ready copy, category labels, list joining, and activity labels are English.
- DateFormatter uses current locale for some strings but not all phrases.
- No localization resources or RTL audit exists.

Priority: P1 for launch markets outside English.

### Persona 13: user with multiple or overlapping workouts

Goal: have the app choose a believable current window.

Result:

- Resolver chooses the latest Ready time, which is understandable.
- History keeps each session.
- Duplicate third-party imports and stale deletion can produce bad history.
- Old estimates are rescored and changed later.

Priority: P1 data correctness.

### Persona 14: user who relies on notification

Goal: tap Ready notification and land on the answer.

Result:

- Notification scheduling is Pro-only and off by default.
- Denied authorization is not surfaced.
- Tap handling does not navigate to Today.

Priority: P1.

## Accessibility and visual system

### Dynamic Type

Largest-size inspection found real clipping on onboarding and a broken hero/card
composition on Today. History, Settings, paywall, and medium sheets should also
be tested at accessibility sizes before signoff.

### VoiceOver

Observed and source-level concerns:

- headings are often static Text rather than accessibility headings;
- page progress is absent;
- decorative icons are announced;
- the Today ring is not a single complete answer;
- confidence pips are combined correctly into a text label, which is a good
  pattern to reuse;
- modal background elements remain in the accessibility tree;
- several Picker controls are exposed as generic text/menu structures;
- Watch Ready icon is announced as Selected;
- Watch effort has no accessible cancel action.

### Contrast

Dark mode itself looked coherent and state colors remained distinct. The
tertiary disclaimer, purchase disclosures, small footer text, and some settings
footers are too faint to be comfortably read. The safety disclaimer should not
depend on users scrolling or increasing contrast.

### Color and non-color cues

State uses color plus ring shape, hourglass/checkmark, and words, which is good.
Confidence uses pips plus a label on Today and History detail. History rows
hide the confidence label and rely on pips without a legend.

### Motion and reduced motion

CountdownRing animates progress with easeInOut. There is no explicit
accessibilityReduceMotion handling. Check ring animation, page animation, and
sheet transitions for users who prefer reduced motion.

### Orientation and device size

Recharge/Info.plist declares portrait, both landscape orientations, and
portrait upside down, but no landscape runtime audit was completed. The
project targets iPhone family only, not iPad. The Watch audit covered only the
46 mm Series 11 simulator.

## Copy and product clarity

Specific copy that needs product review:

- “the answer a Garmin gives you” creates a competitor comparison in the
  welcome frame.
- “Ready for another hard session” can be heard as safe-to-train permission.
- “when another hard session is likely to be reasonable” is still
  recommendation-like.
- “Hard for you” is not self-explanatory before a user has a baseline.
- “Load” and “compared to your usual” have no units or plain-language
  explanation.
- “Your data stays on your devices” needs to be reconciled with the purchase
  data exception.
- The phrase “Every estimate, and how it landed” blurs the free History and
  Pro detail boundary.
- There is no visible last sync or source freshness language anywhere.

## Test and release coverage gaps

The passing 110 logic tests are useful and cover monotonicity, boundaries,
fallback load sources, context bounds, resolver behavior, snapshot coding, and
timeline generation. They do not cover:

- phone-to-Watch snapshot delivery;
- WatchConnectivity offline, duplicate, or queue behavior;
- actual Watch UI;
- Watch complication rendering;
- iOS widget rendering;
- no-workout medium widget;
- Health partial permission, denial, delayed sheet, or re-prompt;
- stale/deleted HealthKit data;
- duplicate third-party workouts;
- Pro entitlement arriving after engine refresh;
- purchase, pending, cancelled, failed, or restore states on device;
- notification denied state or notification tap routing;
- readiness and effort sheets;
- review and What's New sheets;
- Dynamic Type, VoiceOver, contrast, reduced motion, RTL, localization, or
  landscape;
- historical preservation across calibration, context, and model-version
  changes.

The 7 passing iOS UI tests are happy-path existence tests. They verify text
exists, not that content is unobscured, recalculated, localized, modal-isolated,
or accessible at large text sizes. Their 51 Swift 6 main-actor warnings should
be cleaned before relying on the suite as release evidence.

## Recommended handoff order for the fixing agent

1. Establish a real phone-to-Watch and phone-to-Watch-complication snapshot
   transport, then test it with a paired device and a stale/offline state.
2. Fix Dynamic Type and initial tab-bar occlusion, with the disclaimer visible
   and readable without a discovery scroll.
3. Make Health permission state explicit and serialize or cancel the onboarding
   request.
4. Make entitlement changes, profile changes, max-heart-rate changes, and
   restore trigger a deliberate rescore and publish.
5. Preserve historical estimates and model versions instead of overwriting
   old user-visible results.
6. Repair Watch effort discovery and the watchEffort fixture.
7. Fix widget empty-state rendering and notification routing.
8. Remove unused VO2 permission or implement and explain its use.
9. Surface purchase, restore, notification, Health, and feedback errors.
10. Run the accessibility, localization, landscape, real StoreKit, RevenueCat,
    HealthKit, and paired Watch test matrix.

## Second-pass re-analysis

I re-read this report after drafting it and checked each observation against
the source and the runtime evidence again.

Confirmed by both source and runtime:

- phone countdown present while normal paired Watch is empty;
- largest Dynamic Type truncates onboarding and breaks Today;
- Health request can remain pending while Not now advances;
- initial tab bar covers lower Today and History content;
- Watch screenshot effort scene lacks Rate effort;
- Pro premium fixture shows zero weekly load despite populated fixture History;
- paywall plan selection changes the selected card and disclosure;
- dark mode renders, but low-contrast tertiary copy and tab-bar overlap remain;
- 110 logic tests and 7 UI tests pass.

Confirmed by source, with real-device validation still required:

- Pro activation does not rescore and publish;
- settings model and max-heart-rate edits do not rescore and publish;
- old RecoveryStateRecord values are overwritten during rescore;
- empty HealthKit imports skip deletion;
- notification taps do not select Today;
- VO2 max is requested but unused;
- medium widget no-workout path displays “Ready” inside the ring;
- WatchConnectivity has no phone-to-Watch snapshot method;
- Settings Restore has no visible error rendering.

Findings deliberately kept as risks rather than asserted failures:

- exact HealthKit sleep overlap behavior across multiple source apps;
- App Store review URL availability before the listing is live;
- localized price wrapping and RTL layout;
- real-device interpretation of the system access-and-update wording;
- whether the Watch App Group is mirrored on any production pairing configuration.
  The headless paired run failed, and the source has no explicit transport, so
  this remains a release blocker until a real paired-device proof exists.

No app fixes were made. This file is the complete audit handoff.
