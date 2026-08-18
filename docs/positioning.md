# Positioning decision

Decided 2026-08-04, on the evidence in `../archive/scoping-2026-08-04.md`. This is the working
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
the title, and should ideally carry one winnable term. Candidates considered:

| Name | Subtitle | Notes |
|---|---|---|
| Recharge | Recovery Time for Apple Watch | Clear, brandable, "recovery" used for comprehension only |
| Rebound | Training Recovery & Ready Time | Slightly more athletic |
| Ready | Recovery Time for Athletes | Carries `athlete` (15/23); "Ready" alone is generic |
| Endur | Recovery Time & Training Load | Carries `endurance` (24/15); collides with ENDUR × HYROX |

## Launch metadata, settled 2026-08-14

`Recharge` wins the name. The subtitle changed, the title gained "Workout", and
the keyword field was rebuilt. All popularity/difficulty figures below were
re-pulled on 2026-08-14 and reproduce the launch-stack tables above within ±3.

| Field | Value | Count |
|---|---|---|
| Title | `Recharge Workout Recovery Time` | 30/30 |
| Subtitle | `Countdown for Apple Watch` | 25/30 |
| Keywords | `garmin,connect,whoop,oura,coros,polar,athlytic,hyrox,endurance,triathlon,athlete,race,day,tsb,taper` | 99/100 |

### "Recovery Time" alone was ambiguous, and the SERP proves it

