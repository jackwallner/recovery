# Recharge — Project Guide

Garmin-style recovery time for Apple Watch: a countdown after every qualifying
workout and a clear Ready when it expires. XcodeGen project/scheme: `Recharge`,
sim lease owner `recharge`. Repo dir is `~/recovery`; the dir name deliberately
differs from the app name (cf. `~/health` = VO2 Max, `~/vitals` = Total Calories).

## Tech Stack
- Swift 6 / SwiftUI (strict concurrency)
- HealthKit (read-only), SwiftData in an App Group, WidgetKit, WatchConnectivity
- XcodeGen (`project.yml`). Targets: iOS 17+, watchOS 10+
- RevenueCat; gate on **any** active entitlement, never a hardcoded string

## Targets / bundle IDs
- `Recharge` — `com.jackwallner.recovery`
- `RechargeWatch` — `.watch`
- `RechargeWidget` — `.widget`
- `RechargeWatchWidget` — `.watch.widget`
- `RechargeTests` — `.tests`, `RechargeUITests` — `.uitests`
- App Group: `group.com.jackwallner.recovery`

## Architecture

**The phone owns the model.** Only it can query the full HealthKit store and the
long history, so it alone calculates and writes. Everything else reads.

```
HealthKit (iPhone)
  -> HealthKitService          workouts + HR coverage + sleep/HRV/RHR
  -> RecoveryEngine            import, rescore, persist, publish
  -> SwiftData (App Group)     WorkoutRecord / RecoveryStateRecord / DailyContextRecord
  -> RecoverySnapshot          small Codable in App Group UserDefaults
  -> Watch app + both widget extensions (read only)
```

The extensions read `RecoverySnapshot`, not SwiftData, so they never have to
mirror the schema.

### The model (`Shared/Utilities/`)
Pure, `Sendable`, no HealthKit or SwiftData imports — which is what makes the
110-test suite in `RechargeTests` possible without a Health store.

| File | Stage |
|---|---|
| `SessionLoadCalculator` | one workout → one load. HR-reserve TRIMP, then reported effort, then energy, then duration. Also `intensityFraction`, the HR-reserve quality proxy. |
| `RecoveryBaseline` | the person's own recent loads; median, 25th percentile, sample count. `.standard(for:)` is the no-samples population reference the free tier uses. |
| `RecoveryCalculator` | relative load → bounded hours, context adjustment, calibration, personalization, clamp. |
| `AthleteProfile` | who the person is: age, sex, experience, volume, bounce-back. Every field carries its own multiplier, and `gaps` is what onboarding still has to ask. |
| `PersonalRecoveryModel` | the 30-day analysis → one bounded personal multiplier. |
| `RecoveryResolver` | several overlapping windows → the one to show (latest `readyAt`). |
| `WorkoutClassifier` | `HKWorkoutActivityType` raw value → one of four profiles. |
| `CountdownTimeline` | the entry schedule a decaying countdown needs. |

### The two tiers
`RecoveryTier` is stored on every estimate, because the two answer different
questions and a history list that mixes them silently is lying by omission.

- **Standard (free).** `RecoveryBaseline.standard(for:)`, no context, no
  calibration, `RecoveryPersonalization.standard`. The same table for everyone:
  session type, length, and intensity in, hours out. Confidence is capped at
  medium and never reports `buildingBaseline` — there is no baseline being
  built. Category labels drop the "for you".
- **Personalized (Recharge Pro).** The person's own 42-day baseline, overnight
  context, calibration, and the `PersonalRecoveryModel` multiplier.

Age-predicted maximum heart rate (Tanaka, or Gulati for women) applies on
**both** tiers. It is a measurement input, not a personalisation: scoring a
58-year-old against a flat 185 bpm ceiling does not make the free estimate
standard, it makes it wrong.

`RecoveryEngine.rescore` runs two passes — the standard estimate for every
session first, because `PersonalRecoveryModel` needs to know what window each
session *would* have had, then the tier-appropriate one.

### What the 30-day analysis actually measures
Three independent signals, blended geometrically with the questionnaire prior on
a weight that grows with evidence and caps at 0.70, then clamped to
0.72...1.32:

1. **Rebound.** How much of the day-after disturbance in resting heart rate and
   HRV is still present on day two. The closest thing to a direct measurement of
   individual recovery kinetics a wrist sensor can produce. Needs 3 samples.
