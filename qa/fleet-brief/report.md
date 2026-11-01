# Release gate: recovery-ship 433714d23b34

Verdict: **BLOCK** (2026-11-01T18:36:08+00:00)

Every finding blocks except legacy backlog. `qa-gate fix <repo>` fixes them. Motion candidates need a judgement in the ledger: `qa-gate ledger <repo> accept` for an intended change, or `add` a P1 when it is a real glitch.

## Blocking (111)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P2 | a11y-contrast | newcomer,reduce-motion | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.7:1): "Hard · 7:02 AM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.7:1): "Moderate · 8:02 AM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|moderate · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.7:1): "Active recovery · 1:02 AM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|active recovery · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.7:1): "Light · 7:02 AM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|light · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.7:1): "Very hard · 9:02 AM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|very hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.7:1): "Hard · 7:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.7:1): "Moderate · 8:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|moderate · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.7:1): "Active recovery · 1:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|active recovery · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.7:1): "Light · 7:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|light · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.7:1): "Very hard · 9:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|very hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.7:1): "Hard · 7:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.7:1): "Moderate · 8:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|moderate · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.7:1): "Active recovery · 1:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|active recovery · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.7:1): "Light · 7:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|light · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.7:1): "Very hard · 9:05 AM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|very hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-countdown | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-countdown|history` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-countdown | Contrast failed (measured 1.9:1): "Upgrade" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-countdown|upgrade` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-countdown | Contrast failed (measured 1.7:1): "Updated just now" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-countdown|updated just now` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-countdown | Contrast nearly passed (measured 3.4:1): "left" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-countdown|left` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-countdown | Contrast nearly passed (measured 3.4:1): "22h from your run 3h ago" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-countdown|#h from your run #h ago` |
| P2 | a11y-contrast | accessibility,newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-countdown | Contrast nearly passed (measured 3.2:1): "Recharge+" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-countdown|recharge+` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-countdown | Contrast failed (measured 1.9:1): "Standard" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-countdown|standard` |
| P2 | a11y-hit-region | duo,newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Hit area is too small: "Medium confidence" | `a11y-hit-region|testCoreLoopCountdownFromAWorkoutToReady|core-detail|medium confidence` |
| P3 | a11y-element-description | duo,newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Label not human-readable: "1.40×" | `a11y-element-description|testCoreLoopCountdownFromAWorkoutToReady|core-detail|#×` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast failed (measured 2.1:1): "Done" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|done` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.4:1): "Hard" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|hard` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.7:1): "Hard session: 52-minute run." | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|hard session: #-minute run.` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.7:1): "Load estimated from heart rate." | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|load estimated from heart rate.` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.7:1): "Session load" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|session load` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.7:1): "Compared to a typical session" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|compared to a typical session` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.7:1): "Load from" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|load from` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.7:1): "Heart-rate coverage" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|heart-rate coverage` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.7:1): "Estimate" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|estimate` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.7:1): "Model version" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|model version` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast failed (measured 1.9:1): "Medium confidence" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|medium confidence` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-detail | Contrast nearly passed (measured 3.2:1): "Recharge+" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-detail|recharge+` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast failed (measured 3.4:1): "Today" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|today` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast failed (measured 1.9:1): "Upgrade" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|upgrade` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.4:1): "Yesterday" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|yesterday` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast failed (measured 1.7:1): "15h total" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|#h total` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.4:1): "Friday, Oct 30" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|friday, oct #` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.4:1): "Thursday, Oct 29" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|thursday, oct #` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.4:1): "Wednesday, Oct 28" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|wednesday, oct #` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.7:1): "Hard · 7:06 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.7:1): "Moderate · 8:06 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|moderate · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.7:1): "Active recovery · 1:06 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|active recovery · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.7:1): "Light · 7:06 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|light · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast nearly passed (measured 3.7:1): "Very hard · 9:06 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|very hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast failed (measured 1.9:1): "countdown" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|countdown` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast failed (measured 1.9:1): "no countdown" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|no countdown` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast failed (measured 1.9:1): "under the threshold" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|under the threshold` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history | Contrast failed (measured 1.9:1): "26h countdown" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history|#h countdown` |
| P2 | a11y-hit-region | duo,newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Hit area is too small: "Medium confidence" | `a11y-hit-region|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|medium confidence` |
| P3 | a11y-element-description | duo,newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Label not human-readable: "1.40×" | `a11y-element-description|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|#×` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast failed (measured 2.1:1): "Done" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|done` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.4:1): "Hard" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|hard` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.7:1): "Hard session: 52-minute run." | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|hard session: #-minute run.` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.7:1): "Load estimated from heart rate." | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|load estimated from heart rate.` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.7:1): "Session load" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|session load` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.7:1): "Compared to a typical session" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|compared to a typical session` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.7:1): "Load from" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|load from` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.7:1): "Heart-rate coverage" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|heart-rate coverage` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.7:1): "Estimate" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|estimate` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.7:1): "Model version" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|model version` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast failed (measured 1.9:1): "Medium confidence" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|medium confidence` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-detail | Contrast nearly passed (measured 3.2:1): "Recharge+" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-detail|recharge+` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-after-relaunch | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-after-relaunch|history` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-after-relaunch | Contrast failed (measured 1.9:1): "Upgrade" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-after-relaunch|upgrade` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-after-relaunch | Contrast failed (measured 1.7:1): "Updated just now" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-after-relaunch|updated just now` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-after-relaunch | Contrast nearly passed (measured 3.4:1): "left" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-after-relaunch|left` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-after-relaunch | Contrast nearly passed (measured 3.4:1): "22h from your run 3h ago" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-after-relaunch|#h from your run #h ago` |
| P2 | a11y-contrast | accessibility,newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-after-relaunch | Contrast nearly passed (measured 3.2:1): "Recharge+" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-after-relaunch|recharge+` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-after-relaunch | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-after-relaunch|standard` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast failed (measured 3.4:1): "Today" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|today` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast failed (measured 1.9:1): "Upgrade" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|upgrade` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.4:1): "Yesterday" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|yesterday` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast failed (measured 1.7:1): "15h total" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|#h total` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.4:1): "Friday, Oct 30" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|friday, oct #` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.4:1): "Thursday, Oct 29" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|thursday, oct #` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.4:1): "Wednesday, Oct 28" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|wednesday, oct #` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.7:1): "Hard · 7:08 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.7:1): "Moderate · 8:08 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|moderate · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.7:1): "Active recovery · 1:08 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|active recovery · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.7:1): "Light · 7:08 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|light · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast nearly passed (measured 3.7:1): "Very hard · 9:08 AM" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|very hard · #:# am` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast failed (measured 1.9:1): "countdown" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|countdown` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast failed (measured 1.9:1): "no countdown" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|no countdown` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast failed (measured 1.9:1): "under the threshold" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|under the threshold` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | Contrast failed (measured 1.9:1): "26h countdown" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|#h countdown` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-ready | Contrast failed (measured 1.8:1): "Today" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-ready|today` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-ready | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-ready|history` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-ready | Contrast failed (measured 1.9:1): "Recharge+" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-ready|recharge+` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-ready | Contrast failed (measured 1.7:1): "Updated just now" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-ready|updated just now` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-ready | Contrast nearly passed (measured 3.4:1): "18h from your run 1d 2h ago" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-ready|#h from your run #d #h ago` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-today-ready | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-today-ready|standard` |
| P2 | a11y-hit-region | duo,newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Hit area is too small: "High confidence" | `a11y-hit-region|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|high confidence` |
| P3 | a11y-element-description | duo,newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Label not human-readable: "1.20×" | `a11y-element-description|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|#×` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast failed (measured 2.1:1): "Done" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|done` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Countdown ran 15 to 21h." | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|countdown ran # to #h.` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.4:1): "Hard" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|hard` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Hard for you: 52-minute run." | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|hard for you: #-minute run.` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Load estimated from heart rate." | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|load estimated from heart rate.` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Session load" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|session load` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Compared to your usual" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|compared to your usual` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Load from" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|load from` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Heart-rate coverage" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|heart-rate coverage` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Estimate" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|estimate` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "30-day recovery rate" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|#-day recovery rate` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast nearly passed (measured 3.7:1): "Model version" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|model version` |
| P2 | a11y-contrast | newcomer,reduce-motion | testCoreLoopCountdownFromAWorkoutToReady / core-ready-detail | Contrast failed (measured 1.9:1): "High confidence" | `a11y-contrast|testCoreLoopCountdownFromAWorkoutToReady|core-ready-detail|high confidence` |
| P2 | overlap | accessibility | test03UpgradePaywallForAFreeUser / upgrade | button "Yearly, POPULAR, $29.99 per year, 7-day free trial included · Cancel anytime" overlaps "paywall-cta" by 90% (AX3 text only) | `overlap|test03UpgradePaywallForAFreeUser|upgrade|yearly, popular, $# per year, #-day free trial included · ca` |

