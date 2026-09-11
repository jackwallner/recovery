---
paths:
  - "Shared/Utilities/ObservedRecoveryPattern.swift"
  - "Shared/Utilities/AthleteProfile.swift"
  - "Shared/Utilities/RechargeConversionCopy.swift"
  - "Shared/Utilities/RecoveryResolver.swift"
  - "Shared/Services/RecoveryEngine.swift"
  - "Shared/Services/RechargeSettings.swift"
  - "Shared/Services/NotificationService.swift"
  - "Shared/Models/RecoveryModels.swift"
  - "Recharge/Views/EstimateDetailView.swift"
  - "RechargeTests/ObservedRecoveryPatternTests.swift"
  - "RechargeTests/RecoveryTierTests.swift"
  - "RechargeTests/UserCorrectionTests.swift"
  - "RechargeTests/MeasuredInputsTests.swift"
  - "RechargeTests/RecoveryResolverTests.swift"
---

# Recharge: the two tiers and what the user can change

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

### The two tiers
`RecoveryTier` is stored on every estimate, because the two answer different
questions and a history list that mixes them silently is lying by omission.

**The line between them is description and recommendation.**

- **Your usual (free).** `ObservedRecoveryPattern`: the median gap between this
  person's own sessions of comparable size, split into three bands (light /
  moderate / hard) by where the session sits in their own load distribution. No
  model at all — the countdown *is* the habit. Falls back to the modelled
  estimate at their stated training level while their history is too thin to
  show a pattern, and says so in the reasons.
- **Optimal (Recharge+).** What the model recommends for *this* session: the
  person's own 42-day baseline, overnight context, calibration, and the
  `PersonalRecoveryModel` multiplier — stated against the habit, so the free
  figure stays on screen beside the one that replaced it.

**Why the split changed.** It used to be two runs of the same calculation, one
scored against a population reference and one against the person's own load
distribution, and *nothing bounded the distance between them*. A user training
seven days a week in twenty-five-minute sessions was shown **6 hours free and 36
hours paid for the same workout**: their typical training day was about 26 load
units against a reference day of 115, so the paid tier read their ordinary
session as twice normal while the free tier read it as a quarter of normal. Both
figures were correct arithmetic on their own terms and the pair of them was
nonsense — and the direction was backwards from what anybody expects, because
frequency never entered the denominator at all. Only load *per training day*
did, so training often in short blocks lowered the baseline and lengthened every
window.

Two questions produce two answers legibly. One number is what you do; the other
is what the model suggests doing. `RecoveryBaseline.minimumPersonalRatio` /
`maximumPersonalRatio` (0.75–1.40 of the population reference) bound the paid
side separately, so a measured baseline can tune the recommendation but never
relocate it.

**What counts as "going again"** is the whole of the free statistic and it took
two attempts. A lighter session cannot end a gap — somebody who walks the day
after a hard ride has a 24-hour gap because of a walk — but requiring the *same
size again* fails worse in the other direction: a weekly long run is the biggest
thing in that person's week, so nothing matches it until the next one and the
habit came back as "you go again after 7 days" for somebody training five times a
week. The bar is the lower of `comparableFraction` (0.85) of the session just
finished and `typicalFraction` (0.70) of their median session. Gaps over
`maximumGapHours` (7 days) are dropped, because a fortnight off is a holiday, not
a recovery time, and `easy` sessions are excluded on both sides.

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
the usual gap beside the recommended window, for the conversion surfaces. The
paid figure is **blurred everywhere it appears before purchase** — Today's card,
the trial offer page, the Settings row. It used to be printed in full on the
offer page, on the argument that hiding half an argument is not an argument, and
that reasoning was wrong in one specific way: that page is the last thing a user
sees before deciding, so printing the number hands over the entire thing being
sold. It is
computed, never derived. Multiplying the standard hours by
`personalAnalysis.factor` was the old version and it dropped the larger of the
two effects — personalisation changes the *baseline* a session is measured
against as well as applying the multiplier — so the card sometimes showed the
same number twice and hid itself. It falls back to
`PersonalizedPreview.reference` (the canonical hard session, a real point on the
real curve) when there is no qualifying session or the two land on the same
rounded hour, so there is always a difference on screen and it is always
arithmetic.

`RecoveryEngine.rescore` reads `ObservedRecoveryPattern` **once** — a habit does
not change between two rows of the same history — then runs two passes: the free
estimate for every session first, because `PersonalRecoveryModel` needs to know
what window each session *would* have had, then the tier-appropriate one. Both
passes are handed the observed window; only the free one lets it become the
countdown (`RecoveryCalculator` gates on `personalization.tier`), because on
Recharge+ the habit is a sentence rather than the number.

### What the user is allowed to tell the model
Two corrections, both Recharge+, and both added because a control that appears to
do nothing is worse than no control at all.

