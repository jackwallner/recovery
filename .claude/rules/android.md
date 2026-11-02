---
paths:
  - "android/**"
---

# Recharge Android

Native Compose phone port, build verified 2026-10-18. Package `com.jackwallner.recovery`, version
1.1.0, versionCode 1, minSdk 28, compile/targetSdk 36. The iOS app and model v17
remain the specification. Preserve unrelated iOS release-script changes.

## Model and data

- `scripts/sync-android-parity.py` compiles unchanged Swift model files and the
  original `AthleteMatrix` and `RecoveryFixtures`. It exports 4,100 calculation
  cases, 168 personal analyses, 75 observed patterns, seven athlete profiles and
  85 activity classifications. Classification data is also a production resource.
- All 4,407 JVM and 20 Pro device cases pass. Signed APK/AAB and optimized QA
  passed; final light/dark captures were reviewed. The real Health Connect
  fixture, permission revoke/cache clearing and free Ready alert were verified.
  See `project-docs/android/verification.md` for commands and artifact hashes.
- The standard tier uses training level. Recharge+ uses personal baselines,
  overnight context, calibration, intensity corrections and pinned windows.
  Separate residual chains, duplicate suppression, following-night admission,
  historical freezing and the 96-hour ceiling match model v17.
- The Ready notification is free. Effort input for weak strength/mixed signals
  is free. Readiness feedback and intensity corrections are Recharge+.
- Health Connect HRV is RMSSD, compared only with the same on-device baseline.
  One-minute recovery is unavailable and must remain absent. Age is asked for;
  no Health Connect birth-date or sex import is claimed. Wear OS and widgets
  are deferred for v1.
- Read-only access, per-type grants, history/background feature checks, local
  cache and explicit permission-revocation handling are implemented.

## Billing and signing

RevenueCat project `eafb16cb`, Play app `appb52fb43da6`. Any active entitlement
unlocks the single Recharge+ tier, matching iOS. Existing iOS/Test Store package
mappings are preserved, with Play identifiers added:

- `com.jackwallner.recovery.monthly:monthly`
- `com.jackwallner.recovery.yearly:yearly`
- `com.jackwallner.recovery.lifetime`

Keys live in ignored `android/local.properties`; debug uses Test Store, release
requires Play, optimized QA uses no SDK key and no debug hooks. External upload
key: `~/.android/keystores/recharge-upload.p12`. Signing entries were appended to
`~/.recovery_credentials` without replacing its iOS values, mode 600. Never copy
production keys or signing assets to Pro. rc-clean Android filters are registered
on Air and Pro. Play Console and uploads remain deferred.

## Pro isolation

Owned temporary AVD `sol-recharge`, serial `emulator-5582`, API 36 Play x86_64,
720 x 1600 at 320 dpi, 3 GB RAM, headless host GPU graphics (Vulkan disabled). Sources belong only
in `~/tmp/sol-recharge/android` on `jackwallner@192.168.4.25`. Exclude build caches,
local.properties and signing files from sync. Pro local properties may contain
only SDK path and Test Store key. Verify the AVD name before changing it.

Use the existing Pro JDK, `JAVA_HOME=$HOME/.jdk/jdk-21.0.12.1+1/Contents/Home`,
with its bin directory on PATH. The exact verification entry point is
`./scripts/test-android-pro.sh` on Air. It runs connected Gradle tests on Pro,
with `ANDROID_SERIAL=emulator-5582` and a 1536 MB heap.

```sh
ssh jackwallner@192.168.4.25 '~/Library/Android/sdk/emulator/emulator -avd sol-recharge -port 5582 -no-window -no-audio -no-boot-anim -no-metrics -no-snapshot -gpu host -feature -Vulkan'
ssh jackwallner@192.168.4.25 '~/Library/Android/sdk/platform-tools/adb -s emulator-5582 shell getprop sys.boot_completed'
ssh jackwallner@192.168.4.25 '~/Library/Android/sdk/platform-tools/adb -s emulator-5582 emu kill'
```

Stop only `adb -s emulator-5582 emu kill`, confirm the serial and process are gone,
then delete only the `sol-recharge` AVD and `~/tmp/sol-recharge` when finished.

## Verified Play state

No Play app or upload has been staged in this session. Products and an offline
pricing plan, listing copy, high-resolution icon, feature graphic, four native
720 x 1440 free-screen captures and Android policies are prepared. Console,
Play products/credentials, licensed Play billing tests, uploads and submissions
remain deferred. Test Store and Play SDK keys were matched to the correct
project and app records without exposing them. A no-charge Test Store purchase
unlocked Recharge+ through the SDK, and restore returned without an error.

`ReadyNotifications.schedule` cancels only the alarm when a countdown is
finished, preserving the delivered Ready notification. A newly active countdown,
permission revocation, data deletion or disabling notifications clears it.

`ReadyNotifications.deliver` announces `RecoveryResolver.alertDue`, never
`RecoveryResolver.current`. `current` is a display rule: with nothing running it
falls back to the newest session of any kind, so a walk logged after the run
that set the countdown made `deliver` see a session with no countdown and drop
the alert without a trace. `RecoveryBehaviorTest` pins it with
`readyAlertSurvivesAWalkLoggedDuringTheCountdown`. `alertDue` is the latest
countdown that ran out in the last 24 hours, and none while another is running.
iOS schedules from the snapshot taken while the countdown was active, so it never
asks the question.