## Needs a judgement (2)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P1 | motion-jump | accessibility | testCoreLoopCountdownFromAWorkoutToReady / core-history | jump candidate at 214.49s of journeys.mp4 (score 0.131) ([sheet](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/journeys.event-11.png)) | `motion-jump|testCoreLoopCountdownFromAWorkoutToReady|core-history|` |
| P1 | motion-jump | accessibility | testCoreLoopCountdownFromAWorkoutToReady / core-history-after-relaunch | jump candidate at 244.85s of journeys.mp4 (score 0.13) | `motion-jump|testCoreLoopCountdownFromAWorkoutToReady|core-history-after-relaunch|` |

## Legacy backlog, warns until fixed (120)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|history` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast nearly passed (measured 3.4:1): "No recent workout" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|no recent workout` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast nearly passed (measured 3.2:1): "Recharge+" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|recharge+` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|standard` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed (measured 1.8:1): "Today" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|today` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed (measured 1.7:1): "Updated just now" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|updated just now` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed (measured 1.9:1): "Upgrade" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|upgrade` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-1 | Contrast failed (measured 2.6:1): "Continue" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-1|continue` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed (measured 3.7:1): "Across 5 activity types, over the last 120 days." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|across # activity types, over the last # days.` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast failed (measured 2.1:1): "Continue" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|continue` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed (measured 3.7:1): "The same, from the other direction." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|the same, from the other direction.` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "7-day free trial included · Cancel anytime" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|#-day free trial included · cancel anytime` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.7:1): "7-day free · Nothing charged today" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|#-day free · nothing charged today` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast failed (measured 1.7:1): "$29.99 / year after the 7-day free trial. Auto-renews unless cancelled at least 24 hours before the trial ends." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|$# / year after the #-day free trial. auto-renews unless can` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "A recharge time built from your own history" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|a recharge time built from your own history` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "Apple EULA" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|apple eula` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast failed (measured 1.7:1): "For a hard 60-minute session. An example on the real curve until you have recorded one." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|for a hard #-minute session. an example on the real curve un` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "Get Started" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|get started` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "Privacy" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|privacy` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast failed (measured 1.9:1): "RECHARGE+" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|recharge+` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "Restore" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|restore` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "Sleep, HRV, and resting heart rate" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|sleep, hrv, and resting heart rate` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|standard` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "Terms" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|terms` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed (measured 3.4:1): "Weekly load against your 4-week average" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|weekly load against your #-week average` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / welcome | Contrast failed (measured 2.1:1): "Continue" | `a11y-contrast|test01OnboardingToOfferAndToday|welcome|continue` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed (measured 1.9:1): "21h countdown" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|#h countdown` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed (measured 1.7:1): "12h total" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|#h total` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed (measured 1.9:1): "countdown" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|countdown` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.4:1): "Friday, Oct 30" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|friday, oct #` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed (measured 1.9:1): "no countdown" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|no countdown` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed (measured 1.9:1): "Recharge+" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|recharge+` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.4:1): "Thursday, Oct 29" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|thursday, oct #` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed (measured 3.4:1): "Today" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|today` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed (measured 1.9:1): "under the threshold" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|under the threshold` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.4:1): "Wednesday, Oct 28" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|wednesday, oct #` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed (measured 3.4:1): "Yesterday" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|yesterday` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed (measured 1.9:1): "4-WEEK AVG" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|#-week avg` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed (measured 4.2:1): "-14%" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|-#%` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed (measured 1.7:1): "History" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|history` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed (measured 1.9:1): "RECHARGE+" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|recharge+` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|standard` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed (measured 1.9:1): "THIS WEEK" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|this week` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast nearly passed (measured 3.4:1): "18h from your run 3h ago" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|#h from your run #h ago` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|history` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast nearly passed (measured 3.4:1): "left" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|left` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed (measured 1.9:1): "Recharge+" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|recharge+` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|standard` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed (measured 1.7:1): "Updated just now" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|updated just now` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast nearly passed (measured 3.4:1): "22h from your run 3h ago" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|#h from your run #h ago` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|history` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast nearly passed (measured 3.4:1): "left" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|left` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed (measured 1.9:1): "RECHARGE+" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|recharge+` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|standard` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed (measured 1.7:1): "Updated just now" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|updated just now` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed (measured 1.9:1): "Upgrade" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|upgrade` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast nearly passed (measured 3.4:1): "22h from your run 3h ago" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|#h from your run #h ago` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|history` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast nearly passed (measured 3.4:1): "left" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|left` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast nearly passed (measured 3.2:1): "Recharge+" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|recharge+` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|standard` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed (measured 1.7:1): "Updated just now" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|updated just now` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed (measured 1.9:1): "Upgrade" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|upgrade` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed (measured 1.9:1): "7-day free trial included · Cancel anytime" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|#-day free trial included · cancel anytime` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|history` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed (measured 1.9:1): "One-time purchase · No subscription" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|one-time purchase · no subscription` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed (measured 1.9:1): "paywall-disclosure" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|paywall-disclosure` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast nearly passed (measured 3.4:1): "Personalized recovery from your history." | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|personalized recovery from your history.` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast nearly passed (measured 4.0:1): "POPULAR" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|popular` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast nearly passed (measured 3.2:1): "Upgrade" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|upgrade` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed (measured 4.2:1): "-14% shorter" | `a11y-contrast|test04Settings|settings|-#% shorter` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast failed (measured 2.1:1): "Done" | `a11y-contrast|test04Settings|settings|done` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast failed (measured 1.8:1): "RECHARGE+" | `a11y-contrast|test04Settings|settings|recharge+` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast failed (measured 2.1:1): "See Recharge+" | `a11y-contrast|test04Settings|settings|see recharge+` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed (measured 3.4:1): "Standard" | `a11y-contrast|test04Settings|settings|standard` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed (measured 1.9:1): "21h countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|#h countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed (measured 1.7:1): "12h total" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|#h total` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed (measured 1.9:1): "countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.4:1): "Friday, Oct 30" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|friday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed (measured 1.9:1): "no countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|no countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed (measured 1.9:1): "Recharge+" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|recharge+` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.4:1): "Thursday, Oct 29" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|thursday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed (measured 3.4:1): "Today" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|today` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed (measured 1.9:1): "under the threshold" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|under the threshold` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.4:1): "Wednesday, Oct 28" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|wednesday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed (measured 3.4:1): "Yesterday" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|yesterday` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed (measured 1.9:1): "21h countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|#h countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed (measured 1.7:1): "12h total" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|#h total` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed (measured 1.9:1): "countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.4:1): "Friday, Oct 30" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|friday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed (measured 1.9:1): "no countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|no countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed (measured 1.9:1): "Recharge+" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|recharge+` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.4:1): "Thursday, Oct 29" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|thursday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed (measured 3.4:1): "Today" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|today` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed (measured 1.9:1): "under the threshold" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|under the threshold` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.4:1): "Wednesday, Oct 28" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|wednesday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed (measured 3.4:1): "Yesterday" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|yesterday` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast nearly passed (measured 3.4:1): "18h from your run 3h ago" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|#h from your run #h ago` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed (measured 1.9:1): "History" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|history` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast nearly passed (measured 3.4:1): "left" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|left` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed (measured 1.9:1): "Recharge+" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|recharge+` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed (measured 1.9:1): "STANDARD" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|standard` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed (measured 1.7:1): "Updated just now" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|updated just now` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-1 | Hit area is too small: "Step 2 of 9" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-1|step # of #` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-2 | Hit area is too small: "Step 3 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-2|step # of #` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-3 | Hit area is too small: "Step 4 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-3|step # of #` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-4 | Hit area is too small: "Step 5 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-4|step # of #` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-5 | Hit area is too small: "Step 6 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-5|step # of #` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Apple EULA" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|apple eula` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Get Started" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|get started` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Privacy" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|privacy` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Restore" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|restore` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Step 7 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|step # of #` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Terms" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|terms` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / welcome | Hit area is too small: "Step 1 of 9" | `a11y-hit-region|test01OnboardingToOfferAndToday|welcome|step # of #` |
| P2 | clipped |  | test02TodayHistoryAndRechargePlus / recharge-plus | text "RECHARGE+" is broken across 2 lines: RECHARGE / + (AX3 text only) | `clipped|test02TodayHistoryAndRechargePlus|recharge-plus|recharge+` |
| P2 | clipped |  | test02TodayHistoryAndRechargePlus / recharge-plus | text "STANDARD" is broken across 2 lines: STAN- / DARD (AX3 text only) | `clipped|test02TodayHistoryAndRechargePlus|recharge-plus|standard` |
| P2 | truncated |  | test01OnboardingToOfferAndToday / onboarding-offer | text drawn as "* 7-day free • Nothing..." but reads "7-day free · Nothing charged today" (AX3 text only) | `truncated|test01OnboardingToOfferAndToday|onboarding-offer|#-day free · nothing charged today` |
| P2 | truncated |  | test01OnboardingToOfferAndToday / onboarding-offer | button drawn as "Continue with Rech..." but reads "Continue with Recharge+" (AX3 text only) | `truncated|test01OnboardingToOfferAndToday|onboarding-offer|continue with recharge+` |
| P2 | truncated |  | test03UpgradePaywallForAFreeUser / upgrade | text drawn as "renews unless cancelle..." but reads "$29.99 / year after the 7-day free trial. Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel in  | `truncated|test03UpgradePaywallForAFreeUser|upgrade|paywall-disclosure` |