**Intensity, per session.** `EstimateDetailView` used to offer a `WorkoutProfile`
picker — Endurance / Strength / Mixed / Easy — which asked the user to fix the
half the app was already right about: HealthKit says what activity a session was
and `WorkoutClassifier` maps every raw value under test. What the app gets wrong
is *how hard* it was. Worse, the profile picker frequently moved nothing: turning
a walk into an endurance session left the load exactly where the sensors had put
it, so the ring did not budge, which is what it was reported for.

`SessionIntensity` (light / moderate / hard, the Borg CR10 anchors the effort
sheet already asks with) replaces it, and it does two things the profile picker
did not:

- **It short-circuits the load ladder.** `SessionLoadCalculator.profiledLoad`
  returns `overriddenLoad` outright when an override is present. Folding the
  answer in as one more candidate — even as the maximum, which is what `strength`
  does — leaves "Hard" doing nothing on a session whose heart-rate trace already
  read harder. Every other input is a sensor reading or an inference from one,
  and the reason somebody reaches for this control is that those were wrong.
- **It can lift a session off `easy`.** `SessionIntensity.profile(promoting:)`:
  moderate/hard promote `easy` to `endurance`, light demotes `endurance` to
  `easy`, every other profile is untouched. `easy` is the only profile whose
  `windowMultiplier` is zero, so without this a walk marked Hard changed the
  load, changed the cost, and still produced no countdown.

`RecoveryEngine.overrideIntensity` rescores with `unfreezeAll: true` rather than
`unfreezing:` the one record, because every later session is stacked on this
one's residual and thawing only the corrected row leaves the chain after it
describing a countdown that no longer exists.

**Pinned hours, per band.** `ManualRecoveryWindows` holds an optional figure for
each of the three bands, and `RecoveryCalculator.estimate(manualHours:)` uses it
instead of the modelled window. It replaces rather than nudges, for the same
reason the observed window does on the free tier. It is bounded by
`minimumCountdownHours` and `maximumHours`, `recoveryCostHours` follows it (or
History prints a figure the countdown contradicts), and it **never reaches the
standard tier** — that tier's one claim is that its number was read off the
user's own training, and a typed number is not that. The band a session lands in
comes from `ObservedRecoveryPattern.band(forLoad:referenceLoad:)`, the same
tercile split the free tier's own sentence is cut on, so "hard" means the same
thing in the Settings row that pins it and in the reason line that reports it.

### The two figures had to stop contradicting each other
Reported from real use: standard 23h, Recharge+ 8h, and a row underneath reading
**-6%**. Every number was right and the card was nonsense.

`personalFactor` is the thirty-day recovery-rate multiplier and it is the
*smallest* of the three things separating the two figures. The others are that
the tiers answer different questions (a habit read off the calendar against a
window recommended for this session) and that the recommendation is scored
against the person's own baseline rather than the population reference — the
same decomposition `personalizedPreview` exists to avoid getting wrong, arriving
one screen later. The row is labelled "30-day recovery rate" now, and
`EstimateDetailView.reconciliation` prints the total difference beside it with a
sentence naming all three terms.

**The columns are named for the tiers.** "Usual" and "Optimal" were an accurate
description of the two calculations and a hopeless pair of headings: neither word
says which side of the paywall it is on, so somebody reading "23h → 8h" could not
tell which figure they already had. `RechargeConversionCopy.standardColumn` /
`.proColumn` are **Standard** and **Recharge+**, used by Today, the trial page,
the Settings row, the Recharge+ tab, and `RecoveryTier.label`, with
`comparisonCaption` as the one line that names the derivation underneath.

### The readiness question only asks about countdowns the user watched
`ReadinessFeedback` folds into `calibrationFactor`, and `calibrationFactor` is
only ever passed to the *personalized* estimate — so on the free tier the answer
was recorded, stored, and multiplied into nothing. It is Recharge+ only now
(`RecoveryEngine.feedbackEligibleFrom`).

And it may not reach back past setup. Onboarding imports 120 days in one go, so
every countdown in that history has already expired by the time the user reaches
Today: the first thing a brand-new user saw was "How did that feel?" about a
session they did before installing the app, which has no honest answer and spends
their willingness to answer anything.
`RechargeSettings.feedbackEligibleFrom` is stamped at setup (and on first launch
for anyone upgrading into this build), and `RecoveryResolver.awaitingFeedback`
takes it as a bound. Nil means unbounded, which is what every test written before
it assumes.

### The Ready alert is not a Recharge+ feature
It was, and that was the wrong side of the paywall for the one event the whole
app exists to report. The countdown runs out while the app is closed; without an
alert the user has to open Recharge to find out, which is what made a background
chain that works correctly ("Recovery time stacks" in model-stacking-and-versions.md, "The countdown timeline" in countdown-and-watch-sync.md)
read as an app that never updates on its own.

`notifyOnReady` defaults to **true**, `publish()` no longer checks `isPro`,
onboarding asks for permission at the end of setup, and
`hasRequestedReadyNotifications` gets the prompt in front of an upgrading user
exactly once — an enabled toggle with no permission behind it is scheduled and
silently never delivered.
