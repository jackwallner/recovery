# Pre-submit review: Recharge 1.1.4 (build 56), 2026-11-07

## Scope

- Live version: **1.1.2**. `8207d4a` bumps to 1.1.4 "while 1.1.3 awaits release", so 1.1.3 is not on the store yet. The last 1.1.2 build is 50 (`46a6681`).
- Diff: `46a6681..947f513` (origin/main), app sources only: `Recharge/`, `Shared/`, `RechargeWatch/`, `RechargeWidget/`, `RechargeWatchWidget/`, `project.yml`. Tests, qa/, fastlane/, docs and android/ are excluded. That covers both 1.1.3 (localization into 7 languages, accessibility) and 1.1.4 (state machine audit fixes B1 to B4, Language row, `KnownEntitlement`).
- 49 files, about 4,400 diff lines excluding the string catalogs. The `Localizable.xcstrings` growth (76k lines) was checked by script, not read.

## Findings

| Severity | File:line | What happens | Status |
|---|---|---|---|
| P2 | `Shared/Services/RecoveryEngine.swift:1044` | Delete local health data clears `feedbackEligibleFrom`, and no reconnect path (Today, History, Settings) stamps it again. Until the next cold launch (`RechargeApp.init` calls `openFeedbackWindowIfNeeded`), the readiness question is never asked and no Ready moment counts toward the review ask. | Not fixed: fails safe (asks nothing), clears on next launch, and has been this way since 2026-08-23, so it is not a regression from 1.1.2. |
| P2 | `Shared/Services/RecoveryEngine.swift:154` | `refresh` now returns at once while `hasDeferredHealthAccess` is set (B2 fix). A 1.1.2 user whose deleted data was silently re-imported by the B2 bug still carries the flag. After updating, pull to refresh and the background task stop importing for them until they tap Connect Apple Health. Today already shows that card whenever the flag is set. | Not fixed: intended consequence of B2, and the way back is on screen. |
| P2 | `Shared/Services/RecoveryEngine.swift:1073` | After a delete, the Watch is cleared by one `sendSnapshot(.empty)`, and nothing republishes while Health stays disconnected. `sendSnapshot` returns silently if `WCSession` is not activated, so in that case the wrist keeps the deleted countdown until it goes stale (up to 4 days). In practice the session is activated in `RechargeApp.init`, long before a user can reach the Settings delete button. | Not fixed: needs a session that never activated during a foreground visit. Not reproducible as described. |
| P2 | `Shared/Models/RecoverySnapshot.swift:58` | `KnownEntitlement` keeps scoring background wakes (Watch, widgets, Ready alert time) as Recharge+ after a subscription lapses, until the app is next opened and RevenueCat answers. Screens still gate on `isPro`, so nothing paid is unlocked on the phone. | Not fixed: the documented design (`model-tiers.md`, "A process with no scene is a subscriber too"). |
| P2 | `Recharge/Views/PaywallView.swift:39`, `Recharge/Views/SettingsView.swift:432`, `Shared/Utilities/WhatsNew.swift:51` | In-app copy names Garmin ("as they do on Garmin", "the way a Garmin does"). This is a third-party brand, not a link or another platform, and the same English copy is in the approved, live 1.1.2. | Not changed: copy and positioning are out of scope, and the risk is low. |

No P0 or P1 findings.

## What was checked and came back clean

- **Crashes / data loss.** No new force unwraps, `try!`, `as!`, unchecked indexing or `fatalError` in the diff. `OnboardingView.step` clamps its index. No SwiftData schema change (`WorkoutRecord` only gained `reclassify`), and no `Codable` change to `RecoverySnapshot`, so old stores and old App Group payloads decode unchanged. In `refresh`, the B2 guards roll back before every save, and the workout anchor is only committed after a save that succeeded, so a delete made during a read cannot lose or resurrect sessions.
- **Format specifiers in the 7 translations.** A script compared every multi-argument key's specifier types and order (resolving positional `%n$` and `argNum` substitutions) against English. All agree, so no translation can pass an `Int` where `%@` expects an object. `python3 Tools/Localization/check.py`: 932 keys, 7 languages, 0 problems.
- **Purchases.** The offering and package lookup, restore and "any active entitlement" gating did not change beyond copy. Trial copy is shown only when `isEligibleForIntroOffer` is true, on the plan card, the trial callout and all three disclosures. `KnownEntitlement` affects scoring only, never screen gating. On the first RevenueCat answer, `apply` records the entitlement before `isPro` changes and calls `entitlementDidChange` for a free customer, so the engine rescores at the resolved tier. The paywall and the trial page both keep Restore, Terms, Apple EULA and Privacy, and both sheets have a close button.
- **State.** What's New stays at `1.4`, so it does not fire again for 1.1.4. B1 (`isSuperseded`), B3 (`readyMoment`) and B4 (the timeline's stale entry, with `reservedFinalEntries` raised to 3 so the cap still holds) were reviewed against their callers. Every reconnect path turns observers back on, either directly or through `requestAuthorization`.
- **App Review.** Every `Recharge/Debug/*` file and the Settings debug section are inside `#if DEBUG`. The only hard-coded prices are the DEBUG screenshot packages in `StoreService`. No Android or Google Play references. A search of all 7 translations for treat, cure, diagnose and injury words found them only inside the disclaimers, which deny those claims. Health purpose strings are localized in all 8 `CFBundleLocalizations`.

## Tests

Not run to completion. `gh-sim test --scheme Recharge --only RechargeTests` on origin/main `947f513` (run id `recovery@20261107-222809-1058-claude-imacf68d-1107-223812-25346`, GitHub Actions run 42455565060) was still queued after 90 minutes, with 2 of 5 GitHub Macs busy and 16 runs queued fleet-wide. No code changed in this review, so the suite state is that of the last recorded run (433/433 in `state-machines-2026-11-06-verify.md`). If the queued run finishes, fetch it with `gh-sim get <id>`.

Localization lint ran here: `python3 Tools/Localization/check.py` passed (932 keys, 7 languages, 0 problems).
