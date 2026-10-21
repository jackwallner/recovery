#!/usr/bin/env python3
"""Validate Google Play listing copy under android/play-assets/metadata/android.

Checks every locale folder for Play's limits (title 30, short 80, full 4000),
the house rules (no em dashes, no prices, no Apple wording, no promo words in
the title, no treat/cure/diagnose claims), the brand in every title, the Health
Connect and Google Play paragraphs, and the line saying the app is in English in
every non-English listing. Also checks the 50 expected locales are all there and,
when .play-live-listing.json exists, that en-US matches the live listing.
Exit 1 on any failure.

Usage: scripts/validate-play-listing.py [--root DIR]
"""
from __future__ import annotations

import argparse
import json
import re
import sys
from pathlib import Path

REPO = Path(__file__).resolve().parent.parent
ROOT = REPO / "android/play-assets/metadata/android"
LIVE = REPO / ".play-live-listing.json"
LIMITS = {"title.txt": 30, "short_description.txt": 80, "full_description.txt": 4000}
# Play language codes accepted by the Publishing API (fastlane supply list).
PLAY_LANGS = set(
    "af am ar az-AZ be bg bn-BD ca cs-CZ da-DK de-DE el-GR en-AU en-CA en-GB en-IN "
    "en-SG en-US en-ZA es-419 es-ES es-US et eu-ES fa fi-FI fil fr-CA fr-FR gl-ES "
    "hi-IN hr hu-HU hy-AM id is-IS it-IT iw-IL ja-JP ka-GE km-KH kn-IN ko-KR ky-KG "
    "lo-LA lt lv mk-MK ml-IN mn-MN mr-IN ms ms-MY my-MM ne-NP nl-NL no-NO pl-PL "
    "pt-BR pt-PT rm ro ru-RU si-LK sk sl sr sv-SE sw ta-IN te-IN th tr-TR uk vi "
    "zh-CN zh-HK zh-TW zu".split()
)
# The line each non-English listing carries: the Android app is not localized.
ENGLISH_NOTE = {
    "de-DE": "Die App ist auf Englisch.",
    "fr-FR": "L'application est en anglais.",
    "fr-CA": "L'application est en anglais.",
    "es-ES": "La app está en inglés.",
    "es-419": "La app está en inglés.",
    "es-US": "La app está en inglés.",
    "pt-BR": "O app está em inglês.",
    "pt-PT": "A aplicação está em inglês.",
    "it-IT": "L'app è in inglese.",
    "nl-NL": "De app is in het Engels.",
    "sv-SE": "Appen är på engelska.",
    "no-NO": "Appen er på engelsk.",
    "da-DK": "Appen er på engelsk.",
    "fi-FI": "Sovellus on englanninkielinen.",
    "pl-PL": "Aplikacja jest w języku angielskim.",
    "cs-CZ": "Aplikace je v angličtině.",
    "sk": "Aplikácia je v angličtine.",
    "sl": "Aplikacija je v angleščini.",
    "hr": "Aplikacija je na engleskom jeziku.",
    "hu-HU": "Az alkalmazás angol nyelvű.",
    "ro": "Aplicația este în limba engleză.",
    "el-GR": "Η εφαρμογή είναι στα αγγλικά.",
    "tr-TR": "Uygulama İngilizcedir.",
    "ru-RU": "Приложение на английском языке.",
    "uk": "Застосунок англійською мовою.",
    "ar": "التطبيق باللغة الإنجليزية.",
    "iw-IL": "האפליקציה בשפה האנגלית.",
    "hi-IN": "ऐप अंग्रेज़ी में है।",
    "bn-BD": "অ্যাপটি ইংরেজিতে।",
    "mr-IN": "ॲप इंग्रजीत आहे.",
    "ta-IN": "இந்த ஆப் ஆங்கிலத்தில் உள்ளது.",
    "te-IN": "ఈ యాప్ ఇంగ్లీష్‌లో ఉంది.",
    "kn-IN": "ಈ ಆ್ಯಪ್ ಇಂಗ್ಲಿಷ್‌ನಲ್ಲಿದೆ.",
    "ml-IN": "ഈ ആപ്പ് ഇംഗ്ലീഷിലാണ്.",
    "id": "Aplikasi ini dalam bahasa Inggris.",
    "ms": "Aplikasi ini dalam bahasa Inggeris.",
    "ms-MY": "Aplikasi ini dalam bahasa Inggeris.",
    "th": "แอปนี้เป็นภาษาอังกฤษ",
    "vi": "Ứng dụng có giao diện bằng tiếng Anh.",
    "ja-JP": "アプリの表示言語は英語です。",
    "ko-KR": "앱은 영어로 제공됩니다.",
    "zh-CN": "应用界面为英文。",
    "zh-TW": "App 介面為英文。",
    "zh-HK": "App 介面為英文。",
    "ca": "L'aplicació és en anglès.",
}
ENGLISH = {"en-US", "en-GB", "en-AU", "en-CA", "en-IN"}
EXPECTED = ENGLISH | set(ENGLISH_NOTE)
TITLE_BANNED = re.compile(r"\b(free|best|top|#1|new|sale)\b", re.I)
PRICE = re.compile(r"[$€£¥₹]\s?\d|\d[.,]\d\d\s?(?:€|zł|kr|lei|Kč|₺|₽|₴)")
APPLE = re.compile(r"\b(?:Apple|App Store|iPhone|iCloud|iOS|watchOS|HealthKit)\b", re.I)
MEDICAL = re.compile(r"\b(treats?|treatment|cures?|diagnos\w*)\b", re.I)
URL_OK = re.compile(r"https://jackwallner\.github\.io/\S+")


