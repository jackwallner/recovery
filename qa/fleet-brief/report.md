# Release gate: recovery-ship 1af6dee636fb

Verdict: **BLOCK** (2026-11-01T07:47:21+00:00)

Every finding blocks except legacy backlog. `qa-gate fix <repo>` fixes them. Motion candidates need a judgement in the ledger: `qa-gate ledger <repo> accept` for an intended change, or `add` a P1 when it is a real glitch.

## Blocking (4)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P0 | journey-broken | duo | test02TodayHistoryAndRechargePlus /  | Failed to tap "History" Button: No matches found for first query match sequence: `Descendants matching type Button` -> `Elements matching predicate '"History" IN identifiers'`, given input App element pid: 22293 | `journey-broken|test02TodayHistoryAndRechargePlus` |
| P0 | journey-broken | duo | test05ReturnVisitWithInterruption /  | Failed to tap "History" Button: No matches found for first query match sequence: `Descendants matching type Button` -> `Elements matching predicate '"History" IN identifiers'`, given input App element pid: 22664 | `journey-broken|test05ReturnVisitWithInterruption` |
| P1 | fleetqa-stale |  |  /  | vendored FleetQA.swift differs from ~/ios/qa; rerun after install | `fleetqa-stale` |
| P1 | core-journey-missing |  |  /  | no testCoreLoop journey proves the core feature still works; write one (/Users/jackwallner/ios/qa/core-journey-brief.md) | `core-journey-missing` |

## Needs a judgement (1)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P1 | motion-jump | accessibility | test04Settings / settings | jump candidate at 209.36s of journeys.mp4 (score 0.131) ([sheet](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/accessibility/journeys.event-06.png)) | `motion-jump|test04Settings|settings|` |

## Legacy backlog, warns until fixed (197)

