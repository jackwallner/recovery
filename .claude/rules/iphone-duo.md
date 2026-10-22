---
paths:
  - "Recharge/Views/RootView.swift"
  - "Recharge/Views/TodayView.swift"
  - "Recharge/Views/HistoryView.swift"
  - "Recharge/Views/SettingsView.swift"
  - "Recharge/Views/EstimateDetailView.swift"
  - "Recharge/Utilities/UnfoldedSplit.swift"
  - "Recharge/Debug/DuoScreenshotTour.swift"
---

# Recharge: iPhone Duo (2026-10-21)

- Unfolded (regular width, room for two panes of at least 360 pt), `RootView`
  puts Today or Recharge+, with the tab bar, on the leading side of the fold
  and History on the trailing side; the History tab button is hidden there.
  Fold edges come from `GeometryProxy.verticalFold()` (iOS 27.1
  `reservedRegions(.division)`), else an even split. Same shape as Vitals and
  VO2 Max. The math is `UnfoldedSplit`, pinned by `UnfoldedSplitTests`.
- Folding only moves frames: all three tabs stay mounted, so scroll position
  and sheets survive. Never swap layouts with an `if` around the tabs.
- Each pane gets `horizontalSizeClass = .compact` and `toolbarVerticalBehavior
  (.disabled)` (iOS 27.1 otherwise moves a stack's toolbar into a vertical bar
  beside the fold). The pane frame sits outside each screen's own
  `tabBarClearance()` inset, which fills its proposal.
- `\.unfoldedPane` tells a screen which side it fills (`nil` folded and on
  every other iPhone). The trailing pane has no tab bar under it, so
  `tabBarClearance()` reserves nothing there; in the leading pane it fills the
  room with a background band, so a Recharge+ card never rests under the pill
  beside a History pane that runs to the bottom edge. Folded it stays clear.
  Today ignores the top safe area in a pane, because the status bar sits over
  the trailing pane, level with its title.
- Measured on the gh-sim iPhone Duo (iOS 27.1): fold division 455.5...495.5,
  so both panes are 455.5 pt (0 and 495.5). The root is 951 pt once the panes
  disable the vertical toolbar (867 pt before, for under half a second, and an
  even 475/476 split until the fold region arrives). Folded, the root is
  382 pt beside the system's 84 pt vertical bar.
- Settings and a session's `EstimateDetailView` open over History in the
  trailing pane while split (`\.openInTrailingPane`, set only then), so neither
  is a form sheet across the fold. Both take `onDone`, since `dismiss` has
  nothing to dismiss in a pane. Unfolding with Today's or History's sheet up
  moves it into the pane; folding with a pane open shows it as `RootView`'s
  sheet, which counts towards `isPresentingSomething`.
- Still across the fold: onboarding (the root view on first launch) and the
  trial offer, paywall, What's New, readiness and effort sheets, which present
  as centred form sheets. None of them shows in screenshot mode.
- Unattended captures: `RECHARGE_SCREENSHOT_MODE=1` with
  `RECHARGE_SCREENSHOT_SCENE=premiumActive` and `TZ=America/Los_Angeles`
  (the runner is on UTC, which put the fixture sessions at midnight), plus the
  launch arguments
  `-DuoTour -DuoTourFirst 3 -DuoTourStep 12` (see `DuoScreenshotTour` for
  `-DuoRoutes` and `-DuoRoutesRegular`). `DUOTOUR` lines in app.log map shots
  to routes and `DUOGEOM` lines record the measured width and fold.
  `simctl openurl` raises an alert on iOS 27, so the tour runs on a timer and
  gh-sim's `--url noop://N` only paces the screenshots.
