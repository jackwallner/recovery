# Recharge Play Console preparation

Answers drafted from the code on 2026-10-20 (`android/`, version 1.1.0, versionCode 1).
Nothing here has been entered in Play Console. Re-check each answer against the
build being uploaded; a code change that adds a network call or a permission
changes the answers.

## App and listing

- Package `com.jackwallner.recovery`, name "Recharge", category Health & Fitness.
- Listing copy: `play-assets/metadata/android/en-US/` (no prices, no em dashes).
- Graphics: `play-assets/icon-512.png`, `play-assets/feature-graphic.png`,
  four phone screenshots in `play-assets/screenshots/` (free tier only).
- Privacy policy: `docs/android/privacy-policy.html` once published on the
  repo's site. Terms: `docs/android/terms.html`.
- Contact email: Jack's support address. No phone in public metadata.

## App access

Everything that matters is reachable without an account, but Recharge+ is paid.
Give the reviewer the private review code (the value of
`RECHARGE_PLAY_REVIEW_CODE` in `~/.recovery_credentials` on the Air, never in
the repo): Settings, long-press the version line, enter the code. It unlocks
Recharge+ for that install only and never writes a fake purchase.
Note for the reviewer: the countdown needs at least one workout in Health
Connect; without one the app shows "No recent workout" by design.

## Ads, audience, rating

- Ads: none.
- Target audience: 18 and over (training-load estimates for adults).
- IARC questionnaire: no violence, sexual content, gambling, user-generated
  content, user-to-user communication or location sharing. Digital purchases:
  yes (subscriptions and a lifetime unlock).
- Health apps declaration: fitness/training estimate. Not a medical device.
  Never describe the output as diagnosing or treating anything.

## Health Connect permissions declaration

Read-only. Each permission and the feature that uses it:

| Permission | Use |
|---|---|
| READ_EXERCISE | Core: each workout's type, start, end and pauses defines the session that is scored. |
| READ_HEART_RATE | Session intensity (heart-rate-reserve load) and observed maximum heart rate. |
| READ_ACTIVE_CALORIES_BURNED | Load fallback when heart rate is missing. |
| READ_RESTING_HEART_RATE | Heart-rate reserve and overnight context (Recharge+). |
| READ_HEART_RATE_VARIABILITY | Overnight context against the person's own RMSSD baseline (Recharge+). |
| READ_SLEEP | Overnight context after a session (Recharge+). |
| READ_RESPIRATORY_RATE | Overnight context (Recharge+). |
| READ_VO2_MAX | Athlete profile fitness level. |
| READ_WEIGHT | Athlete profile body mass for the energy fallback. |
| READ_HEALTH_DATA_HISTORY | The 30-day baseline needs workouts older than the grant date. Requested only when the feature exists. |
| READ_HEALTH_DATA_IN_BACKGROUND | Periodic WorkManager refresh so the Ready alert fires without opening the app. Requested only when the feature exists. |

No write permissions. The test-only fixture writer lives in the instrumentation
APK, never in the release app.

## Data safety

Data shared with or collected by a third party leaves the device only through
RevenueCat (purchases) and Google Play (billing, in-app review). Health data
never leaves the device.

| Data type | Collected | Shared | Purpose | Notes |
|---|---|---|---|---|
| Health and fitness (all Health Connect types above) | No | No | | Processed on device only; Play's definition of collected is off-device transfer. |
| Purchase history | Yes | No (RevenueCat is a service provider) | App functionality (entitlements), analytics | Required. |
| Device or other IDs | Yes (RevenueCat anonymous app user ID) | No | App functionality | Required. No advertising ID; release has no AD_ID permission. |
| App interactions | Yes (paywall impressions, pitch counts, dates, short surface labels as RevenueCat subscriber attributes) | No | Analytics | Required while purchases are configured. No free text, no health values. |
| App info and performance | Only what RevenueCat and Play billing send (SDK version, app version) | No | App functionality | |

- Encrypted in transit: yes (HTTPS only).
- Deletion: local data via Settings, Delete local health data, or uninstall.
  RevenueCat purchase records: request by email.
- Backups: `android:allowBackup="false"` plus `data_extraction_rules.xml`
  excluding every domain from cloud backup and device transfer, so the
  health-derived cache never leaves the device that way either.

## Products

`scripts/play-products.py` (offline plan by default, `--apply` writes):
`com.jackwallner.recovery.monthly` base plan `monthly`, `.yearly` base plan
`yearly`, seven-day new-customer trial offers, and the in-app product
`com.jackwallner.recovery.lifetime`. The configured US ladder is kept exactly;
Google's conversion is used for other regions only. RevenueCat project
`eafb16cb`, Play app `appb52fb43da6`; attach to the existing entitlement and
offering packages, never replace them.

## Remaining steps, in order

1. Create the Play app (Jack, Console). Accept nothing new on his behalf.
2. Upload the signed AAB from the Air to internal testing (release worker).
3. Create and activate the three products, then confirm the RevenueCat mapping.
4. App content: privacy policy URL, app access (review code), ads, audience,
   IARC, Data safety (table above), Health Connect declaration (table above),
   health apps declaration.
5. Licence-tester purchase and restore on the internal track.
6. Pre-launch report clean, then production with managed publishing off.
