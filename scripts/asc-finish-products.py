#!/usr/bin/env python3
"""Attach one paywall review screenshot to every Recharge product."""
from __future__ import annotations

import argparse
import hashlib
import json
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib

BUNDLE = "com.jackwallner.recovery"
V2 = "https://api.appstoreconnect.apple.com/v2"


def upload_asset(
    client: asc_lib.ASCClient,
    resource_type: str,
    relationship_key: str,
    relationship_type: str,
    parent_id: str,
    image: Path,
) -> None:
    payload = image.read_bytes()
    created = client.post(
        f"/{resource_type}",
        {
            "data": {
                "type": resource_type,
                "attributes": {"fileSize": len(payload), "fileName": image.name},
                "relationships": {
                    relationship_key: {
                        "data": {"type": relationship_type, "id": parent_id}
                    }
                },
            }
        },
    )["data"]
    for operation in created["attributes"]["uploadOperations"]:
        chunk = payload[operation["offset"]:operation["offset"] + operation["length"]]
        request = urllib.request.Request(
            operation["url"],
            data=chunk,
            method=operation["method"],
            headers={item["name"]: item["value"] for item in operation["requestHeaders"]},
        )
        urllib.request.urlopen(request, timeout=300).read()
    client.patch(
        f"/{resource_type}/{created['id']}",
        {
            "data": {
                "type": resource_type,
                "id": created["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(payload).hexdigest(),
                },
            }
        },
    )


def iap_screenshot(client: asc_lib.ASCClient, iap_id: str) -> bool:
    request = urllib.request.Request(
        f"{V2}/inAppPurchases/{iap_id}/appStoreReviewScreenshot",
        headers={"Authorization": f"Bearer {client.token}"},
    )
    with urllib.request.urlopen(request, timeout=60) as response:
        return bool(json.loads(response.read()).get("data"))


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--screenshot",
        default="fastlane/screenshots/en-US/04-pro.png",
        help="PNG showing the purchase UI for App Review",
    )
    args = parser.parse_args()
    image = Path(args.screenshot)
    if not image.is_file():
        raise SystemExit(f"error: no screenshot at {image}")

    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app_id = asc_lib.find_app(client, BUNDLE)["id"]
    for group in asc_lib.list_all(client, f"/apps/{app_id}/subscriptionGroups"):
        subscriptions = asc_lib.list_all(client, f"/subscriptionGroups/{group['id']}/subscriptions")
        for subscription in subscriptions:
            product_id = subscription["attributes"]["productId"]
            try:
                existing = client.get(f"/subscriptions/{subscription['id']}/appStoreReviewScreenshot")
            except RuntimeError:
                existing = {}
            if existing.get("data"):
                print(f"{product_id}: screenshot exists")
                continue
            upload_asset(
                client,
                "subscriptionAppStoreReviewScreenshots",
                "subscription",
                "subscriptions",
                subscription["id"],
                image,
            )
            print(f"{product_id}: screenshot uploaded")

    for purchase in asc_lib.list_all(client, f"/apps/{app_id}/inAppPurchasesV2"):
        product_id = purchase["attributes"]["productId"]
        if iap_screenshot(client, purchase["id"]):
            print(f"{product_id}: screenshot exists")
            continue
        upload_asset(
            client,
            "inAppPurchaseAppStoreReviewScreenshots",
            "inAppPurchaseV2",
            "inAppPurchases",
            purchase["id"],
            image,
        )
        print(f"{product_id}: screenshot uploaded")


if __name__ == "__main__":
    main()
