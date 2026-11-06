#!/usr/bin/env python3
"""Frame raw simulator captures as App Store screenshots.

    compose.py <raw dir> <out dir> <locale>

Reads shots.json beside this script. For every shot with a caption in
<locale>, takes <raw dir>/<id>.png and writes <out dir>/<id>.jpg at the
capture's own pixel size (so a 6.9" iPhone capture stays 1320x2868 and a
13" iPad capture 2064x2752, the sizes App Store Connect asks for): the
caption in white across the top of a gradient in the app icon's colours,
and the screen below it with rounded corners and a soft shadow, running
off the bottom edge. JPEG, not PNG, keeps each file well under a megabyte
without visible loss, and App Store Connect takes either.
"""
import json
import os
import sys

from PIL import Image, ImageDraw, ImageFilter, ImageFont

# The app icon's gradient: cyan top left, violet, pink bottom right.
STOPS = [(0.0, (8, 204, 232)), (0.5, (124, 42, 232)), (1.0, (247, 114, 182))]

FONTS = [
    ("/System/Library/Fonts/HelveticaNeue.ttc", 1),          # Helvetica Neue Bold
    ("/System/Library/Fonts/Supplemental/Arial Bold.ttf", 0),
    ("/Library/Fonts/Arial Bold.ttf", 0),
    ("/usr/share/fonts/truetype/dejavu/DejaVuSans-Bold.ttf", 0),
]


def font(size):
    for path, index in FONTS:
        if os.path.exists(path):
            return ImageFont.truetype(path, size, index=index)
    return ImageFont.load_default()


def mix(a, b, t):
    return tuple(round(a[i] + (b[i] - a[i]) * t) for i in range(3))


def colour_at(t):
    for (t0, c0), (t1, c1) in zip(STOPS, STOPS[1:]):
        if t <= t1:
            return mix(c0, c1, (t - t0) / (t1 - t0))
    return STOPS[-1][1]


def gradient(w, h):
    # Diagonal, drawn small and scaled up: smooth, and quick.
    sw, sh = 64, max(2, round(64 * h / w))
    small = Image.new("RGB", (sw, sh))
    px = small.load()
    for y in range(sh):
        for x in range(sw):
            px[x, y] = colour_at((x / (sw - 1) + y / (sh - 1)) / 2)
    return small.resize((w, h), Image.BICUBIC)


def rounded(img, radius):
    mask = Image.new("L", img.size, 0)
    ImageDraw.Draw(mask).rounded_rectangle([0, 0, img.width - 1, img.height - 1], radius, fill=255)
    out = img.convert("RGBA")
    out.putalpha(mask)
    return out


def compose(raw_path, caption, out_path):
    shot = Image.open(raw_path).convert("RGB")
    w, h = shot.size
    canvas = gradient(w, h).convert("RGBA")
    draw = ImageDraw.Draw(canvas)

    # The caption: up to three lines, centred, sized to the width.
    size = round(w * (0.072 if h > w * 1.6 else 0.058))
    lines = caption.split("\n")
    f = font(size)
    while size > 20 and max(draw.textlength(l, font=f) for l in lines) > w * 0.86:
        size -= 2
        f = font(size)
    line_h = round(size * 1.18)
    top = round(h * 0.055)
    for i, line in enumerate(lines):
        draw.text((w / 2, top + i * line_h), line, font=f, fill="white", anchor="ma")
    text_bottom = top + len(lines) * line_h

    # The screen, scaled to leave a margin, under a soft shadow.
    scale = 0.80
    sw, sh = round(w * scale), round(h * scale)
    screen = rounded(shot.resize((sw, sh), Image.LANCZOS), round(w * 0.055))
    x, y = (w - sw) // 2, text_bottom + round(h * 0.04)

    shadow = Image.new("RGBA", canvas.size, (0, 0, 0, 0))
    ImageDraw.Draw(shadow).rounded_rectangle(
        [x, y + round(h * 0.01), x + sw, y + sh + round(h * 0.01)], round(w * 0.055), fill=(30, 0, 60, 110))
    canvas = Image.alpha_composite(canvas, shadow.filter(ImageFilter.GaussianBlur(round(w * 0.025))))
    canvas.alpha_composite(screen, (x, y))

    canvas.convert("RGB").save(out_path, "JPEG", quality=92, optimize=True, progressive=True)


def main():
    raw_dir, out_dir, locale = sys.argv[1], sys.argv[2], sys.argv[3]
    here = os.path.dirname(os.path.abspath(__file__))
    config = json.load(open(os.path.join(here, "shots.json")))
    os.makedirs(out_dir, exist_ok=True)
    made = 0
    for shot in config["shots"]:
        caption = shot.get("caption", {}).get(locale)
        raw = os.path.join(raw_dir, shot["id"] + ".png")
        if caption is None or not os.path.exists(raw):
            print(f"skipped {shot['id']}: {'no caption' if caption is None else 'no capture'}")
            continue
        compose(raw, caption, os.path.join(out_dir, shot["id"] + ".jpg"))
        made += 1
        print(f"made {shot['id']}")
    if made == 0:
        sys.exit("nothing composed")


if __name__ == "__main__":
    main()
