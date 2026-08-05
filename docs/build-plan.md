# Recharge: build plan

Written 2026-08-04, after the positioning decision in `positioning.md`. This is the
build contract: what gets ported from which app, what has to be written new, and in
what order. Nothing here reopens positioning.

## Locked

| Thing | Value |
|---|---|
| App name | **Recharge: Recovery Time** |
| Subtitle (working) | Recovery Time for Apple Watch |
| Repo dir | `~/recovery` (unchanged; dir name != app name is normal in this fleet, cf. `~/health` = VO2 Max, `~/vitals` = Total Calories) |
| Xcode project / scheme | `Recharge` |
| Slug (bundle + sim lease owner) | `recharge` |
| Bundle IDs | `com.jackwallner.recovery`, `.watch`, `.widget`, `.watch.widget`, `.tests`, `.uitests` |
| App Group | `group.com.jackwallner.recovery` |
| First pass ends at | a TestFlight build |
| Model scope in v1 | all four profiles, including the RPE input |
| Watch hero | hours countdown (Garmin's behavior), with a complication style setting |

`Recharge` needs the suffix because App Store names are unique and the bare word is
taken by phone top-up apps. That SERP is Shopping/Utilities, so there is no fitness
collision, but there is also no free traffic in the name: discovery is the brand
keyword field from `positioning.md`, not the title.

## The two open questions, answered

### What does Garmin actually show?

Garmin has three separate surfaces, and only the first is what this app is:

1. **Recovery Time** — a countdown in **hours** that appears at the end of an
   activity ("Recovery Time 32:00"), decrements in real time, and is available as a
   watch-face data field and a glance. At zero the device reports you as recovered.
   Capped around 4 days on most models.
2. **Training Readiness** — a 0-100 score with a color band (Prime / High /
   Moderate / Low / Poor), which folds in sleep, HRV status, acute load and stress.
3. **Body Battery** — a 0-100 energy gauge, unrelated to a specific session.

The demand evidence in `README.md` is people asking for **(1)**. Athlytic, Bevel and
Training Today already ship a version of **(2)**, and that is the crowded surface we
are differentiating from. So: **hours countdown is the hero**, exactly as Garmin
does it, flipping to `Ready` at zero.

Because you asked for options too, the complication style is a setting, not a
hardcode. One `ComplicationStyle` enum drives every family:

| Style | Recovering | Ready soon | Ready |
|---|---|---|---|
| `countdown` (default, Garmin-like) | `18h` + ring | `1h 20m` + ring | `Ready` + check |
| `readyClock` | `Ready 7:30 AM` | `Ready 7:30 AM` | `Ready` |
| `state` | `RECOVERING` (18h small) | `READY SOON` | `READY` |

Same timeline provider, same cached `RecoveryState`, different rendering. Cheap to
build once the timeline exists, and it is the kind of thing this audience (people who
left Garmin) actually fiddles with.

### What the RPE question meant

RPE = rate of perceived exertion, the 1-10 "how hard did that feel" scale. It matters
because a lifting session produces garbage heart-rate data: the Watch's optical sensor
loses the signal under grip and bar contact, so TRIMP (which is built from heart-rate
reserve) has nothing reliable to chew on. Without an effort input, a heavy 60-minute
squat session and an easy 60-minute stroll look similar to the model.

The build consequence is plumbing, not UI. Every existing app in the fleet moves data
**phone → Watch**: the phone owns HealthKit, writes a cache into the App Group, and the
Watch app and complications read it. An RPE tap on the Watch has to go the other
direction, which needs WatchConnectivity, a queue for when the phone is unreachable,
and a recalculation trigger on arrival. That path exists in the retired Headache
Logger and gets ported rather than invented.

Your call was to do it now, so it is in v1. It adds roughly phase 5 below plus the
strength/mixed fixture set.

## Port map

Nothing on this list gets written from scratch. `Recharge` is the rename of `Vitals`.

### From `~/vitals` (Total Calories) — the infrastructure

| Target | Source | Change |
|---|---|---|
| `project.yml` | `vitals/project.yml` | rename targets, reset version to 1.0.0 / build 1 |
| App Group SwiftData container | `Shared/Services/DataService.swift` | rename suite + model types |
| HealthKit observer + background delivery | `Shared/Services/HealthKitService.swift` | keep the debounce + immediate `completionHandler()` structure, swap the queries |
| RevenueCat wrapper | `Shared/Services/StoreService.swift` | verbatim; gate on `!entitlements.active.isEmpty` |
| Settings store | `Shared/Services/GoalSettings.swift` | pattern only, App Group `UserDefaults` |
| Review funnel | `Shared/Services/ReviewPromptTracker.swift`, `Views/ReviewPromptSheet.swift` | verbatim, new trigger |
| Notifications | `Shared/Services/NotificationService.swift` | verbatim, new copy |
| Theme / WhatsNew / ScreenshotConfig / DateHelpers / AppStoreReviewLinks | `Shared/Utilities/` | verbatim |
| Watch complication scaffolding | `VitalsWatchWidget/WatchComplication.swift` | keep the family switch + entry plumbing, replace the timeline body |
| iOS widget scaffolding | `VitalsWidget/VitalsWidget.swift` | same |
| Entitlements, Info.plist, PrivacyInfo | all four targets | rename, swap Health usage strings |

### From `~/health` (VO2 Max) — cardio domain and store scripts

| Target | Source | Change |
|---|---|---|
| Workout + RHR HealthKit queries | `Shared/Services/CardioContextService.swift` | the `HKSampleQuery` workout/quantity-series helpers lift directly |
| Pure-utility + unit-test shape | `Shared/Utilities/CardioFreshness.swift` + `VO2MaxTests/CardioFreshnessTests.swift` | this is the template for `RecoveryCalculator` and its fixtures |
| Paywall | `VO2Max/Views/PaywallView.swift` | newest in the fleet (2026-08-02) |
| Onboarding | `VO2Max/Views/OnboardingView.swift`, `TrialOfferSheet.swift` | + `posture/Posture/Views/OnboardingTrialView.swift` for the single-decision trial page |
| ASC/RC automation | `scripts/rc-setup.py`, `asc-setup-subscriptions.py`, `asc-ensure-draft-version.py`, `asc-attach-build.py`, `asc-readiness.py`, `asc-submit-for-review.py`, `gen-icon.py` | verbatim, new app id |

### From `~/vitals/_archive/headaches-retired-2026-04-14`

| Target | Source |
|---|---|
| Watch → phone writes for RPE | `HeadacheLogger/Services/PhoneWatchSession.swift`, `HeadacheLoggerWatch/WatchConnectivityController.swift` |

### From `~/baseball` (StatScout)

`fastlane/Appfile`, `Fastfile`, `Deliverfile`, `metadata/en-US/` — the canonical
release template per the `ios-new-project` skill. Plus `scripts/testflight.sh`.

### Genuinely new code

Only four things:

1. `RecoveryCalculator` — pure, `Sendable`, no HealthKit imports, fully unit-tested.
2. The `WorkoutRecord` / `RecoveryState` / `DailyContext` model from `README.md`.
3. The countdown timeline provider. Every existing complication in the fleet renders
   a cumulative daily number; a decaying countdown to a future timestamp needs hourly
   entries out to `readyAt` and a re-anchor on new data.
4. Workout classification into the four profiles, with the HYROX/CrossFit override.

## Phases

Each phase ends green before the next starts.

### Phase 0 — repo and scaffold
`git init` in `~/recovery` (it is currently plain files inside the `~` repo, so `~`
needs `git rm -r --cached recovery` afterwards to record it as a nested repo like
`vitals` and `health`), GitHub repo, `.gitignore`, the renamed `project.yml`,
entitlements, Info.plists, `xcodegen generate`, empty app builds and launches on a
leased pool sim.
**Done when:** `xcodebuild` succeeds for all four targets.

### Phase 1 — the model, headless
`WorkoutRecord` / `RecoveryState` / `DailyContext`, `SessionLoad` (HR-reserve TRIMP,
RPE, and energy fallbacks), profile classification, the percentile-to-window mapping,
context adjustment, clamping, `modelVersion`.

Fixtures from `README.md` phase 1, extended per profile:
30-min easy walk; 45-min easy run; 60-min threshold run; 90-min long run; 45-min ride;
strength with no usable HR; HYROX-style mixed session; duplicate and overlapping
workouts; missing sleep; missing HRV; new user with no 28-day baseline.

Assertions: monotonic **within** each profile (harder or longer never returns a
shorter window under equal context); easy/active recovery never extends an active
countdown; every output inside the documented bounds; the same input at the same
`modelVersion` always returns the same window.
**Done when:** `RechargeTests` passes and I can print a table of fixture → window for
you to sanity-check the numbers before any UI exists.

### Phase 2 — iPhone
HealthKit auth, the observer + background delivery port, workout import, the App Group
cache write, and a Today view: countdown, `Ready at`, confidence, and the "why" line
naming the session that set the window. Plus history and the last-estimate explanation.
**Done when:** a real workout on the leased sim (or seeded HealthKit fixtures) produces
a countdown, verified by simulator screenshot against the strict checklist.

### Phase 3 — Watch app and complications
Watch app reading the cache, then circular / rectangular / inline / corner families,
the hourly timeline provider, the `ComplicationStyle` setting, and the concurrent-window
rule (show the latest `readyAt`, name the session that set it).
**Done when:** all four families render in both recovering and ready states, screenshotted.

### Phase 4 — monetization and funnel
Free/Pro split exactly as `positioning.md` states. Ported paywall, single-decision
onboarding trial page, review funnel with the enjoyment gate. RevenueCat configured,
with the simulator early-return so no fake prod customers.
**Done when:** the paywall renders real products via a StoreKit Testing UI test, and
the monthly product's intro offer is confirmed in ASC before any copy promises a trial.

### Phase 5 — RPE input
`PhoneWatchSession` port, the one-tap Watch RPE prompt after an unclassifiable session,
offline queueing, and recalculation on arrival.
**Done when:** an RPE tap on the Watch changes the countdown on the phone, verified live.

### Phase 6 — store and ship
Icon, screenshots leading with the Watch face, App Preview video via `~/ios/app-previews/`,
metadata with the brand keyword field, the Regulated Medical Device declaration (UI-only,
blocks submission), PPP pricing, ASC record, `./scripts/testflight.sh`.
**Done when:** the build is processing in TestFlight.

## Compliance

The app is a training estimate, never a medical claim. Fixed copy rules, enforced in
review of every string: no "recovered", "safe to train", "injury", "your body is". The
output is a *cardiovascular training estimate*. Health & Fitness category, so the
Regulated Medical Device declaration has to be set in the ASC UI or submission blocks.

## Still needs you

1. **Ready-state threshold.** Below what session load does a workout produce no
   countdown at all? Proposal: anything under the 25th percentile of the person's own
   sessions, floored so a 20-minute walk never starts a countdown.
2. **HYROX / CrossFit default.** Both arrive as `.functionalStrengthTraining` or
   `.highIntensityIntervalTraining`. Proposal: default those two activity types to the
   mixed profile, with a per-session override and a "these are usually my..." setting.
3. **Free vs Pro line on the complication.** `positioning.md` puts all four complication
   families in Free. Confirm, since the complication is the whole product for a Vitals-
   shaped 28-second session and it is also the only thing worth paying for.
4. Whether the marketing site goes up at launch (`jackwallner.com/ios` pattern) or after.
