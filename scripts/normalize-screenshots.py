#!/usr/bin/env python3
"""Normalize raw simulator captures into the sizes App Store Connect accepts.

A pool iPhone 17 Pro captures 1206x2622. ASC wants 1320x2868 for the 6.9-inch
(`APP_IPHONE_67`) set and 1284x2778 for the 6.5-inch (`APP_IPHONE_65`) set, both
as RGB PNG with no alpha. Scaling rather than cropping keeps the layout honest —
a cropped frame would hide exactly the safe-area problems the review is for.

Raw captures are kept beside the normalized assets for design review.
"""
import os
import sys

from PIL import Image

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "Screenshots", "raw")

SETS = {
    "APP_IPHONE_67": ((1320, 2868), os.path.join(ROOT, "fastlane", "screenshots", "en-US")),
    "APP_IPHONE_65": ((1284, 2778), os.path.join(ROOT, "Screenshots", "iphone-65")),
}


def normalize(path, size, out_dir):
    with Image.open(path) as img:
        # Flatten onto white first: ASC rejects any alpha channel, and a
        # straight convert would leave transparent pixels black.
        if img.mode in ("RGBA", "LA", "P"):
            flat = Image.new("RGB", img.size, (255, 255, 255))
            rgba = img.convert("RGBA")
            flat.paste(rgba, mask=rgba.split()[-1])
            img = flat
        else:
            img = img.convert("RGB")
        resized = img.resize(size, Image.LANCZOS)

    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, os.path.basename(path))
    resized.save(out, "PNG")
    return out


def main():
    if not os.path.isdir(RAW):
        print(f"error: no raw captures at {RAW}", file=sys.stderr)
        return 1

    shots = sorted(f for f in os.listdir(RAW) if f.endswith(".png"))
    if not shots:
        print(f"error: no PNGs in {RAW}", file=sys.stderr)
        return 1
    if len(shots) > 10:
        print(f"error: {len(shots)} screenshots; App Store allows at most 10", file=sys.stderr)
        return 1

    for label, (size, out_dir) in SETS.items():
        for shot in shots:
            out = normalize(os.path.join(RAW, shot), size, out_dir)
            print(f"{label} {size[0]}x{size[1]}  {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
