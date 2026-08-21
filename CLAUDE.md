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
269-test suite in `RechargeTests` possible without a Health store.

| File | Stage |
|---|---|
| `SessionLoadCalculator` | one workout → one load. HR-reserve TRIMP, then reported effort, then energy, then duration. Also `intensityFraction`, the HR-reserve quality proxy. |
| `RecoveryBaseline` | the person's own recent loads; median, 25th percentile, sample count. Below `minimumSamples` the median is shrunk toward the population reference (see below). `.standard(for:)` is the no-samples reference the free tier uses. |
| `RecoveryCalculator` | relative load → bounded hours, context adjustment, calibration, personalization, clamp. |
| `AthleteProfile` | who the person is: age, sex, experience, volume, bounce-back, plus what Health measured — VO2 max, the observed maximum heart rate, body mass. Every field carries its own multiplier, and `gaps` is what onboarding still has to ask. |
| `PersonalRecoveryModel` | the 30-day analysis → one bounded personal multiplier. |
| `RecoveryResolver` | several overlapping windows → the one to show (latest `readyAt`). |
| `WorkoutClassifier` | `HKWorkoutActivityType` raw value → one of four profiles. All 84 raw values are pinned and tested against the SDK's own numbering; the table was silently off by one from `badminton` (4) through `crossTraining` (11) for the app's whole life, because it omitted `australianFootball` (3). |
| `CountdownTimeline` | the entry schedule a decaying countdown needs. |
| `HealthIngestSummary` | the receipt: every reading Health actually supplied, phrased for the user. Onboarding, the trial page, Settings, and the Recharge+ tab all render it. |

### The two tiers
`RecoveryTier` is stored on every estimate, because the two answer different
questions and a history list that mixes them silently is lying by omission.

**The line between them is measurement, not personalisation.**

- **Standard (free).** The standard model at the training level the user
  *stated*: `RecoveryBaseline.standard(for:fitnessScale:)`, no context, no
  calibration, `RecoveryPersonalization.standard`. Session type, length and
  intensity in, hours out, against a population reference scaled by
  `AthleteProfile.fitnessScale`. Confidence is capped at medium and never
  reports `buildingBaseline` — there is no baseline being built. Category labels
  drop the "for you".
- **Personalized (Recharge+).** The person's own 42-day baseline, overnight
  context, calibration, and the `PersonalRecoveryModel` multiplier. Everything
  that comes from what they have actually *done*.

`AthleteProfile.fitnessScale` is the one thing about the person that reaches the
free tier, and it is there because Garmin's default is profile-based too:
Firstbeat scales EPOC by an activity class the user enters at setup (0-2
beginner, 3-5 already training, 6-7 highly fit), so the pre-measurement number is
already tuned to a stated level. One denominator cannot serve both a beginner and
a six-times-a-week runner, and `standardTypicalLoad` alone is only the right
answer for somebody sitting exactly in the middle of the scale.

Only the two questions that are genuinely about *training level* feed it —
`WeeklyVolume` and `TrainingExperience` — combined as a geometric mean rather
than a product, because they are **correlated**: someone who has trained ten
years usually also trains often, and multiplying would count one fact twice. The
span is 0.81 to 1.28, so a denominator between about 57 and 90 against the
reference 70. `BounceBackHabit` and the age factor are claims about recovery
*kinetics* rather than training level and stay in `AthleteProfile.prior`, on the
paid tier.

`testMoreTrainingNeverLengthensTheStandardWindow` pins the direction and
`testEveryStatedFitnessLevelStillAnswersAHardHourLikeAHardHour` pins the
envelope. The free-tier promise is now "the same estimate for everyone **who
answered the same way**", asserted by
`testTheStandardEstimateIsIdenticalForTwoPeopleWhoAnsweredTheSameWay`, and
`RecoveryMatrixTests.testTheStandardTierDependsOnTheSessionAndTheHeartRateRangeOnly`
carries the fitness scale in its key so nothing the person has *done* can leak in
behind it.

`weeklyVolume` may be **derived** from the imported history rather than typed
(`RecoveryEngine.derivedTrainingProfile`, 6+ sessions in 28 days), so a free
user's training level can move without them answering anything. Deliberate, and
what Garmin does — activity class updates itself as the watch sees more training.
It stays inside the tier line because what reaches the free estimate is a
four-level bucket, not the person's own distribution of loads.

**VO2 max reaches the free tier**, alongside the two training-level questions,
through `AthleteProfile.vo2Factor` — anchored at 45 ml/kg/min (the same
reference adult `referenceEnergyAtFullReserve` is derived from), square-rooted
because an ordinary training day grows more slowly than capacity does, and
bounded to the same 0.78–1.40 the weekly-volume term already spans so a third
measured term cannot widen the range `GarminAnchorTests` was fitted at. It is
never asked for: it is read or it is absent. It belongs on this side of the tier
line for the same reason the heart-rate ceiling does — it is a *measurement of
training level*, not a personalisation of the window, and what Recharge+ sells
is scoring a session against the person's own distribution of loads.

The maximum heart rate every session's intensity is measured against is now the
person's **observed** one, with the age formula as the fallback rather than the
answer (`AthleteProfile.effectiveMaxHeartRate`). An age formula is a population
average with a standard deviation of 10–12 bpm, which is enormous at the scale it
is used: the whole heart-rate path is `(average − resting) / (max − resting)`, so
a ceiling 12 bpm wrong misprices every session that person will ever record, in
the same direction, forever. Two percentiles guard it — the 98th *within* a
session in `HealthKitService`, the 90th *across* sessions in
`RecoveryEngine.observedMaxHeartRate()` — so one optical artefact cannot become
somebody's permanent ceiling, and `mergeHealthDerivedProfile` only ever lets the
stored figure **rise**, because a quiet month is not evidence the ceiling came
down. The observed figure is only believed when it is at least as high as the
predicted one: a real maximum is elicited by a maximal effort, and a user who has
never gone that hard would otherwise have every intensity reading inflated.

Both apply on **both** tiers. Scoring a 58-year-old against a flat 185 bpm
ceiling does not make the free estimate standard, it makes it wrong; and so does
scoring anybody against a formula when 120 days of their real heart rate are
sitting in Health.

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

### Recovery time stacks, and the residual has to be persisted
A session done inside a running countdown starts its own from where that
countdown would have finished rather than from now, so two hard sessions in a day
cost more than one. Recharge used to take the **maximum** of overlapping windows,
which is the simplest defensible rule and the wrong one: a same-day double read
exactly like a single session, at the one moment somebody coming from a Garmin
expects the number to jump.

