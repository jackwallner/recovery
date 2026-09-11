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
| `ObservedRecoveryPattern` | what the person actually does: median gap to the next real session, by effort band. The free tier's whole answer. |
| `RecoveryBaseline` | the person's own recent loads; median, 25th percentile, sample count. Below `minimumSamples` the median is shrunk toward the population reference (see below). `.standard(for:)` is the no-samples reference the free tier uses. |
| `RecoveryCalculator` | relative load → bounded hours, context adjustment, calibration, personalization, clamp. |
| `AthleteProfile` | who the person is: age, sex, experience, volume, bounce-back, plus what Health measured — VO2 max, the observed maximum heart rate, body mass. Every field carries its own multiplier, and `gaps` is what onboarding still has to ask. |
| `PersonalRecoveryModel` | the 30-day analysis → one bounded personal multiplier. |
| `RecoveryResolver` | several overlapping windows → the one to show (latest `readyAt`). |
| `WorkoutClassifier` | `HKWorkoutActivityType` raw value → one of four profiles. All 84 raw values are pinned and tested against the SDK's own numbering; the table was silently off by one from `badminton` (4) through `crossTraining` (11) for the app's whole life, because it omitted `australianFootball` (3). |
| `CountdownTimeline` | the entry schedule a decaying countdown needs. |
| `HealthIngestSummary` | the receipt: every reading Health actually supplied, phrased for the user. Onboarding, the trial page, Settings, and the Recharge+ tab all render it. |

## Rules that hold everywhere
Condensed from the deep notes below; the reasoning and the bugs behind each one live there.
- Bump `recoveryModelVersion` (`Shared/Models/RecoveryModels.swift`, currently **13**) whenever the numbers change. A bump also thaws frozen records in `RecoveryEngine.rescore`.
- Complication and widget views render from `entry.date`, never from `Date.now`.
- The phone owns the model and the Watch app deliberately cannot read Health. Do not add HealthKit to the Watch to fix a delivery bug.
- Every link in the background chain (HealthKit observer, `WCSession` activation, application context, Watch background task, App Group write, timeline reload) is guarded by a silent `return`. Observer queries and `WCSession` activation run from `RechargeApp.init` (`Recharge/App.swift`), not from a scene callback.
- Read `design.md` before any UI work; `./scripts/design-audit.sh` enforces the tokens.
- A green Debug test suite does not mean the archive builds: anything touching `ScreenshotConfig` or `ScreenshotFixtures` needs a `-configuration Release -destination generic/platform=iOS` build first.
- Never set `CODE_SIGN_IDENTITY: ""` in `project.yml`. It silently strips HealthKit and the App Group from the archive.
- StoreKit Testing does not activate under `xcodebuild test` (only the scheme's Launch action), and product IDs are bundle-prefixed (`com.jackwallner.recovery.yearly`).
- App Store ID `6797089337`. Premium branding is **Recharge+** anywhere a customer can read it. The 49 non-English locales are generated from `scripts/native_locale_content/*.json`; en-US is hand-maintained.

## Deep notes (load on demand)
These files load automatically when you read a file matching their `paths:`. Agents that do not auto-load rules (AGENTS.md readers) should open the file for the area they are touching. Section names cited elsewhere ("see X") are headings in these files. Record new area-specific learnings in the matching file, not here.

| File | Sections | Read when |
|---|---|---|
| `.claude/rules/model-tiers.md` | The two tiers; What the user is allowed to tell the model; The two figures had to stop contradicting each other; The readiness question only asks about countdowns the user watched; The Ready alert is not a Recharge+ feature | Free vs Recharge+ figures, user corrections, reconciliation copy, readiness feedback, the Ready notification |
| `.claude/rules/model-stacking-and-versions.md` | Recovery time stacks, and the residual has to be persisted; What the 30-day analysis actually measures (with the model version history) | Overlapping windows, persisted residuals, the personal multiplier, bumping the model version |
| `.claude/rules/model-session-load.md` | The load ladder is an order of trust; Every source estimates the same quantity; The six-hour floor is Garmin's; Things worth knowing before changing the model; Every session carries a cost | Scoring one session: heart rate, effort, energy, duration, classification, floors, cost vs countdown |
| `.claude/rules/model-baseline-and-anchor.md` | The audit is in the repo; "Typical" is a training day; The standard tier is anchored to Garmin's default; A thin baseline is shrunk | The baseline denominator, `standardTypicalLoad`, the athlete matrix and Garmin anchor tests |
| `.claude/rules/model-open-questions.md` | Open tuning questions | Before retuning any model constant |
| `.claude/rules/ui-shell.md` | The design system is `design.md`; The screens are the Vitals shape now; Clearance for the floating tab bar is the shell's job; A pinned header has to mask what scrolls behind it | Any view, the tab bar, History, UI tests that assert frames |
| `.claude/rules/onboarding-and-pitch.md` | The onboarding copy is centred; The pitch is two numbers; Onboarding reads Health before it asks anything | Onboarding, the trial offer, the paywall pitch, HealthKit read types |
| `.claude/rules/countdown-and-watch-sync.md` | The countdown timeline; The RPE path is the only Watch → phone write; Staleness on the glance surfaces | Complications, widgets, the Watch app, WatchConnectivity, background delivery |
| `.claude/rules/build-and-release.md` | Generating the project; App Store record, metadata and products | `project.yml`, `testflight.sh`, signing, StoreKit config, ASC metadata, IAP copy |
| `.claude/rules/testing-and-fixtures.md` | Paywall verification; fixtures; the seeded Health walkthrough | UI tests, `ScreenshotFixtures`, `HealthSeeder`, verifying the paywall |

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

---
Shared iOS conventions (build, simulator, release/TestFlight, ASC key, signing,
review funnel, gotchas): always-loaded global CLAUDE.md + the `ios-dev` skill.
