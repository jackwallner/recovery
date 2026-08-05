# Recovery Countdown

Research dossier, updated 2026-08-01.

## Recommendation

Build an Apple Watch-first **Recovery Countdown** with a clear **Ready** state. The product should answer one question:

> “After my last meaningful workout, when is my next hard workout likely to be reasonable?”

This is different from a generic readiness score. A score such as 74/100 is already offered by Athlytic, Bevel, Training Today, and many newer apps. A transparent countdown plus a ready marker is closer to the specific Garmin behavior users say they miss.

The product should be named and framed as a training estimate. It should not imply that the app can diagnose fatigue, prevent injury, or determine medical fitness.

## Direct answer on Garmin’s formula

Garmin’s consumer Recovery Time is not open source. Garmin attributes the feature to Firstbeat’s algorithm. Public Garmin documentation describes the inputs at a high level, including recent exercise, sleep quality, and stress, while Garmin’s Training Readiness documentation lists sleep score, recovery time, HRV status, acute load, recent sleep history, and recent stress history as factors in its readiness score. The documentation does not publish the coefficients, model weights, or source code. [Garmin Recovery Time](https://www.garmin.com/en-US/garmin-technology/running-science/physiological-measurements/recovery-time/), [Garmin support](https://support.garmin.com/en-IE/?faq=8ImmxVkZMhE4YYq5Zp2bR8), [Garmin Training Readiness manual](https://www8.garmin.com/manuals/webhelp/GUID-0221611A-992D-495E-8DED-1DD448F7A066/EN-AU/GUID-C21BE0C8-A08E-4DA1-B6C6-2E0E2DDDB372.html)

Firstbeat publishes methodology material and describes TRIMP, acute load, chronic load, and recovery concepts, but Garmin’s combined consumer product remains proprietary. [Firstbeat Training Status](https://support.firstbeat.com/hc/en-us/articles/360024695553-Feature-Firstbeat-Sports-Training-Status), [Firstbeat research options](https://www.firstbeat.com/en/research-options/)

We should build an independent, transparent model using HealthKit data and established training-load methods. We should not copy Garmin’s branding, reverse engineer its output, or claim equivalent accuracy.

## Specific niche

### Primary user

The best initial user is not every Apple Watch owner. It is an Apple Watch owner who:

- trains at least several times per week;
- runs, cycles, rows, does CrossFit or HYROX, or combines endurance and strength;
- has used Garmin, WHOOP, Oura, or a readiness app before;
- wants a simple answer after a hard session;
- finds Apple’s Training Load useful but incomplete;
- does not want a large all-in-one wellness dashboard.

### Job to be done

After a workout, show:

```text
Recovery: 18h 40m
Ready: tomorrow at 7:30 AM
Confidence: building baseline
Why: hard 52-minute run
```

During recovery:

```text
18h left
```

After the estimate expires:

```text
Ready
```

The app should let the user understand the reason without turning the Watch face into a dashboard.

## Demand and gap evidence

- Apple now has native Training Load. It compares the last seven days with the previous 28 days and classifies the load from well below to well above. It does not present the simple post-workout recovery countdown that Garmin users recognize. [Apple Training Load](https://support.apple.com/en-ie/guide/watch/apde4c07a6cf/watchos)
- Users have repeatedly asked for a Garmin-style recovery-time feature on Apple Watch. A Reddit thread specifically asks for an estimated recovery time between runs and comments that Apple Watch lacks a dynamic equivalent. [Garmin Recovery Time request](https://www.reddit.com/r/AppleWatch/comments/1l5wkiu/is_there_an_app_that_offers_something_similar_to/)
- In a recent runner watch-face discussion, users mention recovery time as a desired complication and describe the lack of a good Apple Watch implementation as a gap worth building. [Runner complication discussion](https://www.reddit.com/r/applewatchultra/comments/1tp5h9n/runner_s_watch_face_what_complications_do_you_use/)
- A current App Store app, RecoTime, positions itself around automatic post-workout recovery calculations on iPhone and Apple Watch but does not have enough ratings to display an overview. [RecoTime](https://apps.apple.com/us/app/recotime-smart-recovery-calc/id6751836043)
- A newer HealthKit app called Training Load & Recovery exposes TRIMP, TSB, Apple Effort Score, HRV, resting heart rate, workout history, widgets, and Apple Watch support, but its listing shows only a small number of ratings. [Training Load & Recovery](https://apps.apple.com/us/app/training-load-recovery/id6741155891)

The opportunity is real, but the market is beginning to fill. The defensible point is a narrower and clearer product: a countdown and a ready mark, not a competing wellness operating system.

## Competitor map

| Competitor | What it does | Strength | Weakness or opening |
|---|---|---|---|
| Garmin | Native Recovery Time and Training Readiness | Strong integrated hardware, long history, proprietary Firstbeat model | Requires Garmin ecosystem; model is opaque |
| Apple Training Load | Seven-day versus 28-day relative load | Native, free, already on the Watch | No simple countdown; no direct “ready again” marker |
| Athlytic | HRV-based recovery, exertion, target exertion, sleep, many complications | About 11K ratings and 4.8 in the US listing; broad Apple Watch feature set | Broad score system, not a focused countdown; subscription competition |
| Bevel | Recovery score, sleep, strain, stress, energy bank, nutrition, strength | About 12K to 13K ratings and 4.8; broad polish | All-in-one scope makes the single answer harder to own |
| Training Today | Readiness-style guidance from Apple Health | Familiar Apple Watch recovery category | Score and recommendation, not necessarily a countdown-first product |
| RecoTime | Post-workout smart recovery calculation | Directly targets the idea and supports Apple Watch | Very low visible validation; algorithm details are not public |
| Training Load & Recovery | TRIMP, TSB, HRV, RHR, Apple Watch and widgets | Science-oriented implementation and a transparent vocabulary | Small current rating base, more technical than a mass-market utility |
| SportVitals | Readiness, body battery, training load, recovery time, and other Garmin-like metrics | Ambitious feature coverage and one-time-purchase positioning | Directly overlaps the broader recovery dashboard category |
| MySplit Recovery | Muscle-group recovery and rest timelines | Useful for strength training and muscle-specific input | Different problem, more manual, not a cardiovascular recovery countdown |

Athlytic’s App Store listing explicitly includes recovery and exertion complications and states that it uses Apple Health data. Bevel’s listing includes recovery, sleep, strain, stress, nutrition, and energy bank. These are real competitors, not hypothetical future products. [Athlytic](https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755), [Bevel](https://apps.apple.com/us/app/bevel-ai-health-coach/id6456176249), [MySplit Recovery](https://apps.apple.com/us/app/mysplit-recovery-gym-log/id6756460108)

## What HealthKit gives us

Apple provides enough raw material for a useful v1, but not a precomputed Recovery Time value.

| Signal | HealthKit source | Use |
|---|---|---|
| Workout boundaries | `HKWorkout` | Start, end, duration, activity type |
| Workout energy | Active energy statistics associated with the workout | Fallback load and sanity check |
| Heart rate during workout | Heart-rate samples in the workout interval | Internal cardiovascular load |
| Resting heart rate | `restingHeartRate` | Personal baseline and response modifier |
| HRV | `heartRateVariabilitySDNN` | Recovery context, not a standalone verdict |
| Sleep | `sleepAnalysis` and watchOS sleep data | Sleep context and confidence |
| VO2 max | `vo2Max` | Broad cardio-fitness context and user level |
| User-reported effort | Our own quick input, with any available HealthKit effort metadata as an optional enhancement | User-perceived intensity and fallback |
| Power or zones | Workout statistics and zone data where available | Better cycling/running specificity |

Apple’s `HKWorkout` model exposes duration, activity type, statistics, energy, distance, and zone data. Apple documents observer queries and background delivery for reacting to new workout or health samples. [HKWorkout](https://developer.apple.com/documentation/healthkit/hkworkout), [workouts and activity rings](https://developer.apple.com/documentation/healthkit/workouts-and-activity-rings), [observer queries](https://developer.apple.com/documentation/healthkit/hkobserverquery), [background delivery](https://developer.apple.com/documentation/healthkit/executing-observer-queries)

Apple’s HRV type is SDNN, a discrete measurement in milliseconds. Apple Watch records it automatically, but it is not a continuous high-frequency readiness stream. [Apple HRV HealthKit type](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn?changes=_7__8), [Apple heart-rate support](https://support.apple.com/en-lamr/120277)

## Proposed model

### Principle

We do not need to recreate all of Garmin to deliver a useful product. We need a model that is:

- understandable;
- conservative;
- personalized over time;
- honest about missing data;
- useful even before it is perfect.

### Stage 1: session load

Use the best available method in this order:

1. Heart-rate-based load when the workout has adequate heart-rate coverage.
2. User-reported effort or session-RPE input when heart rate is missing or unreliable.
3. Duration, activity type, active energy, and user-selected intensity as a fallback.

For endurance workouts, the first implementation can use a heart-rate-reserve TRIMP-style calculation. Banister TRIMP combines duration, heart-rate reserve, and an intensity weighting. A published exercise-physiology example gives the familiar form:

```text
hrReserve = (averageHR - restingHR) / (maxHR - restingHR)
TRIMP = durationMinutes * hrReserve * intensityWeight(hrReserve)
```

The exponential weighting makes hard work count more than an equal duration of easy work. [American Physiological Society example of TRIMP](https://journals.physiology.org/doi/abs/10.1152/japplphysiol.00482.2003), [TRIMP explanation](https://www.trainingimpulse.com/banisters-trimp-0)

Do not overstate the model. TRIMP is a load proxy, not a direct measure of tissue recovery.

### Stage 2: personal baseline

The user’s prior level should come primarily from their own recent data:

- 28 to 42 days of workout history;
- typical weekly frequency;
- median and high-percentile session load;
- recent acute load;
- resting heart-rate baseline;
- available VO2 max estimate;
- user-selected training profile.

Use the VO2 max only as context. Do not make a high VO2 max automatically produce a shorter recovery time. A highly fit athlete can still have a large session load.

The model should classify a session relative to the person’s history:

```text
Easy for you
Typical for you
Hard for you
Unusually hard for you
```

This is more useful than comparing everyone with the same fixed hours.

### Stage 3: initial recovery duration

For the first version, use a transparent mapping from session-load percentile to a bounded recovery window. Example product behavior, not a validated medical formula:

| Session relative to personal history | Initial recovery window |
|---|---:|
| Easy | 0 to 8 hours |
| Typical | 8 to 18 hours |
| Hard | 18 to 36 hours |
| Unusually hard | 30 to 72 hours |

The exact values should be tuned with internal fixtures and user feedback, not presented as scientific truth. The result should remain a **training estimate**.

### Stage 4: context adjustments

Sleep, HRV, and resting heart rate can make the estimate more relevant, but they should not let one noisy reading swing the product wildly.

Use context to:

- move the estimate modestly within a bounded range;
- lower confidence when the data is absent or contradictory;
- explain the result;
- display a “body signal changed” note when a persistent baseline deviation exists.

Prefer:

```text
Recovery window: 18 to 28h
Ready estimate: tomorrow morning
Confidence: medium
```

over:

```text
Exactly 21h 17m because your HRV fell 13 percent
```

### Stage 5: user calibration

After the recovery estimate expires, ask an optional one-tap question:

- Felt ready
- Okay but not fresh
- Not ready

Store this locally and use it to calibrate the user’s personal duration bands. Also compare the next workout’s load and heart-rate response with prior sessions. This allows personalization without a cloud model or a large training dataset.

### Pseudocode

```text
onWorkoutFinished(workout):
    sessionLoad = bestAvailableLoad(workout)
    relativeLoad = sessionLoad / personalTypicalLoad
    baseWindow = recoveryWindow(relativeLoad, activityType, duration)
    context = contextAdjustment(sleep, HRV, restingHeartRate)
    estimate = clamp(baseWindow + context, minimum, maximum)
    saveRecoveryState(readyAt: now + estimate, confidence, reasons)
    reloadWatchTimelines()

while currentTime < readyAt:
    display remaining time

at readyAt:
    display Ready
```

The app should not re-extend the timer every time a single low HRV sample arrives. If the model changes during the day, show the reason and preserve a visible history of the original estimate.

## Ready indicators

### Recommended states

1. **Ready**: no current recovery window, or the last session is below the configured threshold.
2. **Recovering**: countdown active.
3. **Ready soon**: less than two hours remain.
4. **Low confidence**: insufficient baseline or poor sample coverage.
5. **No recent workout**: there is no workout to score.

### Complication copy

| Family | Recovering | Ready |
|---|---|---|
| Circular | `18h` with progress ring | checkmark or `OK` |
| Rectangular | `Recover 18h` plus ready time | `Ready` plus last workout |
| Inline | `18h to ready` | `Ready to train` |
| Corner | `18h` | `✓` |

### What “ready” means

The first version should say:

> “Ready for another hard session based on your recent workout load estimate.”

It should not say:

- “Your body is fully recovered.”
- “You are safe to train.”
- “You will not get injured.”
- “Your muscles are recovered.”

Cardiovascular recovery, muscular soreness, connective tissue load, illness, and mental fatigue are not the same thing. If the app does not collect muscle-specific inputs, call the output a cardiovascular training estimate.

## MVP scope

### Free

- HealthKit workout import.
- Watch workout completion detection through HealthKit updates.
- Countdown after qualifying workouts.
- Ready state.
- Basic Apple Watch app.
- Circular, rectangular, inline, and corner complications.
- iPhone explanation of the last estimate.
- Local-only storage.

### Premium

- HRV, resting heart rate, and sleep context.
- Personal baseline and adaptive bands.
- Workout-type profiles.
- Countdown history and estimate accuracy feedback.
- Weekly load and recovery view.
- Optional planned-workout target.

### Do not build first

- Full daily readiness score.
- AI coach.
- Workout planner.
- Injury prediction.
- Muscle-group recovery without manual muscle input.
- Cloud-based model training.

## Reusable local infrastructure

### VO2

VO2 already reads workouts, resting heart rate, and one-minute heart-rate recovery through `CardioContextService`. It has pure analysis utilities and unit tests. That makes it the best source for shared HealthKit query conventions and cardiovascular copy.

The recovery product should not be put directly into VO2 unless the scope remains “cardio fitness context.” Recovery Countdown has a different daily loop, data model, and user promise. Shared code can be extracted later, but a separate app is cleaner for product positioning.

See [VO2 CardioContextService](../health/Shared/Services/CardioContextService.swift), [VO2 analysis utilities](../health/Shared/Utilities/CardioDriverAnalysis.swift), and [VO2 project guide](../health/AGENTS.md).

### Vitals / Total Calories

Vitals has the production pattern for:

- App Group SwiftData;
- HealthKit observer and background delivery;
- current-day cache updates;
- Watch complications reading cached data;
- WidgetKit timeline refresh;
- RevenueCat and TestFlight release plumbing.

See [Vitals HealthKitService](../vitals/Shared/Services/HealthKitService.swift), [Vitals cache](../vitals/Shared/Models/HealthRecord.swift), and [Vitals Watch complication](../vitals/VitalsWatchWidget/WatchComplication.swift).

### Headache Logger archive

The archived Headache Logger has a useful WatchConnectivity approach for queuing local Watch actions and sending them to the iPhone. The recovery app may need this for a Watch “mark how ready I feel” action or manual session-RPE input.

See [PhoneWatchSession](../vitals/_archive/headaches-retired-2026-04-14/HeadacheLogger/Services/PhoneWatchSession.swift) and [WatchConnectivityController](../vitals/_archive/headaches-retired-2026-04-14/HeadacheLoggerWatch/WatchConnectivityController.swift).

## Technical architecture

### iPhone is the model owner

The iPhone should be the canonical calculator because it can query the full HealthKit store and longer history. The Watch should display the latest compact `RecoveryState` snapshot.

```text
HealthKit on iPhone
    -> raw workout and context cache
    -> pure recovery calculator
    -> SwiftData/App Group RecoveryState
    -> WidgetKit Watch complication
    -> Watch app via shared cache or WatchConnectivity
```

The Watch can read some of its own HealthKit data, but it should not be assumed to have the same complete aggregate history as the iPhone. The local Headache Logger documentation explicitly notes that the Watch cannot simply read the iPhone’s HealthKit store and that phone enrichment is needed for broad context.

### Data model

```text
WorkoutRecord
- healthKitUUID
- activityType
- startDate
- endDate
- duration
- activeEnergy
- heartRateCoverage
- sessionLoad
- sourceName

RecoveryState
- lastWorkoutID
- calculatedAt
- readyAt
- phase
- confidence
- reasons
- modelVersion
- userFeedback

DailyContext
- date
- sleepDuration
- restingHeartRate
- HRV
- acuteLoad
- chronicLoad
```

Store `modelVersion` so future formula changes can explain why historical values differ.

### Timeline freshness

The countdown is a good complication candidate because time remaining changes predictably. However, Watch complications are not arbitrary real-time surfaces. Build a timeline with hourly entries and use the latest cached `readyAt`. Reload after a new workout or a context update. The app should still work if the system delays a timeline refresh.

The UI can show a dynamic relative time where the watchOS/widget family supports it, but the data source must still provide a reasonable timeline and fallback state.

## Validation plan

### Phase 1: deterministic fixtures

Create fixture workouts for:

- 30-minute easy walk;
- 45-minute easy run;
- 60-minute threshold run;
- 90-minute long run;
- 45-minute cycling session;
- strength workout with no usable heart-rate coverage;
- duplicate and overlapping workouts;
- missing sleep and missing HRV;
- a new user with no 28-day baseline.

Assert that the model is monotonic in the obvious direction: harder or unusually long sessions should not produce a shorter recovery window than easy sessions under the same context.

### Phase 2: device validation

Use a real Apple Watch and compare:

- workout completion to HealthKit delivery time;
- average and maximum heart-rate coverage;
- source app differences;
- iPhone cache and Watch complication freshness;
- midnight rollover;
- deleted workouts;
- multiple workouts in the same day.

### Phase 3: user calibration

For early testers, show the input explanation and collect only local feedback unless users explicitly opt into a research export. The goal is to learn whether users prefer:

- a time countdown;
- a ready clock time;
- a traffic-light readiness state;
- a specific next-workout suggestion.

Do not tune toward matching Garmin numerically. Tune toward useful decisions and honest confidence.

## Main risks

1. **Algorithm trust.** An opaque number can feel arbitrary. Show the last workout, load category, and confidence.
2. **Physiological overclaiming.** A countdown is an estimate, not a clinical recovery measurement.
3. **Sparse HRV.** Apple Watch HRV is intermittent and SDNN-based, so it cannot be treated like a continuous Garmin/WHOOP signal.
4. **Sport mismatch.** Cardio load does not equal muscle recovery. Either focus the app on cardiovascular training or add explicit strength input later.
5. **Competition.** Athlytic and Bevel already occupy broad recovery. Keep the product small and fast.
6. **Apple native expansion.** Apple may add a recovery countdown or richer training guidance. A focused implementation can still win on clarity, privacy, and cross-source history.

## Go / no-go decision

Go as a separate app if the first prototype can produce a stable, understandable countdown from Apple workouts without requiring a subscription to another recovery platform.

The product is worth testing because the user demand is specific and the native Apple gap is still clear. The formula does not need to be Garmin’s formula. It needs to be a defensible, transparent, conservative model with personal calibration.

## Sources

- [Garmin Recovery Time](https://www.garmin.com/en-US/garmin-technology/running-science/physiological-measurements/recovery-time/)
- [Garmin Recovery Time support](https://support.garmin.com/en-IE/?faq=8ImmxVkZMhE4YYq5Zp2bR8)
- [Garmin Training Readiness manual](https://www8.garmin.com/manuals/webhelp/GUID-0221611A-992D-495E-8DED-1DD448F7A066/EN-AU/GUID-C21BE0C8-A08E-4DA1-B6C6-2E0E2DDDB372.html)
- [Firstbeat Training Status](https://support.firstbeat.com/hc/en-us/articles/360024695553-Feature-Firstbeat-Sports-Training-Status)
- [Apple Training Load](https://support.apple.com/en-ie/guide/watch/apde4c07a6cf/watchos)
- [Apple HKWorkout](https://developer.apple.com/documentation/healthkit/hkworkout)
- [Apple workouts and activity rings](https://developer.apple.com/documentation/healthkit/workouts-and-activity-rings)
- [Apple HKObserverQuery](https://developer.apple.com/documentation/healthkit/hkobserverquery)
- [Apple observer query execution](https://developer.apple.com/documentation/healthkit/executing-observer-queries)
- [Apple HRV type](https://developer.apple.com/documentation/healthkit/hkquantitytypeidentifier/heartratevariabilitysdnn?changes=_7__8)
- [Apple heart-rate support](https://support.apple.com/en-lamr/120277)
- [TRIMP physiology example](https://journals.physiology.org/doi/abs/10.1152/japplphysiol.00482.2003)
- [TRIMP overview](https://www.trainingimpulse.com/banisters-trimp-0)
- [Athlytic](https://apps.apple.com/us/app/athlytic-ai-fitness-coach/id1543571755)
- [Bevel](https://apps.apple.com/us/app/bevel-ai-health-coach/id6456176249)
- [RecoTime](https://apps.apple.com/us/app/recotime-smart-recovery-calc/id6751836043)
- [Training Load & Recovery](https://apps.apple.com/us/app/training-load-recovery/id6741155891)
- [MySplit Recovery](https://apps.apple.com/us/app/mysplit-recovery-gym-log/id6756460108)
- [Apple Watch recovery request](https://www.reddit.com/r/AppleWatch/comments/1l5wkiu/is_there_an_app_that_offers_something_similar_to/)
- [Runner recovery complication discussion](https://www.reddit.com/r/applewatchultra/comments/1tp5h9n/runner_s_watch_face_what_complications_do_you_use/)
