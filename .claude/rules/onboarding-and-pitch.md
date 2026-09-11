---
paths:
  - "Recharge/Views/OnboardingView.swift"
  - "Recharge/Views/Components/OnboardingActions.swift"
  - "Recharge/Views/TrialOfferPage.swift"
  - "Recharge/Views/PaywallView.swift"
  - "Recharge/Views/TodayView.swift"
  - "Shared/Utilities/HealthIngestSummary.swift"
  - "Shared/Services/HealthKitService.swift"
  - "RechargeUITests/RechargeUITests.swift"
---

# Recharge: onboarding and the pitch

Moved verbatim from CLAUDE.md. Loads when a matching file is read; update it here. Section names cited from other files are listed in the CLAUDE.md index.

### The onboarding copy is centred, and it was not before
`OnboardingScroll` is the container every page uses. The previous version wrapped
its content in a plain `ScrollView` whose inner stack carried `minHeight: 0`, so
the two `Spacer`s meant to centre it had nothing to expand into and collapsed:
the title sat against the top of the screen, the buttons against the bottom, and
every page whose copy was short — most of them — had a hand's width of nothing in
between. That is the "lot of blank space" the flow was reported for.

The scroll view is not optional even so: at an accessibility content size the
icon, title and message are several times taller than the screen, and a fixed
`VStack` there clipped them. `minHeight: proxy.size.height` is what makes one
container do both jobs. The slack is deliberately **not** split evenly — the
lower spacer is capped at 32pt so the surplus goes upward and the copy always
comes to rest just above the decision.

### The pitch is two numbers
Average recovery time, an arrow, theirs. That is the whole of it, on the
onboarding offer page, the passive half sheet, Today's one card, and the Settings
row. Both figures come from `RecoveryEngine.personalizedPreview`, computed on
both tiers so no surface ever has to invent one, and the free tier blurs the
right-hand figure rather than replacing it — a mocked-up number on a paywall is a
number somebody will hold the app to.

It replaced a three-column rest-pattern table (You / Similar / Yours, per
intensity band) that answered the same question with nine figures, three of them
measurements, three estimates and three blurred. `RestPattern` and
`RestPatternCard` are deleted.

Under it, on the onboarding page, is `HealthIngestSummary`: every reading Health
actually supplied, printed back. That is the evidence the number on the right came
from somewhere, and it is more persuasive than a feature list because the user
recognises their own data in it. **A row only exists when there is a real value
behind it** — no "not available", no em dashes. A receipt for something that was
not read is not evidence of anything.

The passive offer is a **half sheet** (`TrialOfferSheet.detentHeight`), as in
Vitals: the thing it is arguing about is the countdown on the screen behind it,
and a full-screen cover hides the one piece of evidence the pitch depends on.

### Onboarding reads Health before it asks anything
The flow is welcome → Health → what Health gave us → the gap questions → what the
number means → the tier decision. Three structural rules, all of which were bugs
first (the third is in "The onboarding copy is centred" above):

- **The buttons never move**, the trial offer included. Every page ends in the
  same `OnboardingActions` block, which reserves *both* variable rows: the
  secondary action whether or not the page uses one, and the
  Restore/Terms/Privacy slot whether or not the page is a purchase point.
  Nothing that varies between pages may sit below the primary button, so its
  distance from the bottom of the screen is a constant and everything a page
  wants to say goes above it. The trial page's subscription disclosure and legal
  row used to sit *under* its CTA, lifting the one button in the flow that takes
  money about forty points clear of the four Continue buttons that had just
  trained the thumb. `testTheOnboardingButtonStaysInOnePlace` asserts the frames,
  not a screenshot — but it broke out of its walk the moment the offer page
  appeared and never measured it, so the bug lived on the one page the guard
  could not see. It measures the offer CTA now, and
  `testThePurchaseCTALandsWhereTheContinueButtonWas` states the same claim where
  it actually broke.
- **The step list is frozen once**, when the user leaves the Health page.
  Answering a question removes it from `AthleteProfile.gaps`, so a continuously
  derived array would delete the page the user is standing on. The progress bar
  is measured against the longest possible flow until Health answers, so it can
  only ever jump forward.

**The rule for `readTypes` has not changed; what changed is that the app
consumes more and now shows its working.** Nothing goes in that sheet unless
something the user can see uses it — and `HealthIngestSummary` is what makes that
literally checkable, because every type in the set has a line in the receipt and
a row with no consumer would be a row with no line. Eleven types:

| Type | Consumed by |
|---|---|
| workouts, heart rate | the session load, and the *observed* maximum heart rate |
| active energy | the energy path when heart rate is missing |
| resting HR, HRV | overnight context, and the rebound signal |
| sleep, respiratory rate | overnight context |
| heart-rate recovery | the kinetics signal in `PersonalRecoveryModel` |
| VO2 max | `AthleteProfile.fitnessScale`, on both tiers |
| body mass | the energy path's mass residual |
| date of birth, sex | the age-predicted ceiling, when nothing was measured |

VO2 max was out of this set once, on the grounds that the evidence tying it to
*recovery rate* is weak. That is still true and it is not what it is used for: it
sets the training **level** the session is compared against, which is what
Firstbeat's activity class does at setup on a Garmin.

The readout page prints those readings rather than the app's summary of them
("mostly endurance work", "age 34"). The two do different jobs: a summary asks to
be believed, and a list of the user's own numbers is evidence. It is also the
honest counterpart to a sheet asking for eleven types.

The last onboarding decision is "Continue with Recharge+" or "Get Started". It is
not a "Not now": declining there is choosing the free tier and starting to use
the app, and the button says so. "Get Started" sits **above** the CTA, in the
same reserved secondary slot `OnboardingActions` gives every other page, so the
primary button is the lowest thing on every screen of the flow (the Vitals /
VO2 Max shape). The trial is named in a `Theme.pro` callout above the price and
never on the button: Apple 3.1.2(c) weighs pricing elements against each other,
and the billed amount has to stay the largest one.