`RecoveryCalculator.carriedHours(into:from:)` is the whole rule and it is pure.
The caller that walks the chain lives in `RecoveryEngine.rescore`, which is also
where the subtlety is. **The two tiers carry separate chains.** A standard window
and a personalized window for the same session end at different times, so one
shared residual would splice one tier's arithmetic into the other's.

`hours` stays the session's own cost and `totalHours` is what the countdown
actually runs for, because the two answer different questions: the tier
comparison and `recoveryCostHours` are about the session, while the ring,
`readyAt` and the snapshot are about the countdown. Only a
session that earns a countdown of its own may inherit one, so an easy walk taken
mid-window still cannot start or lengthen anything.

**`carriedHours` has to be stored, and the first cut did not store it.** It was
computed, published and rendered without ever reaching `RecoveryStateRecord`.
`readyAt` is persisted and `hours` is the session cost, so a record that forgets
the residual rehydrates self-contradictory: the countdown ends where an 18-hour
window ends while every figure derived from `totalHours` says 12, and the
"incl. 6h carried" line disappears from exactly the rows that need it. Nothing in
the suite could see it, because `Shared/Models/RecoveryRecords.swift` was not in
the test target. It is now, and `StackedRecoveryPersistenceTests` covers the
round-trip, the rescore path, the legacy nil, and the version bump.

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
window disagrees with what the same session would produce today. Currently **10**
(the app measures more of what it was guessing: the heart-rate ceiling is the
person's own observed maximum rather than an age formula, VO2 max joins the two
training-level questions in `fitnessScale`, body mass closes the energy path's
mass residual, overnight respiratory rate joins the context adjustment,
heart-rate recovery joins the 30-day analysis, and every session carries a
`recoveryCostHours`; 9 clamped the uncertainty range and the non-finite inputs;
8 made recovery time cumulative, see "Recovery time stacks"; 7 scaled the
standard tier to the user's stated training level; 6 re-anchored the standard
reference to Firstbeat's activity class 3-5; 5 was the daily-load baseline fix;
4 moved the energy path onto the TRIMP curve and brought the mixed blind guess
down from RPE 7 to 6). `RecoveryEstimate` has a hand-written `init(from:)` so version-1 records
decode as the unmultiplied standard windows they actually were.

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

**The residual was body mass, and it is now corrected.** HealthKit's active
energy already accounts for weight, so at the same fraction of heart-rate reserve
a 95 kg athlete burns about a quarter more than a 75 kg one, and dividing both by
the same constant read the heavier one as having worked harder — in the same
direction, on every calorie-derived session they ever record.
`SessionLoadCalculator.referenceEnergy(forBodyMass:)` scales the 15.6 kcal/min
reference linearly with mass (bounded 0.6–1.7, because the rest of the derivation
is fixed and one implausible weight sample must not halve or double a history),
falling back to the reference adult when Health has no weight — which is exactly
what this path did before. It is what body mass is in the permission sheet for,
and it is consumed by nothing else: how much somebody weighs says nothing about
how fast they clear a training load, and an app that quietly made heavier users
wait longer would be making a claim it cannot support.

What is left is fitness: at the same reserve fraction a fitter person of the same
mass burns more, and nothing in Health measures that closely enough to divide by.
So an energy-derived load still never rates better than low confidence on a
session that can set a long window.

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

### "Typical" is a training day, and a skewed week is not its middle
The worst inversion the model has had, reported from a real Health store: a user
who trains several times a day was told his ordinary hard ride was a **72-hour**
window against a **20-hour** standard. Training more bought a longer window, and
every extra session made it worse. It took two fixes, and the second only became
visible once the first was in.

**Sessions to days.** `RecoveryBaseline.typicalLoad` was the median of his own
*sessions*, and when most sessions are twenty-minute spins the median **is** a
twenty-minute spin, so a real ride read as 5.2x normal and pinned the ceiling. It
is built from `dailyLoads` now — the same history totalled per day — because
relative load asks what the person is adapted to, and adaptation is a property of
how much they train rather than how they slice it up.

**Median to geometric mean.** Totalling per day fixes the *frequent* trainer and
does nothing for the *polarised* one, whose week is a lot of small days and two
big ones. The reported rider is exactly that shape: 647 load units a week against
a population reference of 210, and yet his median *day* was 57.5, **below** the
reference day of 70, because the middle day of his week is a spin. So he was
still told his ordinary ride was twice his normal and still got a longer window
than the free tier.

Training loads are roughly log-normal, and for a log-normal sample the geometric
mean *is* the median — a light user's 44.0 became 43.8, i.e. nothing measurable
changes on an evenly spread history. The two separate exactly when the
distribution is skewed, which is the case that needed noticing, and unlike an
arithmetic mean the geometric one cannot be redefined by a single three-hour
ultra. His figure moved 57.5 -> 75.2 and his hard ride 35.9h -> 24.6h, now below
the 27.3h standard where it belongs. It is also the same operation the shrinkage
one line below already performs, so both halves of the baseline combine evidence
the same way.

`quietThreshold` deliberately stays a per-session percentile. Whether a workout
was substantial enough to earn a countdown is a question about that workout;
running it off daily totals would mean somebody training three times a day needs
a single session as big as an average person's whole day before the app notices.

`HighVolumeAthleteTests` pins all of it:
`testAddingTrainingVolumeOnlyEverShortensTheWindow` (monotone in volume) and
`testThePopulationTableSitsBetweenALightUserAndAFrequentOne` (the light user
lands above the free tier, the frequent one below it). The open tuning question
about percentile-rank classification is *this* problem, and the geometric mean is
a partial answer to it rather than a replacement.

### The standard tier is anchored to Garmin's default, and the anchor is a test
`WorkoutProfile.standardTypicalLoad` has now been three values, and only the
third one was fitted to anything: 85/105/115, then **52/64/70**, now
**70/86/94**. Ratios unchanged throughout, so nothing about a lift versus a ride
has ever been retuned here — only the level.