## Journeys

| Persona | Journey | Result | Seconds |
|---|---|---|---|
| newcomer | test01OnboardingToOfferAndToday | Passed | 64.85537993907928 |
| newcomer | test02TodayHistoryAndRechargePlus | Passed | 46.08530795574188 |
| newcomer | test03UpgradePaywallForAFreeUser | Passed | 75.66163408756256 |
| newcomer | test04Settings | Passed | 25.719444036483765 |
| newcomer | test05ReturnVisitWithInterruption | Passed | 79.07949304580688 |
| newcomer | testCoreLoopCountdownFromAWorkoutToReady | Passed | 174.9595959186554 |
| accessibility | test01OnboardingToOfferAndToday | Passed | 64.85346400737762 |
| accessibility | test02TodayHistoryAndRechargePlus | Passed | 26.25991702079773 |
| accessibility | test03UpgradePaywallForAFreeUser | Passed | 32.884397983551025 |
| accessibility | test04Settings | Passed | 13.962270021438599 |
| accessibility | test05ReturnVisitWithInterruption | Passed | 33.16077899932861 |
| accessibility | testCoreLoopCountdownFromAWorkoutToReady | Passed | 81.65884304046631 |
| reduce-motion | test01OnboardingToOfferAndToday | Passed | 63.68101894855499 |
| reduce-motion | test02TodayHistoryAndRechargePlus | Passed | 46.044532895088196 |
| reduce-motion | test03UpgradePaywallForAFreeUser | Passed | 44.56299602985382 |
| reduce-motion | test04Settings | Passed | 18.374999046325684 |
| reduce-motion | test05ReturnVisitWithInterruption | Passed | 45.312248945236206 |
| reduce-motion | testCoreLoopCountdownFromAWorkoutToReady | Passed | 113.81609606742859 |
| duo | test01OnboardingToOfferAndToday | Passed | 65.24442100524902 |
| duo | test02TodayHistoryAndRechargePlus | Passed | 23.91604208946228 |
| duo | test03UpgradePaywallForAFreeUser | Passed | 24.232941031455994 |
| duo | test04Settings | Passed | 13.838557958602905 |
| duo | test05ReturnVisitWithInterruption | Passed | 37.94511103630066 |
| duo | testCoreLoopCountdownFromAWorkoutToReady | Passed | 79.98634910583496 |