The standalone Java Health Connect writer lives only in the instrumentation
APK and uses framework APIs, its own UID and its own write permissions. A helper
started outside instrumentation cannot use classes supplied by the target APK.

## References

- https://developer.android.com/health-and-fitness/health-connect/data-types
- https://github.com/androidx/androidx/blob/androidx-main/health/connect/connect-client/src/main/java/androidx/health/connect/client/records/HeartRateVariabilityRmssdRecord.kt

The owned `sol-recharge` AVD, serial `emulator-5582`, emulator process, log watcher
and `~/tmp/sol-recharge` were removed after verification. Other AVDs were preserved.

## Pro Play queue checkpoint, 2026-10-18

This queue runs directly on jmbp with JDK21, using one owned `sol-*` emulator
and one memory-limited Gradle build at a time. The handoff supersedes older
Air-build and SSH examples. Existing RevenueCat Play credentials are confirmed.

Unaccepted reviewer access is on `wip/android-port`, pending JVM, actual-dialog
device, signed artifact, optimized QA and lint verification. Long-press the
Settings version line to enter the private `RECHARGE_PLAY_REVIEW_CODE` from
existing `~/.recovery_credentials`. Only its SHA-256 is in ignored properties.
The input is masked, uses a Password keyboard and disables autocorrect. The
review grant stores only the digest, survives purchase refresh, and becomes
invalid when the configured digest changes. It never writes a fake purchase
cache. Four JVM cases and a private-argument device case cover the flow.

Listing metadata uses `play-assets/metadata/android/en-US`; PNG encodings of
four real free-screen captures preserve their original decoded pixels. App
creation, products, upload and Console declarations remain pending.

Listing copy covers the same 50 Play locales as Sober (fastlane supply layout,
`android/play-assets/listing-en-US.md` lists them). en-US is the live listing
verbatim. Titles keep "Recharge" plus the local recovery-time phrase from the
iOS `name.txt`/`keywords.txt`; every non-English description ends by saying the
app is in English, because the Android app is not localized.
`scripts/validate-play-listing.py` checks limits, house rules, the English line
per locale, and en-US against a local `.play-live-listing.json` when present.

RevenueCat integration check on2026-10-18: developer notifications plus two
transaction webhooks, with the same previously verified destination domains as
VO2 Max. Both disable paywall-event forwarding; no advertising integration is
listed. No credentials, grants or integration settings were changed. Data safety
must still disclose actual app-side collection, including purchase history and
anonymous identifiers, plus custom purchase-screen attributes where used.
RevenueCat's general guide is https://www.revenuecat.com/docs/platform-resources/google-platform-resources/google-plays-data-safety.

Play price conversion preserves the configured US money value explicitly.
Google conversion can choose a different nearby US price point, so use its
conversion for other regions and keep the requested US ladder unchanged.
The offline product plan still passes; no Play product was changed here.

## Host verification, 2026-10-20

Run directly on jmbp (or jmbp2) with `JAVA_HOME=~/jdks/temurin-17/Contents/Home` and
the checked-in wrapper; the SSH Pro scripts above are historical. Lease one idle
`agent-emu-1`/`agent-emu-2` and boot it with
`-memory 3072 -cores 4 -gpu host -feature -Vulkan -no-window -no-snapshot-save`.
Its 2 GB default with swiftshader let system_server die mid-install under a
Gradle build ("Can't find service: package"). Release it with
`adb -s <serial> emu kill` only.

- `scripts/test-android-host.sh`: connected suite (21 cases) plus the external
  revoke check. `scripts/capture-android-host.py OUT`: 13 debug captures, free,
  forced Recharge+ and Test Store plans; it waits for a stable dump before each
  shot because a free to forced-pro relaunch rescored after the first frame.
- A never-used Health Connect shows its own onboarding before the grant sheet
  and ignores Back; tests tap its `secondary_button` ("Go back").
- Tab bar tint is the recovering orange (iOS `.tint(Theme.recovering)`), and
  ring/progress tracks are neutral grays; Material defaults were lavender.
- `data_extraction_rules.xml` excludes every domain from cloud backup and device
  transfer (allowBackup=false does not cover device transfer on 12+).
- Frame cadence on the x86_64 emulator is host bound: optimized QA gfxinfo P50
  32 ms, captures 10 to 23 fps. Not native 60 fps; measure on a real device.

Play Console answers (app access, Health Connect declaration, Data safety) are
in `project-docs/android/play-console.md`. Still pending: Play app creation,
products activation, AAB upload from the Air, App content forms, licence-tester
purchase and restore, then production.

## Play staging, 2026-10-20

Staged one click from review, nothing sent. Listing, graphics, signed vc1 AAB
(drafts on internal and production), three products active, RevenueCat
credentials and every App content form except the IARC content rating are
saved. The permission classifier refused the IARC terms tick; Jack completes
the rating. Reviewer code: `play_handoff.py review-codes recovery` (the sign-in
entry has instructions and no code yet). Then Jack sends for review from
Publishing overview with managed publishing off.
