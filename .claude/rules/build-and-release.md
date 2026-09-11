---
paths:
  - "project.yml"
  - "scripts/**/*"
  - "fastlane/**/*"
  - "Recharge.storekit"
  - "Recharge/Recharge.entitlements"
  - "Shared/Services/StoreService.swift"
---

# Recharge: building, signing, and the App Store record

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

### Generating the project
`./scripts/xcgen.sh` (a thin `xcodegen generate`; `testflight.sh` calls it).

**A green test suite does not mean the archive builds.** `RechargeTests` builds
Debug, where `ScreenshotFixtures` exists; Release drops it and every call site
still has to type-check. That is how build 10 first failed to archive, in the
widget extension, with the whole suite passing. Anything touching
`ScreenshotConfig` or `ScreenshotFixtures` wants a
`-configuration Release -destination generic/platform=iOS` build before you
trust it.

**`CODE_SIGN_IDENTITY: ""` strips every entitlement, and nothing says so.**
It was added to `project.yml` on 2026-08-18 (base settings *and* the `Recharge`
target) and it shipped in builds 21 and 22. An unsigned archive never runs the
step that compiles `Recharge.entitlements` into `Recharge.app.xcent`, so
`com.apple.developer.healthkit` and the App Group were simply absent from the
product; `exportArchive` then re-signed an app that had nothing to carry
forward. On device that reads as HealthKit being broken with no error anywhere:
`requestAuthorization` throws, no permission sheet appears, and the app never
shows up under Health > Sharing > Apps, which is also why restarting the phone
does nothing. Neither Vitals nor VO2 Max sets it, which is the whole reason
their Health access "just works".

The archive is the only place this is visible, so `testflight.sh` now checks the
signed product before uploading: HealthKit and the App Group on the iPhone app,
the App Group on the Watch app and both widget extensions. `codesign -d
--entitlements - --xml` on `$ARCHIVE/Products/Applications/Recharge.app` is the
one-line manual version.

**StoreKit Testing does not activate under `xcodebuild test`.** The `.storekit`
file was referenced from the scheme's Test action, from a test plan (every
relative-path spelling), and started with `SKTestSession` from the UI-test
runner; in all three the app under test reached the live `storekitd` and
`Product.products(for:)` returned an empty array. The test plan and
`patch-schemes.py` are gone. It still works for the **Launch** action, so
running the Recharge scheme from Xcode gets the local catalogue.

StoreKit product identifiers are bundle-prefixed
(`com.jackwallner.recovery.yearly`) in both `Recharge.storekit` and
`RechargeProduct`. Bare identifiers like `yearly` are silently not vended.

### App Store record, metadata and products

- **App Store ID is `6797089337`** (`com.jackwallner.recovery`). `fastlane/metadata/`
  is canonical and is uploaded, not aspirational: as of 2026-08-16 the ASC record
  is named "Recharge Workout Recovery Time", version 1.0.0 is in
  READY_FOR_REVIEW with build 15 attached, and **all 50 locales** carry a
  name, subtitle, keywords, description, promotional text and release notes.
  Build 15 is the first one carrying the Recharge+ rename and the reworded
  disclaimers, so 14 must not be what ships.
  Push edits with `scripts/upload-appstore-metadata.sh` and confirm with
  `scripts/asc-readiness.py`, which diffs ASC against the files and exits
  non-zero on any drift (464 checks, 400 of them the locale diff).
  `scripts/validate-metadata.py` runs first and enforces the field lengths
  (name 24-30, subtitle 24-30, **keywords 94-100**) plus no duplicate keyword
  token and no keyword that repeats a word already in the name or subtitle. The
  24-character floor drops to 12 for `ja`, `ko`, `zh-Hans` and `zh-Hant`,
  because 24 CJK characters is a sentence, not a name.
- **The 49 non-English locales are generated, not hand-edited.**
  `scripts/native_locale_content/*.json` is the source; `apply-native-locales.py`
  writes the folders and `check-native-locales.py` runs the same limits against
  the source so a bad length is caught before 50 folders exist. Editing
  `fastlane/metadata/<locale>/` directly is fine for a one-off but the next apply
  overwrites it. en-US is the exception and is hand-maintained.
- **`products.json` is the customer-facing IAP copy for all 50 locales**, and
  `scripts/asc-sync-product-localizations.py` is what pushes it (the setup
  scripts also write prices, availability and intro offers, which is not what you
  want for a copy change). Premium branding is **Recharge+** everywhere a
  customer can see it; the ASC *reference* names still say "Recharge Pro"
  because Apple makes those immutable and nobody sees them.
  **Products attached to a review submission are locked** — a copy PATCH returns
  409 `ENTITY_ERROR.ATTRIBUTE.INVALID.UNMODIFIABLE`, and a never-submitted
  submission cannot be cancelled, so deleting its items is the only way through.
  That teardown is not free: the four product items can only be put back in the
  ASC web UI (Add for Review on the subscription group page, on each subscription
  page, and on `/distribution/iaps/<id>`), because the first subscription and
  first non-consumable an app ships cannot be attached over the public API.
  `asc-submit-for-review.py --prepare-only` does the half that is scriptable, and
  the plain run now refuses to submit with fewer than 5 items rather than burning
  a review cycle on a 2.1(b) rejection. Adding the version item flips the version
  from PREPARE_FOR_SUBMISSION to READY_FOR_REVIEW, which is why both states are
  accepted.
  ASO reasoning and the measured popularity/difficulty tables live in
  `docs/positioning.md` (en-US) and `docs/localization-aso.md` (per store); the
  numbers come from the Astro tracker, app id `123`.