The level matters more than anything else in the model, because it is the
denominator behind every free-tier number and the shrinkage target for a
Recharge+ user's first few weeks. And it had no guard: every other test in the
suite asserts a *relationship* (monotonicity, tier separation, "more information
never shortens a strength window"), and relationships are invariant to the level.
Both wrong values passed the whole suite.

**What Garmin actually does.** Recovery time is derived from Firstbeat's
Training Effect, which is EPOC scaled by the individual's *activity class* — a
0-to-10 scale where 0-2 is a beginner, 3-5 is someone already engaged in
training, 6-7 is highly fit, and 7.5-10 is an athlete. The class is entered at
setup, before the watch has measured anything, and Garmin's default sits in the
middle band. So the structure Recharge copies is right (an absolute session cost,
scaled by who the person is), but **"the Garmin default" is not a sedentary
person**. The hours mapping itself was never published, which is why the anchor
below is fitted to observed behaviour rather than reimplemented.

52 was chosen to describe "a lightly active adult", on the reasoning that
personalisation has to be able to bring a fit user's window *down* from the
standard. The goal was right and the constant was the wrong lever: the personal
denominator is **measured** from the user's own daily loads and is free to be two
or three times the reference, so lowering the reference never created that
headroom. It only made the free tier longer for everyone, including the beginner
it was lowered for. On the free tier an ordinary 60-minute threshold run returned
**50 hours** and a 75-minute interval session pinned the 72-hour ceiling — for a
session Garmin calls 24-48h.

`GarminAnchorTests` is the guard. Thirteen canonical endurance sessions against
the bands Garmin is observed to produce (easy 0-12h, moderate 12-24h, hard
24-48h, very hard 48-72h); 70 is the value that puts all thirteen inside their
band, and `testAnOrdinaryHardSessionDoesNotPinTheCeiling` states separately that
the 72-hour cap is a bound rather than a working value. The endurance reference
is documented as ~45 minutes at 65% of heart-rate reserve and
`testTheStandardReferenceDescribesSomeoneWhoAlreadyTrains` checks the constant
still equals that training day, so the number and its justification cannot drift
apart.

| free tier, endurance | at 85 | at 52 | at 70 | Garmin |
|---|---|---|---|---|
| 60m easy Z2 | 9.8h | 16.7h | 12.1h | 10-18h |
| 60m steady | 16.2h | 32.5h | 21.0h | 12-26h |
| 60m threshold | 25.8h | 49.8h | 33.9h | 24-48h |
| 75m intervals | 46.9h | **72.0h** | 59.5h | 40-62h |
| 2h long run | 32.2h | 60.2h | 41.7h | 36-66h |

A model-version bump also **thaws frozen records** in `RecoveryEngine.rescore`:
an estimate scored by an older model is not what the app would say today, and
leaving it frozen means a user who updates sees their whole history in the old
numbers with no way to get the new ones.

**Closed: the free tier no longer throws away the questionnaire.** It used to,
and this section used to describe that as an open decision. `fitnessScale` is
the resolution: see "The two tiers" above for what feeds it and why only two of
the four questions do. The point kept here is the one that outlived the change:
"the same table for everyone" was a *product promise*, so retiring it meant
retiring the sentence too, in the App Store description for all 50 locales and
in the `reasons` line the app prints under every standard estimate. Copy that
describes the model is part of the model's surface area, and a claim the code
has stopped honouring is a claim the app is making falsely.

### A thin baseline is shrunk, because everything is divided by it
`RecoveryBaseline.typicalLoad` is the denominator of every relative load, so on a
three-session history the whole model is dividing by a description of three
sessions. The matrix found what that does: a 24-year-old three days into using
the app got **57 hours** for an ordinary 60-minute lift, and a 66-year-old got
the full 72-hour cap, purely because a moderate session is a large multiple of a
small number.

Below `minimumSamples` (8) the personal figure is blended geometrically with the
profile's `standardTypicalLoad` on a weight that grows with the day count; at 8
and above it returns the person's own geometric mean exactly. The two figures above
became 27 and 34 hours. It is the same shrinkage shape `PersonalRecoveryModel`
uses to fold evidence into the questionnaire prior, and it says the same thing:
personalisation earns its way in.

`quietThreshold` already had this property — it stays at the absolute floor until
the sample is big enough — so the two halves of the baseline now agree about when
the person's own history starts counting.

**Confidence counts training days; the quiet threshold counts sessions.** They
are two properties now (`hasEstablishedBaseline` and `hasEnoughSamples`) because
they gate different statistics, and collapsing them into one session count made
the app overclaim. The shrinkage above weights by `dayCount`, so confidence (a
claim about the denominator) has to be counted the same way: somebody training
three times a day clears eight *sessions* on day three, and used to stop
reporting `buildingBaseline` while `typicalLoad` was still five-eighths the
population reference. It overclaimed soonest for the heaviest trainers, who are
the users most likely to go and check. `quietThreshold` keeps the session count,
because whether one workout was substantial enough to earn a countdown is a
question about that workout.
`testAnEstablishedBaselineIsExactlyWhenTheShrinkageHasLetGo` pins the
equivalence over the whole range rather than at one point.

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

### Every session carries a cost, and only some of them start a countdown
`hours` is an instruction to the countdown; `recoveryCostHours` is a description
of the session. They are the same figure for a qualifying session and they
diverge in exactly two places, both of which used to render as the word **None**:
an `easy` session, where `hours` must be zero so a walk can never start or
lengthen a countdown; and a session under the person's quiet threshold, which
does not earn a countdown of its own but is not nothing either.

That word was most of History for anyone who walks or spins on their easy days.
A list whose job is to be the evidence the app is paying attention cannot be a
column of the word "None" — it reads as an import that lost the numbers, and it
made the app look like it had ignored two thirds of the user's training.

The fix is in the model rather than in the copy. `WorkoutProfile.costMultiplier`
is `windowMultiplier` for every profile except `easy`, where it is 0.30 rather
than zero, and the cost skips `minimumCountdownHours` — that floor exists so a
*countdown* is not over before bedtime and has nothing to say about what forty
minutes of walking cost. **Nothing downstream of the countdown reads it**:
`producesCountdown`, `readyAt`, `totalHours`, the snapshot, the complication and
the stacking chain are all still `hours`, so the guarantee the `easy` profile
exists to make is untouched.

It is persisted on `RecoveryStateRecord`, for the reason `carriedHours` is and
after the same near-miss: a computed-published-rendered figure that never reaches
the record rehydrates with History showing a walk as costing nothing while the
app that wrote the record said otherwise. nil decodes as `hours`, which is the
truthful legacy value both ways round.

Today says the same thing in a sentence. The hero **always** narrates the last
session — `"9h from your run 3h ago"`, `"2h from your walk 40m ago · active
recovery, so nothing to wait out"` — including the two states that used to
disown it. "Your ride 12h ago didn't start a countdown" told the user what the
app declined to do rather than what it found, on a first launch, about the only
workout they had come to see.

### The screens are the Vitals shape now
Total Calories and VO2 Max are one large figure on an otherwise empty screen, and
they are the two in the fleet that read as finished products. Recharge's Today
was a stack of eight cards with the countdown as the first of them rather than
the whole of it.

- **Three tabs**: Today, History, and Recharge+ — the paywall before purchase and
  `RechargePlusView` after it, so the thing somebody bought keeps a place in the
  navigation instead of dissolving into settings rows. **Settings is not a tab**;
  it is a gear button on Today, which is what freed the third slot.
- **The tab bar floats over the content.** `ZStack(alignment: .bottom)` plus
  `.ignoresSafeArea(edges: .bottom)`. It was briefly given a layout row of its
  own — `VStack { content; tabBar.background(Theme.background) }` — which paints
  an opaque strip the width of the screen under the capsule and reads as a black
  box with a pill inside it. The cost of overlaying is that every scrollable tab
  must reserve room at rest: `tabBarClearance()`, applied **inside** each
  `NavigationStack` (see below), and a `safeAreaInset` on the paywall, whose CTA
  lives in its own bottom bar and cannot reserve its own.
- **The third tab is built on first visit.** An opacity-zero `PaywallView`
  sitting behind Today puts a second element with every one of its identifiers
  into the accessibility tree, so `firstMatch` on the purchase button picks the
  invisible one and then truthfully reports that it is not hittable. It also
  stopped the paywall fetching products on every cold launch.
- **Everything that explained the number moved to `EstimateDetailView`**, one
  sheet reached from either the ring on Today or a row in History. Everything
  that configured it moved to Settings. The App Review 1.4.1 disclaimer went with
  the explanation, which is where somebody asking what the number means ends up.

### The onboarding copy is centred, and it was not before
`OnboardingScroll` is the container every page uses. The previous version wrapped
its content in a plain `ScrollView` whose inner stack carried `minHeight: 0`, so
the two `Spacer`s meant to centre it had nothing to expand into and collapsed:
the title sat against the top of the screen, the buttons against the bottom, and
every page whose copy was short — most of them — had a hand's width of nothing in
between. That is the "lot of blank space" the flow was reported for.

The scroll view is not optional even so: at an accessibility content size the
icon, title and message are several times taller than the screen, and a fixed
`VStack` there clipped them. `minHeight: proxy.size.height` is what makes one
container do both jobs. The slack is deliberately **not** split evenly — the
lower spacer is capped at 32pt so the surplus goes upward and the copy always
comes to rest just above the decision.

### The pitch is two numbers
Average recovery time, an arrow, theirs. That is the whole of it, on the
onboarding offer page, the passive half sheet, Today's one card, and the Settings
row. Both figures come from `RecoveryEngine.personalizedPreview`, computed on
both tiers so no surface ever has to invent one, and the free tier blurs the
right-hand figure rather than replacing it — a mocked-up number on a paywall is a
number somebody will hold the app to.

It replaced a three-column rest-pattern table (You / Similar / Yours, per
intensity band) that answered the same question with nine figures, three of them
measurements, three estimates and three blurred. `RestPattern` and
`RestPatternCard` are deleted.

Under it, on the onboarding page, is `HealthIngestSummary`: every reading Health
actually supplied, printed back. That is the evidence the number on the right came
from somewhere, and it is more persuasive than a feature list because the user
recognises their own data in it. **A row only exists when there is a real value
behind it** — no "not available", no em dashes. A receipt for something that was
not read is not evidence of anything.

The passive offer is a **half sheet** (`TrialOfferSheet.detentHeight`), as in
Vitals: the thing it is arguing about is the countdown on the screen behind it,
and a full-screen cover hides the one piece of evidence the pitch depends on.

### The countdown timeline
The one piece with no precedent in the fleet. Every other complication here
renders a cumulative daily number that only grows, and one entry with an hourly
refresh is enough. A countdown decays toward a fixed timestamp, so
`CountdownTimeline` pre-computes the whole descent: hourly, then every 15 minutes
through the final two hours, an entry exactly at `readyAt`, and one after it so
the face flips to Ready even if the system never refreshes. **Views must render
from `entry.date`, never from `Date.now`.**

Two things went wrong on the wrist and both looked like a broken complication:

- **The value did not tick.** `CountdownFormat.compactRemaining` returned a bare
  `"\(days)d"` above 24 hours, which is where most of the app's range lives: a
  72-hour window read `3d` for a full day, then `2d` for a full day, then `1d`
  for a full day, while the timeline dutifully carried seventy hourly entries
  that all rendered the same three characters. It steps down through `2d 23h`,
  `23h`, `1h 20m`, `18m` now, capped at six characters so a circular or corner
  slot still fits it. The guarantee is
  `testTheCompactCountdownChangesAtLeastOnceAnHourAcrossTheWholeRange`, asserted
  over every minute of the range rather than at sample points — the old tests all
  passed because none of them asked whether two entries an hour apart *differ*.
- **A fresh install rendered `--`, and stayed that way.** Two devices, two App
  Group containers, so a snapshot has to cross WatchConnectivity and be written
  to the Watch's own disk. The extension cannot take that delivery itself — a
  widget extension is not a running process that can be sent anything, it is
  spun up to answer "give me a timeline" and torn down, so whatever it needs must
  already be on disk. **The user should never have to open the Watch app for
  that to happen**, and `WatchAppDelegate` is the whole reason they do not: the
  system wakes it in the background to take delivery, and it writes the App
  Group and reloads the timelines.

  `handle(_ backgroundTasks:)` broke that chain in three ways and between them
  made "open the Watch app first" the normal case. It completed every task
  immediately, including `WKWatchConnectivityRefreshBackgroundTask` — which is
  the system saying "stay alive, data is arriving", and completing it before
  `hasContentPending` clears lets the payload be dropped. It never scheduled the
  next `WKApplicationRefreshBackgroundTask`, and watchOS background refresh is a
  chain, so the app went quiet after the first wake. And it handed every task
  type the same completion call, which is wrong for a snapshot task. Fixed, with
  `PhoneWatchSession.waitForPendingContent` holding the connectivity task open.

  `ComplicationCopy.DataState.neverSynced` covers the window before the first
  delivery lands and says "Open Recharge to set up". That window should be brief,
  and if a user reports it persisting, the background-wake path is what to look
  at, not the copy.

- **The chain starts on the phone, and its first link was missing.**
  `HealthKitService.enableBackgroundDelivery` installs the observer queries, and
  it was reachable only from the scene's `.task`, by way of
  `synchronizeAuthorization`. A scene is not connected when HealthKit background
  delivery relaunches the app, so the wake a finished workout generates arrived
  at a process with no observer running and did nothing: the phone never
  rescored, never published, and every downstream link — application context,
  Watch wake, App Group write, timeline reload — was waiting on a push that was
  never sent. Apple's guidance is to re-execute observer queries as early in
  launch as possible, so it runs from `RechargeApp.init` now, gated on
  `hasCompletedSetup && !hasDeferredHealthAccess`. It is idempotent
  (`installedObserverTypes` de-duplicates), so the scene path calling it again
  costs nothing.

  **Moving only the observer left the next link behind.** `sendSnapshot` is
  guarded on `activationState == .activated` and returns silently otherwise,
  and `PhoneWatchSession.activate()` was itself called only from the scene's
  `.task` — so a background wake recalculated correctly, wrote the phone's App
  Group, updated the iOS widgets, and published to nobody. The wrist heard
  nothing until the app was next opened by hand, which is the same symptom with
  a different cause one step down the chain. Activation is in `RechargeApp.init`
  now, where Apple says to put it, and `waitForActivation` holds the
  `BGAppRefreshTask` and the observer refresh open until it lands rather than
  trusting the `activationDidCompleteWith` republish, which only helps while the
  process is still alive.

  The general shape is worth stating once: **every link in this chain is guarded
  by a silent `return`, and each one is only as good as the link before it.**
  HealthKit observer, `WCSession` activation, `updateApplicationContext`, the
  Watch's background task, the App Group write, the timeline reload. Fixing one
  and leaving the next in a scene callback moves the failure rather than
  removing it.

  `BGTaskSchedulerPermittedIdentifiers` and `UIBackgroundModes: fetch` were in
  `Info.plist` with nothing registering or submitting a task — a background mode
  the app claimed and did not use, which is also an App Review 2.5.4 problem.
  `com.jackwallner.recovery.refresh` is a real `BGAppRefreshTask` now, on the
  same 30-minute backstop cadence as the Watch's, and Vitals has had exactly
  this since the beginning.

- **A watch background task must not complete before the write lands, and two
  ways of getting that wrong survived the first fix.** `hasContentPending` going
  false means WatchConnectivity has *called its delegate*, not that anything is
  on disk: `forwardSnapshot` still has to hop to the main actor before
  `applyInboundSnapshot` writes the App Group, and completing the task in that
  gap suspends the app between "delivered" and "saved". `inflightApplies` is
  incremented on the delegate queue, before the hop, so `waitForPendingContent`
  can see deliveries that have not finished landing.

  The `WKApplicationRefreshBackgroundTask` case had the same shape as the bug it
  was written to fix: it called `activate()`, which is asynchronous, and
  completed. That task almost always runs in a *fresh* process — the app is
  killed between wakes — so it completed before the session finished activating,
  which made the backstop a no-op in precisely the case it exists for. And on
  that wake there is no pending content to wait for, so the replayed
  `receivedApplicationContext` is the only thing there is to apply and the
  `activationDidCompleteWith` hop that would have applied it loses the race by
  default. `applyReplayedContext` does it synchronously at the end of
  `waitForPendingContent`.

  That replay runs on every wake, so it is usually the *same* payload the wrist
  already holds, and `reloadAllTimelines` spends the budget the countdown needs.
  `applyInboundSnapshot` compares before reloading, and
  `testAReplayedSnapshotComparesEqualSoTheWakeCanSkipTheReload` pins the
  round-trip equality that comparison rests on.

- **"Never synced" was being inferred from the wrong question.** The complication
  asked `snapshot.hasSession`, so a user who had synced perfectly well but simply
  had not trained in four days was told to open Recharge and set it up, with
  nothing to set up and no way to clear it short of doing a workout. An empty
  snapshot and a *missing* one decode to the same value, so only the presence of
  the App Group key separates them: `RecoverySnapshotStore.loadIfPresent` and
  `hasEverSynced` are that distinction, and `load` keeps its forgiving behaviour
  for every caller that just wants something to draw. "No recent qualifying
  workout" is `noRecentWorkout`, and it already existed.

- **A late payload used to win.** The phone reaches the wrist by two routes with
  different delivery semantics (the application context is a latest-value-wins
  slot, `transferUserInfo` is a FIFO queue that drains on reconnect), so a
  transfer queued before an outage can arrive *after* a newer context. On screen
  that is a countdown jumping backwards to a window the user watched expire.
  `sentAt` was already on every payload as a cache-buster (`updateApplicationContext`
  no-ops on a byte-identical dict), and `applyInboundSnapshot` now believes it,
  against a high-water mark persisted in the App Group because the Watch app is
  killed between background wakes. The snapshot's own `calculatedAt` would be
  the more natural key and is the wrong one: `RecoverySnapshot.empty` carries
  `.distantPast`, and the phone legitimately publishes an empty snapshot when the
  last workout is deleted from Health, so ordering on it would refuse the one
  payload whose job is to clear the wrist. The reply to an explicit
  `requestSnapshot` bypasses the check, because it is current by construction,
  and it is the way out if a phone's clock ever moves backwards.

**Recharge's Watch app is the only one in the fleet that cannot read Health.**
`VitalsWatch` and `VO2MaxWatch` both carry `com.apple.developer.healthkit` and
compute their own numbers on the wrist, so their complications work with no
phone involvement at all and never depend on a background wake landing. That is
why they "just work" and this one is fussier, and it is a deliberate choice
here, not an oversight: the phone owns the model, and a watch recomputing it
could disagree with the phone about the same session.

The escape hatch is cheaper than it looks if it is ever needed. `Shared` is
compiled into `RechargeWatch` in full, so `RecoveryEngine`, `HealthKitService`
and `DataService` are already on the wrist, and `RechargeWatch/Info.plist`
already carries both Health usage strings. The missing pieces are the
entitlement and — the part that is actually the work — syncing
`effectiveMaxHeartRate`, `calibrationFactor`, `athleteProfile`, `ambiguousProfile`
and the tier, without which the watch would score against defaults and visibly
disagree with the phone. Do not take this path to fix a delivery bug; take it
only if mirroring is decided against on purpose.

### Clearance for the floating tab bar is the shell's job
`RootView` draws a translucent capsule over the content rather than a system
`TabView`, so every scrollable tab has to reserve room for it at rest. Each
screen used to reserve its own, and it went the way hand-copied numbers go:
Today padded 72, History padded 96, and Settings, a `Form` with no padding to
copy onto, padded nothing at all. `TabBarMetrics` holds the geometry once and
`tabBarClearance()` applies it, so the bar and the room made for it come from the
same constants.

**Do not "fix" the overlay by giving the bar its own layout row.** That was tried
— `VStack { content; tabBar.background(Theme.background) }` — and it removes the
clearance problem by painting an opaque strip the full width of the screen under
the capsule, which reads as a black box with a pill inside it and is the reason
this shell looked wrong next to Vitals.

**The modifier goes inside each `NavigationStack`, not around it.** One call in
`RootView.tabContent` would cover all three tabs and does not work: a
`NavigationStack` manages the safe area of its own content, so an inset applied
from outside never reaches the scroll view within. Nothing about that failure is
visible: it compiles, the layout looks unchanged, and the last row still sits
under the blur.

An inset rather than bottom padding, so the scroll-behind look survives: it moves
where the content comes to rest, not the scroll view's frame, so passing content
still runs under the capsule and only the last row is guaranteed to clear it.

`testTheTabBarDoesNotCoverTheBottomOf{Today,History,RechargePlus}` and
`testTheTabBarDoesNotCoverTheUpgradeTabsCTA` assert frames, and writing them was
most of the work. Three traps, all of which produce a green test that checks
nothing: an element scrolled off-screen reports a frame hundreds of points below
the window, so `exists` is not "visible"; the tab bar's own labels are elements
too, so "the lowest thing on screen" measures the bar against itself; and an
opacity-zero tab is still in the accessibility tree, so `firstMatch` on a button
that exists on two screens can pick the invisible one and then truthfully report
that it is not hittable. Each test names its genuinely-last row. The Settings
variant is gone with the Settings tab.

### A pinned header has to mask what scrolls behind it
History pins its day headers (`pinnedViews: [.sectionHeaders]`), so the outgoing
day's card slides *behind* the header rather than pushing it off. The header's
`Theme.background` was sized to the text plus 8pt of top padding, inside a
`LazyVStack` with `spacing: 10` and a 16pt side margin, so three strips stayed
transparent: 16pt down each side, and the 10pt gap above and below. On a dark
screen the card's fill, its glyph and its hours all showed through around the
pinned label, which reads as a second broken row wedged under the navigation
bar. Reported from a real device and reproduced on the simulator from the
`history` fixture.

The background is inflated by exactly those two constants
(`HistoryView.horizontalMargin`, `HistoryView.rowSpacing`) with negative padding,
so the mask and the layout can never be given different numbers. It is not
covered by a test: XCUITest reports the frames of elements the header is drawing
over, not whether they are visible, so the guard here is the constants being
shared rather than an assertion.

Unrelated to the tab bar, and a different bug from Baby Docs' clipped page
height, though both surface as content ghosting under a bar. What remains on
iOS 26 is the system's own soft scroll-edge blur, which leaves a faint ghost of
the top row on all three tabs; that is Apple's default and a design decision to
change, not a defect.

### Onboarding reads Health before it asks anything
The flow is welcome → Health → what Health gave us → the gap questions → what the
number means → the tier decision. Three structural rules, all of which were bugs
first (the third is in "The onboarding copy is centred" above):

- **The buttons never move**, the trial offer included. Every page ends in the
  same `OnboardingActions` block, which reserves *both* variable rows: the
  secondary action whether or not the page uses one, and the
  Restore/Terms/Privacy slot whether or not the page is a purchase point.
  Nothing that varies between pages may sit below the primary button, so its
  distance from the bottom of the screen is a constant and everything a page
  wants to say goes above it. The trial page's subscription disclosure and legal
  row used to sit *under* its CTA, lifting the one button in the flow that takes
  money about forty points clear of the four Continue buttons that had just
  trained the thumb. `testTheOnboardingButtonStaysInOnePlace` asserts the frames,
  not a screenshot — but it broke out of its walk the moment the offer page
  appeared and never measured it, so the bug lived on the one page the guard
  could not see. It measures the offer CTA now, and
  `testThePurchaseCTALandsWhereTheContinueButtonWas` states the same claim where
  it actually broke.
- **The step list is frozen once**, when the user leaves the Health page.
  Answering a question removes it from `AthleteProfile.gaps`, so a continuously
  derived array would delete the page the user is standing on. The progress bar
  is measured against the longest possible flow until Health answers, so it can
  only ever jump forward.

**The rule for `readTypes` has not changed; what changed is that the app
consumes more and now shows its working.** Nothing goes in that sheet unless
something the user can see uses it — and `HealthIngestSummary` is what makes that
literally checkable, because every type in the set has a line in the receipt and
a row with no consumer would be a row with no line. Eleven types:

| Type | Consumed by |
|---|---|
| workouts, heart rate | the session load, and the *observed* maximum heart rate |
| active energy | the energy path when heart rate is missing |
| resting HR, HRV | overnight context, and the rebound signal |
| sleep, respiratory rate | overnight context |
| heart-rate recovery | the kinetics signal in `PersonalRecoveryModel` |
| VO2 max | `AthleteProfile.fitnessScale`, on both tiers |
| body mass | the energy path's mass residual |
| date of birth, sex | the age-predicted ceiling, when nothing was measured |

VO2 max was out of this set once, on the grounds that the evidence tying it to
*recovery rate* is weak. That is still true and it is not what it is used for: it
sets the training **level** the session is compared against, which is what
Firstbeat's activity class does at setup on a Garmin.

The readout page prints those readings rather than the app's summary of them
("mostly endurance work", "age 34"). The two do different jobs: a summary asks to
be believed, and a list of the user's own numbers is evidence. It is also the
honest counterpart to a sheet asking for eleven types.

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

**`CODE_SIGN_IDENTITY: ""` strips every entitlement, and nothing says so.**
It was added to `project.yml` on 2026-08-18 (base settings *and* the `Recharge`
target) and it shipped in builds 21 and 22. An unsigned archive never runs the
step that compiles `Recharge.entitlements` into `Recharge.app.xcent`, so
`com.apple.developer.healthkit` and the App Group were simply absent from the
product; `exportArchive` then re-signed an app that had nothing to carry
forward. On device that reads as HealthKit being broken with no error anywhere:
`requestAuthorization` throws, no permission sheet appears, and the app never
shows up under Health > Sharing > Apps, which is also why restarting the phone
does nothing. Neither Vitals nor VO2 Max sets it, which is the whole reason
their Health access "just works".

The archive is the only place this is visible, so `testflight.sh` now checks the
signed product before uploading: HealthKit and the App Group on the iPhone app,
the App Group on the Watch app and both widget extensions. `codesign -d
--entitlements - --xml` on `$ARCHIVE/Products/Applications/Recharge.app` is the
one-line manual version.

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
  package. A locked surface anywhere in the app posts
  `.rechargeUpgradeRequested` rather than raising its own sheet, so that
  ordering is the only ordering; a subscriber's tap on the same card posts
  `.rechargePlusRequested` and lands on the tab instead.
- **What a screen may explain:** `RecoveryResolver.current` keeps returning a
  stale estimate so history and the snapshot have something to carry;
  `RecoveryResolver.explanation` is what a screen showing the phase may narrate.
  Past the four-day cutoff they diverge, and using `current` there puts a live
  window beside a "no workout yet" hero.
- **Freshness is user-visible.** A failed HealthKit query returns nothing rather
  than an empty store, so `RecoveryEngine.lastSuccessfulImport` /
  `lastImportFailed` drive the line under Today's date and the Settings Health
  status row.
  iOS never reports read authorization, so that row reports what Health
  *returned*, never which categories were granted.
- **Staleness reaches the glance surfaces, and it annotates rather than
  replaces.** `RecoverySnapshot.healthDataState` carries the fact across the App
  Group and WatchConnectivity, because a widget and a complication have no
  `RecoveryEngine` to ask and would otherwise show an old countdown as if it
  were current. Two rules, both of which were bugs first.

  **It does not blank the number.** `readyAt` was computed before the read
  failed and is still counting down correctly; a failed read says only that
  something *newer* might be missing from it. The first cut replaced the
  countdown everywhere with "Health paused" / "Retry", which threw away the one
  thing the surface knew in order to warn about the one thing it did not, and
  contradicted the phone, which keeps its countdown and adds
  `TodayView.freshness` under the date. Only `ComplicationCopy.secondary` and
  the iOS widget caption change; `primary`, `inline`, `rectangularTitle`, the
  ring, the gauge and the phase glyph are untouched.
  `testStaleHealthDataAnnotatesTheCountdownRatherThanReplacingIt` asserts that
  exactly one of the four strings differs from the synced version, and
  `testOnlyTheStatesWithNoModelReplaceTheValue` keeps `neverSynced` and
  `unreadable` on the other side of that line, since they genuinely have
  nothing to render.

  **It is not `lastImportFailed`.** One query fails routinely for reasons that
  have nothing to do with the user: HealthKit refuses protected reads while the
  device is locked, and both the observer and the `BGAppRefreshTask` fire on
  locked devices constantly. Publishing that straight through would have put a
  warning on the lock screen at the moment the countdown was most correct.
  `HealthDataState.resolve` debounces on `staleAfter` (6h), and
  `lastSuccessfulImport` is mirrored into the App Group because it is otherwise
  in-memory and a background wake usually runs in a fresh process, so every
  cold launch that failed its first read would look like an app that had never
  read anything. The phone still reports every failed attempt, because it has a
  scene, a pull-to-refresh, and room for a line.
- **Paywall verification:** it renders empty under plain `simctl launch` — no
  RevenueCat on simulator and no StoreKit catalogue. Under screenshot mode the
  plan cards come from `StoreService.screenshotPackages`, whose prices mirror
  `Recharge.storekit` and ASC; keep them in step.
  `testPaywallRendersRealProductsUnderStoreKitTesting` in `RechargeUITests`
  asserts all three cards and attaches the render. That covers **layout**;
  localized/PPP price formatting is still only observable on device. Never sign
  off on paywall spacing from a `simctl` screenshot.
- **A fixture that agrees with itself proves nothing.**
  `ScreenshotFixtures.history` never passed `standardHours`, so it defaulted to
  `hours` and every two-tier comparison in the app rendered the same number
  twice on every capture. The comparison the upgrade sells read identically on
  both sides in `premiumActive`. The fixture now carries both figures
  explicitly, spread the way the fixture user's own analysis implies (0.86
  multiplier *and* a personal baseline above the population reference), plus a
  `recoveryCostHours` that differs from `hours` on the two rows where it has to
  (a walk, and a spin under the quiet threshold) and a filled-in
  `healthIngest`. If you add a field that a conversion surface compares, put a
  real difference in the fixture or the capture will show the app doing nothing.
