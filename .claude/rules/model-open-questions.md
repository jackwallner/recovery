---
paths:
  - "Shared/Utilities/SessionLoadCalculator.swift"
  - "Shared/Utilities/RecoveryBaseline.swift"
  - "Shared/Utilities/RecoveryCalculator.swift"
  - "Shared/Utilities/AthleteProfile.swift"
  - "Shared/Models/RecoveryModels.swift"
---

# Recharge: open tuning questions

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

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
