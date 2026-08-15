#!/usr/bin/env python3
"""Field-length and ASO checks over scripts/native_locale_content/ before it is applied.

Same rules validate-metadata.py enforces on fastlane/metadata/, run against the
source files so a bad length is caught while the copy is still being written
rather than after 50 folders have been generated from it.
"""
from __future__ import annotations

import json
import re
import sys
from pathlib import Path

CONTENT = Path(__file__).parent / "native_locale_content"
EULA = "https://www.apple.com/legal/internet-services/itunes/dev/stdeula/"
PRIVACY = "https://jackwallner.github.io/recovery/privacy-policy.html"
# 24 Latin characters and 24 CJK characters are not the same amount of text.
# A 24-character Chinese or Japanese app name is roughly a full sentence and
# reads as keyword stuffing, which is why every other app in the fleet ships
# CJK names at 12-17 characters. The floor exists to stop a field going to
# waste, so it drops for the scripts where 30 characters is already generous.
CJK_LOCALES = frozenset({"ja", "ko", "zh-Hans", "zh-Hant"})
LIMITS = {"name": (24, 30), "subtitle": (24, 30), "keywords": (94, 100)}


def main() -> int:
    problems: list[str] = []
    count = 0
    for path in sorted(CONTENT.glob("*.json")):
        for locale, fields in json.loads(path.read_text(encoding="utf-8")).items():
            count += 1
            description = fields["description"].replace(
                "{price_disclosure}", fields["price_disclosure"]
            )
            for field, (low, high) in LIMITS.items():
                if locale in CJK_LOCALES and field != "keywords":
                    low = 12
                length = len(fields[field])
                if not low <= length <= high:
                    problems.append(f"{locale}: {field} {length}, want {low}-{high}")
            if len(description) > 4000:
                problems.append(f"{locale}: description {len(description)} > 4000")
            if len(fields["promotional_text"]) > 170:
                problems.append(f"{locale}: promo {len(fields['promotional_text'])} > 170")
            if len(fields["release_notes"]) > 4000:
                problems.append(f"{locale}: release notes too long")
            for url in (EULA, PRIVACY):
                if url not in description:
                    problems.append(f"{locale}: description missing {url}")
            if fields["price_disclosure"] not in description:
                problems.append(f"{locale}: description missing its price disclosure")
            if re.search(r"[$£€]\s?\d|\d+[.,]\d{2}\s*(?:per|/)", description):
                problems.append(f"{locale}: description hardcodes a price")
            tokens = [t.strip().lower().replace(" ", "") for t in re.split(r"[,，、]", fields["keywords"]) if t.strip()]
            if len(tokens) != len(set(tokens)):
                problems.append(f"{locale}: duplicate keyword token")
            indexed = {
                w.lower()
                for w in re.findall(r"[\w']+", f"{fields['name']} {fields['subtitle']}", re.UNICODE)
                if len(w) >= 2
            }
            repeated = sorted(t for t in tokens if t in indexed)
            if repeated:
                problems.append(f"{locale}: keywords repeat name/subtitle: {', '.join(repeated)}")
            for key, value in fields["products"].items():
                limit = 30 if key.endswith("_name") or key == "group" else 55
                if not value:
                    problems.append(f"{locale}: empty product field {key}")
                elif len(value) > limit:
                    problems.append(f"{locale}: product {key} {len(value)} > {limit}")
    for problem in problems:
        print(problem)
    print(f"{count} locales checked, {len(problems)} problems")
    return 1 if problems else 0


if __name__ == "__main__":
    sys.exit(main())