The note further up ("on the App Store the word means sobriety tracking and
deleted-file rescue") was written from intuition. It is now measured. The live
top 12 for `recovery`, 2026-08-14:

| # | App | What it is |
|---:|---|---|
| 1 | I Am Sober | sobriety tracker |
| 2 | Photo Recovery: Pic Restore | deleted files |
| 3 | File Recovery - Photo Recovery | deleted files |
| 4 | Photo Recovery : Deleted Photo | deleted files |
| 5 | Photo Recovery: Deleted Files | deleted files |
| 6 | NewForm: Recovery & Wellbeing | addiction |
| 7 | SMART Recovery | addiction |
| 8 | Recovery Path for Addiction | addiction |
| 9 | Sober Me: Tools for Recovery | addiction |
| 10 | RR: Eating Disorder Management | eating disorder |
| 11 | Photo Recovery - Restore Files | deleted files |
| 12 | Nomo - Sobriety Clocks | sobriety |

Not one fitness app. So `Recharge: Recovery Time` was a title that, to a browsing
user, read as a sobriety clock. This is a utility app and the name has to say what
it does, so the title gained the disambiguating word: **`Recharge Workout Recovery
Time`**, 30/30.

The colon went because the four words are exactly 30 characters with a space and
31 with a colon. `workout` (66/82) beat `training` (42/71) for the slot: neither
will rank at zero ratings, so the choice is about which word the modal user says,
and if the app ever earns authority `workout` is the larger prize.

This changes no traffic and is not meant to. Every descriptive phrase in this
category measures at the popularity floor of 5 (`workout recovery` 5/44,
`training recovery` 5/11, `muscle recovery` 5/21, `gym recovery` 5/9,
`recovery time` 5/23). The title is a **comprehension** asset, exactly as the
build plan already says of the `Recharge` suffix.

### The allocation rule

Expected traffic is popularity times the chance of actually ranking at zero
ratings. That second factor is close to 1 on a brand SERP (proven above, and
re-proven on `hyrox` below) and close to 0 on any generic term above difficulty
50. So a character is only worth spending on a brand SERP or on a generic under
difficulty 40, and popularity alone is a trap.

Every term in the field clears that bar:

| Term | Pop | Diff | Why it is winnable |
|---|---:|---:|---|
| garmin | 65 | 59 | brand SERP |
| whoop | 64 | 69 | brand SERP |
| oura | 63 | 42 | brand SERP |
| garmin connect (via `connect`) | 59 | 60 | brand SERP |
| coros | 53 | 43 | brand SERP |
| polar | 51 | 42 | brand SERP |
| athlytic | 47 | 50 | brand SERP, in the launch stack above |
| hyrox | 41 | 17 | best generic in the category |
| endurance | 24 | 15 | |
| triathlon | 19 | 17 | |
| tsb | 17 | 39 | |
| race day (via `race,day`) | 16 | 9 | |
| athlete | 15 | 23 | |
| taper | 5 | 9 | floor popularity, but 6 characters of genuine relevance |

Three terms from the first pass were cut for failing it: `crossfit` (47/52),
`wod` (30/52) and `hrv` (27/60). All three have real popularity and all three are
unreachable until the app has ratings, so they were 20 characters of nothing.
Revisit them in the phase-two stack.

`bevel` (57/49) qualifies on the data and is deliberately left out. It is a
direct competitor *app* rather than a hardware brand the product positions
against, which is closer to 2.3.7's own example, and unlike `athlytic` it was
never in the launch stack. It is the first thing to add if the field
underperforms and the risk appetite holds.

### The title and subtitle cannot be optimised for traffic

Measured 2026-08-14, and this is the finding, not a shrug. Every word that could
plausibly sit in a title or subtitle for this app is either at the popularity
floor or far past the difficulty ceiling:

| Candidate | Pop | Diff | |
|---|---:|---:|---|
| apple watch | 73 | 63 | unreachable |
| countdown | 72 | 74 | unreachable, and the traffic is event countdowns |
| coach | 64 | 77 | unreachable |
| timer | 63 | 70 | unreachable |
| score | 58 | 78 | unreachable |
| tracker | 52 | 81 | unreachable |
| log | 39 | 37 | reachable, but means food and mood logs |
| recovery | 8 | 60 | floor and unreachable |
| recovery time | 5 | 23 | floor |
| post workout | 5 | 45 | floor |
| hybrid training | 5 | 13 | floor |
| strength | 7 | 59 | floor |
| healthkit | 19 | 52 | modest, unreachable |

So the subtitle is a **conversion** asset here, not a ranking one, and it should
be judged that way. "Countdown for Apple Watch" states the behaviour and the
platform, which is what a browsing user needs, and gives up nothing measurable
because neither word was ever going to rank.

Moving `hyrox` into the subtitle was considered and rejected. Visible HYROX use
clearly passes review (the live SERP has `HYROX Academy`, `TrainRox - Hyrox
Workout`, `Hyrox Timer`, `RoxHype`, `HyRhythm - HYROX Tracker`), and title and
subtitle placement outranks the keyword field. But it would narrow a general
recovery app to one race format on the surface most users read first, and the
conversion cost outweighs a difficulty-17 term the keyword field already reaches.

`hyrox` softness re-checked live 2026-08-14: apps with 2, 3 and 17 ratings all
sit in the top 10.

**The subtitle no longer repeats the title.** "Recovery Time for Apple Watch" spent
13 of 29 characters restating words the title already indexes. "Countdown" is worth
little on its own (`recovery countdown` is 5/39) but it is the product's actual
behaviour and it costs nothing to say. "Apple Watch" stays: at 73/63 it is the
second most searched term in the whole set, and it is the honest platform claim.

**Five popularity-5 terms were removed from the keyword field**: `rest day` (5/70),
`training load` (5/11), `readiness` (5/7), `overtraining` (5/7), `strain` (5/41).
They were shipped in the first draft despite `../archive/scoping-2026-08-04.md` already
recording them at the floor. Anything measuring 5 is the floor, not a small
number, so it is not a cheap term, it is a dead one.

**No spaces, no phrases.** Apple tokenises the field on commas *and* spaces and
combines terms itself, so `race day` is written `race,day` and the phrase still
matches. Nothing in the field duplicates a word in the title or subtitle, and
nothing duplicates another keyword.

**The brand block stays**, per the reasoning above. Re-checked live on 2026-08-14:
`StayGreen: Run Coach for WHOOP` ranks #9 for "whoop" with 2 ratings and the mark
visibly in its name, and `Klyft` ranks #8 with 1 rating. Brand SERPs are still soft
and removing the block would give up 245 popularity points (`garmin` 65, `whoop` 64,
`oura` 63, `coros` 53) for nothing that replaces it. The generic vocabulary is still
empty: every "recovery" and "readiness" phrase measures 5.

The standing risk is unchanged and is the reason to revisit this: Garmin and WHOOP
both ship competing App Store apps, so unlike the GLP-1 precedent they have an
incentive to file a 5.2.1 complaint, and one complaint removes the whole block at
once. Mitigation is the non-affiliation line in `description.txt`, which now names
HYROX and CrossFit as well.

**`hyrox` (41/17) went in.** It is the best generic term in the category by a wide
margin, high popularity at a difficulty a zero-authority app can clear, and the app
genuinely scores HYROX sessions, so it is describing a feature rather than packing
metadata. `triathlon` (19/17) went in on the same reasoning. `crossfit` (47/52) and
`wod` (30/52) are at the difficulty-50 ceiling and are expected to do nothing until
the app has ratings; they are there because there was room.

If the keyword field underperforms after launch, the no-brands fallback is:

```
hyrox,endurance,athlete,triathlon,crossfit,wod,hrv,race,day,taper,tsb,marathon,gym,log,deload,zone
```

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
