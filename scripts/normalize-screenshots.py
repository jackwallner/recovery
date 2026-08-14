#!/usr/bin/env python3
"""Compose raw simulator captures into App Store marketing screenshots.

A pool iPhone 17 Pro captures 1206x2622. ASC wants 1320x2868 for the 6.9-inch
(`APP_IPHONE_67`) set and 1284x2778 for the 6.5-inch (`APP_IPHONE_65`) set, both
as RGB PNG with no alpha. Scaling rather than cropping keeps the layout honest,
a cropped frame would hide exactly the safe-area problems the review is for.

Raw captures are kept beside the composed assets for design review. Every frame
has one headline and no marketing subheader. The screen content itself remains
an unedited Simulator capture.
"""
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "Screenshots", "raw")
BACKGROUND = os.path.join(ROOT, "Screenshots", "Artwork", "recharge-background.png")

HEADLINES = {
    "01-countdown.png": "Know when you're Ready",
    "02-ready.png": "A clear Ready",
    "03-history.png": "Every session, explained",
    "04-pro.png": "Recovery, personalized",
    "05-settings.png": "Built around your training",
    "06-watch.png": "Your recovery, at a glance",
}

SETS = {
    "APP_IPHONE_67": ((1320, 2868), os.path.join(ROOT, "Screenshots", "iphone-67")),
    "APP_IPHONE_65": ((1284, 2778), os.path.join(ROOT, "Screenshots", "iphone-65")),
    "APP_IPHONE_67_UPLOAD": ((1320, 2868), os.path.join(ROOT, "fastlane", "screenshots", "en-US")),
}


def font(size, bold=False):
    candidates = [
        "/System/Library/Fonts/Supplemental/Arial Rounded Bold.ttf" if bold else "/System/Library/Fonts/SFNSRounded.ttf",
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


def background(size):
    if not os.path.exists(BACKGROUND):
        raise FileNotFoundError(f"missing generated artwork: {BACKGROUND}")
    with Image.open(BACKGROUND) as source:
        source = source.convert("RGB")
        scale = max(size[0] / source.width, size[1] / source.height)
        resized = source.resize((round(source.width * scale), round(source.height * scale)), Image.LANCZOS)
        left = (resized.width - size[0]) // 2
        top = (resized.height - size[1]) // 2
        return resized.crop((left, top, left + size[0], top + size[1])).convert("RGBA")


def shadowed_card(canvas, content, box, radius, border=0):
    x, y, width, height = box
    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    shadow_draw = ImageDraw.Draw(shadow)
    shadow_draw.rounded_rectangle(
        (x, y + 18, x + width, y + height + 18),
        radius=radius,
        fill=(25, 25, 35, 68),
    )
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(30)))

    frame = Image.new("RGBA", (width, height), (0, 0, 0, 0))
    frame_draw = ImageDraw.Draw(frame)
    frame_draw.rounded_rectangle((0, 0, width, height), radius=radius, fill=(18, 18, 20, 255))
    inner = content.resize((width - border * 2, height - border * 2), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", inner.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle(
        (0, 0, inner.width, inner.height),
        radius=max(1, radius - border),
        fill=255,
    )
    frame.paste(inner, (border, border), mask)
    canvas.alpha_composite(frame, (x, y))


def compose_phone(path, size, out_dir):
    width, height = size
    canvas = background(size)
    draw = ImageDraw.Draw(canvas)
    headline = HEADLINES[os.path.basename(path)]
    centered_text(draw, width, int(height * 0.055), headline, font(int(width * 0.073), True), (19, 19, 23))

    with Image.open(path) as screen:
        screen = screen.convert("RGB")
        target_height = int(height * 0.785)
        target_width = round(screen.width * target_height / screen.height)
        max_width = int(width * 0.82)
        if target_width > max_width:
            target_width = max_width
            target_height = round(screen.height * target_width / screen.width)

    x = (width - target_width) // 2
    y = int(height * 0.175)
    border = max(6, width // 90)
    shadowed_card(canvas, screen, (x, y, target_width, target_height), int(width * 0.075), border)

    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, os.path.basename(path))
    canvas.convert("RGB").save(out, "PNG")
    return out


def compose_watch(path, size, out_dir):
    width, height = size
    canvas = background(size)
    draw = ImageDraw.Draw(canvas)
    centered_text(draw, width, int(height * 0.055), HEADLINES[os.path.basename(path)], font(int(width * 0.073), True), (19, 19, 23))

    with Image.open(path) as watch:
        watch = watch.convert("RGB")
        target_width = int(width * 0.74)
        target_height = int(watch.height * target_width / watch.width)

    frame_padding = int(width * 0.035)
    frame_box_width = target_width + frame_padding * 2
    frame_box_height = target_height + frame_padding * 2
    frame_x = (width - frame_box_width) // 2
    frame_y = int(height * 0.29)
    shadowed_card(
        canvas,
        watch,
        (frame_x, frame_y, frame_box_width, frame_box_height),
        int(width * 0.13),
        frame_padding,
    )

    # Call out the actual top-left circular complication without adding a
    # marketing label or editing the simulator capture itself. The outline is
    # deliberately restrained so the face remains the hero.
    inner_x = frame_x + frame_padding
    inner_y = frame_y + frame_padding
    scale = target_width / watch.width
    highlight = (
        round(inner_x + watch.width * 0.01 * scale),
        round(inner_y + watch.height * 0.01 * scale),
        round(inner_x + watch.width * 0.26 * scale),
        round(inner_y + watch.height * 0.23 * scale),
    )
    glow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    glow_draw = ImageDraw.Draw(glow)
    glow_draw.ellipse(highlight, outline=(255, 125, 70, 150), width=max(12, width // 150))
    canvas.alpha_composite(glow.filter(ImageFilter.GaussianBlur(max(8, width // 95))))
    ImageDraw.Draw(canvas).ellipse(
        highlight,
        outline=(255, 125, 70, 235),
        width=max(5, width // 260),
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
            out = compose_watch(path, size, out_dir) if shot == "06-watch.png" else compose_phone(path, size, out_dir)
            print(f"{label} {size[0]}x{size[1]}  {out}")
    return 0


if __name__ == "__main__":
    sys.exit(main())
