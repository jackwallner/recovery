#!/usr/bin/env python3
"""Read-only App Store Connect release readiness audit for Recharge 1.0.0."""
from __future__ import annotations

import base64
import hashlib
import json
import os
import re
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib  # noqa: E402

BUNDLE = "com.jackwallner.recovery"
VERSION = os.environ.get("ASC_APP_VERSION", "1.0.0")
ROOT = Path(__file__).parent.parent
project_text = (ROOT / "project.yml").read_text()
project_build = re.search(r'CURRENT_PROJECT_VERSION:\s*"(\d+)"', project_text)
BUILD = os.environ.get("ASC_BUILD_NUMBER", project_build.group(1) if project_build else "")
PRODUCT_LOCALES = set(json.loads((Path(__file__).parent / "asc-supported-locales.json").read_text())["locales"])
LISTING_LOCALES = {
    path.parent.name for path in (ROOT / "fastlane" / "metadata").glob("*/description.txt")
}
SCREENSHOT_COUNT = len(list((ROOT / "fastlane" / "screenshots" / "en-US").glob("*.png")))
WATCH_SCREENSHOT = ROOT / "Screenshots" / "raw" / "06-watch.png"
WATCH_DISPLAY_TYPE = "APP_WATCH_SERIES_4"
WATCH_SCREENSHOT_CHECKSUM = hashlib.md5(WATCH_SCREENSHOT.read_bytes()).hexdigest()
REVIEW_SCREENSHOT = ROOT / "fastlane" / "screenshots" / "en-US" / "04-pro.png"
REVIEW_SCREENSHOT_CHECKSUM = hashlib.md5(REVIEW_SCREENSHOT.read_bytes()).hexdigest()
PRODUCTS = {
    "com.jackwallner.recovery.monthly",
    "com.jackwallner.recovery.yearly",
    "com.jackwallner.recovery.lifetime",
}
SUBSCRIPTION_PRICES = {
    "com.jackwallner.recovery.monthly": ("ONE_MONTH", "5.99"),
    "com.jackwallner.recovery.yearly": ("ONE_YEAR", "29.99"),
}
LIFETIME_PRICE = "59.99"


def check(condition: bool, message: str, failures: list[str]) -> None:
    print(("PASS" if condition else "FAIL") + f"  {message}")
    if not condition:
        failures.append(message)


def metadata(locale: str, field: str) -> str:
    return (ROOT / "fastlane" / "metadata" / locale / f"{field}.txt").read_text().strip()


def price_point_territory(identifier: str) -> str | None:
    try:
        padded = identifier + "=" * (-len(identifier) % 4)
        return json.loads(base64.b64decode(padded)).get("t")
    except (ValueError, json.JSONDecodeError):
        return None