## Motion

| Persona | Motion s | Windows | Candidates | Gaps > 25 ms | 60 fps |
|---|---|---|---|---|---|
| newcomer | 30.272 | 59 | 11 | 62 | True |
| accessibility | 31.369 | 61 | 15 | 51 | True |
| reduce-motion | 24.19 | 52 | 9 | 41 | True |

## Launch entrances to look at

Each launch's frames after the springboard zoom, left to right then down, 4 frames per
row at the recorded rate. A blank stretch, text that reflows, or content that arrives and
pushes the layout is a finding: `qa-gate ledger <repo> add`.

- [entrance-01-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-01-launch-scene.png)
- [entrance-10-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-10-launch-scene.png)
- [entrance-14-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-14-launch-scene.png)
- [entrance-18-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-18-launch-scene.png)
- [entrance-20-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-20-launch-scene.png)
- [entrance-24-test05returnvisitwithinterruption.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-24-test05returnvisitwithinterruption.png)
- [entrance-26-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-26-launch-scene.png)
- [entrance-31-testcoreloopcountdownfromaworkouttoready.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-31-testcoreloopcountdownfromaworkouttoready.png)
- [entrance-34-testcoreloopcountdownfromaworkouttoready.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/newcomer/entrance-34-testcoreloopcountdownfromaworkouttoready.png)
- [entrance-01-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-01-launch-scene.png)
- [entrance-10-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-10-launch-scene.png)
- [entrance-14-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-14-launch-scene.png)
- [entrance-18-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-18-launch-scene.png)
- [entrance-20-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-20-launch-scene.png)
- [entrance-24-test05returnvisitwithinterruption.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-24-test05returnvisitwithinterruption.png)
- [entrance-26-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-26-launch-scene.png)
- [entrance-31-testcoreloopcountdownfromaworkouttoready.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-31-testcoreloopcountdownfromaworkouttoready.png)
- [entrance-34-testcoreloopcountdownfromaworkouttoready.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/accessibility/entrance-34-testcoreloopcountdownfromaworkouttoready.png)
- [entrance-01-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/reduce-motion/entrance-01-launch-scene.png)
- [entrance-10-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/reduce-motion/entrance-10-launch-scene.png)
- [entrance-14-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/reduce-motion/entrance-14-launch-scene.png)
- [entrance-18-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/reduce-motion/entrance-18-launch-scene.png)
- [entrance-20-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/reduce-motion/entrance-20-launch-scene.png)
- [entrance-32-testcoreloopcountdownfromaworkouttoready.png](/Users/jackwallner/recovery-ship/build/qa/433714d23b34/reduce-motion/entrance-32-testcoreloopcountdownfromaworkouttoready.png)

Skipped personas: german (app not localized).
