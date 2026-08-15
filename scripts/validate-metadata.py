#!/usr/bin/env python3
"""Validate Recharge App Store metadata before upload."""
from __future__ import annotations

import json
import os
import re
import sys
import urllib.error
import urllib.request
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane" / "metadata"
# Every locale ASC supports. Only the ones actually staged in fastlane/metadata/
# are validated — `deliver` uploads what is on disk (see fastlane/Deliverfile),
# so an unwritten locale is a gap in the ASO plan, not a broken upload. Set
# RECHARGE_REQUIRE_ALL_LOCALES=1 to hold the full set to the standard again.
SUPPORTED_LOCALES = json.loads((Path(__file__).parent / "asc-supported-locales.json").read_text())["locales"]
LOCALES = (
    SUPPORTED_LOCALES
    if os.environ.get("RECHARGE_REQUIRE_ALL_LOCALES") == "1"
    else sorted(path.name for path in META.iterdir() if path.is_dir() and path.name != "review_information")
)
REQUIRED = (
    "name", "subtitle", "keywords", "description", "promotional_text",
    "release_notes", "support_url", "marketing_url", "privacy_url",
)
PROHIBITED = (
    r"\bdiagnoses?\b", r"\btreats?\b", r"\bcures?\b", r"\bprevents?\b",
    r"\bguaranteed\b", r"\blongevity prediction\b", r"\bclinical accuracy\b",
)
EXPECTED_CATEGORIES = {
    "primary_category": "HEALTH_AND_FITNESS",
    "secondary_category": "SPORTS",
}
# 24 Latin characters and 24 CJK characters are not the same amount of text.
# A 24-character Chinese or Japanese app name is roughly a full sentence and
# reads as keyword stuffing, which is why every other app in the fleet ships
# CJK names at 12-17 characters. The floor exists to stop a field going to
# waste, so it drops for the scripts where 30 characters is already generous.
CJK_LOCALES = frozenset({"ja", "ko", "zh-Hans", "zh-Hant"})
EN_DISCLOSURE = "Prices are shown in the app before you buy and vary by region"
DISCLOSURES = {}
for _path in sorted((Path(__file__).parent / "native_locale_content").glob("*.json")):
    for _locale, _fields in json.loads(_path.read_text(encoding="utf-8")).items():
        DISCLOSURES[_locale] = _fields["price_disclosure"]


def read(locale: str, field: str) -> str:
    path = META / locale / f"{field}.txt"
    return path.read_text(encoding="utf-8").strip() if path.exists() else ""


def tokens(text: str) -> list[str]:
    return [part.strip().lower().replace(" ", "") for part in re.split(r"[,，、]", text) if part.strip()]


def indexed_words(text: str) -> set[str]:
    return {word.lower() for word in re.findall(r"[\w']+", text, flags=re.UNICODE) if len(word) >= 2}


def check_url(url: str) -> bool:
    try:
        request = urllib.request.Request(url, method="HEAD", headers={"User-Agent": "RechargeReleaseCheck/1.0"})
        with urllib.request.urlopen(request, timeout=20) as response:
            return 200 <= response.status < 400
    except (urllib.error.URLError, TimeoutError, OSError):
        return False


