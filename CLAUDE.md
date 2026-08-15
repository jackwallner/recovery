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
196-test suite in `RechargeTests` possible without a Health store.

| File | Stage |
|---|---|
| `SessionLoadCalculator` | one workout → one load. HR-reserve TRIMP, then reported effort, then energy, then duration. Also `intensityFraction`, the HR-reserve quality proxy. |
| `RecoveryBaseline` | the person's own recent loads; median, 25th percentile, sample count. Below `minimumSamples` the median is shrunk toward the population reference (see below). `.standard(for:)` is the no-samples reference the free tier uses. |
| `RecoveryCalculator` | relative load → bounded hours, context adjustment, calibration, personalization, clamp. |
| `AthleteProfile` | who the person is: age, sex, experience, volume, bounce-back. Every field carries its own multiplier, and `gaps` is what onboarding still has to ask. |
| `PersonalRecoveryModel` | the 30-day analysis → one bounded personal multiplier. |
| `RecoveryResolver` | several overlapping windows → the one to show (latest `readyAt`). |
| `WorkoutClassifier` | `HKWorkoutActivityType` raw value → one of four profiles. All 84 raw values are pinned and tested against the SDK's own numbering; the table was silently off by one from `badminton` (4) through `crossTraining` (11) for the app's whole life, because it omitted `australianFootball` (3). |
| `CountdownTimeline` | the entry schedule a decaying countdown needs. |

### The two tiers
`RecoveryTier` is stored on every estimate, because the two answer different
questions and a history list that mixes them silently is lying by omission.

- **Standard (free).** `RecoveryBaseline.standard(for:)`, no context, no
  calibration, `RecoveryPersonalization.standard`. The same table for everyone:
  session type, length, and intensity in, hours out. Confidence is capped at
  medium and never reports `buildingBaseline` — there is no baseline being
  built. Category labels drop the "for you".
- **Personalized (Recharge+).** The person's own 42-day baseline, overnight
  context, calibration, and the `PersonalRecoveryModel` multiplier.

Age-predicted maximum heart rate (Tanaka, or Gulati for women) applies on
**both** tiers. It is a measurement input, not a personalisation: scoring a
58-year-old against a flat 185 bpm ceiling does not make the free estimate
standard, it makes it wrong.

Every session is scored **both** ways on both tiers, and
`RecoveryEngine.personalizedPreview` carries the most recent qualifying one:
standard hours beside personalized hours, for the conversion surfaces. It is
computed, never derived. Multiplying the standard hours by
`personalAnalysis.factor` was the old version and it dropped the larger of the
two effects — personalisation changes the *baseline* a session is measured
against as well as applying the multiplier — so the card sometimes showed the
same number twice and hid itself. It falls back to
`PersonalizedPreview.reference` (the canonical hard session, a real point on the
real curve) when there is no qualifying session or the two land on the same
rounded hour, so there is always a difference on screen and it is always
arithmetic.

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
window disagrees with what the same session would produce today. Currently **4**
(the energy path moved onto the TRIMP curve and the mixed blind guess came down
from RPE 7 to 6). `RecoveryEstimate` has a hand-written
`init(from:)` so version-1 records decode as the unmultiplied standard windows
they actually were.

### The load ladder is an order of trust, and for strength it was wrong
Heart rate, then reported effort, then energy, then duration. For endurance that
order is right. For **strength** it produced the worst bug the model has had: the
same 60-minute lift scored 5.3 hours with a clean heart-rate trace, 7.2 hours
from energy alone, and 24 hours once the user answered the effort prompt. More
information made the number smaller, and answering the question the app itself
asked was punished with a shorter window.

Every signal under-reads a lifting session, each in its own way, so
`SessionLoadCalculator.strengthLoad` takes the **maximum** across heart rate,
effort, energy, and the duration-only guess rather than the first available one.
`durationLoad` is in that maximum as the floor, not as a last resort: sixty
minutes of resistance work costs what it costs, and a heart-rate trace reading a
third of the energy-derived figure is the sensor being wrong.

**Mixed deliberately does not include energy in its maximum.** Court and combat
sports hold the optical signal, so heart rate there is a real measurement rather
than a systematic under-read, and letting the coarse energy inference outbid it
turned a 90-minute social tennis match into a 36-hour window.
`testEnergyDoesNotOutbidHeartRateOnAMixedSession` pins that.

### Every source estimates the same quantity, and now on the same curve
The three load sources answer one question — what fraction of heart-rate reserve
did this session sustain — and `SessionLoadCalculator.trimpPerMinute` is the
single definition of what a minute at that fraction costs. Heart rate measures
the fraction; energy infers it from the burn rate through
`referenceEnergyAtFullReserve` (15.6 kcal/min, from %HRR ≈ %VO2R for a 75 kg
adult at 45 ml/kg/min); duration falls back to the type's `assumedEffort`.

