#!/usr/bin/env python3
"""Replace the editable draft's 13-inch iPad screenshots with a composed set.

    python3 scripts/asc-upload-ipad-screenshots.py <composed-dir>

`<composed-dir>/<locale>/NN-name.png` comes from `compose-ipad-screenshots.py`.
Only locales that have a folder are touched, and only the draft version. It
never submits anything.
"""
from __future__ import annotations

import hashlib
import sys
import urllib.request
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib  # noqa: E402

BUNDLE = "com.jackwallner.recovery"
DISPLAY_TYPE = "APP_IPAD_PRO_3GEN_129"


def upload_asset(client: asc_lib.ASCClient, set_id: str, image: Path) -> None:
    payload = image.read_bytes()
    created = client.post(
        "/appScreenshots",
        {
            "data": {
                "type": "appScreenshots",
                "attributes": {"fileSize": len(payload), "fileName": image.name},
                "relationships": {"appScreenshotSet": {"data": {"type": "appScreenshotSets", "id": set_id}}},
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
                "attributes": {"uploaded": True, "sourceFileChecksum": hashlib.md5(payload).hexdigest()},
            }
        },
    )


def screenshot_set(client: asc_lib.ASCClient, localization_id: str) -> dict:
    sets = [
        item
        for item in asc_lib.list_all(client, f"/appStoreVersionLocalizations/{localization_id}/appScreenshotSets")
        if item["attributes"].get("screenshotDisplayType") == DISPLAY_TYPE
    ]
    if sets:
        return sets[0]
    return client.post(
        "/appScreenshotSets",
        {
            "data": {
                "type": "appScreenshotSets",
                "attributes": {"screenshotDisplayType": DISPLAY_TYPE},
                "relationships": {
                    "appStoreVersionLocalization": {"data": {"type": "appStoreVersionLocalizations", "id": localization_id}}
                },
            }
        },
    )["data"]


def main() -> None:
    if len(sys.argv) != 2:
        raise SystemExit(__doc__)
    base = Path(sys.argv[1])
    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app = asc_lib.find_app(client, BUNDLE)
    draft = asc_lib.find_editable_version(client, app["id"])
    if not draft:
        raise SystemExit("error: no editable version; run scripts/asc-ensure-draft-version.py")
    version = draft["attributes"]["versionString"]
    localizations = {
        item["attributes"]["locale"]: item
        for item in asc_lib.list_all(client, f"/appStoreVersions/{draft['id']}/appStoreVersionLocalizations?limit=200")
    }
    for folder in sorted(p for p in base.iterdir() if p.is_dir()):
        locale = folder.name
        images = sorted(folder.glob("*.png"))
        if locale not in localizations:
            raise SystemExit(f"error: {version} has no {locale} localization")
        target = screenshot_set(client, localizations[locale]["id"])
        for old in asc_lib.list_all(client, f"/appScreenshotSets/{target['id']}/appScreenshots"):
            client.delete(f"/appScreenshots/{old['id']}")
        for image in images:
            upload_asset(client, target["id"], image)
        names = [
            item["attributes"].get("fileName")
            for item in asc_lib.list_all(client, f"/appScreenshotSets/{target['id']}/appScreenshots")
        ]
        if names != [image.name for image in images]:
            raise SystemExit(f"error: {locale} order {names!r}")
        print(f"{version} {locale}: {len(names)} iPad screenshots")


if __name__ == "__main__":
    main()
