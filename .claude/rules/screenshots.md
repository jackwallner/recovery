---
paths:
  - "artifacts/asc-screenshots/**"
  - "fastlane/screenshots/**"
---

# Screenshots

## Localized store sets
Kit: `artifacts/asc-screenshots/l10n-20261105` (call it KIT). Targets are in `KIT/app.json`.
Four phone frames per locale (01 countdown, 02 ready, 03 history, 05 settings).
04 (Recharge+ paywall shows prices) and 06 (Watch) are left out of every
non-English locale: StoreKit prices do not exist on a plain simulator launch.

Recapture and rebuild, from a machine with gh-sim:
1. `KIT/tools/capture.sh [store_locale ...]` runs ONE `gh-sim launch` job and
   sorts shots into `KIT/raw/<locale>/phone/` (raws are git-ignored). With no
   arguments it also captures the en-US baseline. Keep a job to 12 screens
   (three locales): a 32-screen job died on the runner after screen 24.
2. `KIT/tools/build_all.sh [store_locale ...]` composes with `reskin.py`, runs
   `gate.py --catalog Shared/Localizable.xcstrings`, and copies passing sets to
   `fastlane/screenshots/<locale>/` as `01_countdown.png` etc. (the repo's
   underscore names; `en-live/` uses hyphens).
3. Headers live in `KIT/copy/headers.json` (keys use the hyphen file names);
   geometry in `KIT/frames.json` (Arial Rounded MT Bold 96, bezel located with `locate.py --bezel`).

Quirks:
- Scenes come from launch arguments (`-RECHARGE_SCREENSHOT_MODE 1
  -RECHARGE_SCREENSHOT_SCENE ready`), a DEBUG-only path in
  `ScreenshotConfig.setting`, plus `-AppleLanguages (xx) -AppleLocale xx_YY`.
- Captures show the free-tier state (Recharge+ figure blurred and locked); the
  old English frames showed a different state. Intentional, it is what ships.
- GitHub's Macs queued for 2+ hours the night this was built; submit once and wait.
- `gate.py` needs an `en-US` entry in `headers.json` as the English reference.
