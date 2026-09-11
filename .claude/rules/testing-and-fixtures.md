---
paths:
  - "RechargeUITests/**/*.swift"
  - "Recharge/Debug/**/*.swift"
  - "Shared/Utilities/ScreenshotConfig.swift"
  - "Shared/Services/StoreService.swift"
  - "Recharge/Views/PaywallView.swift"
---

# Recharge: paywall verification, fixtures, and the seeded walkthrough

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

- **Paywall verification:** it renders empty under plain `simctl launch` — no
  RevenueCat on simulator and no StoreKit catalogue. Under screenshot mode the
  plan cards come from `StoreService.screenshotPackages`, whose prices mirror
  `Recharge.storekit` and ASC; keep them in step.
  `testPaywallRendersRealProductsUnderStoreKitTesting` in `RechargeUITests`
  asserts all three cards and attaches the render. That covers **layout**;
  localized/PPP price formatting is still only observable on device. Never sign
  off on paywall spacing from a `simctl` screenshot.

- **A fixture that agrees with itself proves nothing.**
  `ScreenshotFixtures.history` never passed `standardHours`, so it defaulted to
  `hours` and every two-tier comparison in the app rendered the same number
  twice on every capture. The comparison the upgrade sells read identically on
  both sides in `premiumActive`. The fixture now carries both figures
  explicitly, spread the way the fixture user's own analysis implies (0.86
  multiplier *and* a personal baseline above the population reference), plus a
  `recoveryCostHours` that differs from `hours` on the two rows where it has to
  (a walk, and a spin under the quiet threshold) and a filled-in
  `healthIngest`. If you add a field that a conversion surface compares, put a
  real difference in the fixture or the capture will show the app doing nothing.
- **Two ways to look at the app, and they answer different questions.**
  Screenshot mode hands `RecoveryEngine` a fixed array of finished estimates, so
  it is fast, reproducible, and proves nothing about the import path.
  `RECHARGE_SEED_HEALTH=1` writes a real training history into the simulator's
  Health store (`Recharge/Debug/HealthSeeder.swift`, DEBUG only, requests
  **write** authorization the real app never asks for) and everything downstream
  runs for real: classification, coverage, the observed maximum, the quiet
  threshold, day grouping, stacking, the 30-day analysis.
  `SeededWalkthroughTests` drives it, it runs by default, and one pass takes
  about 35 seconds against the full 120-day window.

  **It spent its whole life failing at the permission sheet, and the diagnosis
  in this file was wrong.** The sheet is presented into the app's own window
  through `_UIRemoteViewControllerSceneHostingImpl`, so on screen it looks like
  part of Recharge, but every element of it belongs to
  `com.apple.HealthPrivacyService`, and `XCUIApplication()` reports only the
  screen underneath plus an empty `Other` where the sheet is hosted. So
  `app.buttons["Turn On All"]` never existed, the helper's
  `guard … else { return }` returned **silently**, the sheet stayed up, and the
  app parked forever on the `requestAuthorization` continuation inside
  `seedIfRequested()`. The identical 364-second failure at 21, 60 and 120 days
  was 60 seconds of that wait plus the 300-second wait for the tab bar; the
  seeder had not written a single sample in any of them, which is also why
  nothing about it reached the device log. `HKWorkoutBuilder` was never
  involved: it writes 120 days (about 600 workouts and 30,000 heart-rate
  samples) in roughly two seconds.

  Four things about the sheet, all of which cost a run to find and none of
  which are guessable:

  - Query `XCUIApplication(bundleIdentifier: "com.apple.HealthPrivacyService")`.
  - The rows are `Cell`s, not `Button`s and not `Switch`es. "Turn On All" is
    `UIA.Health.AuthSheet.AllCategoryButton`; Allow is `UIA.Health.Allow.Button`.
  - Only the **cell-level** identifiers are trustworthy. The simulator gives a
    row's inner title and switch the identifier of a *different* row (Active
    Energy's switch is `UIA.Health.HeartRateVariability.SwitchCell.Switch`).
    `UIA.Health.{Read,Write}.<Type>.SwitchCell` on the cell is correct, and the
    cell carries the on/off value, so the whole check works off cells and needs
    no scrolling, which matters, because the table is ~1,860pt of content in an
    812pt window and the entire read section is below the fold.
  - **Never return silently from a permission helper.** Every step asserts now.
    A helper that gives up quietly hands its failure to whatever runs next,
    which then reports something with no connection to the cause: in this case
    "the tab bar never appeared", six minutes later, in a file about seeding.

  The second bug was the same trap the tab-bar frame tests are written around,
  arriving from a new direction. Seeded data ends with a countdown that has
  already run out, so Today raises its readiness question a beat *after* the
  import lands, later than the one-shot sheet dismissal ran. The half sheet
  covered the floating tab bar, every subsequent tap computed a hit point of
  `{-1, -1}` and fell back to the element's centre (i.e. onto the sheet), and
  the test **passed**, because `navigationBars["History"]` reports `exists` from
  a tab that is only `opacity(0)`. Three of the five attachments were the same
  screenshot of Today. Interrupts are cleared in a loop, before and after the
  import, and `show(_:in:landmark:)` asserts `isHittable` on a landmark of the
  tab it just tapped.

  One thing that was already known and is still true: HealthKit **never
  re-asks** once a permission sheet has been answered, so a run that was denied
  write access stays denied until the app is uninstalled (`xcrun simctl
  uninstall <udid> com.jackwallner.recovery`). And tapping "Turn On All" is not
  the same as everything being on. When they diverge the only evidence is one
  line in the device log reading `Seeding failed: Not authorized`, so the test
  now polls the cell values and names any category still off.

  `RECHARGE_SEED_DAYS` overrides the window for a one-off; there is no longer a
  reason to seed less than `HealthKitService.importDays`.

  **The first green run immediately earned the test back.** History showed one
  62-minute Wednesday lift four times over, once per run the seeder had ever
  done, stacking into a 72-hour countdown out of a single session:
  `HKWorkoutBuilder` never carried `seedMarker`, so `deleteExistingSeed` could
  not see the workouts it had written, while the heart-rate and energy samples
  *inside* them were marked and were deleted. What accumulated was a pile of
  workouts with no heart-rate trace, the shape most likely to be read as a
  model bug rather than a seeding one. The workout carries the marker now and
  the delete predicate additionally matches anything written by this source,
  which is exactly "seeded" (Recharge never writes to Health) and clears what
  older builds left behind. HealthKit data survives an uninstall, so this was
  never going to clean itself up.

  Worth knowing separately: the app stacked those four duplicates into one
  72-hour window without complaint. Duplicate workouts are a real thing in a
  real store (a phone syncing a Garmin alongside an Apple Watch writes both),
  and nothing in `RecoveryEngine` currently notices. Not changed here, because
  it is a model decision rather than a test one.
