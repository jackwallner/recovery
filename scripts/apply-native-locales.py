#!/usr/bin/env python3
"""Write fastlane/metadata/<locale>/ from the native locale content files.

`scripts/native_locale_content/*.json` is the source of truth for every
non-English App Store listing. Each file holds one or more locales:

    {
      "de-DE": {
        "name": "...", "subtitle": "...", "keywords": "...",
        "promotional_text": "...", "release_notes": "...",
        "price_disclosure": "...",          # the sentence validate-metadata.py looks for
        "description": "...",               # {price_disclosure} is substituted in
        "products": {"group": "...", "monthly_name": "...", ...}
      }
    }

en-US is deliberately not in here: it is hand-maintained in
`fastlane/metadata/en-US/` and is the copy the whole set is translated from.
"""
from __future__ import annotations

import json
import sys
from pathlib import Path

ROOT = Path(__file__).resolve().parent.parent
META = ROOT / "fastlane" / "metadata"
CONTENT = Path(__file__).parent / "native_locale_content"

# Identical in every storefront: one English marketing site, one privacy policy.
SHARED_URLS = {
    "support_url": "https://jackwallner.github.io/recovery/support.html",
    "marketing_url": "https://jackwallner.github.io/recovery/",
    "privacy_url": "https://jackwallner.github.io/recovery/privacy-policy.html",
}


def load() -> dict[str, dict]:
    locales: dict[str, dict] = {}
    for path in sorted(CONTENT.glob("*.json")):
        for locale, fields in json.loads(path.read_text(encoding="utf-8")).items():
            if locale in locales:
                raise SystemExit(f"error: {locale} defined twice ({path.name})")
            locales[locale] = fields
    return locales


def main() -> None:
    locales = load()
    if not locales:
        raise SystemExit(f"error: no content files in {CONTENT}")
    for locale, fields in locales.items():
        folder = META / locale
        folder.mkdir(parents=True, exist_ok=True)
        description = fields["description"].replace(
            "{price_disclosure}", fields["price_disclosure"]
        )
        text_fields = {
            "name": fields["name"],
            "subtitle": fields["subtitle"],
            "keywords": fields["keywords"],
            "promotional_text": fields["promotional_text"],
            "release_notes": fields["release_notes"],
            "description": description,
            **SHARED_URLS,
        }
        for field, value in text_fields.items():
            (folder / f"{field}.txt").write_text(value.strip() + "\n", encoding="utf-8")
        (folder / "products.json").write_text(
            json.dumps(fields["products"], ensure_ascii=False, indent=2) + "\n",
            encoding="utf-8",
        )
        print(f"{locale}: written")
    print(f"{len(locales)} locales written to {META}")


if __name__ == "__main__":
    sys.exit(main())
