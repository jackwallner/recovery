---
paths:
  - "Recharge/**"
  - "Shared/**"
  - "RechargeWatch/**"
  - "RechargeWidget/**"
  - "RechargeWatchWidget/**"
  - "Tools/Localization/**"
  - "RechargeTests/LocalizationTests.swift"
---

# Recharge: localization (added 2026-11-04)

The copy is routed through one string catalog so other languages can be added
without touching Swift. The catalog holds English only for now; translations
are written into it by separate runs.

## Setup
- One catalog, `Shared/Localizable.xcstrings` (source `en`, every key
  `extractionState: manual`). `Shared/` is a source of every target, so the app,
  Watch app, both widget extensions compile it, and `project.yml` adds it (and
  `Shared/Utilities/Localization.swift`) to `RechargeTests` by hand.
- `Recharge/InfoPlist.xcstrings` holds the two Health purpose strings. The Watch
  and widget plists have none. Display names are the brand and stay plain.
- `python3 Tools/Localization/check.py` (repo root, no Xcode needed) fails on a
  source literal with no key, a literal that reaches the screen without one
  (`return "..."`, a ternary or `??` of literals, an implicit-return
  `case x: "..."`), a key nothing uses, and, once `LANGS` is filled in, a key
  missing a language or with mismatched format specifiers. Run it before every
  build that touches copy. `LANGS` is empty until translations land: add each
  language there, and to `LocalizationTests.languages`, and to
  `CFBundleLocalizations` when it ships.
- `// l10n-ignore` (line) or `// l10n-ignore-begin` / `-end` (block) exempts
  stored values and developer-only text. Nothing else should use them.

## Adding or changing copy
- `Text("literal")`, `Button`, `Label`, `Section`, `navigationTitle`, `alert`
  and friends localize themselves. Copy held in a `String` (view parameters,
  enums, models, notifications, error messages) is
  `String(localized: "...", bundle: .recharge)`. Always pass `bundle: .recharge`
  (`Bundle(for:)` on a class in `Localization.swift`): the logic tests are not
  hosted by the app, so `Bundle.main` there is the test runner and a plural key
  would silently fall back to its unpluralized text.
- A `String` parameter that ends in `Text(title)` is verbatim. Callers pass
  `String(localized:)`, or the parameter is a `LocalizedStringKey`
  (`primaryButton`). `Text(cond ? "a" : "b")` is not localized reliably, so
  every ternary branch is its own `String(localized:)`.
- Whole sentences only. Branch and give each variant its own key (see
  `SessionSourceCopy`: 4 shapes x just-now/ago x with/without a full stop = 16
  keys; `RecoveryCalculator.reasons`; `ComplicationCopy`). The few keys that
  take a separately keyed label as an argument (`"%@ → %@"` for the two tier
  names, `"Recharge read this as %@ from %@..."`) are listed in the catalog
  review notes of the commit that added them; do not add more.
- Counts of things are plural variations (a `%#@n@` substitution when the
  sentence has other arguments). `en` has `one` and `other`. Counts that
  describe a fixed constant (`windowDays`, `importDays`) are still plural keys
  because Slavic languages inflect by number. Compound adjectives
  (`%lld-minute`, `%lld-day recovery rate`) and unit suffixes (`%lldh`) are not.
- The interpolation type is part of the key: an `Int` is `%lld`, a `String` is
  `%@`. Interpolate numbers as `Int`, or format them with
  `.formatted(.number...)` first and interpolate the `String`. A key written
  against the wrong specifier is never found by a translation.
- Stored English values are translated at display time and never rewritten:
  `activityLabel` ("run", "lifting session") is in SwiftData and the snapshot
  and keys the symbol lookup, so screens show it through
  `WorkoutClassifier.displayLabel` (mid-sentence) or `displayTitle` (heading).
  `reasons` are built at scoring time and persisted in the language then
  active; they refresh on the next rescore.
- No `.capitalized`/`.lowercased()`/`.uppercased()` on translated text: the
  lowercase and title forms are separate keys. Numbers, dates, mass and lists
  use Foundation (`formatted`, `DateFormatter` templates, `Measurement`,
  `ListFormatter`).
- Prices come only from StoreKit (`localizedPriceString`). The period phrases
  around them ("%@ per year") are keys; the trial length is
  `IntroTrialLength`, never parsed back out of a label.
- Brand stays untranslated and is written into the key, not interpolated:
  Recharge, Recharge+, Garmin, Apple Health, HRV, HIIT.
- Compliance wording (`testReasonsNeverMakeAMedicalClaim` and friends) applies
  to every language: no "recovered", "safe to train", "injury", "your body".

## Left in English on purpose
Mail subject "Recharge feedback" (read by the developer), SF Symbol and route
strings, StoreKit screenshot fixtures (`StoreService.screenshotPackages`) and
the two StoreKit Testing diagnostics, `Recharge/Debug/**`, the Settings DEBUG
section, and the hidden measuring `Text(verbatim:)` in `OnboardingActions`.
