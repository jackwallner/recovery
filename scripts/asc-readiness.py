#!/usr/bin/env python3
"""Read-only App Store Connect release readiness audit for Recharge 1.0.0."""
from __future__ import annotations

import json
import os
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib  # noqa: E402

BUNDLE = "com.jackwallner.recovery"
VERSION = os.environ.get("ASC_APP_VERSION", "1.0.0")
BUILD = os.environ.get("ASC_BUILD_NUMBER", "3")
LOCALES = set(json.loads((Path(__file__).parent / "asc-supported-locales.json").read_text())["locales"])
PRODUCTS = {
    "com.jackwallner.recovery.monthly",
    "com.jackwallner.recovery.yearly",
    "com.jackwallner.recovery.lifetime",
}


def check(condition: bool, message: str, failures: list[str]) -> None:
    print(("PASS" if condition else "FAIL") + f"  {message}")
    if not condition:
        failures.append(message)


def iap_screenshot(client: asc_lib.ASCClient, iap_id: str) -> bool:
    request = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot",
        headers={"Authorization": f"Bearer {client.token}"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return bool(json.loads(response.read()).get("data"))


def main() -> None:
    failures: list[str] = []
    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app = asc_lib.find_app(client, BUNDLE)
    app_id = app["id"]
    attrs = app["attributes"]
    check(attrs.get("contentRightsDeclaration") == "DOES_NOT_USE_THIRD_PARTY_CONTENT", "content rights declared", failures)

    version = asc_lib.find_version_by_string(client, app_id, VERSION)
    check(bool(version), f"version {VERSION} exists", failures)
    if not version:
        raise SystemExit(1)
    version_id = version["id"]
    # PREPARE_FOR_SUBMISSION before submitting; READY_FOR_REVIEW once the
    # version has been added to a review submission. Both are healthy.
    check(
        version["attributes"].get("appStoreState") in ("PREPARE_FOR_SUBMISSION", "READY_FOR_REVIEW"),
        "version is editable or queued for review",
        failures,
    )

    build = client.get(f"/appStoreVersions/{version_id}/build").get("data")
    check(bool(build), "build attached", failures)
    if build:
        check(build["attributes"].get("version") == BUILD, f"build {BUILD} attached", failures)
        check(build["attributes"].get("processingState") == "VALID", "attached build is VALID", failures)
        check(not build["attributes"].get("expired"), "attached build is not expired", failures)

    version_locs = asc_lib.list_all(client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    check({item["attributes"]["locale"] for item in version_locs} == LOCALES, f"{len(LOCALES)} version localizations", failures)
    info = asc_lib.find_editable_app_info(client, app_id)
    check(bool(info), "editable app info exists", failures)
    if info:
        info_locs = asc_lib.list_all(client, f"/appInfos/{info['id']}/appInfoLocalizations")
        check({item["attributes"]["locale"] for item in info_locs} == LOCALES, f"{len(LOCALES)} app info localizations", failures)
        rating = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration").get("data", {}).get("attributes", {})
        check(rating.get("healthOrWellnessTopics") is True, "health/wellness age-rating flag set", failures)
        check(rating.get("medicalOrTreatmentInformation") == "NONE", "no medical-treatment content declared", failures)

    review = client.get(f"/appStoreVersions/{version_id}/appStoreReviewDetail").get("data")
    check(bool(review), "review information present", failures)
    if review:
        review_attrs = review["attributes"]
        check(not review_attrs.get("demoAccountRequired"), "no demo account required", failures)
        check(bool(review_attrs.get("notes")), "review notes present", failures)

    screenshots = 0
    for localization in version_locs:
        sets = asc_lib.list_all(client, f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets")
        for screenshot_set in sets:
            screenshots += len(asc_lib.list_all(client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots"))
    # The capture script supplies five iPhone 6.7" shots for the first listing.
    check(screenshots == 5, f"canonical screenshot set present ({screenshots})", failures)

    all_products: set[str] = set()
    for group in asc_lib.list_all(client, f"/apps/{app_id}/subscriptionGroups"):
        group_locs = asc_lib.list_all(client, f"/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations")
        check({item["attributes"]["locale"] for item in group_locs} == LOCALES, "subscription group localized in all locales", failures)
        for subscription in asc_lib.list_all(client, f"/subscriptionGroups/{group['id']}/subscriptions"):
            product_id = subscription["attributes"]["productId"]
            all_products.add(product_id)
            check(subscription["attributes"].get("state") == "READY_TO_SUBMIT", f"{product_id} READY_TO_SUBMIT", failures)
            locs = asc_lib.list_all(client, f"/subscriptions/{subscription['id']}/subscriptionLocalizations")
            check({item["attributes"]["locale"] for item in locs} == LOCALES, f"{product_id} localized in all locales", failures)
            prices = asc_lib.list_all(client, f"/subscriptions/{subscription['id']}/prices?limit=200")
            offers = asc_lib.list_all(client, f"/subscriptions/{subscription['id']}/introductoryOffers?limit=200")
            check(len(prices) >= 170, f"{product_id} territory prices ({len(prices)})", failures)
            check(len(offers) >= 170, f"{product_id} one-week trials ({len(offers)})", failures)
            check(bool(client.get(f"/subscriptions/{subscription['id']}/subscriptionAvailability").get("data")), f"{product_id} availability set", failures)
            check(bool(client.get(f"/subscriptions/{subscription['id']}/appStoreReviewScreenshot").get("data")), f"{product_id} review screenshot set", failures)

    for iap in asc_lib.list_all(client, f"/apps/{app_id}/inAppPurchasesV2"):
        product_id = iap["attributes"]["productId"]
        all_products.add(product_id)
        check(iap["attributes"].get("state") == "READY_TO_SUBMIT", f"{product_id} READY_TO_SUBMIT", failures)
        old_api = asc_lib.API
        try:
            asc_lib.API = "https://api.appstoreconnect.apple.com/v2"
            locs = asc_lib.list_all(client, f"/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations")
        finally:
            asc_lib.API = old_api
        check({item["attributes"]["locale"] for item in locs} == LOCALES, f"{product_id} localized in all locales", failures)
        check(iap_screenshot(client, iap["id"]), f"{product_id} review screenshot set", failures)

    check(all_products == PRODUCTS, "expected monthly, yearly, and lifetime products only", failures)
    availability = client.get(f"/apps/{app_id}/appAvailabilityV2").get("data", {})
    check(availability.get("attributes", {}).get("availableInNewTerritories") is True, "available in new territories", failures)

    if failures:
        print(f"\nNot ready: {len(failures)} failed check(s)", file=sys.stderr)
        raise SystemExit(1)
    print("\nASC release is ready for the manual Submit for Review action.")


if __name__ == "__main__":
    main()
