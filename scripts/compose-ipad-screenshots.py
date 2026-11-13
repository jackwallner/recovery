#!/usr/bin/env python3
"""Compose the 13-inch iPad App Store screenshots (2064x2752, APP_IPAD_PRO_3GEN_129).

Source frames are portrait captures from the iPad tour test
(`RechargeUITests/IPadTourUITests`), kept in `Screenshots/raw-ipad/`. Each frame
gets one headline and no subheader, on the same artwork as the iPhone set. The
headlines match the iPhone set per locale. Locales that have no iPhone set of
their own inherit en-US in App Store Connect, so they inherit this set too.

    python3 scripts/compose-ipad-screenshots.py <output-dir>
"""
import os
import subprocess
import sys
import tempfile

from PIL import Image, ImageDraw, ImageFilter, ImageFont

ROOT = os.path.dirname(os.path.dirname(os.path.abspath(__file__)))
RAW = os.path.join(ROOT, "Screenshots", "raw-ipad")
BACKGROUND = os.path.join(ROOT, "Screenshots", "Artwork", "recharge-background.png")
SIZE = (2064, 2752)

# Frame name -> source capture. The Watch frame of the iPhone set has no iPad
# equivalent: the Watch capture is 416 px wide and would upscale badly.
FRAMES = {
    "01-countdown": "premium-today-port-screen.png",
    "02-ready": "ready-today-port-screen.png",
    "03-history": "premium-detail-port-screen.png",
    "04-pro": "premium-plus-port-screen.png",
    "05-settings": "premium-settings-port-screen.png",
}

EN = {
    "01-countdown": "Know when it completes",
    "02-ready": "A clear completion state",
    "03-history": "Every session, explained",
    "04-pro": "Recovery, personalized",
    "05-settings": "Built around your training",
}


def four(a, b, c, d):
    return {"01-countdown": a, "02-ready": b, "03-history": c, "05-settings": d}


# The localized iPhone sets have four frames (no 04-pro, no watch).
LOCALES = {
    "en-US": EN,
    "cs": four("Víš, kdy je\nregenerace hotová", "Poznáš to hned:\nPřipraveno", "Každý trénink\ns vysvětlením", "Přizpůsobeno\ntvému tréninku"),
    "es-ES": four("Saber cuándo termina\ntu recuperación", "Un aviso claro:\nListo", "Cada sesión,\ncon su explicación", "Hecho a la medida\nde tu entrenamiento"),
    "es-MX": four("Saber cuándo termina\ntu recuperación", "Un aviso claro:\nListo", "Cada sesión,\ncon su explicación", "Hecho a la medida\nde tu entrenamiento"),
    "it": four("Scopri quando finisce\nil tuo recupero", "Un segnale chiaro:\nPronto", "Ogni allenamento,\nspiegato", "Su misura per\nil tuo allenamento"),
    "de-DE": four("Sieh, wann deine\nErholung endet", "Ein klares Signal:\nBereit", "Jede Einheit\nverständlich erklärt", "Abgestimmt auf\ndein Training"),
    "zh-Hans": four("随时知道\n恢复何时结束", "完成状态清晰可见\n就绪一目了然", "每次训练\n都有清晰说明", "围绕你的训练\n量身打造"),
    "fr-FR": four("Sache quand ta\nrécupération se termine", "Un signal clair:\nPrêt", "Chaque séance\nexpliquée", "Adapté à\nton entraînement"),
    "th": four("รู้ว่าเมื่อไร\nที่คุณฟื้นตัวครบ", "สถานะชัดเจน\nเมื่อพร้อมแล้ว", "ทุกการออกกำลังกาย\nอธิบายให้เข้าใจ", "ปรับให้เข้ากับ\nการฝึกของคุณ"),
}

FONTS = {
    "zh-Hans": ("/System/Library/Fonts/Hiragino Sans GB.ttc", 2),
}
DEFAULT_FONT = ("/System/Library/Fonts/Avenir Next Condensed.ttc", 0)  # Bold

INK = (19, 19, 23)


def font(locale, size):
    path, index = FONTS.get(locale, DEFAULT_FONT)
    return ImageFont.truetype(path, size, index=index)


def background():
    with Image.open(BACKGROUND) as source:
        source = source.convert("RGB")
        scale = max(SIZE[0] / source.width, SIZE[1] / source.height)
        resized = source.resize((round(source.width * scale), round(source.height * scale)), Image.LANCZOS)
        left = (resized.width - SIZE[0]) // 2
        top = (resized.height - SIZE[1]) // 2
        return resized.crop((left, top, left + SIZE[0], top + SIZE[1])).convert("RGBA")


def compose(locale, name, headline, out_dir):
    canvas = background()
    draw = ImageDraw.Draw(canvas)
    width, height = SIZE

    # Headline: one fixed size for the whole set, centred, two lines at most.
    if locale == "th":
        # Pillow has no complex-text layout here, so Thai marks need Core Text.
        with tempfile.TemporaryDirectory() as tmp:
            text_png = os.path.join(tmp, "headline.png")
            subprocess.run(
                ["swift", os.path.join(ROOT, "scripts", "render-headline.swift"), text_png,
                 str(width), "460", "Thonburi-Bold", "170", "14", headline],
                check=True,
            )
            with Image.open(text_png) as text:
                canvas.alpha_composite(text.convert("RGBA"), (0, 110))
    else:
        head_font = font(locale, 170)
        spacing = 22 if locale == "zh-Hans" else 8
        box = draw.multiline_textbbox((0, 0), headline, font=head_font, spacing=spacing, align="center")
        text_width = box[2] - box[0]
        if text_width > width - 160:
            raise SystemExit(f"{locale} {name}: headline is {text_width}px wide")
        draw.multiline_text(((width - text_width) / 2 - box[0], 130), headline, font=head_font, fill=INK, spacing=spacing, align="center")

    with Image.open(os.path.join(RAW, FRAMES[name])) as shot:
        shot = shot.convert("RGB")

    border = 26
    top = 680
    frame_h = height - top - 90
    inner_h = frame_h - border * 2
    inner_w = round(shot.width * inner_h / shot.height)
    frame_w = inner_w + border * 2
    x = (width - frame_w) // 2
    radius = 64

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle((x, top + 20, x + frame_w, top + frame_h + 20), radius=radius, fill=(25, 25, 35, 70))
    canvas.alpha_composite(shadow.filter(ImageFilter.GaussianBlur(34)))

    frame = Image.new("RGBA", (frame_w, frame_h), (0, 0, 0, 0))
    ImageDraw.Draw(frame).rounded_rectangle((0, 0, frame_w, frame_h), radius=radius, fill=(18, 18, 20, 255))
    inner = shot.resize((inner_w, inner_h), Image.LANCZOS).convert("RGBA")
    mask = Image.new("L", inner.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle((0, 0, inner_w, inner_h), radius=radius - border, fill=255)
    frame.paste(inner, (border, border), mask)
    canvas.alpha_composite(frame, (x, top))

    os.makedirs(out_dir, exist_ok=True)
    out = os.path.join(out_dir, f"{name}.png")
    canvas.convert("RGB").save(out, "PNG")
    return out


def main():
    if len(sys.argv) != 2:
        print(__doc__)
        return 2
    base = sys.argv[1]
    for locale, headlines in LOCALES.items():
        for name, headline in headlines.items():
            print(compose(locale, name, headline, os.path.join(base, locale)))
    return 0


if __name__ == "__main__":
    sys.exit(main())
