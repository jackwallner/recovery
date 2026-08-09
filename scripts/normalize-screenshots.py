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

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "Screenshots", "raw")

SETS = {
    "APP_IPHONE_67": ((1320, 2868), os.path.join(ROOT, "Screenshots", "iphone-67")),
    "APP_IPHONE_65": ((1284, 2778), os.path.join(ROOT, "Screenshots", "iphone-65")),
    "APP_IPHONE_67_UPLOAD": ((1320, 2868), os.path.join(ROOT, "fastlane", "screenshots", "en-US")),
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


def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/SFNS.ttf" if bold else "/System/Library/Fonts/SFNSRounded.ttf",
        "/System/Library/Fonts/SFNS.ttf",
    ]
    for candidate in candidates:
        if os.path.exists(candidate):
            return ImageFont.truetype(candidate, size)
    return ImageFont.load_default()


def centered_text(draw, canvas_width, y, value, text_font, fill, spacing=12):
    box = draw.multiline_textbbox((0, 0), value, font=text_font, spacing=spacing, align="center")
    width = box[2] - box[0]
    draw.multiline_text(((canvas_width - width) / 2, y), value, font=text_font, fill=fill, spacing=spacing, align="center")


def compose_watch(path, size, out_dir):
    width, height = size
    canvas = Image.new("RGB", size, (248, 248, 252))
    glow = Image.new("RGBA", size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(
        (width * 0.08, height * 0.23, width * 0.92, height * 0.78),
        fill=(255, 120, 64, 45),
    )
    canvas = Image.alpha_composite(canvas.convert("RGBA"), glow.filter(ImageFilter.GaussianBlur(width // 7)))
    draw = ImageDraw.Draw(canvas)

    centered_text(draw, width, int(height * 0.09), "Recovery time,\non your wrist", font(int(width * 0.10), True), (20, 20, 24), 8)
    centered_text(
        draw,
        width,
        int(height * 0.245),
        "Raise your wrist for the countdown.\nNo second device required.",
        font(int(width * 0.037)),
        (95, 95, 105),
        12,
    )

    with Image.open(path) as watch:
        watch = watch.convert("RGB")
        target_width = int(width * 0.68)
        target_height = int(watch.height * target_width / watch.width)
        watch = watch.resize((target_width, target_height), Image.LANCZOS)

    frame_padding = int(width * 0.035)
    frame_box_width = target_width + frame_padding * 2
    frame_box_height = target_height + frame_padding * 2
    frame_x = (width - frame_box_width) // 2
    frame_y = int(height * 0.37)
    shadow = Image.new("RGBA", size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (frame_x, frame_y + 18, frame_x + frame_box_width, frame_y + frame_box_height + 18),
        radius=int(width * 0.13),
        fill=(0, 0, 0, 70),
    )
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(28)))
    draw = ImageDraw.Draw(canvas)
    draw.rounded_rectangle(
        (frame_x, frame_y, frame_x + frame_box_width, frame_y + frame_box_height),
        radius=int(width * 0.13),
        fill=(18, 18, 20, 255),
    )
    canvas.paste(watch.convert("RGBA"), (frame_x + frame_padding, frame_y + frame_padding))

    centered_text(
        ImageDraw.Draw(canvas),
        width,
        int(height * 0.86),
        "Watch app and four complication families",
        font(int(width * 0.036), True),
        (35, 35, 40),
    )

    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, os.path.basename(path))
    canvas.convert("RGB").save(out, "PNG")
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
            path = os.path.join(RAW, shot)
            out = compose_watch(path, size, out_dir) if shot == "06-watch.png" else normalize(path, size, out_dir)
            print(f"{label} {size[0]}x{size[1]}  {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