- **Two ways to look at the app, and they answer different questions.**
  Screenshot mode hands `RecoveryEngine` a fixed array of finished estimates, so
  it is fast, reproducible, and proves nothing about the import path.
  `RECHARGE_SEED_HEALTH=1` writes a real training history into the simulator's
  Health store (`Recharge/Debug/HealthSeeder.swift`, DEBUG only, requests
  **write** authorization the real app never asks for) and everything downstream
  runs for real: classification, coverage, the observed maximum, the quiet
  threshold, day grouping, stacking, the 30-day analysis.
  `SeededWalkthroughTests` drives it, it runs by default, and one pass takes
  about 35 seconds against the full 120-day window.

  **It spent its whole life failing at the permission sheet, and the diagnosis
  in this file was wrong.** The sheet is presented into the app's own window
  through `_UIRemoteViewControllerSceneHostingImpl`, so on screen it looks like
  part of Recharge, but every element of it belongs to
  `com.apple.HealthPrivacyService`, and `XCUIApplication()` reports only the
  screen underneath plus an empty `Other` where the sheet is hosted. So
  `app.buttons["Turn On All"]` never existed, the helper's
  `guard … else { return }` returned **silently**, the sheet stayed up, and the
  app parked forever on the `requestAuthorization` continuation inside
  `seedIfRequested()`. The identical 364-second failure at 21, 60 and 120 days
  was 60 seconds of that wait plus the 300-second wait for the tab bar; the
  seeder had not written a single sample in any of them, which is also why
  nothing about it reached the device log. `HKWorkoutBuilder` was never
  involved: it writes 120 days (about 600 workouts and 30,000 heart-rate
  samples) in roughly two seconds.

  Four things about the sheet, all of which cost a run to find and none of
  which are guessable:

  - Query `XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")`.
  - The rows are `Cell`s, not `Button`s and not `Switch`es. "Turn On All" is
    `UIA.Health.AuthSheet.AllCategoryButton`; Allow is `UIA.Health.Allow.Button`.
  - Only the **cell-level** identifiers are trustworthy. The simulator gives a
    row's inner title and switch the identifier of a *different* row (Active
    Energy's switch is `UIA.Health.HeartRateVariability.SwitchCell.Switch`).
    `UIA.Health.{Read,Write}.<Type>.SwitchCell` on the cell is correct, and the
    cell carries the on/off value, so the whole check works off cells and needs
    no scrolling, which matters, because the table is ~1,860pt of content in an
    812pt window and the entire read section is below the fold.
  - **Never return silently from a permission helper.** Every step asserts now.
    A helper that gives up quietly hands its failure to whatever runs next,
    which then reports something with no connection to the cause: in this case
    "the tab bar never appeared", six minutes later, in a file about seeding.

  The second bug was the same trap the tab-bar frame tests are written around,
  arriving from a new direction. Seeded data ends with a countdown that has
  already run out, so Today raises its readiness question a beat *after* the
  import lands, later than the one-shot sheet dismissal ran. The half sheet
  covered the floating tab bar, every subsequent tap computed a hit point of
  `{-1, -1}` and fell back to the element's centre (i.e. onto the sheet), and
  the test **passed**, because `navigationBars["History"]` reports `exists` from
  a tab that is only `opacity(0)`. Three of the five attachments were the same
  screenshot of Today. Interrupts are cleared in a loop, before and after the
  import, and `show(_:in:landmark:)` asserts `isHittable` on a landmark of the
  tab it just tapped.

  One thing that was already known and is still true: HealthKit **never
  re-asks** once a permission sheet has been answered, so a run that was denied
  write access stays denied until the app is uninstalled (`xcrun simctl
  uninstall <udid> com.jackwallner.recovery`). And tapping "Turn On All" is not
  the same as everything being on. When they diverge the only evidence is one
  line in the device log reading `Seeding failed: Not authorized`, so the test
  now polls the cell values and names any category still off.

  `RECHARGE_SEED_DAYS` overrides the window for a one-off; there is no longer a
  reason to seed less than `HealthKitService.importDays`.

  **The first green run immediately earned the test back.** History showed one
  62-minute Wednesday lift four times over, once per run the seeder had ever
  done, stacking into a 72-hour countdown out of a single session:
  `HKWorkoutBuilder` never carried `seedMarker`, so `deleteExistingSeed` could
  not see the workouts it had written, while the heart-rate and energy samples
  *inside* them were marked and were deleted. What accumulated was a pile of
  workouts with no heart-rate trace, the shape most likely to be read as a
  model bug rather than a seeding one. The workout carries the marker now and
  the delete predicate additionally matches anything written by this source,
  which is exactly "seeded" (Recharge never writes to Health) and clears what
  older builds left behind. HealthKit data survives an uninstall, so this was
  never going to clean itself up.

  Worth knowing separately: the app stacked those four duplicates into one
  72-hour window without complaint. Duplicate workouts are a real thing in a
  real store (a phone syncing a Garmin alongside an Apple Watch writes both),
  and nothing in `RecoveryEngine` currently notices. Not changed here, because
  it is a model decision rather than a test one.