The energy path used to map kilocalories onto a perceived effort on a straight
line while the heart-rate path used Banister's exponential. Two different
shapes: they agreed for a hard session and the inference roughly **doubled** the
measurement for an easy one. A 60-minute easy run therefore scored *no countdown
at all* from a clean heart-rate trace and an eighteen-hour countdown from the
phone's calorie estimate alone — the same session, logged on two devices,
disagreeing about whether it had happened.

`WorkoutProfile.mixed.assumedEffort` came down from 7 to 6 for the reason
strength's came down from 6 to 5: at 7 the blind guess outscored every informed
source for a typical session, so a manually entered game beat a recorded one and
the longest window in the app belonged to the session it knew least about.

**The residual is body mass, not intensity.** HealthKit's active energy already
accounts for weight, so a heavier or fitter person burns more at the same reserve
fraction and the inference over-reads them. Reading body mass would fix it and
costs a new row in the Health permission sheet; it has not been done. An
energy-derived load never rates better than low confidence on a session that can
set a long window, which is the honest thing available today.

### The audit is in the repo, and it is what found the last two bugs
`RechargeTests/AthleteMatrix.swift` is the population: every activity type
HealthKit defines (plus one it does not), at three durations and three
intensities, for seven personas — a 24-year-old newcomer, a masters endurance
athlete whose predicted ceiling is well under the 185 default, a lifter, a hybrid
athlete, a 66-year-old returner, the modal recreational user, and someone who
answered nothing at all — under seven combinations of working sensors. Around
thirty thousand scored sessions per tier, none of them chosen because the model
looked good on it.

`RecoveryMatrixTests` asserts **properties**, not values, so a tuning change may
move every number in the table but may not: invert monotonicity in duration or
intensity, let an honest hard effort answer shorten a window, let a personal
detail reach a standard estimate, make a bigger training history lengthen a
window, produce a non-finite or unbounded countdown, or make a medical claim.

Sensor-availability spread, model version 4, measured by
`testSensorAvailabilityDoesNotMoveTheWindowMuch` (which prints the table):

| profile | mean | p95 | worst |
|---|---|---|---|
| endurance | 1.63x | 2.84x | 2.97x |
| strength | 1.36x | 2.29x | 2.33x |
| mixed | 1.87x | 3.42x | 3.53x |

Read those with the guarantee beside them, because the guarantee is the stronger
statement: for **strength**, more information may only ever *lengthen* the
window, since the rule takes a maximum across all four sources and a maximum over
a superset cannot be smaller
(`testForAStrengthSessionMoreInformationNeverShortensTheWindow`). The spread that
remains is almost entirely the blind fallback — a session with no heart rate, no
energy, and no effort answer is scored at what its type usually costs, and no
such guess can know that this particular hour was an easy one.

An earlier version of this file claimed a mean of 1.23x from a 36-session x
5-persona matrix that was never committed. The numbers above replace it because
they can be reproduced from the repository.

### A thin baseline is shrunk, because everything is divided by it
`RecoveryBaseline.typicalLoad` is the denominator of every relative load, so on a
three-session history the whole model is dividing by a description of three
sessions. The matrix found what that does: a 24-year-old three days into using
the app got **57 hours** for an ordinary 60-minute lift, and a 66-year-old got
the full 72-hour cap, purely because a moderate session is a large multiple of a
small number.

Below `minimumSamples` (8) the personal median is now blended geometrically with
the profile's `standardTypicalLoad` on a weight that grows with the sample count;
at 8 and above it returns the median exactly, as before. The two figures above
became 27 and 34 hours. It is the same shrinkage shape `PersonalRecoveryModel`
uses to fold evidence into the questionnaire prior, and it says the same thing:
personalisation earns its way in.

`quietThreshold` already had this property — it stays at the absolute floor until
the sample is big enough — so the two halves of the baseline now agree about when
the person's own history starts counting.

