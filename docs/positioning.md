# Positioning decision

Decided 2026-08-04, on the evidence in `scoping-2026-08-04.md`. This is the working
brief. `README.md` remains the product/model dossier; nothing here overrides its
mechanics, it only settles framing, scope, and go-to-market.

## The one-line position

> Garmin-style recovery time, on the Apple Watch you already own.

The app answers the question a Garmin or WHOOP user asks after a hard session,
using only HealthKit data and an Apple Watch. No ring, no strap, no subscription
to a hardware ecosystem.

## Why this frame

The demand evidence in the dossier is literally people asking for Garmin's Recovery
Time on Apple Watch. That is the language users already have for this product, and
it is the only language in this category with search volume attached: the generic
vocabulary (`recovery time`, `readiness`, `training load`, `training status`) is
uniformly at Apple popularity 5, while `garmin` is 65, `whoop` 64, `oura` 63,
`polar` 51, `coros` 50.

## Brand terms are reachable at launch

**Correction to an earlier draft of this document**, which claimed `garmin` (diff 59)
and `whoop` (diff 69) were out of reach until the app had ~50 ratings, on the
strength of the difficulty-50 zero-authority ceiling in
`~/aso-niche-audit-2026-06-05.md`. That ceiling holds for generic category keywords.
It does not hold on brand SERPs.

Evidence from the live `whoop` results (popularity 64, difficulty 69):

| App | Ratings | Rank for "whoop" | "whoop" visible in name/subtitle? |
|---|---:|---:|---|
| Bevel | 13,716 | 5 | No |
| Athlytic | 10,746 | 8 | No |
| Aurora Wellness | **0** | **9** | No |
| Klyft | **1** | **10** | No |
| Calibrate | 1 | 16 | No |
| umo | 3 | 20 | No |

Three apps with 0-3 ratings sit in the top 20 of a difficulty-69 brand term, none
of them showing the brand anywhere visible. They are ranking on the hidden keyword
field alone. Brand SERPs are soft because past the first-party app there is little
genuinely relevant competition.

Same pattern on the other brands: `Jaan: Oura Demystified` (0 ratings) is #7 for
"oura"; `RunGap` #4 and `MaxMile` (2 ratings) #7 for "coros".

So all five brands go in the keyword field at launch: `garmin`, `whoop`, `oura`,
`polar`, `coros`. No phased rollout.

### Visible brand use in the name or subtitle

This is available too, and the market uses it heavily. From the live `zepbound`
results:

| App | Brand placement | Ratings |
|---|---|---:|
| Zepbound Tracker by GlucoPal | **name**; subtitle "For GLP-1s, Mounjaro, Wegovy" | 2,449 |
| Shotsy GLP-1 Tracker | subtitle "GLP1 Shot - Zepbound, Wegovy" | 28,650 |
| MeAgain | subtitle "Wegovy Pill Zepbound GLP1 Shot" | 27,192 |
| DreamMe | subtitle "Wegovy, Zepbound Mounjaro glp1" | 2,288 |
| Zepbound Tracker: Jab Journey | subtitle is literally `wegovy,mounjaro,ozempic,glp-1` | 41 |
| Dosely | subtitle "Track GLP1 Zepbound Wegovy" | 0 |

These are Eli Lilly and Novo Nordisk trademarks in visible metadata, at every
authority level, passing review. Our own Simple GLP is more conservative than the
market: brands in the keyword field only
(`ozempic,wegovy,mounjaro,zepbound,semaglutide,…`), subtitle "Free, Private
Injection Log".

**The distinction that still matters** is not trademark-vs-not, it is whether the
trademark owner has a reason to complain. Guideline 5.2.1 is enforced by complaint,
not at review time — which is why the GLP apps survive. Eli Lilly ships no competing
tracker, so a Zepbound tracker is a complement and adherence is in Lilly's interest.
WHOOP and Garmin both ship their own App Store apps and would be looking at a
competitor using their mark on the same storefront. Same mechanism, different
incentive to file.

Given the ranking table above shows the keyword field alone reaches the top 10 of
`whoop` at zero ratings, visible placement buys ranking we can already get, in
exchange for the one risk that actually has teeth. Recommendation: brands in the
keyword field, comparison language in description and screenshots (factual, no
implied endorsement or affiliation), title and subtitle kept clean. Revisit if the
keyword field underperforms.

## Launch keyword stack

Brand terms, all in from day one (soft SERPs, reachable at zero ratings):

| Keyword | Pop | Diff |
|---|---:|---:|
| garmin | 65 | 59 |
| whoop | 64 | 69 |
| oura | 63 | 42 |
| garmin connect | 60 | 60 |
| polar | 51 | 42 |
| coros | 50 | 43 |
| training peaks | 49 | 62 |
| athlytic | 47 | 50 |

Generic terms clearing the popularity floor at winnable difficulty:

| Keyword | Pop | Diff |
|---|---:|---:|
| hyrox | 41 | 17 |
| endurance | 24 | 15 |
| stress tracker | 19 | 49 |
| tsb | 17 | 39 |
| race day | 16 | 9 |
| athlete | 15 | 23 |
| sleep coach | 13 | 15 |

Contested but worth a slot if characters allow: `hrv` 27/60,
`heart rate variability` 30/53, `wod` 30/52, `marathon training` 19/51,
`gym log` 23/54. These are ordinary category terms, so the difficulty-50 ceiling
does apply — expect them to do nothing until the app has ratings.