2. **Tolerance.** Whether sessions started *inside* a predicted window held
   their usual intensity. Revealed preference. HR-reserve only, deliberately: an
   RPE-derived intensity compared against a reserve fraction answers the
   question with a change of units. Needs 3 samples.
3. **Density.** Chronic weekly load against a population reference, on a log
   scale. The classic activity-class adjustment, capped at a third of the
   sample weight the observed signals reach.

The prior is never fully discarded — it carries age, which nothing in the
history can observe.

Four profiles, each with its own curve: `endurance`, `strength`, `mixed`, `easy`.
`easy` always returns zero hours, so an active-recovery walk can never start or
shorten a countdown.

`recoveryModelVersion` (in `RecoveryModels.swift`) must be bumped whenever the
numbers change. It is stored on every estimate so history can explain why an old
window disagrees with what the same session would produce today. Currently **2**
(the standard/personalized split). `RecoveryEstimate` has a hand-written
`init(from:)` so version-1 records decode as the unmultiplied standard windows
they actually were.

### Things worth knowing before changing the model
- **Monotonicity is structural, not incidental.** `RecoveryCalculator.curve` is a
  continuous piecewise-linear function of relative load. Replacing it with
  discrete category buckets would break the "harder never returns a shorter
  window" guarantee that `RecoveryCalculatorTests` asserts.
- **Heart-rate coverage is the honesty check.** A lifting session returns a
  plausible average over three minutes of a sixty-minute session; TRIMP built on
  that is a lie. Below 50% coverage the model falls through to effort or energy.
- **Load scales are normalised on purpose.** Session-RPE (Foster) is multiplied by
  `effortToTrimpScale` so a 60-minute RPE-8 lift lands near a 60-minute threshold
  run. `testTheThreeSourcesLandOnAComparableScale` guards the drift.
- Numbers are tunable and were sanity-checked against the fixture table before
  any UI existed. Run it any time:
  `xcodebuild test -project Recharge.xcodeproj -scheme Recharge -destination "id=$UDID" -only-testing:RechargeTests/FixtureTableTests/testPrintFixtureTable`

### The countdown timeline
The one piece with no precedent in the fleet. Every other complication here
renders a cumulative daily number that only grows, and one entry with an hourly
refresh is enough. A countdown decays toward a fixed timestamp, so
`CountdownTimeline` pre-computes the whole descent: hourly, then every 15 minutes
through the final two hours, an entry exactly at `readyAt`, and one after it so
the face flips to Ready even if the system never refreshes. **Views must render
from `entry.date`, never from `Date.now`.**

### Onboarding reads Health before it asks anything
The flow is welcome → Health → what Health found → the gap questions → what the
number means → the tier decision. Two structural rules, both of which were bugs
first:

- **The buttons never move.** Every page ends in the same `OnboardingActions`
  block, which reserves the secondary row whether or not the page uses one.
  `testTheOnboardingButtonStaysInOnePlace` asserts the frames, not a screenshot.
- **The step list is frozen once**, when the user leaves the Health page.
  Answering a question removes it from `AthleteProfile.gaps`, so a continuously
  derived array would delete the page the user is standing on. The progress bar
  is measured against the longest possible flow until Health answers, so it can
  only ever jump forward.

`HKCharacteristicType(.dateOfBirth)` and `.biologicalSex` are in `readTypes`
because age drives the heart-rate ceiling on both tiers. Same rule as before:
nothing goes in that sheet unless something the user can see consumes it. VO2
max is still out — the evidence tying it to *recovery rate* is weak, so it does
not earn a row in the permission sheet.

The last onboarding decision is "Continue with Recharge Pro" or "Get started
with Standard". It is not a "Not now": declining there is choosing the free tier
and starting to use the app, and the button says so.

### The RPE path is the only Watch → phone write
Everything else runs phone → Watch. The effort tap has to go the other way, so it
uses `PhoneWatchSession` (ported from the retired Headache Logger): `sendMessage`
when reachable, `transferUserInfo` otherwise, plus an App Group backstop queue.
The phone names the session needing an answer via the `pendingEffortSessionID`
App Group key, because the Watch has no workout history of its own.

### Generating the project
`./scripts/xcgen.sh` (a thin `xcodegen generate`; `testflight.sh` calls it).

**A green test suite does not mean the archive builds.** `RechargeTests` builds
Debug, where `ScreenshotFixtures` exists; Release drops it and every call site
still has to type-check. That is how build 10 first failed to archive, in the
widget extension, with the whole suite passing. Anything touching
`ScreenshotConfig` or `ScreenshotFixtures` wants a
`-configuration Release -destination generic/platform=iOS` build before you
trust it.

