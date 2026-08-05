#!/usr/bin/env python3
"""Recharge app icon: a countdown ring with an hourglass in its opening.

Fleet design language (soft diagonal gradient, one confident white glyph,
generous negative space), with the app's own idea: a countdown ring that has
most of the way to go, so the icon reads as "time left" rather than a generic
heart or flame. The gap in the ring is the point; the hourglass names the app.
"""
import math
import os

from PIL import Image, ImageDraw

S = 1024
SS = 4              # supersample factor
W = S * SS

AMBER = (255, 158, 51)     # Theme.recovering
CORAL = (255, 115, 71)     # Theme.recoveringSecondary

RING_INSET = 0.20          # fraction of the canvas
RING_WIDTH = 0.115
# Leave a wedge open at the top so the ring reads as still running.
START_ANGLE = -68
SWEEP = 292


def lerp(a, b, t):
    return tuple(int(round(a[i] + (b[i] - a[i]) * t)) for i in range(3))


def gradient(size):
    """Diagonal top-left amber -> bottom-right coral."""
    img = Image.new("RGB", (size, size))
    px = img.load()
    for y in range(size):
        for x in range(size):
            px[x, y] = lerp(AMBER, CORAL, (x + y) / (2 * (size - 1)))
    return img


def rounded_cap(draw, cx, cy, r, fill):
    draw.ellipse((cx - r, cy - r, cx + r, cy + r), fill=fill)


def rounded_polyline(draw, points, width, fill):
    """Draw a stroked path with the same round treatment as the ring."""
    draw.line(points, fill=fill, width=int(width), joint="curve")
    radius = width / 2
    for x, y in points:
        rounded_cap(draw, x, y, radius, fill)


def draw_ring(draw, size):
    inset = size * RING_INSET
    width = size * RING_WIDTH
    box = (inset, inset, size - inset, size - inset)
    outer_radius = (size - 2 * inset) / 2
    # PIL grows an arc's width *inward* from the bounding box, so the stroke's
    # centreline sits half a width inside the box, not on it. Placing the caps
    # on the box radius leaves them floating off the ends.
    centre_radius = outer_radius - width / 2
    cx = cy = size / 2

    draw.arc(box, START_ANGLE, START_ANGLE + SWEEP, fill=(255, 255, 255), width=int(width))

    # Round both ends so the arc matches the app's stroke style.
    for angle in (START_ANGLE, START_ANGLE + SWEEP):
        rad = math.radians(angle)
        rounded_cap(
            draw,
            cx + centre_radius * math.cos(rad),
            cy + centre_radius * math.sin(rad),
            width / 2,
            (255, 255, 255),
        )


# A compact hourglass outline, normalised to x, y in [-1, 1]. The ring is the
# timer; this inner glyph makes the countdown meaning survive the 40pt icon.
HOURGLASS = [
    (-0.78, -1.00),  # top-left bar
    (0.78, -1.00),   # top-right bar
    (0.16, 0.00),    # right waist
    (0.78, 1.00),    # bottom-right bar
    (-0.78, 1.00),   # bottom-left bar
    (-0.16, 0.00),   # left waist
]
HOURGLASS_HALF_HEIGHT = 0.135
HOURGLASS_HALF_WIDTH = 0.085
HOURGLASS_STROKE = 0.030


def draw_marker(draw, size):
    """An hourglass in the ring's opening, at the ring's weight.

    The outline leaves the gradient visible through the glass and is sized to
    remain legible after the downscale to a 40pt home-screen icon.
    """
    cx = cy = size / 2
    points = [
        (cx + x * size * HOURGLASS_HALF_WIDTH, cy + y * size * HOURGLASS_HALF_HEIGHT)
        for x, y in HOURGLASS
    ]
    points.append(points[0])
    rounded_polyline(draw, points, size * HOURGLASS_STROKE, (255, 255, 255))


def main():
    img = gradient(W)
    draw = ImageDraw.Draw(img)
    draw_ring(draw, W)
    draw_marker(draw, W)
    img = img.resize((S, S), Image.LANCZOS).convert("RGB")

    root = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
    targets = [
        os.path.join(root, "Recharge/Assets.xcassets/AppIcon.appiconset/icon_1024.png"),
        os.path.join(root, "RechargeWatch/Assets.xcassets/AppIcon.appiconset/icon_1024.png"),
        os.path.join(root, "docs/icon_256.png"),
    ]
    for path in targets:
        os.makedirs(os.path.dirname(path), exist_ok=True)
        out = img.resize((256, 256), Image.LANCZOS) if path.endswith("icon_256.png") else img
        out.save(path)
        print(f"wrote {path}")


if __name__ == "__main__":
    main()