| Sev | Oracle | Persona | Journey / checkpoint | Detail | Fingerprint |
|---|---|---|---|---|---|
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / welcome | Hit area is too small: "Step 1 of 9" | `a11y-hit-region|test01OnboardingToOfferAndToday|welcome|step # of #` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / welcome | Contrast failed: "Continue" | `a11y-contrast|test01OnboardingToOfferAndToday|welcome|continue` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / welcome | Contrast nearly passed: "Finish a qualifying workout and Recharge starts a training-load countdown. When it runs out, the estimate is complete. Recharge reads Apple Health and never writes to it." | `a11y-contrast|test01OnboardingToOfferAndToday|welcome|finish a qualifying workout and recharge starts a training-l` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-1 | Hit area is too small: "Step 2 of 9" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-1|step # of #` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-1 | Contrast failed: "Continue" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-1|continue` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-1 | Contrast nearly passed: "Your workouts and heart rate build the estimate. Your own highest heart rate sets the range intensity is measured against. Sleep, resting heart rate, HRV, breathing rate, card | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-1|your workouts and heart rate build the estimate. your own hi` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-2 | Hit area is too small: "Step 3 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-2|step # of #` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast failed: "Continue" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|continue` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "2 short questions left, for the things Health can't answer." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|# short questions left, for the things health can't answer.` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "Across 5 activity types, over the last 120 days." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|across # activity types, over the last # days.` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "Measured from 88 sessions. Every intensity reading is scored against it." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|measured from # sessions. every intensity reading is scored ` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "Sets the training level your sessions are compared against." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|sets the training level your sessions are compared against.` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "Watched night to night for signs the last session is still with you." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|watched night to night for signs the last session is still w` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "The same, from the other direction." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|the same, from the other direction.` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "How far your heart rate falls in the minute after a session ends." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|how far your heart rate falls in the minute after a session ` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "A short night lengthens the estimate a little; a long one shortens it." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|a short night lengthens the estimate a little; a long one sh` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast nearly passed: "Adds another overnight signal to the estimate alongside sleep, HRV, and resting heart rate." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|adds another overnight signal to the estimate alongside slee` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-3 | Hit area is too small: "Step 4 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-3|step # of #` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-3 | Contrast nearly passed: "Skip this one" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-3|skip this one` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-3 | Contrast nearly passed: "Years of consistent training change how the same relative load lands." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-3|years of consistent training change how the same relative lo` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-4 | Hit area is too small: "Step 5 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-4|step # of #` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-4 | Contrast nearly passed: "Skip this one" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-4|skip this one` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-4 | Contrast nearly passed: "Your own read on it. Recharge starts here and replaces it with what your data shows." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-4|your own read on it. recharge starts here and replaces it wi` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-5 | Hit area is too small: "Step 6 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-5|step # of #` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-5 | Contrast nearly passed: "I understand" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-5|i understand` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-5 | Contrast nearly passed: "Recharge estimates a training-load recovery window from your recent workouts. It is not a measure of muscle repair, illness, injury risk, or whether you are fit to train, and  | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-5|recharge estimates a training-load recovery window from your` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Get Started" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|get started` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Restore" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|restore` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Terms" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|terms` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Apple EULA" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|apple eula` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Privacy" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|privacy` |
| P2 | a11y-hit-region |  | test01OnboardingToOfferAndToday / onboarding-offer | Hit area is too small: "Step 7 of 7" | `a11y-hit-region|test01OnboardingToOfferAndToday|onboarding-offer|step # of #` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "7-day free trial included · Cancel anytime" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|#-day free trial included · cancel anytime` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast failed: "$29.99 / year after the 7-day free trial. Auto-renews unless cancelled at least 24 hours before the trial ends." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|$# / year after the #-day free trial. auto-renews unless can` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Get Started" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|get started` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Continue with Recharge+" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|continue with recharge+` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Restore" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|restore` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Terms" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|terms` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Apple EULA" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|apple eula` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Privacy" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|privacy` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "7-day free · Nothing charged today" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|#-day free · nothing charged today` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast failed: "For a hard 60-minute session. An example on the real curve until you have recorded one." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|for a hard #-minute session. an example on the real curve un` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|standard is the model at your training level. recharge+ scor` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "A recharge time built from your own history" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|a recharge time built from your own history` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Sleep, HRV, and resting heart rate" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|sleep, hrv, and resting heart rate` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast nearly passed: "Weekly load against your 4-week average" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|weekly load against your #-week average` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast failed: "STANDARD" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|standard` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-offer | Contrast failed: "RECHARGE+" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-offer|recharge+` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed: "Today" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|today` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed: "History" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|history` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed: "Upgrade" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|upgrade` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed: "Updated just now" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|updated just now` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast nearly passed: "No recent workout" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|no recent workout` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast nearly passed: "Recharge+" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|recharge+` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed: "STANDARD" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|standard` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast nearly passed: "A hard 60-minute session. Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|a hard #-minute session. standard is the model at your train` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed: "Today" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|today` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed: "History" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|history` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed: "Recharge+" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|recharge+` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed: "Updated just now" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|updated just now` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast nearly passed: "left" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|left` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast nearly passed: "18h from your run 3h ago" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|#h from your run #h ago` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast failed: "STANDARD" | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|standard` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / today | Contrast nearly passed: "Your last run. Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." | `a11y-contrast|test02TodayHistoryAndRechargePlus|today|your last run. standard is the model at your training level.` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "Today" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|today` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "History" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|history` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "Recharge+" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|recharge+` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Yesterday" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|yesterday` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Friday, Oct 30" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|friday, oct #` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "12h total" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|#h total` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Thursday, Oct 29" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|thursday, oct #` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Wednesday, Oct 28" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|wednesday, oct #` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Tuesday, Oct 27" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|tuesday, oct #` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Hard · 9:15 PM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|hard · #:# pm` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Moderate · 9:15 PM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|moderate · #:# pm` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Active recovery · 2:15 PM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|active recovery · #:# pm` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Light · 8:15 PM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|light · #:# pm` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast nearly passed: "Very hard · 10:15 PM" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|very hard · #:# pm` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "countdown" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|countdown` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "no countdown" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|no countdown` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "under the threshold" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|under the threshold` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "21h countdown" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|#h countdown` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed: "Today" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|today` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed: "History" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|history` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed: "Recharge+" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|recharge+` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed: "Your countdowns are measured, not looked up." | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|your countdowns are measured, not looked up.` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed: "STANDARD" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|standard` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed: "Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|standard is the model at your training level. recharge+ scor` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed: "-14%" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|-#%` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed: "Your windows run about 14% shorter than the standard estimate." | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|your windows run about #% shorter than the standard estimate` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed: "Resting heart rate and HRV settle back quickly after your hard sessions (6 measured)." | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|resting heart rate and hrv settle back quickly after your ha` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed: "You have held your usual intensity training inside the estimated window." | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|you have held your usual intensity training inside the estim` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast nearly passed: "Based on 20 sessions in the last 30 days, about 4.7 a week." | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|based on # sessions in the last # days, about # a week.` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed: "THIS WEEK" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|this week` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed: "4-WEEK AVG" | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|#-week avg` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / recharge-plus | Contrast failed: "Load is a proxy built from your own sessions, not a measurement." | `a11y-contrast|test02TodayHistoryAndRechargePlus|recharge-plus|load is a proxy built from your own sessions, not a measurem` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed: "Today" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|today` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed: "History" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|history` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed: "Upgrade" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|upgrade` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed: "Updated just now" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|updated just now` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast nearly passed: "left" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|left` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast nearly passed: "22h from your run 3h ago" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|#h from your run #h ago` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast nearly passed: "Recharge+" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|recharge+` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed: "STANDARD" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|standard` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast nearly passed: "Your last run. Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|your last run. standard is the model at your training level.` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed: "Today" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|today` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed: "History" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|history` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast nearly passed: "Upgrade" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|upgrade` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast nearly passed: "paywall-cta" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|paywall-cta` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed: "paywall-disclosure" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|paywall-disclosure` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast nearly passed: "Personalized recovery from your history." | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|personalized recovery from your history.` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast nearly passed: "Every session scored against your own 42-day baseline and 30-day recovery pattern." | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|every session scored against your own #-day baseline and #-d` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast nearly passed: "POPULAR" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|popular` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed: "7-day free trial included · Cancel anytime" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|#-day free trial included · cancel anytime` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / upgrade | Contrast failed: "One-time purchase · No subscription" | `a11y-contrast|test03UpgradePaywallForAFreeUser|upgrade|one-time purchase · no subscription` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed: "Today" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|today` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed: "History" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|history` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed: "Upgrade" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|upgrade` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed: "Updated just now" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|updated just now` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast nearly passed: "left" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|left` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast nearly passed: "22h from your run 3h ago" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|#h from your run #h ago` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast nearly passed: "Recharge+" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|recharge+` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed: "STANDARD" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|standard` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast nearly passed: "Your last run. Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|your last run. standard is the model at your training level.` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast nearly passed: "countdown" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|countdown` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast failed: "Done" | `a11y-contrast|test04Settings|settings|done` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "Recharge time" | `a11y-contrast|test04Settings|settings|recharge time` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "Standard" | `a11y-contrast|test04Settings|settings|standard` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "-14% shorter" | `a11y-contrast|test04Settings|settings|-#% shorter` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "How quickly your last 30 days say you come back. It is one of the things Recharge+ changes, not the whole difference between the two figures above." | `a11y-contrast|test04Settings|settings|how quickly your last # days say you come back. it is one of` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "Resting heart rate and HRV settle back quickly after your hard sessions (6 measured)." | `a11y-contrast|test04Settings|settings|resting heart rate and hrv settle back quickly after your ha` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "You have held your usual intensity training inside the estimated window." | `a11y-contrast|test04Settings|settings|you have held your usual intensity training inside the estim` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "Based on 20 sessions in the last 30 days, about 4.7 a week." | `a11y-contrast|test04Settings|settings|based on # sessions in the last # days, about # a week.` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast failed: "See Recharge+" | `a11y-contrast|test04Settings|settings|see recharge+` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "The free estimate scores each session at your training level, the way a Garmin does before it knows you. Recharge+ scores it against your own sessions, sleep, and heart rate." | `a11y-contrast|test04Settings|settings|the free estimate scores each session at your training level` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast failed: "RECHARGE+" | `a11y-contrast|test04Settings|settings|recharge+` |
| P2 | a11y-contrast |  | test04Settings / settings | Contrast nearly passed: "For your last run. Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." | `a11y-contrast|test04Settings|settings|for your last run. standard is the model at your training le` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "Today" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|today` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "History" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|history` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "Recharge+" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|recharge+` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Yesterday" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|yesterday` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Friday, Oct 30" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|friday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "12h total" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|#h total` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Thursday, Oct 29" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|thursday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Wednesday, Oct 28" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|wednesday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Tuesday, Oct 27" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|tuesday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Hard · 9:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|hard · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Moderate · 9:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|moderate · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Active recovery · 2:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|active recovery · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Light · 8:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|light · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast nearly passed: "Very hard · 10:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|very hard · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "no countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|no countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "under the threshold" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|under the threshold` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "21h countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|#h countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "Today" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|today` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "History" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|history` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "Recharge+" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|recharge+` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Yesterday" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|yesterday` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Friday, Oct 30" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|friday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "12h total" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|#h total` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Thursday, Oct 29" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|thursday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Wednesday, Oct 28" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|wednesday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Tuesday, Oct 27" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|tuesday, oct #` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Hard · 9:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|hard · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Moderate · 9:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|moderate · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Active recovery · 2:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|active recovery · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Light · 8:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|light · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast nearly passed: "Very hard · 10:17 PM" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|very hard · #:# pm` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "no countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|no countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "under the threshold" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|under the threshold` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "21h countdown" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|#h countdown` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed: "Today" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|today` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed: "History" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|history` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed: "Recharge+" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|recharge+` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed: "Updated just now" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|updated just now` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast nearly passed: "left" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|left` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast nearly passed: "18h from your run 3h ago" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|#h from your run #h ago` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast failed: "STANDARD" | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|standard` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / today-after-relaunch | Contrast nearly passed: "Your last run. Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." | `a11y-contrast|test05ReturnVisitWithInterruption|today-after-relaunch|your last run. standard is the model at your training level.` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast failed: "Your highest heart rate" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|your highest heart rate` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-2 | Contrast failed: "187 bpm" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-2|# bpm` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / onboarding-3 | Contrast failed: "Less than a year" | `a11y-contrast|test01OnboardingToOfferAndToday|onboarding-3|less than a year` |
| P2 | truncated |  | test01OnboardingToOfferAndToday / onboarding-offer | text drawn as "Continue with Rechar..." but reads "Standard is the model at your training level. Recharge+ scores this session against your own baseline, sleep, and heart rate." (AX3 text only) | `truncated|test01OnboardingToOfferAndToday|onboarding-offer|standard is the model at your training level. recharge+ scor` |
| P2 | truncated |  | test01OnboardingToOfferAndToday / onboarding-offer | text drawn as "* 7-day free • Nothing C..." but reads "7-day free · Nothing charged today" (AX3 text only) | `truncated|test01OnboardingToOfferAndToday|onboarding-offer|#-day free · nothing charged today` |
| P2 | truncated |  | test01OnboardingToOfferAndToday / onboarding-offer | button drawn as "Continue with Rechar..." but reads "Continue with Recharge+" (AX3 text only) | `truncated|test01OnboardingToOfferAndToday|onboarding-offer|continue with recharge+` |
| P2 | a11y-contrast |  | test01OnboardingToOfferAndToday / first-today | Contrast failed: "26h" | `a11y-contrast|test01OnboardingToOfferAndToday|first-today|#h` |
| P2 | a11y-contrast |  | test02TodayHistoryAndRechargePlus / history | Contrast failed: "Ride" | `a11y-contrast|test02TodayHistoryAndRechargePlus|history|ride` |
| P2 | clipped |  | test02TodayHistoryAndRechargePlus / recharge-plus | text "STANDARD" is broken across 2 lines: STAN- / DARD (AX3 text only) | `clipped|test02TodayHistoryAndRechargePlus|recharge-plus|standard` |
| P2 | clipped |  | test02TodayHistoryAndRechargePlus / recharge-plus | text "RECHARGE+" is broken across 2 lines: RECHARGE / + (AX3 text only) | `clipped|test02TodayHistoryAndRechargePlus|recharge-plus|recharge+` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-free | Contrast failed: "22h" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-free|#h` |
| P2 | truncated |  | test03UpgradePaywallForAFreeUser / upgrade | text drawn as "at least 24 hours before..." but reads "$29.99 / year after the 7-day free trial. Auto-renews unless cancelled at least 24 hours before the end of the current period. Manage or cancel i | `truncated|test03UpgradePaywallForAFreeUser|upgrade|paywall-disclosure` |
| P2 | a11y-contrast |  | test03UpgradePaywallForAFreeUser / today-after-upgrade | Contrast failed: "22h" | `a11y-contrast|test03UpgradePaywallForAFreeUser|today-after-upgrade|#h` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-before-interruption | Contrast failed: "Ride" | `a11y-contrast|test05ReturnVisitWithInterruption|history-before-interruption|ride` |
| P2 | a11y-contrast |  | test05ReturnVisitWithInterruption / history-after-interruption | Contrast failed: "Ride" | `a11y-contrast|test05ReturnVisitWithInterruption|history-after-interruption|ride` |
| P2 | reduce-motion-ignored |  | all / all | with Reduce Motion on the journeys still moved for 16.9s against 19.9s without it (85%); check which animations ignore it | `reduce-motion-ignored|all|all|` |

