#!/usr/bin/env python3
"""Push fastlane/metadata/<locale>/products.json to every ASC product localization.

`asc-setup-subscriptions.py` and `asc-setup-release.py` also write these, but
they create prices, availability, and introductory offers on the way past, which
is not what you want when the only thing that changed is customer-facing copy.
This does the localizations and nothing else.

Products attached to a review submission are locked
(ENTITY_ERROR.ATTRIBUTE.INVALID.UNMODIFIABLE). Delete the submission items
first, run this, then re-add the products for review.
"""
from __future__ import annotations

import argparse
import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE = "com.jackwallner.recovery"
V2 = "https://api.appstoreconnect.apple.com/v2"


def product_copy(locale: str) -> dict:
    path = asc_lib.META / locale / "products.json"
    if not path.exists():
        raise SystemExit(f"error: no products.json for {locale}")
    return json.loads(path.read_text(encoding="utf-8"))


def sync(
    client: asc_lib.ASCClient,
    resource: str,
    parent_path: str,
    relationship: str,
    parent_type: str,
    parent_id: str,
    fields: dict[str, tuple[str, str]],
    locales: list[str],
    dry_run: bool,
) -> None:
    """`fields` maps locale -> (name, description); description None omits it."""
    existing = {
        item["attributes"]["locale"]: item
        for item in asc_lib.list_all(client, parent_path)
    }
    changed = 0
    for locale in locales:
        name, description = fields[locale]
        attributes = {"name": name}
        if description is not None:
            attributes["description"] = description
        current = existing.get(locale)
        if current:
            live = current["attributes"]
            if all(live.get(key) == value for key, value in attributes.items()):
                continue
            changed += 1
            if dry_run:
                print(f"  {locale}: {live.get('name')!r} -> {name!r}")
                continue
            client.patch(
                f"/{resource}/{current['id']}",
                {"data": {"type": resource, "id": current["id"], "attributes": attributes}},
            )
        else:
            changed += 1
            if dry_run:
                print(f"  {locale}: create {name!r}")
                continue
            client.post(
                f"/{resource}",
                {
                    "data": {
                        "type": resource,
                        "attributes": {"locale": locale, **attributes},
                        "relationships": {
                            relationship: {"data": {"type": parent_type, "id": parent_id}}
                        },
                    }
                },
            )
    print(f"  {changed} of {len(locales)} localizations {'would change' if dry_run else 'updated'}")


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--dry-run", action="store_true")
    args = parser.parse_args()

    locales = json.loads(
        (Path(__file__).parent / "asc-supported-locales.json").read_text()
    )["locales"]
    copy = {locale: product_copy(locale) for locale in locales}

    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app_id = asc_lib.find_app(client, BUNDLE)["id"]

    for group in asc_lib.list_all(client, f"/apps/{app_id}/subscriptionGroups"):
        print(f"group {group['attributes']['referenceName']}")
        sync(
            client,
            "subscriptionGroupLocalizations",
            f"/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations",
            "subscriptionGroup",
            "subscriptionGroups",
            group["id"],
            {locale: (copy[locale]["group"], None) for locale in locales},
            locales,
            args.dry_run,
        )
        for subscription in asc_lib.list_all(client, f"/subscriptionGroups/{group['id']}/subscriptions"):
            product_id = subscription["attributes"]["productId"]
            prefix = "monthly" if product_id.endswith(".monthly") else "yearly"
            print(f"{product_id}")
            sync(
                client,
                "subscriptionLocalizations",
                f"/subscriptions/{subscription['id']}/subscriptionLocalizations",
                "subscription",
                "subscriptions",
                subscription["id"],
                {
                    locale: (copy[locale][f"{prefix}_name"], copy[locale][f"{prefix}_desc"])
                    for locale in locales
                },
                locales,
                args.dry_run,
            )

    for purchase in asc_lib.list_all(client, f"/apps/{app_id}/inAppPurchasesV2"):
        print(purchase["attributes"]["productId"])
        # Only the read side of IAP localizations lives on /v2; the write side is
        # /v1, which is why the base URL is swapped for the listing alone.
        original = asc_lib.API
        try:
            asc_lib.API = V2
            existing = asc_lib.list_all(client, f"/inAppPurchases/{purchase['id']}/inAppPurchaseLocalizations")
        finally:
            asc_lib.API = original
        by_locale = {item["attributes"]["locale"]: item for item in existing}
        changed = 0
        for locale in locales:
            name = copy[locale]["lifetime_name"]
            description = copy[locale]["lifetime_desc"]
            current = by_locale.get(locale)
            if current and current["attributes"].get("name") == name and current["attributes"].get("description") == description:
                continue
            changed += 1
            if args.dry_run:
                print(f"  {locale}: {(current or {}).get('attributes', {}).get('name')!r} -> {name!r}")
                continue
            if current:
                client.patch(
                    f"/inAppPurchaseLocalizations/{current['id']}",
                    {"data": {"type": "inAppPurchaseLocalizations", "id": current["id"],
                              "attributes": {"name": name, "description": description}}},
                )
            else:
                client.post(
                    "/inAppPurchaseLocalizations",
                    {"data": {"type": "inAppPurchaseLocalizations",
                              "attributes": {"locale": locale, "name": name, "description": description},
                              "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": purchase["id"]}}}}},
                )
        print(f"  {changed} of {len(locales)} localizations {'would change' if args.dry_run else 'updated'}")


if __name__ == "__main__":
    main()
