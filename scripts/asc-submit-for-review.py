#!/usr/bin/env python3
"""Submit the editable App Store version for review.

Creates a reviewSubmission (if none open), adds the appStoreVersion as an item,
and flips the submission to submitted. Idempotent-ish: reuses an existing
unsubmitted reviewSubmission for the app rather than creating a second one.

**This only adds the version.** Guideline 2.1(b) rejects an app whose paywall
references products that were not submitted with the binary, and the first
subscription and first non-consumable an app ever ships cannot be attached over
the public API at all: `reviewSubmissionItems` takes no product relationship,
and the standalone submission endpoints return
`FIRST_SUBSCRIPTION_MUST_BE_SUBMITTED_ON_VERSION`. The flag ASC's own UI sets is
`submitWithNextAppStoreVersion`, which the public API refuses as an unknown
field. So the three products go in by hand, once, in the ASC web UI, and
`--prepare-only` exists to set the submission up and stop before submitting so
that can happen.

Usage: asc-submit-for-review.py [--version 1.0.0] [--dry-run] [--prepare-only]
"""
from __future__ import annotations

import argparse
import os
import sys
from pathlib import Path

sys.path.insert(0, str(Path(__file__).parent))
import asc_lib  # noqa: E402

BUNDLE = "com.jackwallner.recovery"
PLATFORM = "IOS"


def main() -> None:
    parser = argparse.ArgumentParser()
    parser.add_argument("--version", default=os.environ.get("ASC_APP_VERSION", "1.0.0"))
    parser.add_argument("--dry-run", action="store_true")
    parser.add_argument(
        "--prepare-only",
        action="store_true",
        help="create the submission and add the version, then stop so the IAPs can be added in the UI",
    )
    args = parser.parse_args()

    client = asc_lib.ASCClient(asc_lib.bearer_token(*asc_lib.load_credentials()))
    app = asc_lib.find_app(client, BUNDLE)
    app_id = app["id"]

    version = asc_lib.find_version_by_string(client, app_id, args.version)
    if not version:
        raise SystemExit(f"error: version {args.version} not found")
    version_id = version["id"]
    state = version["attributes"].get("appStoreState")
    print(f"version {args.version} state={state} id={version_id}")
    if state != "PREPARE_FOR_SUBMISSION":
        raise SystemExit(f"error: version is {state}, expected PREPARE_FOR_SUBMISSION")

    build = client.get(f"/appStoreVersions/{version_id}/build").get("data")
    if not build:
        raise SystemExit("error: no build attached to version")
    b = build["attributes"]
    print(f"attached build {b.get('version')} processing={b.get('processingState')} expired={b.get('expired')}")
    if b.get("processingState") != "VALID" or b.get("expired"):
        raise SystemExit("error: attached build is not VALID / is expired")

    if args.dry_run:
        print("DRY RUN: would create reviewSubmission, add version item, and submit.")
        return

    # 1) Create the review submission for this app + platform.
    open_subs = [
        s for s in asc_lib.list_all(client, f"/reviewSubmissions?filter[app]={app_id}&limit=50")
        if not s["attributes"].get("submitted")
    ]
    if open_subs:
        submission = open_subs[0]
        print(f"reusing unsubmitted reviewSubmission {submission['id']}")
    else:
        submission = client.post(
            "/reviewSubmissions",
            {
                "data": {
                    "type": "reviewSubmissions",
                    "attributes": {"platform": PLATFORM},
                    "relationships": {"app": {"data": {"type": "apps", "id": app_id}}},
                }
            },
        )["data"]
        print(f"created reviewSubmission {submission['id']}")
    submission_id = submission["id"]

    # 2) Add the appStoreVersion as an item (skip if already present).
    items = asc_lib.list_all(client, f"/reviewSubmissions/{submission_id}/items?limit=50")
    has_version = any(
        (it.get("relationships", {}).get("appStoreVersion", {}).get("data") or {}).get("id") == version_id
        for it in items
    )
    if has_version:
        print("version already an item on this submission")
    else:
        client.post(
            "/reviewSubmissionItems",
            {
                "data": {
                    "type": "reviewSubmissionItems",
                    "relationships": {
                        "reviewSubmission": {"data": {"type": "reviewSubmissions", "id": submission_id}},
                        "appStoreVersion": {"data": {"type": "appStoreVersions", "id": version_id}},
                    },
                }
            },
        )
        print("added appStoreVersion item")

    if args.prepare_only:
        print()
        print("prepared, not submitted. Still to do in the App Store Connect UI:")
        print("  1. Subscription group page  -> Add for Review -> the open draft")
        print("  2. Each subscription page   -> Add for Review -> the open draft")
        print("  3. The lifetime IAP page (/distribution/iaps/<id>) -> same")
        print("Then re-run without --prepare-only. Expect 5 items on the submission.")
        return

    # 3) Submit.
    client.patch(
        f"/reviewSubmissions/{submission_id}",
        {"data": {"type": "reviewSubmissions", "id": submission_id, "attributes": {"submitted": True}}},
    )
    final = client.get(f"/reviewSubmissions/{submission_id}").get("data", {})
    print(f"submitted. state={final.get('attributes', {}).get('state')} submitted={final.get('attributes', {}).get('submitted')}")


if __name__ == "__main__":
    main()