- **Screenshot mode:** `RECHARGE_SCREENSHOT_MODE=1` +
  `RECHARGE_SCREENSHOT_SCENE=<recovering|ready|history|settings|paywall|premiumActive|onboarding|watchRecovering|watchReady>`.
  Bypasses HealthKit entirely and seeds `ScreenshotFixtures`. The `settings`
  scene raises the Settings **sheet** from Today, because Settings stopped being
  a tab; `RedesignCaptureTests` walks every screen this way in about a minute.
- `RevenueCatConfig.apiKey` is a placeholder in the repo. `scripts/testflight.sh`
  substitutes `RC_PUBLIC_KEY` from `~/.recovery_credentials` for the archive and
  restores the placeholder on exit, so the key never lands in a commit. Never
  configure it on simulator. The substitution is a `sed` on a source file and a
  `sed` that matches nothing succeeds, so the script now **verifies the archive**
  rather than trusting the edit: the placeholder must be absent from
  `$ARCHIVE/Products` and the real key present, both checked before upload.
  Every way this goes wrong produces a valid archive whose paywall silently never
  loads an offering on a real device, and nothing downstream notices.
- **App Store ID is `6797089337`** (`com.jackwallner.recovery`). `fastlane/metadata/`
  is canonical and is uploaded, not aspirational: as of 2026-08-16 the ASC record
  is named "Recharge Workout Recovery Time", version 1.0.0 is in
  READY_FOR_REVIEW with build 15 attached, and **all 50 locales** carry a
  name, subtitle, keywords, description, promotional text and release notes.
  Build 15 is the first one carrying the Recharge+ rename and the reworded
  disclaimers, so 14 must not be what ships.
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
  That teardown is not free: the four product items can only be put back in the
  ASC web UI (Add for Review on the subscription group page, on each subscription
  page, and on `/distribution/iaps/<id>`), because the first subscription and
  first non-consumable an app ships cannot be attached over the public API.
  `asc-submit-for-review.py --prepare-only` does the half that is scriptable, and
  the plain run now refuses to submit with fewer than 5 items rather than burning
  a review cycle on a 2.1(b) rejection. Adding the version item flips the version
  from PREPARE_FOR_SUBMISSION to READY_FOR_REVIEW, which is why both states are
  accepted.
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
4. **`costMultiplier` for `easy` is 0.30 and it is a first-pass value.** It is
   the only constant in the model fitted to nothing at all: `windowMultiplier`
   for the other three profiles is anchored through the Garmin bands, and easy
   has no band because Garmin gives it no countdown either. What it has to
   satisfy is weak — a 40-minute walk should read as a small number rather than
   as zero — and it satisfies that at almost any value between 0.2 and 0.4.
5. **The 90th-percentile observed maximum heart rate has never been checked
   against a real store with a known maximum.** The two guards around it are
   sound in opposite directions (a spike cannot raise it, a quiet month cannot
   lower it) and the choice between the 90th and, say, the 95th is a guess about
   how often somebody's hardest sessions are genuinely maximal. Worth revisiting
   the first time a user reports an intensity reading that looks wrong.

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
