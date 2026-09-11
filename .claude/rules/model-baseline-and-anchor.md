---
paths:
  - "Shared/Utilities/RecoveryBaseline.swift"
  - "Shared/Models/RecoveryModels.swift"
  - "RechargeTests/AthleteMatrix.swift"
  - "RechargeTests/RecoveryMatrixTests.swift"
  - "RechargeTests/GarminAnchorTests.swift"
  - "RechargeTests/HighVolumeAthleteTests.swift"
  - "RechargeTests/RecoveryBaselineTests.swift"
---

# Recharge: the baseline, the audit matrix, and the Garmin anchor

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

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
the resolution: see "The two tiers" in model-tiers.md for what feeds it and why only two of
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