## Journeys

| Persona | Journey | Result | Seconds |
|---|---|---|---|
| newcomer | test01OnboardingToOfferAndToday | Passed | 76.63610696792603 |
| newcomer | test02TodayHistoryAndRechargePlus | Passed | 48.29879403114319 |
| newcomer | test03UpgradePaywallForAFreeUser | Passed | 51.43388307094574 |
| newcomer | test04Settings | Passed | 27.18098497390747 |
| newcomer | test05ReturnVisitWithInterruption | Passed | 59.89859199523926 |
| accessibility | test01OnboardingToOfferAndToday | Passed | 69.73006904125214 |
| accessibility | test02TodayHistoryAndRechargePlus | Passed | 40.46940505504608 |
| accessibility | test03UpgradePaywallForAFreeUser | Passed | 35.78825604915619 |
| accessibility | test04Settings | Passed | 13.691475987434387 |
| accessibility | test05ReturnVisitWithInterruption | Passed | 33.69245004653931 |
| reduce-motion | test01OnboardingToOfferAndToday | Passed | 66.67922711372375 |
| reduce-motion | test02TodayHistoryAndRechargePlus | Passed | 33.71746802330017 |
| reduce-motion | test03UpgradePaywallForAFreeUser | Passed | 35.44966793060303 |
| reduce-motion | test04Settings | Passed | 15.630532026290894 |
| reduce-motion | test05ReturnVisitWithInterruption | Passed | 42.75411605834961 |
| duo | test01OnboardingToOfferAndToday | Passed | 63.248517990112305 |
| duo | test02TodayHistoryAndRechargePlus | Failed | 14.198415040969849 |
| duo | test03UpgradePaywallForAFreeUser | Passed | 23.841205954551697 |
| duo | test04Settings | Passed | 13.22605299949646 |
| duo | test05ReturnVisitWithInterruption | Failed | 8.782121062278748 |

