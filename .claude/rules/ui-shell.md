---
paths:
  - "design.md"
  - "Shared/Utilities/Theme.swift"
  - "Shared/Utilities/Interaction.swift"
  - "scripts/design-audit.sh"
  - "Recharge/Views/**/*.swift"
  - "RechargeUITests/**/*.swift"
---

# Recharge: design system and app shell

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

### The design system is `design.md`, and it is checked by a script
**Read `design.md` before any UI work.** `Shared/Utilities/Theme.swift` holds the
tokens (`Space`, a 4pt grid; `Radius`, three continuous values; `Elevation`;
`minimumTapTarget`), `Shared/Utilities/Interaction.swift` holds
`PressableButtonStyle` and `Haptics`, and `./scripts/design-audit.sh` fails on
the six things that drift: a button with no pressed state, a raw corner radius, a
`.cornerRadius()` or `style: .circular`, an off-grid padding in `Recharge/Views`,
a `Color(red:)` outside `Theme`, and `Theme.bigNumber` used without the tabular
digits that `.countdownNumber(_:)` carries with it.

What it replaced was not a wrong system, it was no system: four corner radii,
paddings at 3, 5, 6, 7, 10, 14, 15, 18 and 22, eighteen `.buttonStyle(.plain)`
call sites with no pressed state on any of them, a gear button with a 37pt tap
target, and a "Request access" pill whose background was drawn by modifiers hung
on the `Button` rather than on its label, so the padded capsule around the words
was decoration you could not tap. Each of those arrived as a reasonable local
decision. The sum is what a user reads in the first fifty milliseconds, and the
judgment it produces is applied to everything after it.

Typography was already consistent (SF Rounded throughout, tabular digits on the
countdown) and is the reason the app was one pass away rather than a redesign.

### The screens are the Vitals shape now
Total Calories and VO2 Max are one large figure on an otherwise empty screen, and
they are the two in the fleet that read as finished products. Recharge's Today
was a stack of eight cards with the countdown as the first of them rather than
the whole of it.

- **Three tabs**: Today, History, and Recharge+ — the paywall before purchase and
  `RechargePlusView` after it, so the thing somebody bought keeps a place in the
  navigation instead of dissolving into settings rows. **Settings is not a tab**;
  it is a gear button on Today, which is what freed the third slot.
- **The tab bar floats over the content.** `ZStack(alignment: .bottom)` plus
  `.ignoresSafeArea(edges: .bottom)`. It was briefly given a layout row of its
  own — `VStack { content; tabBar.background(Theme.background) }` — which paints
  an opaque strip the width of the screen under the capsule and reads as a black
  box with a pill inside it. The cost of overlaying is that every scrollable tab
  must reserve room at rest: `tabBarClearance()`, applied **inside** each
  `NavigationStack` (see below), and a `safeAreaInset` on the paywall, whose CTA
  lives in its own bottom bar and cannot reserve its own.
- **The third tab is built on first visit.** An opacity-zero `PaywallView`
  sitting behind Today puts a second element with every one of its identifiers
  into the accessibility tree, so `firstMatch` on the purchase button picks the
  invisible one and then truthfully reports that it is not hittable. It also
  stopped the paywall fetching products on every cold launch.
- **Everything that explained the number moved to `EstimateDetailView`**, one
  sheet reached from either the ring on Today or a row in History. Everything
  that configured it moved to Settings. The App Review 1.4.1 disclaimer went with
  the explanation, which is where somebody asking what the number means ends up.

### Clearance for the floating tab bar is the shell's job
`RootView` draws a translucent capsule over the content rather than a system
`TabView`, so every scrollable tab has to reserve room for it at rest. Each
screen used to reserve its own, and it went the way hand-copied numbers go:
Today padded 72, History padded 96, and Settings, a `Form` with no padding to
copy onto, padded nothing at all. `TabBarMetrics` holds the geometry once and
`tabBarClearance()` applies it, so the bar and the room made for it come from the
same constants.

**Do not "fix" the overlay by giving the bar its own layout row.** That was tried
— `VStack { content; tabBar.background(Theme.background) }` — and it removes the
clearance problem by painting an opaque strip the full width of the screen under
the capsule, which reads as a black box with a pill inside it and is the reason
this shell looked wrong next to Vitals.

**The modifier goes inside each `NavigationStack`, not around it.** One call in
`RootView.tabContent` would cover all three tabs and does not work: a
`NavigationStack` manages the safe area of its own content, so an inset applied
from outside never reaches the scroll view within. Nothing about that failure is
visible: it compiles, the layout looks unchanged, and the last row still sits
under the blur.

An inset rather than bottom padding, so the scroll-behind look survives: it moves
where the content comes to rest, not the scroll view's frame, so passing content
still runs under the capsule and only the last row is guaranteed to clear it.

`testTheTabBarDoesNotCoverTheBottomOf{Today,History,RechargePlus}` and
`testTheTabBarDoesNotCoverTheUpgradeTabsCTA` assert frames, and writing them was
most of the work. Three traps, all of which produce a green test that checks
nothing: an element scrolled off-screen reports a frame hundreds of points below
the window, so `exists` is not "visible"; the tab bar's own labels are elements
too, so "the lowest thing on screen" measures the bar against itself; and an
opacity-zero tab is still in the accessibility tree, so `firstMatch` on a button
that exists on two screens can pick the invisible one and then truthfully report
that it is not hittable. Each test names its genuinely-last row. The Settings
variant is gone with the Settings tab.

### A pinned header has to mask what scrolls behind it
History pins its day headers (`pinnedViews: [.sectionHeaders]`), so the outgoing
day's card slides *behind* the header rather than pushing it off. The header's
`Theme.background` was sized to the text plus 8pt of top padding, inside a
`LazyVStack` with `spacing: 10` and a 16pt side margin, so three strips stayed
transparent: 16pt down each side, and the 10pt gap above and below. On a dark
screen the card's fill, its glyph and its hours all showed through around the
pinned label, which reads as a second broken row wedged under the navigation
bar. Reported from a real device and reproduced on the simulator from the
`history` fixture.

The background is inflated by exactly those two constants
(`HistoryView.horizontalMargin`, `HistoryView.rowSpacing`) with negative padding,
so the mask and the layout can never be given different numbers. It is not
covered by a test: XCUITest reports the frames of elements the header is drawing
over, not whether they are visible, so the guard here is the constants being
shared rather than an assertion.

Unrelated to the tab bar, and a different bug from Baby Docs' clipped page
height, though both surface as content ghosting under a bar. What remains on
iOS 26 is the system's own soft scroll-edge blur, which leaves a faint ghost of
the top row on all three tabs; that is Apple's default and a design decision to
change, not a defect.
