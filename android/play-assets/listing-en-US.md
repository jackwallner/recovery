# Recharge: Google Play listing

Title, short and full description per locale live in
`metadata/android/<play-locale>/` (fastlane supply layout). en-US is the live
Play listing, copied verbatim. No prices in copy: Play shows them.

Locales (50): en-US (default), en-GB/AU/CA/IN, de-DE, fr-FR/CA, es-ES/419/US,
pt-BR/PT, it-IT, nl-NL, sv-SE, no-NO, da-DK, fi-FI, pl-PL, cs-CZ, sk, sl, hr,
hu-HU, ro, el-GR, tr-TR, ru-RU, uk, ar, iw-IL, hi-IN, bn-BD, mr-IN, ta-IN,
te-IN, kn-IN, ml-IN, id, ms, ms-MY, th, vi, ja-JP, ko-KR, zh-CN/TW/HK, ca.

ASO: titles lead with "Recharge" plus the highest-intent local phrase for
workout recovery time, taken from the matching iOS `fastlane/metadata`
`name.txt` and `keywords.txt`. Short descriptions open with that phrase.
Every non-English description says the app is in English (the Android app is
not localized). No em dashes, no prices, no Apple wording, no treat, cure or
diagnose claims.

Check with `scripts/validate-play-listing.py`.
