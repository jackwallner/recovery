---
paths:
  - "Recharge/Utilities/IPadLayout.swift"
  - "Recharge/Views/OnboardingView.swift"
  - "Recharge/Views/TodayView.swift"
  - "Recharge/Views/RootView.swift"
  - "RechargeUITests/IPadTourUITests.swift"
  - "project.yml"
---

# Recharge: iPad layout (2026-11-12)

iPad support is native and permanent: `TARGETED_DEVICE_FAMILY: "1,2"` on the app
and the iOS widget, four orientations in `UISupportedInterfaceOrientations~ipad`.
The watchOS targets are untouched. Once an iPad-capable build ships it cannot be
removed, so any iPad change is held to App Review quality.

- **The shell is the Duo split.** A full-screen iPad is regular width and wider
  than 720 pt, so `UnfoldedSplit` gives Today (or Recharge+) plus the tab bar on
  the leading side and History on the trailing side, with settings and a
  session's detail opening over History. Each pane is forced compact, so every
  screen keeps its phone layout inside its pane. Split View 1/3 and 1/2 are
  narrower than 720 and fall back to the single column. See `iphone-duo.md`.
- **`Device.isPad` and `readableWidth(_:)`** (`Recharge/Utilities/IPadLayout.swift`)
  are the only two switches. Phones never take an iPad branch.
- **Today's ring** grows to 440 pt (or 70 percent of the pane) on iPad; phones
  stay at 300. The header gets a normal top margin instead of the Duo's
  status-bar overlap.
- **Onboarding** is one 560 pt column, centred, at most 780 pt tall, in a
  regular window only. Every page gets the same frame, so the primary button
  still never moves between pages (see `onboarding-and-pitch.md`).
- **Sheets**: the paywall and the trial offer use `iPadSheet()`, a custom
  `PresentationSizing` (600 by 880 pt, clamped to the window, iOS 18+). An iPad form
  sheet ignores detents and is a short card that clips the plan list, and
  `.page` stretches it across the whole window.
- **HealthKit degrades gracefully.** The iPad has no Health data of its own
  unless the person has Health on iPad; the app already treats an empty store as
  "no recent workout", which reads correctly. `UIRequiredDeviceCapabilities`
  keeps `healthkit`, which iPadOS 17+ satisfies.
- **Proof.** `RechargeUITests/IPadTourUITests` rotates the simulator
  (`XCUIDevice.shared.orientation`, since `gh-sim` cannot) and attaches every
  main screen, the paywall and onboarding in both orientations:
  `gh-sim test --scheme RechargeUITests --only RechargeUITests/IPadTourUITests --device 'iPad Pro 13-inch (M5)'`.
  Read the frames; do not trust the test going green.
