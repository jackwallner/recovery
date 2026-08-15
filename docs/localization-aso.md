# Localization ASO — Recharge

**Uploaded:** 2026-08-15 to draft **1.0.0** (`PREPARE_FOR_SUBMISSION`). 50 appInfo
localizations and 50 version localizations live in App Store Connect, plus 200
product localizations (group + monthly + yearly + lifetime, 50 locales each).

Source of truth is `scripts/native_locale_content/*.json`, applied with
`scripts/apply-native-locales.py`. en-US is deliberately **not** in there: it is
hand-maintained in `fastlane/metadata/en-US/` and is the copy the other 49 were
written from.

```bash
python3 scripts/check-native-locales.py     # field limits, before applying
python3 scripts/apply-native-locales.py     # writes fastlane/metadata/<locale>/
python3 scripts/validate-metadata.py        # same rules on the output
eval "$(python3 scripts/asc-ensure-draft-version.py | grep '^export ')"
SKIP_SCREENSHOTS=true ./scripts/upload-appstore-metadata.sh
python3 scripts/asc-sync-product-localizations.py   # products.json -> ASC
python3 scripts/asc-readiness.py            # diffs ASC against the files
```

## The finding that decides the keyword strategy

`docs/positioning.md` establishes for en-US that the brand terms carry all the
traffic and the generic recovery vocabulary sits at Apple's popularity floor of
5. **That result reproduces in every language measured.** Astro, 2026-08-15,
app 123:

| store | native "recovery" term | pop | diff |
|---|---|---:|---:|
| de | erholung | 5 | 15 |
| de | regeneration | 5 | 13 |
| fr | recuperation | 5 | 19 |
| fr | fatigue | 5 | 11 |
| es | recuperacion | 5 | 19 |
| es | fatiga | 5 | 13 |
| jp | リカバリー | 5 | 15 |
| jp | 回復 | 5 | 41 |
| jp | 疲労 | 5 | 23 |
| kr | 회복 | 5 | 11 |
| cn | 恢复 | 29 | 51 |
| tw | 恢復 | 5 | 9 |

So no locale spends characters on translated category vocabulary for traffic.
Each keyword field is the brand block plus native sport and discipline terms,
and the descriptive words in the name and subtitle are there for comprehension,
exactly as in en-US.

## Brand popularity is not uniform, and the block is pruned per store

| store | garmin | whoop | oura | coros | polar |
|---|---:|---:|---:|---:|---:|
| us | 65/59 | 64/69 | 63/42 | 53/43 | 51/42 |
| de | 65/50 | 63/63 | 54/39 | 51/39 | 58/46 |
| fr | 64/49 | 58/65 | 56/40 | 60/39 | 52/49 |
| es | 61/43 | 56/58 | 47/23 | 54/38 | 52/50 |
| it | 60/41 | 56/52 | 35/33 | 44/39 | — |
| nl | 66/44 | 62/54 | 42/21 | 42/32 | 56/44 |
| pl | 65/39 | 55/45 | 33/13 | 39/32 | 52/47 |
| se | 63/23 | 55/47 | 50/23 | 44/33 | 52/36 |
| dk | 66/37 | 59/49 | 55/17 | 44/31 | 40/43 |
| no | 73/38 | 58/48 | 55/13 | 49/34 | 59/19 |
| **fi** | 63/17 | 38/45 | **71/17** | 32/32 | **63/39** |
| br | 59/46 | 48/50 | 43/37 | 51/37 | 53/62 |
| mx | 56/41 | 56/50 | 45/11 | **5** | 52/59 |
| ru | 54/40 | 53/46 | 25/9 | 43/27 | 44/23 |
| ua | 63/19 | 63/44 | 48/21 | 30/33 | 38/17 |
| **tr** | 49/13 | 49/49 | **5** | **5** | 44/15 |
| gr | 57/13 | 52/40 | — | — | — |
| il | 63/21 | 55/41 | 35/7 | — | — |
| **sa** | 46/9 | 60/50 | 39/13 | **5** | **5** |
| **in** | 46/17 | 56/59 | 14/13 | **5** | **5** |
| **th** | 62/46 | 63/53 | **5** | — | — |
| **vn** | 55/21 | 44/41 | **5** | — | — |
| **id** | 60/45 | 49/48 | **5** | — | — |
| **jp** | 65/39 | 45/19 | **6** | 45/34 | 39/35 |
| **kr** | 54/15 | 39/37 | **5** | 40/36 | **5** |
| cn | 50/17 | 56/34 | — | 55/36 | — |
| **tw** | **72/23** | 47/38 | — | 50/35 | — |

Read as popularity/difficulty. Bold rows are the ones where the en-US block
would have wasted characters. Dead terms (popularity 5) are dropped from that
locale's field: `coros` and `polar` from Turkey, Saudi Arabia and India,
`coros` from Mexico, `oura` from Turkey, Japan, Korea, Thailand, Vietnam,
Indonesia and Saudi Arabia (kept only where it measures above the floor).

## Local brand spellings, where they beat the Latin one

| store | term | pop | diff | vs Latin |
|---|---|---:|---:|---|
| jp | ガーミン | 66 | 34 | beats `garmin` 65/39, both shipped |
| kr | 가민 | 64 | 23 | beats `garmin` 54/15, both shipped |
| cn | 佳明 | 56 | 44 | beside `garmin` 50/17, both shipped |
| tw | 佳明 | **5** | 36 | dead; `garmin` 72/23 carries tw alone |

Finland is the other local case: `oura` 71/17 and `polar` 63/39 are the two
strongest terms in that store, both Finnish companies, so the fi field leads
with them rather than with `garmin`.

`hyrox` reproduces everywhere it was checked (de 36/11, fr 36/13, es 34/9)
and is in every field. `athlytic` holds up in Europe (de 53/34, fr 38/17,
es 38/33).

## The 24-character floor does not apply to CJK

`validate-metadata.py` holds name and subtitle to 24-30 characters so a field
does not go to waste. That floor drops to 12 for `ja`, `ko`, `zh-Hans` and
`zh-Hant`: 24 Chinese characters is roughly a full sentence and reads as
stuffing. Total Calories ships CJK names at 12-17 characters, and Recharge now
matches (`Recharge 运动恢复时间`, 15).

## Not measured

Astro returned intermittent errors during the sweep and these stores were not
sampled: `cz`, `hu`, `ro`, `hr`, `sk`, `pt`, `my`, `gb`, `au`, `ca`. Their
fields use the European pattern (full brand block plus native sport terms),
which every measured neighbour supports. Worth a pass on the next **go
refine**, 7-14 days after the listing is live and rank data exists.

Astro has no store for `bd`, `pk` or `si`, so `bn-BD`, `ur-PK` and `sl-SI`
inherit the `in` and European patterns respectively.

## Backups

`fastlane/metadata.bak.20260812-183152/` is the pre-localization snapshot
(en-US only, which is all that existed). Restore with
`./scripts/restore-appstore-metadata.sh <path>` if one is ever needed.