## Motion

| Persona | Motion s | Windows | Candidates | Gaps > 25 ms | 60 fps |
|---|---|---|---|---|---|
| newcomer | 19.892 | 37 | 12 | 63 | True |
| accessibility | 19.204 | 34 | 7 | 56 | True |
| reduce-motion | 16.897 | 35 | 6 | 41 | True |

## Launch entrances to look at

Each launch's frames after the springboard zoom, left to right then down, 4 frames per
row at the recorded rate. A blank stretch, text that reflows, or content that arrives and
pushes the layout is a finding: `qa-gate ledger <repo> add`.

- [entrance-01-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/newcomer/entrance-01-launch-scene.png)
- [entrance-01-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/accessibility/entrance-01-launch-scene.png)
- [entrance-18-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/accessibility/entrance-18-launch-scene.png)
- [entrance-01-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/reduce-motion/entrance-01-launch-scene.png)
- [entrance-10-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/reduce-motion/entrance-10-launch-scene.png)
- [entrance-14-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/reduce-motion/entrance-14-launch-scene.png)
- [entrance-18-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/reduce-motion/entrance-18-launch-scene.png)
- [entrance-20-launch-scene.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/reduce-motion/entrance-20-launch-scene.png)
- [entrance-24-test05returnvisitwithinterruption.png](/Users/jackwallner/recovery-ship/build/qa/1af6dee636fb/reduce-motion/entrance-24-test05returnvisitwithinterruption.png)

Skipped personas: german (app not localized).
