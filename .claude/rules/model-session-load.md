---
paths:
  - "Shared/Utilities/SessionLoadCalculator.swift"
  - "Shared/Utilities/WorkoutClassifier.swift"
  - "Shared/Utilities/RecoveryCalculator.swift"
  - "Shared/Models/RecoveryModels.swift"
  - "Shared/Models/RecoveryRecords.swift"
  - "Recharge/Views/HistoryView.swift"
  - "RechargeTests/SessionLoadCalculatorTests.swift"
  - "RechargeTests/RecoveryCalculatorTests.swift"
  - "RechargeTests/FixtureTableTests.swift"
  - "RechargeTests/WorkoutClassifierTests.swift"
---

# Recharge: scoring a single session

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

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