**StoreKit Testing does not activate under `xcodebuild test`.** The `.storekit`
file was referenced from the scheme's Test action, from a test plan (every
relative-path spelling), and started with `SKTestSession` from the UI-test
runner; in all three the app under test reached the live `storekitd` and
`Product.products(for:)` returned an empty array. The test plan and
`patch-schemes.py` are gone. It still works for the **Launch** action, so
running the Recharge scheme from Xcode gets the local catalogue.

StoreKit product identifiers are bundle-prefixed
(`com.jackwallner.recovery.yearly`) in both `Recharge.storekit` and
`RechargeProduct`. Bare identifiers like `yearly` are silently not vended.

## App-specific notes
- **Compliance is enforced in tests.** `testReasonsNeverMakeAMedicalClaim` and
  `testNoPhaseCopyMakesAMedicalClaim` fail on "recovered", "safe to train",
  "injury", "your body", "cure", "diagnos". The output is a *cardiovascular
  training estimate*, always. Health & Fitness category, so the **Regulated
  Medical Device declaration must be set in the ASC UI** or submission blocks.
- **Review funnel trigger:** a countdown reaching Ready
  (`ReviewPromptTracker.recordReadyMoment`), gated at two Ready moments so the
  loop has paid off twice before the ask.
- **`RootView` is the only place that may interrupt.** What's New, the review
  ask, and the passive trial offer are evaluated in that order and stop at the
  first one that fires; all of them yield to a sheet Today is already showing,
  which it reports through `isPresentingSheet`. SwiftUI silently drops a second
  present, and a review prompt that never appeared has still spent the one
  chance the funnel gets. The trial offer additionally needs the 14-day
  `passiveTrialOfferAllowed` cooldown, a resolved `customerInfo`, and a loaded
  package.
- **What a screen may explain:** `RecoveryResolver.current` keeps returning a
  stale estimate so history and the snapshot have something to carry;
  `RecoveryResolver.explanation` is what a screen showing the phase may narrate.
  Past the four-day cutoff they diverge, and using `current` there puts a live
  window beside a "no workout yet" hero.
- **Freshness is user-visible.** A failed HealthKit query returns nothing rather
  than an empty store, so `RecoveryEngine.lastSuccessfulImport` /
  `lastImportFailed` drive the Today footer and the Settings Health status row.
  iOS never reports read authorization, so that row reports what Health
  *returned*, never which categories were granted.
- **Paywall verification:** it renders empty under plain `simctl launch` — no
  RevenueCat on simulator and no StoreKit catalogue. Under screenshot mode the
  plan cards come from `StoreService.screenshotPackages`, whose prices mirror
  `Recharge.storekit` and ASC; keep them in step.
  `testPaywallRendersRealProductsUnderStoreKitTesting` in `RechargeUITests`
  asserts all three cards and attaches the render. That covers **layout**;
  localized/PPP price formatting is still only observable on device. Never sign
  off on paywall spacing from a `simctl` screenshot.
- **Screenshot mode:** `RECHARGE_SCREENSHOT_MODE=1` +
  `RECHARGE_SCREENSHOT_SCENE=<recovering|ready|history|settings|paywall|premiumActive|onboarding|watchRecovering|watchReady>`.
  Bypasses HealthKit entirely and seeds `ScreenshotFixtures`.
- `RevenueCatConfig.apiKey` is a placeholder in the repo. `scripts/testflight.sh`
  substitutes `RC_PUBLIC_KEY` from `~/.recovery_credentials` for the archive and
  restores the placeholder on exit, so the key never lands in a commit. Never
  configure it on simulator.
- **App Store ID is `6797089337`** (`com.jackwallner.recovery`). The ASC record
  is still named "Recovery App Placeholder"; the real name, subtitle, and
  keywords are in `fastlane/metadata/en-US/` and have not been uploaded yet.

## Open tuning questions
1. Relative load is measured against the **median** of the person's sessions,
   which is dominated by easy days, so a genuinely hard session reads as a large
   multiple. A percentile-rank classification would be more robust. Deferred
   until real user data exists.
2. The absolute countdown floor (`RecoveryCalculator.absoluteCountdownFloor`,
   18 load units, ~a 20-minute walk) and the 25th-percentile quiet threshold are
   both first-pass values.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