def iap_screenshot(client: asc_lib.ASCClient, iap_id: str) -> dict | None:
    request = urllib.request.Request(
        f"https://api.appstoreconnect.apple.com/v2/inAppPurchases/{iap_id}/appStoreReviewScreenshot",
        headers={"Authorization": f"Bearer {client.token}"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return json.loads(response.read()).get("data")


def optional_data(client: asc_lib.ASCClient, path: str) -> dict | None:
    try:
        return client.get(path).get("data")
    except RuntimeError:
        return None


def main() -> None:
    failures: list[str] = []
    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app = asc_lib.find_app(client, BUNDLE)
    app_id = app["id"]
    attrs = app["attributes"]
    # Read the expected name off disk rather than hardcoding it, so renaming the
    # app is a one-file change and this check cannot silently go stale.
    check(attrs.get("name") == asc_lib.read_meta("en-US", "name"), "ASC app record name is current", failures)
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
    check(version["attributes"].get("copyright") == (ROOT / "fastlane/metadata/copyright.txt").read_text().strip(), "copyright is current", failures)

    build = client.get(f"/appStoreVersions/{version_id}/build").get("data")
    check(bool(build), "build attached", failures)
    if build:
        check(build["attributes"].get("version") == BUILD, f"build {BUILD} attached", failures)
        check(build["attributes"].get("processingState") == "VALID", "attached build is VALID", failures)
        check(not build["attributes"].get("expired"), "attached build is not expired", failures)
        valid_builds = [
            item for item in asc_lib.list_all(client, f"/builds?filter[app]={app_id}&limit=200")
            if item["attributes"].get("processingState") == "VALID" and not item["attributes"].get("expired")
        ]
        newest_build = max(
            (item["attributes"].get("version", "") for item in valid_builds),
            key=lambda value: int(value) if value.isdigit() else -1,
            default="",
        )
        check(build["attributes"].get("version") == newest_build, f"attached build is newest VALID build ({newest_build})", failures)

    version_locs = asc_lib.list_all(client, f"/appStoreVersions/{version_id}/appStoreVersionLocalizations")
    check({item["attributes"]["locale"] for item in version_locs} == LISTING_LOCALES, f"{len(LISTING_LOCALES)} version localizations", failures)
    version_fields = {
        "description": "description",
        "keywords": "keywords",
        "marketingUrl": "marketing_url",
        "promotionalText": "promotional_text",
        "supportUrl": "support_url",
    }
    for localization in version_locs:
        locale = localization["attributes"]["locale"]
        for asc_field, local_field in version_fields.items():
            check(
                localization["attributes"].get(asc_field) == metadata(locale, local_field),
                f"{locale} {local_field} matches canonical metadata",
                failures,
            )
    info = asc_lib.find_editable_app_info(client, app_id)
    check(bool(info), "editable app info exists", failures)
    if info:
        info_locs = asc_lib.list_all(client, f"/appInfos/{info['id']}/appInfoLocalizations")
        check({item["attributes"]["locale"] for item in info_locs} == LISTING_LOCALES, f"{len(LISTING_LOCALES)} app info localizations", failures)
        info_fields = {
            "name": "name",
            "subtitle": "subtitle",
            "privacyPolicyUrl": "privacy_url",
        }
        for localization in info_locs:
            locale = localization["attributes"]["locale"]
            for asc_field, local_field in info_fields.items():
                check(
                    localization["attributes"].get(asc_field) == metadata(locale, local_field),
                    f"{locale} {local_field} matches canonical metadata",
                    failures,
                )
        rating = client.get(f"/appInfos/{info['id']}/ageRatingDeclaration").get("data", {}).get("attributes", {})
        check(rating.get("healthOrWellnessTopics") is True, "health/wellness age-rating flag set", failures)
        check(rating.get("medicalOrTreatmentInformation") == "NONE", "no medical-treatment content declared", failures)
        primary = client.get(f"/appInfos/{info['id']}/primaryCategory").get("data", {})
        secondary = client.get(f"/appInfos/{info['id']}/secondaryCategory").get("data", {})
        check(primary.get("id") == "HEALTH_AND_FITNESS", "primary category is Health & Fitness", failures)
        check(secondary.get("id") == "SPORTS", "secondary category is Sports", failures)

    review = client.get(f"/appStoreVersions/{version_id}/appStoreReviewDetail").get("data")
    check(bool(review), "review information present", failures)
    if review:
        review_attrs = review["attributes"]
        check(not review_attrs.get("demoAccountRequired"), "no demo account required", failures)
        check(bool(review_attrs.get("notes")), "review notes present", failures)

    screenshot_counts: dict[str, int] = {}
    live_screenshots: list[dict] = []
    live_watch_screenshots: list[dict] = []
    for localization in version_locs:
        sets = asc_lib.list_all(client, f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets")
        for screenshot_set in sets:
            count = len(asc_lib.list_all(client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots"))
            if count:
                display_type = screenshot_set["attributes"]["screenshotDisplayType"]
                screenshot_counts[display_type] = screenshot_counts.get(display_type, 0) + count
                if display_type == "APP_IPHONE_67":
                    live_screenshots.extend(
                        asc_lib.list_all(client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots")
                    )
                if display_type == WATCH_DISPLAY_TYPE:
                    live_watch_screenshots.extend(
                        asc_lib.list_all(client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots")
                    )
    check(
        screenshot_counts == {
            "APP_IPHONE_67": SCREENSHOT_COUNT,
            WATCH_DISPLAY_TYPE: 1,
        },
        f"canonical iPhone and Apple Watch screenshot sets present ({screenshot_counts})",
        failures,
    )
    expected_paths = sorted((ROOT / "fastlane" / "screenshots" / "en-US").glob("*.png"))
    expected_names = [path.name for path in expected_paths]
    expected_checksums = [hashlib.md5(path.read_bytes()).hexdigest() for path in expected_paths]
    live_attrs = [item["attributes"] for item in live_screenshots]
    check([item.get("fileName") for item in live_attrs] == expected_names, "screenshot order and filenames are current", failures)
    check([item.get("sourceFileChecksum") for item in live_attrs] == expected_checksums, "screenshot checksums match local artwork", failures)
    check(
        all(item.get("imageAsset", {}).get("width") == 1320 and item.get("imageAsset", {}).get("height") == 2868 for item in live_attrs),
        "screenshots are 1320x2868",
        failures,
    )
    check(
        all(item.get("assetDeliveryState", {}).get("state") == "COMPLETE" for item in live_attrs),
        "screenshot processing is complete",
        failures,
    )
    watch_attrs = [item["attributes"] for item in live_watch_screenshots]
    check(
        [item.get("fileName") for item in watch_attrs] == [WATCH_SCREENSHOT.name],
        "Apple Watch screenshot is current",
        failures,
    )
    check(
        [item.get("sourceFileChecksum") for item in watch_attrs] == [WATCH_SCREENSHOT_CHECKSUM],
        "Apple Watch screenshot checksum matches the raw face capture",
        failures,
    )
    check(
        all(
            item.get("imageAsset", {}).get("width") == 368
            and item.get("imageAsset", {}).get("height") == 448
            for item in watch_attrs
        ),
        "Apple Watch screenshot is 368x448",
        failures,
    )
    check(
        all(item.get("assetDeliveryState", {}).get("state") == "COMPLETE" for item in watch_attrs),
        "Apple Watch screenshot processing is complete",
        failures,
    )

    all_products: set[str] = set()
    for group in asc_lib.list_all(client, f"/apps/{app_id}/subscriptionGroups"):
        group_locs = asc_lib.list_all(client, f"/subscriptionGroups/{group['id']}/subscriptionGroupLocalizations")
        check({item["attributes"]["locale"] for item in group_locs} == PRODUCT_LOCALES, "subscription group localized in all locales", failures)
        for subscription in asc_lib.list_all(client, f"/subscriptionGroups/{group['id']}/subscriptions"):
            product_id = subscription["attributes"]["productId"]
            all_products.add(product_id)
            check(subscription["attributes"].get("state") == "READY_TO_SUBMIT", f"{product_id} READY_TO_SUBMIT", failures)
            expected_period, expected_price = SUBSCRIPTION_PRICES[product_id]
            check(subscription["attributes"].get("subscriptionPeriod") == expected_period, f"{product_id} period is current", failures)
            check(bool(subscription["attributes"].get("reviewNote")), f"{product_id} review note present", failures)
            locs = asc_lib.list_all(client, f"/subscriptions/{subscription['id']}/subscriptionLocalizations")
            check({item["attributes"]["locale"] for item in locs} == PRODUCT_LOCALES, f"{product_id} localized in all locales", failures)
            prices = asc_lib.list_all(client, f"/subscriptions/{subscription['id']}/prices?limit=200")
            offers = asc_lib.list_all(client, f"/subscriptions/{subscription['id']}/introductoryOffers?limit=200")
            check(bool(prices), f"{product_id} pricing set ({len(prices)} scheduled prices)", failures)
            usa_schedule = client.get(
                f"/subscriptions/{subscription['id']}/prices?filter[territory]=USA&include=subscriptionPricePoint&limit=200"
            )
            price_points = {
                item["id"]: item["attributes"].get("customerPrice")
                for item in usa_schedule.get("included", [])
                if item.get("type") == "subscriptionPricePoints"
            }
            new_customer_prices = [
                (
                    item["attributes"].get("startDate") or "",
                    price_points.get(
                        (item.get("relationships", {}).get("subscriptionPricePoint", {}).get("data") or {}).get("id")
                    ),
                )
                for item in usa_schedule.get("data", [])
                if not item["attributes"].get("preserved")
            ]
            current_usa_price = max(new_customer_prices, default=("", None))[1]
            check(current_usa_price == expected_price, f"{product_id} new-customer USA price is ${expected_price}", failures)
            check(len(offers) >= 170, f"{product_id} one-week trials ({len(offers)})", failures)
            check(bool(optional_data(client, f"/subscriptions/{subscription['id']}/subscriptionAvailability")), f"{product_id} availability set", failures)
            review_screenshot = optional_data(client, f"/subscriptions/{subscription['id']}/appStoreReviewScreenshot")
            check(bool(review_screenshot), f"{product_id} review screenshot set", failures)
            if review_screenshot:
                check(
                    review_screenshot["attributes"].get("sourceFileChecksum") == REVIEW_SCREENSHOT_CHECKSUM,
                    f"{product_id} review screenshot matches current paywall",
                    failures,
                )

    for iap in asc_lib.list_all(client, f"/apps/{app_id}/inAppPurchasesV2"):
        product_id = iap["attributes"]["productId"]
        all_products.add(product_id)
        check(iap["attributes"].get("state") == "READY_TO_SUBMIT", f"{product_id} READY_TO_SUBMIT", failures)
        check(iap["attributes"].get("inAppPurchaseType") == "NON_CONSUMABLE", f"{product_id} is non-consumable", failures)
        check(bool(iap["attributes"].get("reviewNote")), f"{product_id} review note present", failures)
        old_api = asc_lib.API
        try:
            asc_lib.API = "https://api.appstoreconnect.apple.com/v2"
            locs = asc_lib.list_all(client, f"/inAppPurchases/{iap['id']}/inAppPurchaseLocalizations")
        finally:
            asc_lib.API = old_api
        check({item["attributes"]["locale"] for item in locs} == PRODUCT_LOCALES, f"{product_id} localized in all locales", failures)
        review_screenshot = iap_screenshot(client, iap["id"])
        check(bool(review_screenshot), f"{product_id} review screenshot set", failures)
        if review_screenshot:
            check(
                review_screenshot["attributes"].get("sourceFileChecksum") == REVIEW_SCREENSHOT_CHECKSUM,
                f"{product_id} review screenshot matches current paywall",
                failures,
            )
        manual_prices = client.get(
            f"/inAppPurchasePriceSchedules/{iap['id']}/manualPrices?include=inAppPurchasePricePoint&limit=200"
        )
        usa_points = [
            item for item in manual_prices.get("included", [])
            if item.get("type") == "inAppPurchasePricePoints" and price_point_territory(item["id"]) == "USA"
        ]
        check(
            len(usa_points) == 1 and usa_points[0]["attributes"].get("customerPrice") == LIFETIME_PRICE,
            f"{product_id} USA price is ${LIFETIME_PRICE}",
            failures,
        )

    check(all_products == PRODUCTS, "expected monthly, yearly, and lifetime products only", failures)
    availability = client.get(f"/apps/{app_id}/appAvailabilityV2").get("data", {})
    check(availability.get("attributes", {}).get("availableInNewTerritories") is True, "available in new territories", failures)
    old_api = asc_lib.API
    try:
        asc_lib.API = "https://api.appstoreconnect.apple.com/v2"
        territories = asc_lib.list_all(
            client,
            f"/appAvailabilities/{availability['id']}/territoryAvailabilities?limit=200",
        )
    finally:
        asc_lib.API = old_api
    check(len(territories) == 175 and all(item["attributes"].get("available") for item in territories), "available in all 175 territories", failures)

    if failures:
        print(f"\nNot ready: {len(failures)} failed check(s)", file=sys.stderr)
        raise SystemExit(1)
    print("\nAutomated ASC release checks passed.")
    print("MANUAL  Confirm the Regulated Medical Device declaration in the App Store Connect UI before submission.")


if __name__ == "__main__":
    main()
