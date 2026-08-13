#!/usr/bin/env python3
"""Idempotently prepare Recharge 1.0.0 metadata, rating, IAP, and review info."""
from __future__ import annotations

import json
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE = "com.jackwallner.recovery"
PRODUCT_ID = "com.jackwallner.recovery.lifetime"
# App Store Connect's internal reference name is immutable after creation.
# The localized customer-facing name is Recharge Pro Lifetime.
PRODUCT_REFERENCE_NAME = "Recharge Pro Lifetime"
PRODUCT_DESCRIPTION = "Unlock Recharge Pro forever. One payment."
PRICE = "59.99"

# Kept in step with the REVIEW_NOTES heredoc in fastlane/Fastfile.
REVIEW_NOTES = """Recharge shows a recovery-time countdown after every qualifying workout, and a clear Ready state when it expires.

No account or login is required. On first launch, connect Apple Health. The app requests read access to Workouts, Heart Rate, Resting Heart Rate, Heart Rate Variability, Sleep, Active Energy, Date of Birth, and Biological Sex, and never writes Health data. Date of Birth and Biological Sex set the heart-rate range used to measure session intensity. If the review device has no recorded workout, the app shows an explicit empty state rather than a number. Recharge presents a cardiovascular training estimate only; it makes no diagnostic, treatment, or injury-prevention claim, and a disclaimer to that effect is shown on the main screen.

Today shows the current countdown with the reasoning behind the estimate, History lists every scored session with the load and heart-rate coverage behind it, and Settings exposes the Watch complication style. The Apple Watch app and its complications mirror the same countdown.

Recharge Pro offers monthly and yearly auto-renewable subscriptions with a 7-day free trial for eligible new subscribers, plus an optional one-time lifetime non-consumable. Price, billing period, renewal behavior, restore, terms, and privacy all appear at the purchase point. The app does not use non-exempt encryption."""


