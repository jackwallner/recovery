#!/usr/bin/env python3
"""Replace the draft's iPhone 6.9-inch screenshots with the local set."""
from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib  # noqa: E402

BUNDLE = "com.jackwallner.recovery"
VERSION = "1.0.0"
LOCALE = "en-US"
DISPLAY_TYPE = "APP_IPHONE_67"
SCREENSHOTS = Path(__file__).parent.parent / "fastlane/screenshots/en-US"


def upload_asset(client: asc_lib.ASCClient, set_id: str, image: Path) -> None:
    payload = image.read_bytes()
    created = client.post(
        "/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileSize": len(payload), "fileName": image.name},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": set_id}
                    }
                },
            }
        },
    )["data"]
    for operation in created["attributes"]["uploadOperations"]:
        chunk = payload[operation["offset"] : operation["offset"] + operation["length"]]
        request = urllib.request.Request(
            operation["url"],
            data=chunk,
            method=operation["method"],
            headers={item["name"]: item["value"] for item in operation["requestHeaders"]},
        )
        urllib.request.urlopen(request, timeout=300).read()
    client.patch(
        f"/appScreenshots/{created['id']}",
        {
            "data": {
                "type": "appScreenshots",
                "id": created["id"],
                "attributes": {
                    "uploaded": True,
                    "sourceFileChecksum": hashlib.md5(payload).hexdigest(),
                },
            }
        },
    )


def main() -> None:
    images = sorted(SCREENSHOTS.glob("*.png"))
    if not images:
        raise SystemExit(f"error: no screenshots in {SCREENSHOTS}")

    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app = asc_lib.find_app(client, BUNDLE)
    version = asc_lib.find_version_by_string(client, app["id"], VERSION)
    if not version:
        raise SystemExit(f"error: version {VERSION} not found")
    localizations = asc_lib.list_all(
        client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations"
    )
    localization = next(
        (item for item in localizations if item["attributes"].get("locale") == LOCALE),
        None,
    )
    if not localization:
        raise SystemExit(f"error: no {LOCALE} version localization")

    sets = [
        item
        for item in asc_lib.list_all(
            client, f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets"
        )
        if item["attributes"].get("screenshotDisplayType") == DISPLAY_TYPE
    ]
    if sets:
        screenshot_set = sets[0]
        for duplicate in sets[1:]:
            for screenshot in asc_lib.list_all(
                client, f"/appScreenshotSets/{duplicate['id']}/appScreenshots"
            ):
                client.delete(f"/appScreenshots/{screenshot['id']}")
            client.delete(f"/appScreenshotSets/{duplicate['id']}")
    else:
        screenshot_set = client.post(
            "/appScreenshotSets",
            {
                "data": {
                    "type": "appScreenshotSets",
                    "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                    "relationships": {
                        "appStoreVersionLocalization": {
                            "data": {
                                "type": "appStoreVersionLocalizations",
                                "id": localization["id"],
                            }
                        }
                    },
                }
            },
        )["data"]

    for screenshot in asc_lib.list_all(
        client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots"
    ):
        client.delete(f"/appScreenshots/{screenshot['id']}")

    for image in images:
        upload_asset(client, screenshot_set["id"], image)
        print(f"uploaded {image.name}")

    current = asc_lib.list_all(
        client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots"
    )
    names = [item["attributes"].get("fileName") for item in current]
    expected = [image.name for image in images]
    if names != expected:
        raise SystemExit(f"error: live screenshot order {names!r}, expected {expected!r}")
    print(f"iPhone screenshot set is current: {len(current)} images")


if __name__ == "__main__":
    main()
