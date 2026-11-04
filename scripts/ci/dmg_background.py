#!/usr/bin/env python3
"""The macOS installer DMG's window background (scripts/ci/dmg_settings.py):
branding/dmg/background.png (640x400) and background@2x.png (1280x800) - an
arrow from the app's icon to the Applications folder and a one-line hint.

The PNGs are committed; run this only to change them (needs Pillow):
    python3 -m venv /tmp/pillow && /tmp/pillow/bin/pip install pillow==13.0.0
    /tmp/pillow/bin/python scripts/ci/dmg_background.py

Keep the geometry in step with dmg_settings.py (window 640x400, the app at
x=160 and Applications at x=480, both at y=180, icons 128pt).
"""
import os

from PIL import Image, ImageDraw, ImageFont

REPO = os.path.dirname(os.path.dirname(os.path.dirname(os.path.abspath(__file__))))
OUT = os.path.join(REPO, "branding", "dmg")
FONT = os.path.join(REPO, "engine", "Open_Sans", "static", "OpenSans-Regular.ttf")
HINT = "Drag Rayzr Editor to Applications"

W, H = 640, 400
ICON_Y = 180
APP_X, APPS_X = 160, 480
# Light (Finder draws the icon labels in black), the brand's orange arrow.
TOP, BOTTOM = (250, 250, 252), (232, 233, 238)
ARROW = (242, 156, 72)
TEXT = (96, 99, 108)


def render(scale):
    w, h = W * scale, H * scale
    img = Image.new("RGB", (w, h))
    px = ImageDraw.Draw(img)
    for y in range(h):  # a soft vertical gradient
        t = y / (h - 1)
        px.line([(0, y), (w, y)], fill=tuple(round(a + (b - a) * t) for a, b in zip(TOP, BOTTOM)))

    # The arrow: a shaft between the icons, a head at Applications' side.
    s = scale
    y = ICON_Y * s
    x0, x1 = (APP_X + 92) * s, (APPS_X - 92) * s
    head = 14 * s
    thick = 4 * s
    px.rounded_rectangle([x0, y - thick // 2, x1 - head + s, y + thick // 2], radius=thick // 2, fill=ARROW)
    px.polygon([(x1 - head - 2 * s, y - head), (x1, y), (x1 - head - 2 * s, y + head)], fill=ARROW)

    font = ImageFont.truetype(FONT, 15 * s)
    tw = px.textlength(HINT, font=font)
    px.text(((w - tw) / 2, 318 * s), HINT, font=font, fill=TEXT)
    return img


def main():
    os.makedirs(OUT, exist_ok=True)
    for scale, name in ((1, "background.png"), (2, "background@2x.png")):
        img = render(scale)
        # (72 / 144 dpi: dmgbuild's tiffutil -cathidpicheck pairs them as one HiDPI image.)
        img.save(os.path.join(OUT, name), optimize=True, dpi=(72 * scale, 72 * scale))
        print("wrote", os.path.relpath(os.path.join(OUT, name), REPO), img.size)


if __name__ == "__main__":
    main()