def main() -> None:
    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app = asc_lib.find_app(client, BUNDLE)
    app_id = app["id"]
    print(f"app {app_id}")

    client.patch(
        f"/apps/{app_id}",
        {
            "data": {
                "type": "apps",
                "id": app_id,
                "attributes": {"contentRightsDeclaration": "DOES_NOT_USE_THIRD_PARTY_CONTENT"},
            }
        },
    )
    print("content rights declared")

    info = asc_lib.find_editable_app_info(client, app_id)
    if not info:
        raise SystemExit("error: editable appInfo not found")

    client.patch(
        f"/appInfos/{info['id']}",
        {
            "data": {
                "type": "appInfos",
                "id": info["id"],
                "relationships": {
                    "primaryCategory": {"data": {"type": "appCategories", "id": "HEALTH_AND_FITNESS"}},
                    "secondaryCategory": {"data": {"type": "appCategories", "id": "SPORTS"}},
                },
            }
        },
    )
    print("categories set")

    declaration = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration").get("data")
    if declaration:
        attrs = {
            "advertising": False,
            "alcoholTobaccoOrDrugUseOrReferences": "NONE",
            "contests": "NONE",
            "gambling": False,
            "gamblingSimulated": "NONE",
            "gunsOrOtherWeapons": "NONE",
            "healthOrWellnessTopics": True,
            "lootBox": False,
            "medicalOrTreatmentInformation": "NONE",
            "messagingAndChat": False,
            "parentalControls": False,
            "profanityOrCrudeHumor": "NONE",
            "ageAssurance": False,
            "sexualContentGraphicAndNudity": "NONE",
            "sexualContentOrNudity": "NONE",
            "horrorOrFearThemes": "NONE",
            "matureOrSuggestiveThemes": "NONE",
            "unrestrictedWebAccess": False,
            "userGeneratedContent": False,
            "violenceCartoonOrFantasy": "NONE",
            "violenceRealisticProlongedGraphicOrSadistic": "NONE",
            "violenceRealistic": "NONE",
        }
        client.patch(
            f"/ageRatingDeclarations/{declaration['id']}",
            {"data": {"type": "ageRatingDeclarations", "id": declaration["id"], "attributes": attrs}},
        )
        print("age rating set")

    territories = [item["id"] for item in asc_lib.list_all(client, "/territories?limit=200")]
    iaps = asc_lib.list_all(client, f"/apps/{app_id}/inAppPurchasesV2")
    iap = next((item for item in iaps if item["attributes"].get("productId") == PRODUCT_ID), None)
    if not iap:
        asc_lib.API = "https://api.appstoreconnect.apple.com/v2"
        iap = client.post(
            "/inAppPurchases",
            {
                "data": {
                    "type": "inAppPurchases",
                    "attributes": {
                        "name": PRODUCT_REFERENCE_NAME,
                        "productId": PRODUCT_ID,
                        "inAppPurchaseType": "NON_CONSUMABLE",
                        "reviewNote": "One-time purchase that unlocks Recharge Pro forever.",
                    },
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        )["data"]
        asc_lib.API = "https://api.appstoreconnect.apple.com/v1"
        print("lifetime IAP created")
    iap_id = iap["id"]

    asc_lib.API = "https://api.appstoreconnect.apple.com/v2"
    existing_locs = asc_lib.list_all(client, f"/inAppPurchases/{iap_id}/inAppPurchaseLocalizations")
    asc_lib.API = "https://api.appstoreconnect.apple.com/v1"
    locales = json.loads((Path(__file__).parent / "asc-supported-locales.json").read_text())["locales"]
    localization_by_locale = {item["attributes"].get("locale"): item for item in existing_locs}
    for locale in locales:
        product_path = asc_lib.META / locale / "products.json"
        product = json.loads(product_path.read_text()) if product_path.exists() else {}
        name = product.get("lifetime_name") or PRODUCT_REFERENCE_NAME
        description = product.get("lifetime_desc") or PRODUCT_DESCRIPTION
        existing = localization_by_locale.get(locale)
        if existing:
            attrs = existing.get("attributes", {})
            if attrs.get("name") != name or attrs.get("description") != description:
                client.patch(
                    f"/inAppPurchaseLocalizations/{existing['id']}",
                    {
                        "data": {
                            "type": "inAppPurchaseLocalizations",
                            "id": existing["id"],
                            "attributes": {"name": name, "description": description},
                        }
                    },
                )
            continue
        client.post(
            "/inAppPurchaseLocalizations",
            {
                "data": {
                    "type": "inAppPurchaseLocalizations",
                    "attributes": {"locale": locale, "name": name, "description": description},
                    "relationships": {"inAppPurchaseV2": {"data": {"type": "inAppPurchases", "id": iap_id}}},
                }
            },
        )
    print(f"IAP localizations set for {len(locales)} locales")

    try:
        asc_lib.API = "https://api.appstoreconnect.apple.com/v2"
        client.get(f"/inAppPurchases/{iap_id}/iapPriceSchedule")
        schedule_exists = True
    except RuntimeError:
        schedule_exists = False
    try:
        points = asc_lib.list_all(client, f"/inAppPurchases/{iap_id}/pricePoints?filter[territory]=USA&limit=200")
        point = next((item for item in points if item["attributes"].get("customerPrice") == PRICE), None)
        if not point:
            raise SystemExit(f"error: USA price point {PRICE} unavailable")
        if schedule_exists:
            print("IAP price schedule already exists")
        else:
            asc_lib.API = "https://api.appstoreconnect.apple.com/v1"
            client.post(
                "/inAppPurchasePriceSchedules",
                {
                    "data": {
                        "type": "inAppPurchasePriceSchedules",
                        "relationships": {
                            "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                            "baseTerritory": {"data": {"type": "territories", "id": "USA"}},
                            "manualPrices": {"data": [{"type": "inAppPurchasePrices", "id": "${price0}"}]},
                        },
                    },
                    "included": [
                        {
                            "type": "inAppPurchasePrices",
                            "id": "${price0}",
                            "attributes": {"startDate": None},
                            "relationships": {
                                "inAppPurchasePricePoint": {"data": {"type": "inAppPurchasePricePoints", "id": point["id"]}}
                            },
                        }
                    ],
                },
            )
            print(f"IAP price set ${PRICE}")
    finally:
        asc_lib.API = "https://api.appstoreconnect.apple.com/v1"

    try:
        asc_lib.API = "https://api.appstoreconnect.apple.com/v2"
        client.get(f"/inAppPurchases/{iap_id}/inAppPurchaseAvailability")
        print("IAP availability exists")
    except RuntimeError:
        asc_lib.API = "https://api.appstoreconnect.apple.com/v1"
        client.post(
            "/inAppPurchaseAvailabilities",
            {
                "data": {
                    "type": "inAppPurchaseAvailabilities",
                    "attributes": {"availableInNewTerritories": True},
                    "relationships": {
                        "inAppPurchase": {"data": {"type": "inAppPurchases", "id": iap_id}},
                        "availableTerritories": {"data": [{"type": "territories", "id": item} for item in territories]},
                    },
                }
            },
        )
        print(f"IAP available in {len(territories)} territories")
    finally:
        asc_lib.API = "https://api.appstoreconnect.apple.com/v1"

    version = asc_lib.find_editable_version(client, app_id)
    if not version:
        raise SystemExit("error: editable draft version not found")
    client.patch(
        f"/appStoreVersions/{version['id']}",
        {
            "data": {
                "type": "appStoreVersions",
                "id": version["id"],
                "attributes": {"copyright": "2026 Jack Wallner"},
            }
        },
    )
    detail = client.get(f"/appStoreVersions/{version['id']}/appStoreReviewDetail").get("data")
    attrs = {
        "contactFirstName": "Jack",
        "contactLastName": "Wallner",
        "contactPhone": "+1 425 753 3411",
        "contactEmail": "jackwallner@gmail.com",
        "demoAccountRequired": False,
        "notes": REVIEW_NOTES,
    }
    if detail:
        client.patch(
            f"/appStoreReviewDetails/{detail['id']}",
            {"data": {"type": "appStoreReviewDetails", "id": detail["id"], "attributes": attrs}},
        )
    else:
        client.post(
            "/appStoreReviewDetails",
            {
                "data": {
                    "type": "appStoreReviewDetails",
                    "attributes": attrs,
                    "relationships": {"appStoreVersion": {"data": {"type": "appStoreVersions", "id": version["id"]}}},
                }
            },
        )
    print("review information set")


if __name__ == "__main__":
    main()