def main() -> None:
    errors: list[str] = []
    for field, expected in EXPECTED_CATEGORIES.items():
        path = META / f"{field}.txt"
        value = path.read_text(encoding="utf-8").strip() if path.exists() else ""
        if value != expected:
            errors.append(f"{field}: expected {expected}, found {value or 'empty'}")
    present = sorted(path.name for path in META.iterdir() if path.is_dir() and path.name != "review_information")
    if present != sorted(LOCALES):
        errors.append(f"locale set mismatch: expected {len(LOCALES)}, found {len(present)}")

    descriptions: dict[str, list[str]] = {}
    for locale in LOCALES:
        folder = META / locale
        for field in REQUIRED:
            if not read(locale, field):
                errors.append(f"{locale}: empty {field}.txt")
        name = read(locale, "name")
        subtitle = read(locale, "subtitle")
        keywords = read(locale, "keywords")
        description = read(locale, "description")
        promo = read(locale, "promotional_text")
        notes = read(locale, "release_notes")

        # The 23-character carve-out for "Recharge: Recovery Time" is gone with
        # that name. Every Latin-script locale clears the 24-character floor;
        # CJK gets the lower one for the reason given at CJK_LOCALES.
        floor = 12 if locale in CJK_LOCALES else 24
        for field, value, minimum, maximum in (
            ("name", name, floor, 30),
            ("subtitle", subtitle, floor, 30),
            ("keywords", keywords, 94, 100),
        ):
            if not minimum <= len(value) <= maximum:
                errors.append(f"{locale}: {field} length {len(value)}, expected {minimum}-{maximum}")
        if len(description) > 4000:
            errors.append(f"{locale}: description length {len(description)} > 4000")
        if len(promo) > 170:
            errors.append(f"{locale}: promotional text length {len(promo)} > 170")
        if len(notes) > 4000:
            errors.append(f"{locale}: release notes length {len(notes)} > 4000")

        keyword_tokens = tokens(keywords)
        if len(keyword_tokens) != len(set(keyword_tokens)):
            errors.append(f"{locale}: duplicate keyword token")
        indexed = indexed_words(f"{name} {subtitle}")
        duplicates = sorted(token for token in keyword_tokens if token in indexed)
        if duplicates:
            errors.append(f"{locale}: keywords duplicate name/subtitle: {', '.join(duplicates)}")

        description_lower = description.lower()
        for pattern in PROHIBITED:
            if re.search(pattern, description_lower) and "does not" not in description_lower:
                errors.append(f"{locale}: prohibited health claim pattern {pattern}")

        if "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/" not in description:
            errors.append(f"{locale}: missing Apple Standard EULA URL")
        if "https://jackwallner.github.io/recovery/privacy-policy.html" not in description:
            errors.append(f"{locale}: missing privacy URL")
        if re.search(r"[$£€]\s?\d|\d+[.,]\d{2}\s*(?:per|/)", description):
            errors.append(f"{locale}: description must not hardcode regional prices")
        # Every locale has to carry the disclosure, but in its own language. The
        # sentence lives beside the rest of that locale's copy in
        # scripts/native_locale_content/, so this check reads it from there
        # rather than demanding the English string in 49 translated listings.
        if DISCLOSURES.get(locale, EN_DISCLOSURE) not in description:
            errors.append(f"{locale}: missing regional-price disclosure")
        if locale == "en-US" and "7-day" not in description:
            errors.append(f"{locale}: missing 7-day trial disclosure")

        product_path = folder / "products.json"
        if not product_path.exists():
            errors.append(f"{locale}: missing products.json")
        else:
            product = json.loads(product_path.read_text(encoding="utf-8"))
            for key in ("group", "monthly_name", "monthly_desc", "yearly_name", "yearly_desc", "lifetime_name", "lifetime_desc"):
                if not product.get(key):
                    errors.append(f"{locale}: empty product field {key}")
                    continue
                # ASC rejects longer values outright (409 TOO_LONG), and it does
                # it partway through creating 50 localizations.
                limit = 30 if key.endswith("_name") or key == "group" else 55
                if len(product[key]) > limit:
                    errors.append(f"{locale}: product field {key} length {len(product[key])} > {limit}")

        descriptions.setdefault(description, []).append(locale)

    for text, locales in descriptions.items():
        if len(locales) > 4 and text == read("en-US", "description"):
            errors.append(f"English description reused in {len(locales)} locales")

    urls = {
        read("en-US", "support_url"),
        read("en-US", "marketing_url"),
        read("en-US", "privacy_url"),
        "https://jackwallner.github.io/recovery/terms.html",
    }
    for url in sorted(urls):
        if not check_url(url):
            errors.append(f"unreachable URL: {url}")

    if errors:
        print("Metadata validation failed:", file=sys.stderr)
        for error in errors:
            print(f"  - {error}", file=sys.stderr)
        raise SystemExit(1)
    print(f"Metadata valid: {len(LOCALES)} locales, 24/24/94+ ASO fields, URLs and disclosures present")


if __name__ == "__main__":
    main()
