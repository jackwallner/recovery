#!/usr/bin/env python3
"""Recharge app icon: a countdown ring with a bolt in its opening.

Fleet design language (soft diagonal gradient, one confident white glyph,
generous negative space), with the app's own idea: a countdown ring that has
most of the way to go, so the icon reads as "time left" rather than a generic
heart or flame. The gap in the ring is the point; the bolt names the app.
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


# Classic six-point bolt, normalised to x, y in [-1, 1]. The two long diagonals
# are deliberately parallel so the limbs read as one consistent stroke.
BOLT = [
    (0.45, -1.00),   # top tip
    (-0.75, 0.10),   # left shoulder, just below the waist
    (-0.05, 0.10),   # waist notch
    (-0.45, 1.00),   # bottom tip
    (0.75, -0.10),   # right shoulder, just above the waist
    (0.05, -0.10),   # waist notch
]
BOLT_HALF_HEIGHT = 0.145
BOLT_HALF_WIDTH = 0.098


def draw_marker(draw, size):
    """A bolt in the ring's opening: the app's own name, at the ring's weight.

    Sized so its furthest tip sits at 0.152*size from the centre, comfortably
    inside the ring's inner opening (0.185*size), and heavy enough to survive
    the downscale to a 40pt home-screen icon.
    """
    cx = cy = size / 2
    draw.polygon(
        [
            (cx + x * size * BOLT_HALF_WIDTH, cy + y * size * BOLT_HALF_HEIGHT)
            for x, y in BOLT
        ],
        fill=(255, 255, 255),
    )


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