### The six-hour floor is Garmin's, and it is sourced
`RecoveryCalculator.minimumCountdownHours` is 6, because Garmin documents its
recovery time as spanning "a minimum of 6 hours to a maximum of 4 days" (Edge 840
and fenix 7 owner's manuals). A session either earns a countdown or it does not;
one that earns three hours at 6pm is Ready before bedtime, which reads as the app
having quietly ignored the workout. It is applied after every other adjustment,
and monotonicity survives because a maximum against a constant is still
non-decreasing.

The **maximum** deliberately stays at 72h against Garmin's documented 96h. We
have less signal and the conservative end is the safer one for a health app.

Firstbeat publishes **no** strength-training method at all — the EPOC/Training
Effect white papers are entirely HR-driven cardio, and the recovery-time
hours-mapping itself was never published. So the strength handling above is a
design decision defended by internal consistency, not a number copied from a
reference. Say so rather than implying otherwise.

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

The last onboarding decision is "Continue with Recharge+" or "Get Started". It is
not a "Not now": declining there is choosing the free tier and starting to use
the app, and the button says so. "Get Started" sits **above** the CTA, in the
same reserved secondary slot `OnboardingActions` gives every other page, so the
primary button is the lowest thing on every screen of the flow (the Vitals /
VO2 Max shape). The trial is named in a `Theme.pro` callout above the price and
never on the button: Apple 3.1.2(c) weighs pricing elements against each other,
and the billed amount has to stay the largest one.

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
- **App Store ID is `6797089337`** (`com.jackwallner.recovery`). `fastlane/metadata/`
  is canonical and is uploaded, not aspirational: as of 2026-08-15 the ASC record
  is named "Recharge Workout Recovery Time", version 1.0.0 is in
  PREPARE_FOR_SUBMISSION with build 14 attached, and **all 50 locales** carry a
  name, subtitle, keywords, description, promotional text and release notes.
  Push edits with `scripts/upload-appstore-metadata.sh` and confirm with
  `scripts/asc-readiness.py`, which diffs ASC against the files and exits
  non-zero on any drift (464 checks, 400 of them the locale diff).
  `scripts/validate-metadata.py` runs first and enforces the field lengths
  (name 24-30, subtitle 24-30, **keywords 94-100**) plus no duplicate keyword
  token and no keyword that repeats a word already in the name or subtitle. The
  24-character floor drops to 12 for `ja`, `ko`, `zh-Hans` and `zh-Hant`,
  because 24 CJK characters is a sentence, not a name.
- **The 49 non-English locales are generated, not hand-edited.**
  `scripts/native_locale_content/*.json` is the source; `apply-native-locales.py`
  writes the folders and `check-native-locales.py` runs the same limits against
  the source so a bad length is caught before 50 folders exist. Editing
  `fastlane/metadata/<locale>/` directly is fine for a one-off but the next apply
  overwrites it. en-US is the exception and is hand-maintained.
- **`products.json` is the customer-facing IAP copy for all 50 locales**, and
  `scripts/asc-sync-product-localizations.py` is what pushes it (the setup
  scripts also write prices, availability and intro offers, which is not what you
  want for a copy change). Premium branding is **Recharge+** everywhere a
  customer can see it; the ASC *reference* names still say "Recharge Pro"
  because Apple makes those immutable and nobody sees them.
  **Products attached to a review submission are locked** — a copy PATCH returns
  409 `ENTITY_ERROR.ATTRIBUTE.INVALID.UNMODIFIABLE`, and a never-submitted
  submission cannot be cancelled, so deleting its items is the only way through.
  ASO reasoning and the measured popularity/difficulty tables live in
  `docs/positioning.md` (en-US) and `docs/localization-aso.md` (per store); the
  numbers come from the Astro tracker, app id `123`.

## Open tuning questions
1. Relative load is measured against the **median** of the person's sessions,
   which is dominated by easy days, so a genuinely hard session reads as a large
   multiple. A percentile-rank classification would be more robust. Deferred
   until real user data exists.
2. The absolute countdown floor (`RecoveryCalculator.absoluteCountdownFloor`,
   18 load units, ~a 20-minute walk) and the 25th-percentile quiet threshold are
   both first-pass values.
3. **The reported-effort path still has the shape mismatch the energy path just
   lost.** `effortToTrimpScale` is a straight line calibrated at the hard end: 60
   minutes at RPE 8 scores 144 against a heart-rate reading of 143, which is why
   it was chosen, but 60 minutes at RPE 4 scores 72 against a reading of 41. The
   fix is the same one energy got — map the RPE to a reserve-equivalent (RPE/10
   is close to the ACSM correspondence) and run it through `trimpPerMinute` —
   and it lands almost exactly on the current value at RPE 8, so the anchor
   survives. It was **not** done before 1.0 because it moves every blind
   `assumedEffort` fallback onto the new curve as well, which cuts a no-data
   60-minute lift from ~14h to ~7h and would undo the "sixty minutes of
   resistance work costs what it costs" floor without re-deriving all four
   constants first. It is the largest remaining source of sensor spread and the
   thing to do first when the model is next opened. `RecoveryMatrixTests` will
   show the improvement directly.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
