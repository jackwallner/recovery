# Recharge design system

Follow this file for all UI work. `Shared/Utilities/Theme.swift` and
`Shared/Utilities/Interaction.swift` are the code half of it, and
`./scripts/design-audit.sh` is what checks the half a machine can check.

## Why it exists

A user forms a visual judgment of a screen in about 50 milliseconds and then
reads everything after it through that judgment. Nobody writes a review saying
the padding was inconsistent; they just don't subscribe. So the failure mode this
file prevents is not ugliness, it is a screen that reads as unfinished while
every individual element on it looks fine.

The specific failure is drift. Recharge had four corner radii, paddings at 3, 5,
6, 7, 10, 14, 15, 18 and 22, and eighteen buttons with no pressed state, none of
which anybody chose. Each one arrived as a reasonable local decision. The sum is
the thing users see.

A design system does not make those decisions better. It makes them once.

## The tokens

Everything below is in `Theme`. A raw number in a view is now an exception that
has to earn itself, not the default path.

**Type.** One family: SF Pro Rounded, via `.system(_:design: .rounded)`. The
countdown is the app, and a rounded face is what makes a large number read as
friendly rather than clinical. Weights are `.regular`, `.semibold` and `.bold`
only. Big figures go through `.countdownNumber(_:)`, never `Theme.bigNumber`
directly, because that modifier carries the tabular digits with the font.

**Spacing.** `Theme.Space`, a 4pt grid: `hair` 2, `xxs` 4, `xs` 8, `sm` 12, `md`
16, `lg` 20, `xl` 24, `xxl` 32, and `step(n)` for the rest. Nothing sits between
two steps. `hair` exists for the gap inside a label-and-value pair, which is
typography rather than layout.

**Radius.** `Theme.Radius`: `card` 20, `control` 16, `chip` 10. Three rather than
one, because on iOS a 20pt button inside a 20pt card reads as a mistake: a nested
corner has to shrink or it looks like it has burst its container. Every one of
them is `.continuous`, which is the shape Apple actually draws and one of the
subtlest premium tells on the platform. `.cornerRadius()` and `style: .circular`
are banned outright, and the audit fails on both.

**Colour.** Defined once in `Theme` and never at a call site. The palette carries
state: amber while a countdown runs, green at Ready, `pro` blue on anything the
free tier cannot reach. `Color(red:...)` outside `Theme.swift` is an audit
failure.

**Elevation.** `Theme.Elevation` has two entries, `card` and `floating`.
Elevation is information about what sits above what. It is not decoration, and a
shadow used as decoration is one of the reliable cheap tells.

**Icons.** SF Symbols only, and the mapping lives in `Theme.symbol(...)` so a
state can never be drawn with a mismatched glyph.

## Interaction

**Every custom-drawn button reacts.** `.pressable()` for controls,
`.pressable(.card)` for large surfaces, which move less because a card scaling
as hard as a 44pt control reads as the whole screen wobbling. `.buttonStyle(.plain)`
is what the app had before, and on a custom label it means literally nothing
happens on touch down. A dead control reads as a broken one, and the user blames
the app rather than the style. Reduce Motion keeps the feedback and drops the
movement.

**Haptics mark state changes the user caused**, through `Haptics`: a plan
selected, a purchase completed, an effort answer recorded, a countdown reaching
Ready. Not scrolling, not navigation, and not anything the system already taps
for. A signal that fires on every tap stops being a signal, so the bar for adding
one is that the user would otherwise have to read the screen to know it worked.

**44pt minimum tap target**, `Theme.minimumTapTarget`. Watch for the specific
version of this bug that this app had twice: styling a `Button` rather than its
label leaves the hit area at the text's own bounds, so the padded pill around the
words is decoration you cannot tap. The background and the target have to be
drawn by the same view.

## The native layer

The app sits on a home screen next to software built by hundred-person design
teams. Users don't consciously compare, but their thumbs do.

- Continuous corner curves everywhere (above).
- Tabular numerals on anything that changes: `.countdownNumber(_:)` or
  `.monospacedDigit()`. A proportional font re-lays digits out as they tick, so a
  hero counting down jitters sideways and the ring behind it looks redrawn.
- Safe areas respected. The floating tab bar is an overlay, so scrollable tabs
  reserve room with `tabBarClearance()` **inside** the `NavigationStack`. See
  CLAUDE.md for why that placement is load-bearing.
- Native navigation. Three tabs, real headers, sheets for secondary screens.
- Never more than one interrupting sheet. `RootView` owns that ordering.

## Where the effort goes

In funnel order, not evenly:

1. **Icon and screenshots.** They convert before anyone touches the app.
2. **Onboarding and paywall.** A beautiful paywall on top of an ugly onboarding
   converts like an ugly paywall.
3. **The first ten seconds inside the app.** Today's hero.
4. **Everything else.** Settings does not need to be gorgeous.

Polishing evenly is how a redesign runs out of time with the paywall untouched.

## Enforcement

`./scripts/design-audit.sh` checks the mechanical half: pressed states, radii,
continuous corners, the spacing grid, colour definition, tabular digits. Run it
before a build worth shipping. It is deliberately narrow, and it covers spacing
only in `Recharge/Views`, because the Watch and the complications work at sizes
where the phone's grid is not the right answer.

What it cannot check is taste: hierarchy, copy, and whether a screen is worth
looking at. That is still twenty minutes with the app in your hand, in funnel
order, once a week.

One warning, since a design system is an excellent place to hide: this one was
set up in an afternoon and is meant to stay set up. If you are on your second
week of tuning tokens, you have turned a trust signal into a hiding place.
