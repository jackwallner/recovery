---
paths:
  - "Shared/Utilities/RecoveryCalculator.swift"
  - "Shared/Utilities/PersonalRecoveryModel.swift"
  - "Shared/Services/RecoveryEngine.swift"
  - "Shared/Models/RecoveryModels.swift"
  - "Shared/Models/RecoveryRecords.swift"
  - "RechargeTests/StackedRecoveryTests.swift"
  - "RechargeTests/StackedRecoveryPersistenceTests.swift"
  - "RechargeTests/PersonalRecoveryModelTests.swift"
---

# Recharge: stacking, the 30-day analysis, and model versions

Moved verbatim from AGENTS.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the AGENTS.md index.

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

### The nights after the session move a running countdown (Recharge+)
Garmin updates recovery time through the day from sleep, stress and activity
(owner's manuals: "updates your recovery time throughout the day based on
changes in sleep, stress, relaxation, and physical activity"). Recharge used to
read only the night *before* the session, so a hard session followed by four
hours of broken sleep counted down exactly like one followed by eight good ones.

`RecoveryContext.followingNights` carries the nights after, and
`RecoveryCalculator.contextAdjustment(_:nightsBefore:)` scores each night on its
own and averages them with the nights after weighted double
(`followingNightWeight`), inside the same -15%/+20% clamp. A night only counts
if it began before the countdown would have ended, judged against the window
as the nights before it left it, so a bad night after Ready can never reopen
a finished window, and the rule needs no clock. Version 16 judged every night
against the night-before window alone, which let a bad second night back in
after a good first night had already brought Ready forward
(`testABadNightAfterAGoodNightBroughtReadyForwardIsNotAdmitted`). The engine passes up to four following
nights from `DailyContextRecord`; a rescore triggered by the morning's sleep or
HRV write is what moves the countdown, and `publish()` reschedules the Ready
alert. HRV and breathing rate are now the **median** of the day rather than the
last sample, which was often the post-session one.

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
3. **Kinetics.** Median one-minute heart-rate recovery against 25 bpm.

**Density is gone (version 16).** It was chronic weekly load against a
population reference, which is what the personal baseline already divides by
and what `fitnessScale` already moves the reference with, so a daily trainer was
discounted for the same fact three times. Weekly volume left the questionnaire
prior for the same reason. Volume now reaches the model exactly twice, once per
tier: `fitnessScale` on the standard tier, the measured baseline on Recharge+.

The prior is never fully discarded — it carries age, which nothing in the
history can observe.

Four profiles, each with its own curve: `endurance`, `strength`, `mixed`, `easy`.
`easy` always returns zero hours, so an active-recovery walk can never start or
shorten a countdown.

`recoveryModelVersion` (in `RecoveryModels.swift`) must be bumped whenever the
numbers change. It is stored on every estimate so history can explain why an old
window disagrees with what the same session would produce today. Currently **17**
(the nights after a session are admitted one at a time; 16 was Garmin parity, see the doc comment on `recoveryModelVersion` and
`GarminScenarioTests`: the free countdown is the model again, a 96-hour ceiling,
sub-threshold minutes past the hour discounted, time-in-zone heart rate, the
nights after the session, a capped quiet threshold, no density; 15 scored
duplicate workouts once; 14 was release hardening; 13 let the user correct a session's intensity and pin their own hours to the three
bands, see "What the user is allowed to tell the model" in model-tiers.md; 12 moved tolerance
evidence onto the next session's start time and unioned overlapping sleep
intervals; 11 was where the tiers stopped being two runs of the same calculation: the free one describes
the person's own gap between sessions and the paid one recommends a window
against it, and the personal denominator is bounded to 0.75-1.40x the population
reference; 10 measured more of what the model was guessing: the heart-rate ceiling is the
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
