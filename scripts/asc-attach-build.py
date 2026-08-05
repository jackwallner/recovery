#!/usr/bin/env python3
"""Attach a valid TestFlight build to the editable App Store version."""
from __future__ import annotations

import argparse
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib  # noqa: E402

BUNDLE = "com.jackwallner.recharge"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default="1.0.0")
    parser.add_argument("--build", default="19")
    args = parser.parse_args()

    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app = asc_lib.find_app(client, BUNDLE)
    version = asc_lib.find_version_by_string(client, app["id"], args.version)
    if not version:
        raise SystemExit(f"error: version {args.version} not found")

    builds = asc_lib.list_all(
        client,
        f"/builds?filter[app]={app['id']}&filter[version]={args.build}&limit=20",
    )
    valid = [
        build for build in builds
        if build["attributes"].get("processingState") == "VALID"
        and not build["attributes"].get("expired")
    ]
    if not valid:
        raise SystemExit(f"error: no valid build {args.build}")
    build = valid[0]

    client.patch(
        f"/appStoreVersions/{version['id']}/relationships/build",
        {"data": {"type": "builds", "id": build["id"]}},
    )
    attached = client.get(f"/appStoreVersions/{version['id']}/build").get("data")
    if not attached or attached["id"] != build["id"]:
        raise SystemExit("error: attached build did not read back")
    print(f"Attached build {args.build} to App Store version {args.version}")


if __name__ == "__main__":
    main()
