# Recharge Android verification

## Scope

Native Kotlin/Compose port of the iOS phone app and recovery model v17.
Wear OS and widgets are deferred. Play Console, uploads and review submission
are deferred. The iOS source and release scripts are unchanged by this port.

## Parity

`scripts/sync-android-parity.py` compiles the original Swift models and exports
4,100 calculation cases, 168 personal analyses, 75 observed patterns, seven
athlete profiles and all 85 activity classifications. Expected values include
hours, residuals, bounds, sources, confidence, categories and exact reason copy.

The 4,407 JVM tests cover those cases, stacking, historical freezing, model
version changes, both tiers, calibration, corrections, local persistence,
heart-rate coverage, source selection, overlapping sleep, review pacing and
conversion diagnostics. An empty or missing Health Connect record is never a
fabricated workout.

## Health Connect differences

- Read-only workouts, heart rate, active energy, resting heart rate, RMSSD HRV,
  sleep, breathing rate, VO2 max and weight, each with its own grant.
- RMSSD stays on its own baseline. It is not presented as Apple Health SDNN.
- Age is asked for. No birth-date or sex import is claimed.
- One-minute heart-rate recovery is unavailable and excluded from the model.
- Workout pauses are excluded from duration. Heart rate is selected from one
  source rather than double-counted, and duplicate workouts are scored once.
- Core workout revocation clears the cache and health-derived profile fields.
  Optional revocation removes affected inputs and recalculates estimates.
- History and background access are requested only when the platform feature
  exists. WorkManager refreshes periodically; Ready alerts use inexact alarms.
- Ready alerts and fallback effort input remain free. Personal baselines,
  overnight context, calibration, intensity corrections and pinned hours use
  the Recharge+ boundary.

## Billing

RevenueCat project `eafb16cb`, Play app `appb52fb43da6`, existing offering and
three package mappings. Any active entitlement unlocks Recharge+, as on iOS.
Debug uses Test Store. Release requires an external Play key and upload key.
Optimized QA uses no SDK key and the release no-op launch options.

The offline product plan preserves the three iOS IDs with Play subscription
base plans. Proposed Android prices are about 20 percent below the iOS ladder.
No Play request is made unless `scripts/play-products.py --apply` is used.

## Commands

From `android/`:

```sh
./gradlew testDebugUnitTest assembleDebug assembleDebugAndroidTest assembleQa assembleRelease bundleRelease --no-daemon
```

From the repository root, with the owned Pro AVD booted:

```sh
./scripts/test-android-pro.sh
python3 scripts/test-android-qa.py
python3 scripts/capture-android-pro.py
python3 scripts/verify-android-release.py --bundletool /path/to/bundletool.jar
```

The standalone Java fixture activity belongs only to the test APK. It uses
framework APIs and its own UID to write and delete synthetic Health Connect
records. The production app has no health-write permission.

The Pro harness requires nonzero JVM and device counts, checks the AVD identity,
and exercises an external Health Connect revoke across process restart.
Local proof and build outputs are ignored under `android/verification/` and
`android/app/build/`.

## Remaining Play work

Create the Play app, review and activate the proposed products and trial offers,
connect Play receipt-validation credentials, complete Health Connect permissions
and App content declarations, stage the listing, test Play billing through a
licensed test track, upload and submit for review. No real store purchase was made. A Test Store purchase unlocked Recharge+
through RevenueCat without a debug entitlement override; restore returned
without an error. Play billing still requires a licensed Play test track.

## Final run

Verified 2026-10-18: 4,407 JVM tests and all 20 Pro device cases pass, with no
skipped cases. The real Health Connect fixture is written by the separate test
APK, read through the production bridge, scored and persisted, then deleted.
It verifies a 60-minute run with a 10-minute pause and 155 bpm heart-rate samples.
Optional revocation strips sensor inputs, and an external workout-permission
revoke across process restart removes the cache.

The Ready alert is free, survives a refresh after its countdown has expired,
and does not repeat. Disabled alerts are not delivered. Effort input remains
free; intensity correction, pinned hours, personal baselines and body signals
retain the Recharge+ boundary.

Optimized QA ignored every debug seed, paid-unlock and onboarding-bypass extra,
completed free onboarding and displayed no fabricated workout. Final light and
dark screenshots, Ready, history, session detail and loaded Test Store plans
were reviewed. Four free screenshots are native 720 x 1440 JPEG files under
`play-assets/screenshots/`. Test Store prices are not Play prices.

Both SDK keys were matched to their app records in RevenueCat project
`eafb16cb`: Test Store `app123c8920b3`, Play `appb52fb43da6`. Keys remain local.
The signed APK/AAB are version 1.1.0, versionCode 1, targetSdk 36. APK and AAB
signatures, 16 KB APK ZIP alignment, bundle alignment settings and all four
native ELF libraries pass verification. No test key, debug launch hook,
health-write permission or advertising-ID permission is present in release.

- APK SHA-256: `5f936c8c74e6f0e90af793cecf87c7ed5f901d2a9972caed062a6c35671fa2ce`
- AAB SHA-256: `2c01af74c33e288ddb3e32fdecb5d2f330f4bd1f1e30afd9afbee66eee733644`

The owned `sol-recharge` AVD, serial `emulator-5582`, emulator process, log watcher
and `~/tmp/sol-recharge` were removed after verification. Other AVDs were preserved.