Never: `workout` 66/82, `fitness` 68/84, `sleep` 63/81, `running app` 62/83,
`workout tracker` 62/74, `strava` 75/75, `widget` 70/83.

The 100-character keyword field cannot hold all of this. The brand block alone
(`garmin,whoop,oura,polar,coros,garmin connect,training peaks,athlytic`) is ~70
characters, which is most of the budget and probably the right allocation given it
is where all the volume is.

Note that no term containing "recovery" appears anywhere above. "Recovery" is for
human comprehension on the product page, not for traffic; on the App Store the
word means sobriety tracking and deleted-file rescue.

## Naming

The name must not lean on "recovery" for discovery, must leave Garmin/WHOOP out of
the title, and should ideally carry one winnable term. Candidates, undecided:

| Name | Subtitle | Notes |
|---|---|---|
| Recharge | Recovery Time for Apple Watch | Clear, brandable, "recovery" used for comprehension only |
| Rebound | Training Recovery & Ready Time | Slightly more athletic |
| Ready | Recovery Time for Athletes | Carries `athlete` (15/23); "Ready" alone is generic |
| Endur | Recovery Time & Training Load | Carries `endurance` (24/15); collides with ENDUR × HYROX |

## Product scope

**Hybrid profiles per workout type** (chosen over cardio-only). The load model runs
separate recovery curves per session category rather than one universal TRIMP-to-hours
mapping.

Profiles to build:

| Profile | Load source | Recovery shape |
|---|---|---|
| Endurance (run, ride, row, swim) | HR-reserve TRIMP from workout heart-rate samples | Baseline curve from the dossier's percentile table |
| Strength / lifting | Session RPE prompt, duration, active energy (HR coverage is unreliable) | Slower decay, longer tail than endurance at equal perceived effort |
| Mixed / functional (HYROX, CrossFit, circuits) | TRIMP where HR coverage allows, RPE otherwise, weighted toward the higher of the two | Longest window; both systems taxed |
| Easy / active recovery (walk, yoga, mobility) | Duration and energy only | Near-zero contribution; must never extend an existing countdown |

Implications this scope creates, all of which need deciding during the build:

1. Strength and mixed profiles need a **one-tap RPE input** when HR coverage is
   poor. That is a Watch-to-phone write, so it needs the WatchConnectivity pattern
   from the retired Headache Logger
   (`~/vitals/_archive/headaches-retired-2026-04-14/HeadacheLogger/Services/PhoneWatchSession.swift`),
   not the read-only App Group cache pattern that Vitals and VO2 use.
2. Sessions must be **classified** into a profile. `HKWorkoutActivityType` handles
   the obvious cases; HYROX and CrossFit both surface as
   `.functionalStrengthTraining` or `.highIntensityIntervalTraining` and will need
   a user-set default plus a per-session override.
3. Four profiles means four times the fixture surface. The dossier's Phase 1
   fixture list expands accordingly, and the monotonicity assertion has to hold
   *within* each profile, not across them.
4. Concurrent recovery windows from different profiles need a resolution rule.
   Simplest defensible rule: the countdown shows the latest `readyAt` across all
   active windows, and the explanation names which session set it.

## Monetization

Fleet standard freemium, unchanged from the dossier's split:

- **Free**: HealthKit import, countdown, Ready state, Watch app, all four
  complication families, iPhone explanation of the last estimate.
- **Pro**: HRV / RHR / sleep context, weekly load view, per-session workout-type
  override, and optional Ready notifications.
- Monthly / yearly / lifetime, 7-day trial, yearly-only single-decision onboarding
  trial page as the final onboarding screen, full three-plan paywall behind
  Settings and feature gates. Per `~/ios/paywalls/current-paywall-playbook.md` and
  `~/ios/onboarding/trial-conversion-thumb-zone.md`.
- Gate on `!entitlements.active.isEmpty`, never a hardcoded entitlement string —
  four fleet apps already have a wrong named entitlement that only works because
  of this fallback (`~/revenuecat-entitlement-audit.md`).
- Verify in ASC that the monthly product actually carries the intro offer before
  shipping any copy that promises a trial. Streak Counter shipped that bug.

## Go-to-market

Brand-term ASO plus a comparison-led product page.

- Product page hero: the Garmin comparison. Screenshots lead with the countdown on
  a Watch face, not with an iPhone dashboard.
- App Preview video showing the post-workout countdown appearing and the Ready
  state arriving. Pipeline exists at `~/ios/app-previews/`.
- Keyword field per the launch stack above; refresh to the phase-two stack once
  ratings clear ~50.
- No paid UA. Nothing in the fleet supports it at $10-20 per paying user against a
  best-case $2.12 per download.

## Risks carried by this decision

1. All the volume is on brand terms, and brand searchers usually want the
   first-party app. If those impressions convert badly there is no fallback,
   because the generic vocabulary in this category is empty. A trademark complaint
   from Garmin or WHOOP would also remove the entire keyword stack at once.
2. Seven apps already ship this product and none has more than three ratings. The
   frame is a bet that their problem was positioning, not demand. That bet is not
   yet validated.
3. Apple ships Training Load natively and could add a countdown at any WWDC.
4. Four workout profiles is materially more model surface than the dossier's
   single curve, and it is the part most likely to feel wrong to a real user.