def read(p: Path) -> str:
    return p.read_text(encoding="utf-8").strip() if p.exists() else ""


def check_file(name: str, text: str, limit: int) -> list[str]:
    errs: list[str] = []
    if not 0 < len(text) <= limit:
        errs.append(f"{name} {len(text)}/{limit}")
    if "—" in text:
        errs.append(f"{name} has an em dash")
    if re.search("[­​﻿]", text):
        errs.append(f"{name} has an invisible character")
    if m := PRICE.search(text):
        errs.append(f"{name} looks like it has a price: {m.group(0)!r}")
    if m := APPLE.search(URL_OK.sub("", text)):
        errs.append(f"{name} mentions Apple wording: {m.group(0)!r}")
    if m := MEDICAL.search(text):
        errs.append(f"{name} makes a medical claim: {m.group(0)!r}")
    if name != "full_description.txt" and "\n" in text:
        errs.append(f"{name} spans lines")
    return errs


def check(locale_dir: Path) -> list[str]:
    loc = locale_dir.name
    errs: list[str] = []
    if loc not in PLAY_LANGS:
        errs.append(f"unknown Play language code {loc}")
    for name, limit in LIMITS.items():
        if not (locale_dir / name).exists():
            errs.append(f"missing {name}")
            continue
        errs += check_file(name, read(locale_dir / name), limit)
    title = read(locale_dir / "title.txt")
    full = read(locale_dir / "full_description.txt")
    if TITLE_BANNED.search(title):
        errs.append(f"title has a promo word: {title!r}")
    if not title.startswith("Recharge"):
        errs.append("title does not lead with the Recharge brand")
    for phrase in ("Health Connect", "Google Play", "Recharge+"):
        if phrase not in full:
            errs.append(f"full description lacks {phrase!r}")
    note = ENGLISH_NOTE.get(loc)
    if note and note not in full:
        errs.append(f"full description lacks the app-is-in-English line {note!r}")
    return errs


def check_live(root: Path) -> list[str]:
    if not LIVE.exists():
        return []
    errs: list[str] = []
    fields = {"title": "title.txt", "shortDescription": "short_description.txt", "fullDescription": "full_description.txt"}
    for listing in json.loads(LIVE.read_text(encoding="utf-8"))["listings"]:
        loc = listing["language"]
        for key, name in fields.items():
            if loc == "en-US" and read(root / loc / name) != listing[key].strip():
                errs.append(f"{loc}/{name} differs from the live listing")
    return errs


def main() -> int:
    ap = argparse.ArgumentParser()
    ap.add_argument("--root", type=Path, default=ROOT)
    args = ap.parse_args()
    bad = 0
    dirs = sorted(d for d in args.root.iterdir() if d.is_dir())
    for d in dirs:
        errs = check(d)
        t, s, f = (read(d / n) for n in LIMITS)
        print(f"{'OK ' if not errs else 'BAD'} {d.name:7} t{len(t):>3} s{len(s):>3} f{len(f):>5}  {t}")
        for e in errs:
            print(f"      - {e}")
        bad += bool(errs)
    extra = check_live(args.root)
    missing = sorted(EXPECTED - {d.name for d in dirs})
    if missing:
        extra.append(f"missing locales: {' '.join(missing)}")
    for e in extra:
        print(f"BAD {e}")
    print(f"\n{len(dirs)} locales, {bad} with problems{', plus ' + str(len(extra)) + ' listing-wide' if extra else ''}")
    return 1 if bad or extra else 0


if __name__ == "__main__":
    sys.exit(main())
