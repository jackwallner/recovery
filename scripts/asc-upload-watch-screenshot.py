#!/usr/bin/env python3
"""Upload the current raw Apple Watch face capture to the draft version."""
from __future__ import annotations

import argparse
import hashlib
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib  # noqa: E402

BUNDLE = "com.jackwallner.recovery"
VERSION = "1.0.0"
DISPLAY_TYPE = "APP_WATCH_SERIES_4"


def upload_asset(
    client: asc_lib.ASCClient,
    screenshot_set_id: str,
    image: Path,
) -> dict:
    payload = image.read_bytes()
    created = client.post(
        "/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileSize": len(payload), "fileName": image.name},
                "relationships": {
                    "appScreenshotSet": {
                        "data": {"type": "appScreenshotSets", "id": screenshot_set_id}
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
    return client.patch(
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
    )["data"]


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument(
        "--screenshot",
        default="Screenshots/raw/06-watch.png",
        help="Raw Apple Watch face PNG captured from the simulator",
    )
    args = parser.parse_args()
    image = Path(args.screenshot)
    if not image.is_file():
        raise SystemExit(f"error: no screenshot at {image}")

    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app = asc_lib.find_app(client, BUNDLE)
    version = asc_lib.find_version_by_string(client, app["id"], VERSION)
    if not version:
        raise SystemExit(f"error: no ASC version {VERSION}")
    localizations = asc_lib.list_all(
        client, f"/appStoreVersions/{version['id']}/appStoreVersionLocalizations"
    )
    localization = next(
        (item for item in localizations if item["attributes"].get("locale") == "en-US"),
        None,
    )
    if not localization:
        raise SystemExit("error: no en-US version localization")

    sets = asc_lib.list_all(
        client, f"/appStoreVersionLocalizations/{localization['id']}/appScreenshotSets"
    )
    matching = [
        item
        for item in sets
        if item["attributes"].get("screenshotDisplayType") == DISPLAY_TYPE
    ]
    if matching:
        screenshot_set = matching[0]
        for duplicate in matching[1:]:
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

    expected_checksum = hashlib.md5(image.read_bytes()).hexdigest()
    existing = asc_lib.list_all(
        client, f"/appScreenshotSets/{screenshot_set['id']}/appScreenshots"
    )
    current = next(
        (
            item
            for item in existing
            if item["attributes"].get("fileName") == image.name
            and item["attributes"].get("sourceFileChecksum") == expected_checksum
        ),
        None,
    )
    if current and current["attributes"].get("assetDeliveryState", {}).get("state") == "COMPLETE":
        print(f"Apple Watch screenshot is current: {current['id']}")
        return
    for screenshot in existing:
        client.delete(f"/appScreenshots/{screenshot['id']}")

    uploaded = upload_asset(client, screenshot_set["id"], image)
    print(
        f"Uploaded {image} as {DISPLAY_TYPE}: "
        f"{uploaded['id']} ({expected_checksum})"
    )


if __name__ == "__main__":
    main()
