#!/usr/bin/env python3
"""Write round 33's templates: colourway and layout variants by industry,
and animated templates, from the app's own content only.

    python3 tools/generate_template_variants.py
    python3 tools/generate_templates.py

writes

  - templates/round33-variants.json: twelve industry topic packs (real
    estate, fitness, restaurants and menus, beauty, weddings, education,
    nonprofits, tech, travel, receipts and invoices, coupons, business
    cards), each of seven base layouts, every base in 4 colourways x 2
    font combinations — 8 templates a base, the first the base itself and
    the other seven `variantOf` it. Odd colourways are the layout mirrored,
    and where the colourway's place and the combination's add up odd, a
    layout's picture slot is filled with one of Motion.json's stills (the
    photo variant) — so each style comes with and without a photo. Each
    carries its `topic` and `style`.
  - templates/round33-animated.json: animated templates — Instagram Reels
    and Stories, TikToks, animated Instagram posts, YouTube intros,
    five-page animated presentations and animated invitations — with
    entrances and exits (text by letter, word or line, photo zoom and pan,
    draw and twinkle), page animations, transitions, page durations, motion
    loop backgrounds and a sound effect.

Everything is seeded from each template's own id (zlib.crc32), so the
output is the same on every run and on every machine. The colourways are
Themes.palettes (copied below, as the Kotlin has them), the font
combinations come from textcombos.json (the Text tab's combinations), the
pictures and loops from Motion.json and the sounds from sfx.json; the copy
is the word list below. Nothing is downloaded.
"""

import json
import os
import random
import zlib

HERE = os.path.dirname(os.path.abspath(__file__))
ROOT = os.path.dirname(HERE)
SPEC_DIR = os.path.join(ROOT, "templates")
CONTENT_DIR = os.path.join(ROOT, "core/src/main/resources/com/canvia/core/content")
VARIANTS_OUT = os.path.join(SPEC_DIR, "round33-variants.json")
ANIMATED_OUT = os.path.join(SPEC_DIR, "round33-animated.json")

# The template sizes the packs use, in pixels (templates/sizes.json).
SIZES = {
    "insta-post": (1080, 1080), "insta-story": (1080, 1920), "insta-reel": (1080, 1920),
    "tiktok-video": (1080, 1920), "youtube-video": (1920, 1080), "presentation": (1920, 1080),
    "facebook-post": (1200, 630), "flyer-letter": (2550, 3300), "postcard": (1800, 1200),
    "invitation": (1500, 2100), "menu": (2550, 3300), "a4": (2480, 3508),
    "us-letter": (2550, 3300), "business-card": (1050, 600), "gift-certificate": (2400, 1050),
    "ticket": (1650, 600), "linkedin-post": (1200, 627), "pinterest-pin": (1000, 1500),
    "insta-portrait": (1080, 1350), "poster": (1587, 2245),
}

# Themes.palettes, in its order: the colourways.
PALETTES = [
    ("Bold", ["#1a1a2e", "#e94560", "#0f3460", "#16c79a", "#f9ed69"]),
    ("Pastel", ["#6c5b7b", "#c06c84", "#f67280", "#f8b195", "#fdf6f0"]),
    ("Ocean", ["#03045e", "#0077b6", "#00b4d8", "#90e0ef", "#caf0f8"]),
    ("Terracotta", ["#5c3d2e", "#b85c38", "#e0824b", "#e8b796", "#f2d8c2", "#faf3eb"]),
    ("Neon", ["#10002b", "#3c096c", "#7b2cbf", "#f72585", "#4cc9f0", "#fee440"]),
    ("Ink", ["#0d0d0d", "#2e2e2e", "#5c5c5c", "#9e9e9e", "#d6d6d6", "#f5f5f4"]),
    ("Botanical", ["#1b3a2a", "#2d5a3d", "#4a7c59", "#8fbc8f", "#cde6c2", "#f3f7ee"]),
    ("Golden", ["#5f0f40", "#9a031e", "#e36414", "#fb8b24", "#ffc971", "#fff3e0"]),
    ("Midnight", ["#0a1128", "#1b2a4a", "#31487a", "#c6a15b", "#e8cf9a", "#f7f2e7"]),
    ("Nordic", ["#3a3f44", "#7a8288", "#a9b4b0", "#d8cfc4", "#ede8e2", "#faf9f7"]),
]

# A text combination's style, by its category in the Text tab — the styles
# the Filters sheet offers.
STYLE_OF_CATEGORY = {
    "Minimal": "minimal", "Sale": "bold", "Retro": "bold", "Event": "bold",
    "Wedding": "elegant", "Quote": "elegant", "Kids": "playful", "Social": "playful",
    "Headline": "corporate", "Badge": "corporate",
}


def load(name):
    with open(os.path.join(CONTENT_DIR, name)) as fh:
        return json.load(fh)


FAMILIES = {f["id"]: f["weights"] for f in load("Fonts.json")["families"]}
MOTION = load("Motion.json")
LOOPS = [m["id"] for m in MOTION["loops"]]
STILLS = [m["id"] for m in MOTION["stills"]]


def font_pairs():
    """Every text combination's heading and body faces — its largest text
    and its smallest — where both are families the app bundles, once each,
    by style, in the file's order."""
    out = {s: [] for s in STYLE_OF_CATEGORY.values()}
    seen = set()
    for combo in load("textcombos.json"):
        texts = [e for e in combo["elements"] if e["type"] == "text"]
        if len(texts) < 2:
            continue
        head = max(texts, key=lambda e: e["fontSize"])
        body = min(texts, key=lambda e: e["fontSize"])
        pair = ((head["fontFamily"], head["fontWeight"]), (body["fontFamily"], body["fontWeight"]))
        if any(fam not in FAMILIES or w not in FAMILIES[fam] for fam, w in pair) or pair in seen:
            continue
        seen.add(pair)
        out[STYLE_OF_CATEGORY[combo["category"]]].append(pair)
    return out


PAIRS = font_pairs()


# ------------------------------------------------------------------ colour

def luminance(hex_color):
    def channel(v):
        v /= 255.0
        return v / 12.92 if v <= 0.03928 else ((v + 0.055) / 1.055) ** 2.4
    r, g, b = (int(hex_color[i:i + 2], 16) for i in (1, 3, 5))
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)


def contrast(a, b):
    la, lb = sorted((luminance(a), luminance(b)), reverse=True)
    return (la + 0.05) / (lb + 0.05)


def saturation(hex_color):
    r, g, b = (int(hex_color[i:i + 2], 16) / 255.0 for i in (1, 3, 5))
    hi, lo = max(r, g, b), min(r, g, b)
    light = (hi + lo) / 2
    return 0.0 if hi == lo else (hi - lo) / (1 - abs(2 * light - 1))


def roles(colours, dark):
    """A palette as a template's roles: the page ("bg"), its type ("ink"),
    the most saturated of the rest ("accent"), a quieter panel ("soft"),
    type on the accent ("on"), and a kicker's colour — the accent where it
    reads on the page at 3:1, else the ink. A dark colourway is the
    palette's darkest under its lightest; a light one the reverse."""
    ranked = sorted(colours, key=luminance)
    bg, ink = (ranked[0], ranked[-1]) if dark else (ranked[-1], ranked[0])
    middle = ranked[1:-1]
    accent = max(middle, key=lambda c: (saturation(c), -abs(luminance(c) - 0.3)))
    soft = ranked[1] if dark else ranked[-2]
    on = bg if contrast(bg, accent) >= contrast(ink, accent) else ink
    kicker = accent if contrast(accent, bg) >= 3.0 else ink
    return {"bg": bg, "ink": ink, "accent": accent, "soft": soft, "on": on, "kicker": kicker}


# ------------------------------------------------------------------ layout

def n(v):
    """A number as the file writes it: whole."""
    return int(round(v))


def lines_of(text, size, w):
    per_line = max(1.0, w / (size * 0.55))
    return sum(max(1, -(-len(p) // int(per_line))) for p in text.split("\n"))


def height(text, size, w, lh):
    return lines_of(text, size, w) * size * lh


class Page:
    """One page being laid out: its size, its margin, its elements (each
    with the role an animation gives it) and its fonts."""

    def __init__(self, size_id, pal, pair, mirror, scale=1.0):
        self.scale = scale
        self.w, self.h = SIZES[size_id]
        self.u = min(self.w, self.h)
        self.m = round(max(self.w, self.h) * 0.06)
        self.pal = pal
        self.head, self.body = pair
        self.mirror = mirror
        self.els = []

    def fx(self, x, w):
        """[x] for a box [w] wide, mirrored when the page is."""
        return self.w - x - w if self.mirror else x

    def side(self, align):
        if not self.mirror or align == "center":
            return align
        return "right" if align == "left" else "left"

    def text(self, role, words, x, y, w, size, face="body", align="left", color="ink",
             lh=None, spacing=0, upper=False):
        family, weight = self.head if face == "head" else self.body
        size = max(14, n(size * self.scale))
        lh = lh or (1.05 if face == "head" else 1.35)
        words = words.upper() if upper else words
        el = {"type": "text", "text": words, "x": n(self.fx(x, w)), "y": n(y), "w": n(w),
              "fontSize": size, "fontFamily": family, "fontWeight": weight,
              "align": self.side(align), "lineHeight": lh, "color": self.pal[color]}
        if spacing:
            el["letterSpacing"] = spacing
        self.els.append((role, el))
        return y + height(words, size, w, lh)

    def shape(self, role, shape_id, x, y, w, h, color="accent", opacity=1.0, radius=0):
        el = {"type": "shape", "shapeId": shape_id, "x": n(self.fx(x, w)), "y": n(y), "w": n(w), "h": n(h),
              "fill": {"kind": "solid", "color": self.pal[color]}}
        if radius and shape_id == "rect":
            el["radius"] = n(radius)
        if opacity != 1.0:
            el["opacity"] = opacity
        self.els.append((role, el))

    def line(self, role, x, y, w, thickness, color="accent", dash="solid"):
        el = {"type": "line", "x": n(self.fx(x, w)), "y": n(y), "w": n(w), "thickness": max(2, n(thickness)),
              "color": self.pal[color], "dash": dash}
        self.els.append((role, el))

    def image(self, role, src, x, y, w, h, radius=0):
        el = {"type": "image", "src": src, "x": n(self.fx(x, w)), "y": n(y), "w": n(w), "h": n(h)}
        if radius:
            el["radius"] = n(radius)
        self.els.append((role, el))

    def sticker(self, role, glyph, x, y, size):
        self.els.append((role, {"type": "sticker", "glyph": glyph, "x": n(self.fx(x, size)), "y": n(y),
                                "w": n(size), "h": n(size)}))

    def pill(self, words, x, y, size, align="left"):
        """A call to action: the words on an accent pill as wide as they are."""
        size *= self.scale
        w = min(self.w - 2 * self.m, len(words) * size * 0.62 + size * 2.4)
        h = size * 2.4
        if align == "center":
            x = (self.w - w) / 2
        self.shape("cta", "rect", x, y, w, h, radius=h / 2)
        self.text("cta", words, x, y + (h - size * 1.2) / 2, w, size / self.scale, align="center", color="on", lh=1.2)
        return y + h

    def fits(self):
        """Whether every text box, at the height its words come to, ends
        inside the page's margin, and none runs into another above or
        below it that shares its width."""
        boxes = []
        for _, el in self.els:
            if el["type"] != "text":
                continue
            bottom = el["y"] + height(el["text"], el["fontSize"], el["w"], el["lineHeight"])
            if bottom > self.h - self.m * 0.4:
                return False
            boxes.append((el["y"], bottom, el["x"], el["x"] + el["w"]))
        boxes.sort()
        for i, a in enumerate(boxes):
            for b in boxes[i + 1:]:
                if b[0] < a[1] - 2 and b[2] < a[3] and a[2] < b[3]:
                    return False
        return True


def laid_out(size_id, pal, pair, mirror, layout, c, photo):
    """[layout] on a new page, its type made smaller a tenth at a time until
    it [fits] — at most down to half."""
    for k in range(6):
        p = Page(size_id, pal, pair, mirror, scale=1.0 - 0.1 * k)
        LAYOUTS[layout](p, c, photo)
        if p.fits():
            return p
    raise SystemExit(f"{layout} on {size_id} does not fit: {c.get('name')}")


def hero(p, c, photo):
    """A big headline down one side: a kicker, the headline, a rule, a line
    of copy and a pill, a circle bled off the far corner — and, as the
    photo variant, a picture beside or above the words."""
    u, m = p.u, p.m
    d = u * 0.7
    p.shape("decor", "circle", p.w - d * 0.55, -d * 0.25, d, d, opacity=0.16)
    x, w = m, p.w - 2 * m
    y = m * 1.4
    if photo:
        if p.w > p.h:
            p.image("photo", photo, p.w * 0.52, m, p.w * 0.48 - m, p.h - 2 * m, radius=u * 0.03)
            w = p.w * 0.46 - m
        else:
            ph = p.h * 0.36
            p.image("photo", photo, m, m, p.w - 2 * m, ph, radius=u * 0.03)
            y = m + ph + m * 0.6
    y = p.text("kicker", c["kicker"], x, y, w, u * 0.034, color="kicker", spacing=6, upper=True) + u * 0.025
    y = p.text("headline", c["headline"], x, y, w, u * (0.085 if photo else 0.11), face="head") + u * 0.03
    p.line("rule", x, y, w * 0.25, u * 0.008)
    y += u * 0.05
    y = p.text("body", c["body"], x, y, w * 0.9, u * 0.038) + u * 0.05
    p.pill(c["cta"], x, min(y, p.h - m - u * 0.09), u * 0.032)


def centered(p, c, photo):
    """Everything centred on a soft panel inset from the edge: kicker,
    headline, rule, copy and a detail line, with a star either side of the
    kicker — and, as the photo variant, a round picture on top."""
    u, m = p.u, p.m
    inset = m * 0.6
    p.shape("panel", "rect", inset, inset, p.w - 2 * inset, p.h - 2 * inset, color="soft", radius=u * 0.02)
    x, w = m * 1.3, p.w - 2.6 * m
    y = m * 1.8
    if photo:
        d = min(u * 0.34, p.h * 0.3)
        p.image("photo", photo, (p.w - d) / 2, y, d, d, radius=d / 2)
        y += d + u * 0.05
    star = u * 0.04
    p.shape("decor", "star", x, y, star, star)
    p.shape("decor", "star", x + w - star, y, star, star)
    y = p.text("kicker", c["kicker"], x + star * 1.5, y, w - star * 3, u * 0.032, align="center",
               color="kicker", spacing=6, upper=True) + u * 0.03
    y = p.text("headline", c["headline"], x, y, w, u * (0.09 if photo else 0.115), face="head", align="center") + u * 0.03
    p.line("rule", (p.w - w * 0.2) / 2, y, w * 0.2, u * 0.006)
    y += u * 0.05
    y = p.text("body", c["body"], x, y, w, u * 0.036, align="center") + u * 0.04
    p.text("detail", c["detail"], x, min(y, p.h - m * 1.6 - u * 0.04), w, u * 0.03, align="center",
           color="kicker", spacing=2)


def split(p, c, photo):
    """A colour panel across part of the page with the headline on it, and
    the copy and three points beside or under it — as the photo variant, a
    picture fills the panel and the headline moves over to the words."""
    u, m = p.u, p.m
    wide = p.w > p.h
    if wide:
        px, py, pw, ph = 0, 0, p.w * 0.42, p.h
        x, y, w = pw + m, m * 1.2, p.w - pw - 2 * m
    else:
        px, py, pw, ph = 0, 0, p.w, p.h * 0.42
        x, y, w = m, ph + m * 0.8, p.w - 2 * m
    if photo:
        p.image("photo", photo, px, py, pw, ph)
        y = p.text("headline", c["headline"], x, y, w, u * 0.085, face="head") + u * 0.03
    else:
        p.shape("panel", "rect", px, py, pw, ph)
        p.shape("decor", "circle", px + pw - u * 0.25, py + ph - u * 0.25, u * 0.4, u * 0.4, color="on", opacity=0.12)
        p.text("headline", c["headline"], px + m, py + m * 1.2, pw - 2 * m, u * (0.09 if wide else 0.1), face="head", color="on")
    y = p.text("body", c["body"], x, y, w, u * 0.038) + u * 0.04
    bullet = u * 0.022
    points = "\n".join(c["points"])
    for i in range(len(c["points"])):
        p.shape("decor", "circle", x, y + i * u * 0.04 * p.scale * 1.5 + u * 0.012 * p.scale, bullet, bullet)
    y = p.text("points", points, x + bullet * 2, y, w - bullet * 2, u * 0.04, lh=1.5) + u * 0.04
    p.text("detail", c["detail"], x, min(y, p.h - m - u * 0.04), w, u * 0.03, color="kicker", spacing=2, upper=True)


def listing(p, c, photo):
    """A menu, a price list or an invoice: a band with the title, then rows
    of items with their prices at the right, rules above and below, and a
    total — and, as the photo variant, a picture in the band's corner."""
    u, m = p.u, p.m
    band = p.h * 0.2
    p.shape("panel", "rect", 0, 0, p.w, band)
    tw = p.w - 2 * m
    if photo:
        d = band - m
        p.image("photo", photo, p.w - m - d, m / 2, d, d, radius=u * 0.02)
        tw -= d + m * 0.5
    p.text("headline", c["title"], m, m * 0.9, tw, u * 0.075, face="head", color="on")
    p.text("kicker", c["subtitle"], m, band - m * 0.9, tw, u * 0.026, color="on", spacing=4, upper=True)
    y = band + m
    p.line("rule", m, y, p.w - 2 * m, u * 0.003, color="ink")
    y += m * 0.6
    size = u * 0.034
    names = "\n".join(i[0] for i in c["items"])
    prices = "\n".join(i[1] for i in c["items"])
    p.text("points", names, m, y, (p.w - 2 * m) * 0.7, size, lh=1.9)
    end = p.text("points", prices, m + (p.w - 2 * m) * 0.7, y, (p.w - 2 * m) * 0.3, size, align="right", lh=1.9)
    y = end + m * 0.4
    p.line("rule", m, y, p.w - 2 * m, u * 0.003, color="ink", dash="dotted")
    y += m * 0.6
    p.text("body", c["total"][0], m, y, (p.w - 2 * m) * 0.6, u * 0.042, face="head")
    p.text("body", c["total"][1], m + (p.w - 2 * m) * 0.6, y, (p.w - 2 * m) * 0.4, u * 0.042, face="head", align="right")
    p.text("detail", c["footer"], m, p.h - m * 1.6, p.w - 2 * m, u * 0.024, align="center", color="kicker", spacing=2)


def card(p, c, photo):
    """A business card: a name, a role and contact lines beside a monogram
    — or, as the photo variant, a round picture — over an accent bar."""
    u, m = p.u, p.m
    p.shape("panel", "rect", 0, p.h - u * 0.07, p.w, u * 0.07)
    d = u * 0.36
    mx = p.w - m - d
    if photo:
        p.image("photo", photo, mx, m, d, d, radius=d / 2)
    else:
        p.shape("decor", "circle", mx, m, d, d)
        p.text("monogram", c["initials"], mx, m + d * 0.26, d, d * 0.38, face="head", align="center", color="on")
    w = p.w - 3 * m - d
    y = p.text("headline", c["name"], m, m, w, u * 0.1, face="head") + u * 0.02
    y = p.text("kicker", c["role"], m, y, w, u * 0.045, color="kicker", spacing=3, upper=True) + u * 0.06
    p.line("rule", m, y, w * 0.3, u * 0.008)
    y += u * 0.05
    p.text("body", "\n".join(c["contacts"]), m, y, w, u * 0.045, lh=1.4)


def coupon(p, c, photo):
    """A coupon: dashed edges to cut along, the offer set huge, what it is
    for, the code on a pill and when it ends, with scissors — and, as the
    photo variant, a picture down one end."""
    u, m = p.u, p.m
    p.line("rule", m * 0.5, m * 0.5, p.w - m, u * 0.008, color="ink", dash="dashed")
    p.line("rule", m * 0.5, p.h - m * 0.5, p.w - m, u * 0.008, color="ink", dash="dashed")
    p.sticker("decor", "✂", m * 0.6, m * 0.5 - u * 0.05, u * 0.1)
    x, w = m, p.w - 2 * m
    if photo:
        iw = p.w * 0.3
        p.image("photo", photo, p.w - iw - m * 0.5, m, iw, p.h - 2 * m)
        w -= iw
    else:
        d = u * 0.8
        p.shape("decor", "seal", p.w - d * 0.7, p.h - d * 0.7, d, d, opacity=0.2)
    y = m * 1.1
    y = p.text("kicker", c["kicker"], x, y, w, u * 0.06, color="kicker", spacing=4, upper=True) + u * 0.02
    y = p.text("headline", c["offer"], x, y, w, u * 0.24, face="head", lh=1.0) + u * 0.02
    y = p.text("body", c["body"], x, y, w, u * 0.06) + u * 0.04
    end = p.pill(c["code"], x, min(y, p.h - m - u * 0.15), u * 0.05)
    p.text("detail", c["expiry"], x + w * 0.5, end - u * 0.09, w * 0.5, u * 0.045, align="right", color="kicker")


LAYOUTS = {"hero": hero, "centered": centered, "split": split, "listing": listing, "card": card, "coupon": coupon}
# What a base's name ends in: its type, so the same copy at two sizes is
# two names.
SIZE_WORDS = {
    "insta-post": "Post", "insta-story": "Story", "insta-reel": "Reel", "tiktok-video": "TikTok",
    "youtube-video": "Intro", "presentation": "Slide", "facebook-post": "Facebook Post",
    "flyer-letter": "Flyer", "postcard": "Postcard", "invitation": "Invitation", "menu": "Menu",
    "a4": "A4", "us-letter": "Letter", "business-card": "Card", "gift-certificate": "Voucher",
    "ticket": "Ticket", "linkedin-post": "LinkedIn Post", "pinterest-pin": "Pin",
    "insta-portrait": "Portrait Post", "poster": "Poster",
}

# Which layouts have a picture slot, for a photo variant.
PHOTO_LAYOUTS = {"hero", "centered", "split", "listing", "card", "coupon"}


# --------------------------------------------------------------- word list

# The copy every pack's templates are written in: for each topic, its
# category, its styles (the first combination of a base comes from the
# first, the second from the second), its bases — a size, a layout and the
# copy it takes — and the copy.
TOPICS = [
    {
        "topic": "real-estate", "label": "Real Estate", "category": "Business", "styles": ["corporate", "elegant"],
        "bases": [("insta-post", "hero", 0), ("insta-story", "split", 1), ("flyer-letter", "split", 2),
                  ("facebook-post", "hero", 3), ("postcard", "centered", 0), ("insta-portrait", "centered", 1),
                  ("business-card", "card", 0)],
        "copy": [
            {"name": "Open House", "kicker": "Open house this Sunday", "headline": "Your Next Home Starts Here",
             "body": "Three bedrooms, a sunny garden and a kitchen made for long dinners.",
             "cta": "Book a viewing", "detail": "14 Linden Avenue · 1 to 4 pm",
             "points": ["3 bedrooms, 2 baths", "South-facing garden", "Walk to the station"]},
            {"name": "Just Listed", "kicker": "Just listed", "headline": "Light-Filled Loft in the Old Mill",
             "body": "Exposed brick, tall windows and a rooftop terrace with city views.",
             "cta": "See the listing", "detail": "Offers over 425,000",
             "points": ["1,200 sq ft open plan", "Private roof terrace", "Secure parking"]},
            {"name": "Sold In Days", "kicker": "Sold in 6 days", "headline": "Thinking of Selling? Let's Talk",
             "body": "A free, no-pressure valuation from the agents who know your street.",
             "cta": "Get a valuation", "detail": "Harbour & Hill Estates",
             "points": ["Free valuation", "Local market report", "Photos and floor plans"]},
            {"name": "Dream Home", "kicker": "New development", "headline": "Riverside Homes Now Selling",
             "body": "Two and three bedroom homes, ready to move into this spring.",
             "cta": "Register interest", "detail": "Show home open daily",
             "points": ["Energy rated A", "Ten-year warranty", "Help to buy accepted"]},
        ],
        "cards": [{"name": "Maya Ellison", "initials": "ME", "role": "Real estate agent",
                   "contacts": ["(555) 214-8890", "maya@harbourhill.homes", "harbourhill.homes"]}],
    },
    {
        "topic": "fitness", "label": "Fitness", "category": "Personal", "styles": ["bold", "minimal"],
        "bases": [("insta-post", "hero", 0), ("insta-story", "centered", 1), ("flyer-letter", "hero", 2),
                  ("facebook-post", "split", 3), ("pinterest-pin", "split", 0), ("insta-portrait", "hero", 1),
                  ("poster", "centered", 2)],
        "copy": [
            {"name": "Strong Start", "kicker": "New member offer", "headline": "Train Harder, Feel Stronger",
             "body": "Your first month of classes for half price, every class included.",
             "cta": "Join today", "detail": "Ironworks Gym · Open 5 am to 11 pm",
             "points": ["50 classes a week", "Personal coaching", "No joining fee"]},
            {"name": "Morning Hiit", "kicker": "6:30 am every weekday", "headline": "Morning HIIT Club",
             "body": "Thirty minutes, all levels welcome, done before your coffee cools.",
             "cta": "Save my spot", "detail": "Bring water and a towel",
             "points": ["30 minute sessions", "All levels welcome", "First class free"]},
            {"name": "Summer Shred", "kicker": "8 week challenge", "headline": "The Summer Shred Starts Monday",
             "body": "Workouts, meal plans and weekly check-ins with a coach.",
             "cta": "Take the challenge", "detail": "Limited to 40 places",
             "points": ["Weekly weigh-ins", "Meal plan included", "Prizes for the top 3"]},
            {"name": "Yoga Flow", "kicker": "Breathe and move", "headline": "Sunrise Yoga in the Park",
             "body": "Gentle flow for every body, mats provided, by donation.",
             "cta": "Find a class", "detail": "Saturdays at 8 am",
             "points": ["Mats provided", "Beginners welcome", "Pay what you can"]},
        ],
    },
    {
        "topic": "restaurant", "label": "Restaurant", "category": "Food", "styles": ["elegant", "playful"],
        "bases": [("menu", "listing", 0), ("a4", "listing", 1), ("insta-post", "hero", 0),
                  ("insta-story", "centered", 1), ("facebook-post", "split", 2), ("flyer-letter", "centered", 2),
                  ("insta-portrait", "split", 3)],
        "copy": [
            {"name": "Supper Menu", "kicker": "Tonight's specials", "headline": "Fresh Pasta Made Every Morning",
             "body": "Hand-rolled tagliatelle, slow-cooked ragù and a glass of house red.",
             "cta": "Reserve a table", "detail": "Trattoria Nonna · Tue to Sun",
             "points": ["Hand-rolled pasta", "Wood-fired oven", "Family recipes"]},
            {"name": "Brunch Club", "kicker": "Weekends 9 to 3", "headline": "Bottomless Brunch",
             "body": "Pancake towers, eggs your way and coffee that keeps coming.",
             "cta": "Book brunch", "detail": "Groups of up to 12",
             "points": ["Vegan options", "Kids eat free", "Live music Sundays"]},
            {"name": "Taco Tuesday", "kicker": "Every Tuesday", "headline": "Three Tacos, One Price",
             "body": "Carnitas, charred corn and the hottest salsa on the block.",
             "cta": "Order now", "detail": "Dine in or take away",
             "points": ["Fresh tortillas", "House salsas", "Happy hour 5 to 7"]},
            {"name": "Bakery Fresh", "kicker": "Baked before sunrise", "headline": "Warm Bread, Every Day",
             "body": "Sourdough, croissants and cinnamon buns straight from the oven.",
             "cta": "Visit us", "detail": "Open from 7 am",
             "points": ["Sourdough daily", "Gluten-free loaves", "Custom cakes"]},
        ],
        "lists": [
            {"name": "Dinner Menu", "title": "Trattoria Nonna", "subtitle": "Dinner menu",
             "items": [("Burrata, heirloom tomato", "12"), ("Tagliatelle al ragù", "18"),
                       ("Wild mushroom risotto", "17"), ("Grilled sea bream", "24"), ("Tiramisu", "8")],
             "total": ("Set menu, three courses", "35"), "footer": "Please tell us about any allergies"},
            {"name": "Cafe Price List", "title": "Morning Ritual Café", "subtitle": "Coffee and bakes",
             "items": [("Flat white", "3.40"), ("Oat latte", "3.80"), ("Almond croissant", "3.20"),
                       ("Banana bread", "2.90"), ("Avocado toast", "7.50")],
             "total": ("Coffee and a bake", "5.90"), "footer": "Oat and soy milk at no extra cost"},
        ],
    },
    {
        "topic": "beauty", "label": "Beauty", "category": "Marketing", "styles": ["elegant", "minimal"],
        "bases": [("insta-post", "centered", 0), ("insta-story", "hero", 1), ("facebook-post", "hero", 2),
                  ("flyer-letter", "split", 3), ("business-card", "card", 0), ("insta-portrait", "centered", 2),
                  ("pinterest-pin", "hero", 3)],
        "copy": [
            {"name": "Glow Up", "kicker": "New treatment", "headline": "The Signature Glow Facial",
             "body": "Sixty minutes of cleansing, massage and a mask made for your skin.",
             "cta": "Book now", "detail": "Lumière Skin Studio",
             "points": ["Skin consultation", "Hydrating mask", "Take-home samples"]},
            {"name": "Salon Week", "kicker": "This week only", "headline": "20% Off Colour and Cut",
             "body": "Balayage, glosses and fresh cuts with our senior stylists.",
             "cta": "Book a chair", "detail": "Velvet Hair Lounge",
             "points": ["Senior stylists", "Free consultation", "Late opening Thu"]},
            {"name": "Nail Bar", "kicker": "Walk-ins welcome", "headline": "Gel Nails in 45 Minutes",
             "body": "Long-lasting colour in over a hundred shades, chip-free for weeks.",
             "cta": "See our shades", "detail": "Polished Nail Bar",
             "points": ["100+ shades", "Nail art", "Loyalty card"]},
            {"name": "Spa Day", "kicker": "Treat yourself", "headline": "A Spa Day Just for You",
             "body": "Massage, sauna and a light lunch in the garden lounge.",
             "cta": "Gift a spa day", "detail": "Gift cards available",
             "points": ["Full body massage", "Sauna and steam", "Lunch included"]},
        ],
        "cards": [{"name": "Lena Moreau", "initials": "LM", "role": "Skin therapist",
                   "contacts": ["(555) 310-4477", "lena@lumiereskin.studio", "@lumiereskin"]}],
    },
    {
        "topic": "wedding", "label": "Wedding", "category": "Events", "styles": ["elegant", "minimal"],
        "bases": [("invitation", "centered", 0), ("invitation", "hero", 1), ("insta-post", "centered", 2),
                  ("insta-story", "centered", 3), ("postcard", "split", 0), ("a4", "listing", 0),
                  ("facebook-post", "hero", 2)],
        "copy": [
            {"name": "Wedding Invite", "kicker": "Together with their families", "headline": "Amelia & James",
             "body": "Request the pleasure of your company at their wedding.",
             "cta": "RSVP by May 1", "detail": "June 14 · Hartwell House · 3 pm",
             "points": ["Ceremony at 3 pm", "Dinner and dancing", "Carriages at midnight"]},
            {"name": "Save Our Date", "kicker": "Save the date", "headline": "Sofia and Daniel Are Getting Married",
             "body": "Formal invitation to follow. We can't wait to celebrate with you.",
             "cta": "Save the date", "detail": "09.21 · Lake Como",
             "points": ["Welcome drinks Friday", "Wedding Saturday", "Brunch Sunday"]},
            {"name": "Thank You Guests", "kicker": "Thank you", "headline": "For Making Our Day",
             "body": "Your love, laughter and dancing made it the best day of our lives.",
             "cta": "See the photos", "detail": "With love, Priya & Tom",
             "points": ["Photos online", "Playlist shared", "Cake recipe inside"]},
            {"name": "Engagement Party", "kicker": "She said yes", "headline": "Engagement Party",
             "body": "Join us for drinks, nibbles and a toast to the happy couple.",
             "cta": "Let us know", "detail": "Saturday 8 pm · The Glasshouse",
             "points": ["Cocktails", "Live band", "Dress to impress"]},
        ],
        "lists": [
            {"name": "Wedding Day Order", "title": "Our Wedding Day", "subtitle": "Order of the day",
             "items": [("Ceremony", "2:00"), ("Drinks on the lawn", "3:00"), ("Wedding breakfast", "5:00"),
                       ("Speeches", "7:00"), ("First dance", "8:30")],
             "total": ("Carriages", "12:00"), "footer": "Amelia & James · June 14"},
        ],
    },
    {
        "topic": "education", "label": "Education", "category": "Education", "styles": ["playful", "corporate"],
        "bases": [("presentation", "split", 0), ("presentation", "hero", 1), ("a4", "listing", 0),
                  ("insta-post", "centered", 2), ("flyer-letter", "hero", 3), ("facebook-post", "split", 1),
                  ("poster", "centered", 0)],
        "copy": [
            {"name": "Lesson Opener", "kicker": "Science · Year 7", "headline": "How Plants Make Food",
             "body": "Today we follow sunlight, water and air into a leaf.",
             "cta": "Let's begin", "detail": "Lesson 4 of 12",
             "points": ["What a leaf needs", "Where sugar comes from", "Try it at home"]},
            {"name": "Study Skills", "kicker": "Exam season", "headline": "Five Ways to Study Smarter",
             "body": "Short sessions, spaced practice and testing yourself beat cramming.",
             "cta": "Get the guide", "detail": "Library study hall",
             "points": ["Spaced repetition", "Practice tests", "Teach a friend"]},
            {"name": "Open Evening", "kicker": "You're invited", "headline": "Open Evening for New Families",
             "body": "Meet our teachers, see the labs and ask us anything.",
             "cta": "Book a place", "detail": "Thursday 6 pm · Main hall",
             "points": ["Tours every 20 minutes", "Meet the head", "Clubs fair"]},
            {"name": "Book Fair", "kicker": "This week", "headline": "The Great Book Fair",
             "body": "Hundreds of new books, author visits and story time every lunch.",
             "cta": "Come and browse", "detail": "School library",
             "points": ["Author visits", "Story time", "Every book 20% off"]},
        ],
        "lists": [
            {"name": "Class Timetable", "title": "Year 7 Timetable", "subtitle": "Autumn term",
             "items": [("Maths", "9:00"), ("English", "10:00"), ("Science lab", "11:15"),
                       ("Lunch", "12:30"), ("History", "1:30")],
             "total": ("Clubs", "3:15"), "footer": "Bring your planner every day"},
        ],
    },
    {
        "topic": "nonprofit", "label": "Nonprofit", "category": "Events", "styles": ["playful", "corporate"],
        "bases": [("insta-post", "hero", 0), ("insta-story", "split", 1), ("flyer-letter", "centered", 2),
                  ("facebook-post", "hero", 3), ("poster", "split", 0), ("presentation", "split", 1),
                  ("pinterest-pin", "centered", 2)],
        "copy": [
            {"name": "Food Drive", "kicker": "Community food drive", "headline": "Every Can Feeds a Family",
             "body": "Drop off tins, pasta and rice at any branch until Friday.",
             "cta": "Find a drop-off", "detail": "Riverside Food Bank",
             "points": ["Tins and dried food", "Toiletries", "Baby supplies"]},
            {"name": "Volunteer Day", "kicker": "Volunteers wanted", "headline": "Give a Day, Change a Park",
             "body": "Planting, painting and a picnic lunch for everyone who helps.",
             "cta": "Sign up", "detail": "Saturday 10 am · Elm Park",
             "points": ["Tools provided", "Lunch on us", "All ages welcome"]},
            {"name": "Charity Run", "kicker": "5k fun run", "headline": "Run for Clean Water",
             "body": "Every kilometre you run funds a well in a village that needs one.",
             "cta": "Register now", "detail": "Sunday 9 am · Harbour front",
             "points": ["Medal for everyone", "Family route", "Live music"]},
            {"name": "Animal Rescue", "kicker": "Adopt, don't shop", "headline": "Meet Your New Best Friend",
             "body": "Dogs and cats waiting for a home, vaccinated and ready to love.",
             "cta": "Meet them", "detail": "Second Chance Rescue",
             "points": ["Vaccinated", "Microchipped", "Lifetime support"]},
        ],
    },
    {
        "topic": "tech", "label": "Tech", "category": "Business", "styles": ["minimal", "corporate"],
        "bases": [("presentation", "hero", 0), ("presentation", "split", 1), ("linkedin-post", "hero", 2),
                  ("insta-post", "split", 3), ("insta-story", "hero", 0), ("business-card", "card", 0),
                  ("facebook-post", "centered", 1)],
        "copy": [
            {"name": "Product Launch", "kicker": "Now available", "headline": "Meet Orbit 2.0",
             "body": "Faster sync, offline mode and a dashboard your whole team can read.",
             "cta": "Start free trial", "detail": "orbit.app",
             "points": ["Twice as fast", "Works offline", "Team dashboards"]},
            {"name": "Webinar Live", "kicker": "Free webinar", "headline": "Shipping Faster with Small Teams",
             "body": "Our CTO on the habits that took us from monthly to daily releases.",
             "cta": "Save my seat", "detail": "Thursday 5 pm GMT",
             "points": ["Live Q&A", "Slides included", "Recording sent after"]},
            {"name": "We Are Hiring", "kicker": "We're hiring", "headline": "Senior Android Engineer",
             "body": "Remote-first, four-day weeks and a product people love.",
             "cta": "Apply now", "detail": "Kotlin · Compose · Remote",
             "points": ["Remote-first", "Four-day week", "Learning budget"]},
            {"name": "Feature Update", "kicker": "What's new", "headline": "Dark Mode Is Here",
             "body": "Easier on the eyes at night, and it follows your phone's setting.",
             "cta": "Update now", "detail": "Version 4.2",
             "points": ["Follows your phone", "Custom accents", "Battery friendly"]},
        ],
        "cards": [{"name": "Ravi Patel", "initials": "RP", "role": "Lead engineer",
                   "contacts": ["(555) 902-1188", "ravi@orbit.app", "github.com/ravip"]}],
    },
    {
        "topic": "travel", "label": "Travel", "category": "Travel", "styles": ["playful", "elegant"],
        "bases": [("insta-post", "hero", 0), ("insta-story", "centered", 1), ("postcard", "hero", 2),
                  ("facebook-post", "split", 3), ("pinterest-pin", "split", 0), ("flyer-letter", "hero", 1),
                  ("insta-portrait", "centered", 2)],
        "copy": [
            {"name": "Island Escape", "kicker": "7 nights from 899", "headline": "Escape to the Islands",
             "body": "Turquoise water, white sand and nothing to do but swim.",
             "cta": "Book your trip", "detail": "Flights and hotel included",
             "points": ["Beachfront villa", "Breakfast daily", "Boat day trip"]},
            {"name": "City Break", "kicker": "Weekend in Lisbon", "headline": "Three Days, One City",
             "body": "Trams, tiles, custard tarts and sunsets from the viewpoints.",
             "cta": "See the itinerary", "detail": "Spring departures",
             "points": ["Old town walking tour", "Tram 28 ride", "Fado night"]},
            {"name": "Mountain Trek", "kicker": "Guided trek", "headline": "Walk the Alps This Summer",
             "body": "Hut to hut across high meadows, with a guide and your bags carried.",
             "cta": "Join the trek", "detail": "Small groups of 10",
             "points": ["6 days walking", "Mountain huts", "Bags carried"]},
            {"name": "Road Trip", "kicker": "Coastal road trip", "headline": "The Long Way Round",
             "body": "Cliffs, lighthouses and fish and chips on the harbour wall.",
             "cta": "Plan the route", "detail": "Car hire from 29 a day",
             "points": ["8 coastal towns", "Hidden beaches", "Sunset stops"]},
        ],
    },
    {
        "topic": "receipts", "label": "Receipts", "category": "Business", "styles": ["minimal", "corporate"],
        "bases": [("a4", "listing", 0), ("us-letter", "listing", 1), ("a4", "listing", 2), ("us-letter", "listing", 3),
                  ("insta-portrait", "listing", 1), ("a4", "listing", 3), ("us-letter", "listing", 0)],
        "copy": [],
        "lists": [
            {"name": "Studio Invoice", "title": "Invoice #0042", "subtitle": "Northlight Design Studio",
             "items": [("Brand identity", "1,800.00"), ("Logo files and guide", "450.00"),
                       ("Business cards, 500", "120.00"), ("Website hero images", "600.00"), ("Revisions, 2 rounds", "0.00")],
             "total": ("Total due", "2,970.00"), "footer": "Payment due within 30 days · Thank you"},
            {"name": "Shop Receipt", "title": "Receipt", "subtitle": "The Corner Shop · Order 1187",
             "items": [("Sourdough loaf", "4.50"), ("Free-range eggs, 12", "3.80"), ("Oat milk", "1.95"),
                       ("Coffee beans, 250 g", "8.00"), ("Seasonal flowers", "6.00")],
             "total": ("Total paid", "24.25"), "footer": "Thank you for shopping local"},
            {"name": "Freelance Invoice", "title": "Invoice", "subtitle": "Jo Carter · Photographer",
             "items": [("Half-day shoot", "650.00"), ("Editing, 40 images", "320.00"), ("Travel", "45.00"),
                       ("Usage licence, 1 year", "250.00"), ("Rush delivery", "80.00")],
             "total": ("Amount due", "1,345.00"), "footer": "Bank transfer · Ref INV-2026-118"},
            {"name": "Repair Estimate", "title": "Estimate", "subtitle": "Fixit Home Repairs",
             "items": [("Call-out", "60.00"), ("Replace kitchen tap", "95.00"), ("Fit two shelves", "70.00"),
                       ("Parts and materials", "48.00"), ("Waste removal", "25.00")],
             "total": ("Estimated total", "298.00"), "footer": "Valid for 30 days"},
        ],
    },
    {
        "topic": "coupons", "label": "Coupons", "category": "Marketing", "styles": ["bold", "playful"],
        "bases": [("gift-certificate", "coupon", 0), ("ticket", "coupon", 1), ("insta-post", "coupon", 2),
                  ("facebook-post", "coupon", 3), ("gift-certificate", "coupon", 1), ("postcard", "coupon", 0),
                  ("ticket", "coupon", 2)],
        "copy": [],
        "coupons": [
            {"name": "Coffee Coupon", "kicker": "Coupon", "offer": "20% OFF", "body": "Any drink at Morning Ritual Café",
             "code": "CODE: BREW20", "expiry": "Ends 31 December"},
            {"name": "Free Dessert", "kicker": "Treat on us", "offer": "FREE", "body": "Dessert with any main course",
             "code": "CODE: SWEET", "expiry": "Dine in only"},
            {"name": "Spring Sale", "kicker": "Spring sale", "offer": "BUY 1 GET 1", "body": "On every plant in the greenhouse",
             "code": "CODE: BLOOM", "expiry": "This weekend only"},
            {"name": "Gift Voucher", "kicker": "Gift voucher", "offer": "50", "body": "To spend on anything in store",
             "code": "No. 004127", "expiry": "Valid for 12 months"},
        ],
    },
    {
        "topic": "business-cards", "label": "Business Cards", "category": "Business", "styles": ["minimal", "elegant"],
        "bases": [("business-card", "card", 0), ("business-card", "card", 1), ("business-card", "card", 2),
                  ("business-card", "card", 3), ("business-card", "card", 4), ("business-card", "card", 5),
                  ("business-card", "card", 6)],
        "copy": [],
        "cards": [
            {"name": "Ada Okafor", "initials": "AO", "role": "Architect",
             "contacts": ["(555) 448-2210", "ada@okaforstudio.com", "okaforstudio.com"]},
            {"name": "Tom Lindqvist", "initials": "TL", "role": "Photographer",
             "contacts": ["(555) 671-0932", "hello@tomlind.photo", "@tomlindphoto"]},
            {"name": "Grace Chen", "initials": "GC", "role": "Family lawyer",
             "contacts": ["(555) 209-5561", "g.chen@chenlegal.law", "12 Court Street"]},
            {"name": "Luis Romero", "initials": "LR", "role": "Head chef",
             "contacts": ["(555) 390-7714", "luis@casaromero.kitchen", "casaromero.kitchen"]},
            {"name": "Nadia Haddad", "initials": "NH", "role": "Yoga teacher",
             "contacts": ["(555) 556-0040", "nadia@stillpoint.yoga", "@stillpointyoga"]},
            {"name": "Owen Brooks", "initials": "OB", "role": "Electrician",
             "contacts": ["(555) 781-3302", "owen@brookselectric.co", "24 hour call-outs"]},
            {"name": "Hana Sato", "initials": "HS", "role": "Product designer",
             "contacts": ["(555) 120-8846", "hana@hanasato.design", "hanasato.design"]},
        ],
    },
]


def copy_for(pack, layout, index):
    """The copy a base takes: a list's, a card's or a coupon's for those
    layouts, else the pack's general copy — each by its place, round."""
    key = {"listing": "lists", "card": "cards", "coupon": "coupons"}.get(layout, "copy")
    pool = pack.get(key) or pack["copy"]
    return pool[index % len(pool)]


def seeded(key):
    return random.Random(zlib.crc32(key.encode("utf-8")))


def strip(els):
    return [el for _, el in els]


def variants():
    """Every pack's bases, each in 4 colourways x 2 font combinations."""
    out = []
    for pack in TOPICS:
        for b, (size_id, layout, index) in enumerate(pack["bases"]):
            c = copy_for(pack, layout, index)
            base_id = f"{pack['topic']}-{size_id}-{layout}-{b + 1}"
            rng = seeded(base_id)
            colourways = rng.sample(range(len(PALETTES)), 4)
            pairs = []
            for style in pack["styles"]:
                pool = PAIRS[style]
                pairs.append((style, pool[rng.randrange(len(pool))]))
            still = STILLS[rng.randrange(len(STILLS))]
            for v in range(8):
                cw, f = divmod(v, 2)
                word, colours = PALETTES[colourways[cw]]
                style, pair = pairs[f]
                mirror = cw % 2 == 1
                photo = "asset:" + still if (cw + f) % 2 == 1 and layout in PHOTO_LAYOUTS else None
                p = laid_out(size_id, roles(colours, dark=cw in (1, 2)), pair, mirror, layout, c, photo)
                # The base is named for its copy and its type; a colourway
                # adds its palette's word, and a photo variant says so.
                name = f"{c['name']} {SIZE_WORDS[size_id]}"
                if v:
                    name += f" {word}" + (" Photo" if photo else "")
                t = {
                    "id": base_id if v == 0 else f"{base_id}-v{v + 1}",
                    "name": name,
                    "category": pack["category"],
                    "sizeId": size_id,
                    "topic": pack["topic"],
                    "style": style,
                    "background": {"kind": "color", "color": p.pal["bg"]},
                    "elements": strip(p.els),
                }
                if v:
                    t["variantOf"] = base_id
                out.append(t)
    return out


# ---------------------------------------------------------------- animated

# Each role's entrance in an animated template, by the template's recipe
# (its place, round): what the headline does, how the rest arrive.
HEADLINE_MOTION = [
    {"kind": "ascend", "by": "letter"}, {"kind": "words", "by": "word"}, {"kind": "lineRise", "by": "line"},
    {"kind": "typewriter", "by": "letter"}, {"kind": "bounceIn", "by": "word"}, {"kind": "clarify", "by": "line"},
    {"kind": "letterPop", "by": "letter"}, {"kind": "spread", "by": "word"}, {"kind": "baseline"},
]
REST_MOTION = ["rise", "fade", "slideLeft", "pop", "breathe", "drift", "wipe"]
PAGE_MOTION = ["rise", "fade", "pan", "breathe", "tumble", "stomp"]
SET_TRANSITIONS = ["fade", "slide", "push", "zoom", "wipe", "circle"]


def animate(els, n, pace=1.0):
    """[els] with entrances by role: the headline by its recipe's text
    motion, a photo zooming or panning, decoration drawing on or
    twinkling, the rest arriving one after another by the recipe's kind;
    and the headline leaving by fading at the page's end."""
    headline = dict(HEADLINE_MOTION[n % len(HEADLINE_MOTION)])
    rest = REST_MOTION[n % len(REST_MOTION)]
    out = []
    delay = 0.0
    for role, el in els:
        el = dict(el)
        if role == "headline":
            el["animation"] = {**headline, "delay": round(delay, 2), "duration": round(1.2 * pace, 2)}
            el["exitAnimation"] = {"kind": "fade", "delay": 0.0, "duration": 0.5}
            delay += 0.5 * pace
        elif role == "photo":
            el["animation"] = {"kind": "photoZoom" if n % 2 == 0 else "photoPan", "delay": 0.0, "duration": 1.0}
        elif role == "decor":
            el["animation"] = ({"kind": "twinkle", "delay": round(delay, 2), "duration": 0.6} if n % 3 == 0
                               else {"kind": "draw", "delay": 0.0, "duration": 1.2})
        elif role == "panel":
            el["animation"] = {"kind": "wipe", "delay": 0.0, "duration": round(0.6 * pace, 2)}
        else:
            el["animation"] = {"kind": rest, "delay": round(delay, 2), "duration": round(0.6 * pace, 2)}
            delay += 0.25 * pace
        out.append(el)
    return out


def motion_background(rng):
    """One of Motion.json's loops playing behind the page."""
    return {"kind": "image", "src": "motion:" + LOOPS[rng.randrange(len(LOOPS))]}


# What each kind of animated template is: its size, its layouts in turn,
# its category and the copy it takes, and how many.
ANIMATED = [
    ("reel", "insta-reel", ["hero", "centered", "split"], "Social", 7),
    ("story", "insta-story", ["centered", "split", "hero"], "Social", 7),
    ("tiktok", "tiktok-video", ["split", "hero", "centered"], "Social", 7),
    ("post", "insta-post", ["hero", "split", "centered"], "Marketing", 7),
    ("intro", "youtube-video", ["centered", "hero"], "Personal", 6),
    ("invite", "invitation", ["centered", "hero"], "Events", 5),
]

ANIMATED_COPY = [
    {"name": "New Drop Friday", "kicker": "Midnight launch", "headline": "New Drop Friday",
     "body": "Twelve new pieces, one night only, in sizes for everyone.", "cta": "Shop the drop",
     "detail": "Link in bio", "points": ["Limited run", "Free shipping", "Easy returns"]},
    {"name": "Day In My Life", "kicker": "Vlog", "headline": "A Day in My Life",
     "body": "Coffee, a studio session and a sunset ride home.", "cta": "Watch now",
     "detail": "New every Sunday", "points": ["Morning routine", "Studio tour", "Golden hour"]},
    {"name": "Recipe In 60", "kicker": "60 second recipe", "headline": "Crispy Chilli Noodles",
     "body": "Five ingredients, one pan, ready before the rice cooker clicks.", "cta": "Save this recipe",
     "detail": "Serves two", "points": ["5 ingredients", "1 pan", "10 minutes"]},
    {"name": "Workout Countdown", "kicker": "3 rounds", "headline": "Ten Minute Burn",
     "body": "Squats, push-ups and mountain climbers, no kit needed.", "cta": "Start the timer",
     "detail": "Rest 30 seconds between", "points": ["Squats", "Push-ups", "Mountain climbers"]},
    {"name": "Big Announcement", "kicker": "It's official", "headline": "We're Opening a Second Shop",
     "body": "Same coffee, more seats, right by the river.", "cta": "See you there",
     "detail": "Opening March 3", "points": ["Bigger kitchen", "River terrace", "Late opening"]},
    {"name": "Flash Sale", "kicker": "24 hours only", "headline": "Flash Sale 40% Off",
     "body": "Everything in store and online until midnight.", "cta": "Shop now",
     "detail": "Code FLASH40", "points": ["Everything 40% off", "Online and in store", "Ends midnight"]},
    {"name": "Travel Diary", "kicker": "Postcards from", "headline": "Kyoto in Autumn",
     "body": "Temples, maple leaves and the best ramen of my life.", "cta": "Follow the trip",
     "detail": "Part 1 of 5", "points": ["Fushimi Inari", "Arashiyama", "Gion at night"]},
    {"name": "Podcast Episode", "kicker": "New episode", "headline": "Building in Public",
     "body": "What we learned sharing every number for a year.", "cta": "Listen now",
     "detail": "Episode 42", "points": ["Revenue", "Mistakes", "What's next"]},
]

INVITE_COPY = [
    {"name": "Birthday Bash", "kicker": "You're invited", "headline": "Maya Turns Thirty",
     "body": "Dinner, dancing and far too much cake.", "cta": "RSVP by June 2",
     "detail": "Saturday 7 pm · The Rooftop", "points": []},
    {"name": "Garden Party", "kicker": "Join us", "headline": "A Summer Garden Party",
     "body": "Lemonade, lawn games and a long table under the trees.", "cta": "Let us know",
     "detail": "Sunday 2 pm · 8 Orchard Lane", "points": []},
    {"name": "Baby Shower", "kicker": "Oh baby", "headline": "A Shower for Ella",
     "body": "Tea, cake and wishes for the little one on the way.", "cta": "RSVP to Jess",
     "detail": "May 18 · 3 pm", "points": []},
    {"name": "Wedding Celebration", "kicker": "Save the date", "headline": "Leo & Ana",
     "body": "We're getting married, and we'd love you there.", "cta": "Invitation to follow",
     "detail": "08.30 · Seville", "points": []},
    {"name": "Graduation Party", "kicker": "Class of 2026", "headline": "Sam Graduated",
     "body": "Come and celebrate with food, music and proud parents.", "cta": "RSVP by Friday",
     "detail": "July 12 · 5 pm", "points": []},
]

DECKS = [
    {"name": "Animated Pitch", "topic": "tech", "copy": [
        {"kicker": "Seed round 2026", "headline": "Orbit: Sync for Small Teams", "body": "The calm way to share work.",
         "points": [], "detail": "orbit.app", "title": "Title"},
        {"kicker": "The problem", "headline": "Files Live in Ten Places", "body": "Teams lose an hour a day hunting for the latest version.",
         "points": ["Scattered tools", "Lost versions", "Slow handoffs"], "detail": "Survey of 400 teams", "title": "Problem"},
        {"kicker": "Our answer", "headline": "One Shared Space", "body": "Everything your team makes, synced and searchable.",
         "points": ["Works offline", "Instant search", "Every version kept"], "detail": "Live since March", "title": "Solution"},
        {"kicker": "Traction", "headline": "1,200 Teams in Six Months", "body": "Growing 18% month on month with no paid ads.",
         "points": ["18% monthly growth", "92% retention", "NPS of 61"], "detail": "As of September", "title": "Traction"},
        {"kicker": "Thank you", "headline": "Let's Build It Together", "body": "Raising 1.5M to grow the team to twelve.",
         "points": [], "detail": "hello@orbit.app", "title": "Close"},
    ]},
    {"name": "Animated Lesson", "topic": "education", "copy": [
        {"kicker": "Geography", "headline": "Why Volcanoes Erupt", "body": "A journey to the centre of the Earth.",
         "points": [], "detail": "Lesson 3", "title": "Title"},
        {"kicker": "Inside the Earth", "headline": "Layers Under Our Feet", "body": "Crust, mantle and a core as hot as the sun's surface.",
         "points": ["Crust", "Mantle", "Core"], "detail": "Draw the layers", "title": "Layers"},
        {"kicker": "Pressure", "headline": "Magma Rises", "body": "Molten rock is lighter than the rock around it, so it pushes up.",
         "points": ["Heat", "Gas", "Pressure"], "detail": "Think: a shaken bottle", "title": "Magma"},
        {"kicker": "Types", "headline": "Three Kinds of Volcano", "body": "Shield, cinder cone and stratovolcano.",
         "points": ["Shield", "Cinder cone", "Stratovolcano"], "detail": "Which is Etna?", "title": "Types"},
        {"kicker": "Your turn", "headline": "Build a Model Volcano", "body": "Baking soda, vinegar and a little washing-up liquid.",
         "points": [], "detail": "Due next Tuesday", "title": "Activity"},
    ]},
    {"name": "Animated Report", "topic": "business", "copy": [
        {"kicker": "Quarterly review", "headline": "Q3 at a Glance", "body": "Northwind Retail, July to September.",
         "points": [], "detail": "Board meeting", "title": "Title"},
        {"kicker": "Revenue", "headline": "Sales Up 14%", "body": "Online grew fastest, led by the new mobile checkout.",
         "points": ["Online up 31%", "Stores up 6%", "Wholesale flat"], "detail": "Year on year", "title": "Revenue"},
        {"kicker": "Customers", "headline": "40,000 New Customers", "body": "Most found us through referrals and reviews.",
         "points": ["Referrals 38%", "Search 27%", "Social 21%"], "detail": "Q3 sign-ups", "title": "Customers"},
        {"kicker": "Next quarter", "headline": "Three Priorities", "body": "Faster delivery, a loyalty scheme and two new stores.",
         "points": ["Next-day delivery", "Loyalty launch", "Two new stores"], "detail": "Owners named", "title": "Priorities"},
        {"kicker": "Questions", "headline": "Thank You", "body": "Full figures are in the appendix.",
         "points": [], "detail": "finance@northwind.example", "title": "Close"},
    ]},
]


def animated():
    out = []
    for k, (kind, size_id, layouts, category, count) in enumerate(ANIMATED):
        pool = INVITE_COPY if kind == "invite" else ANIMATED_COPY
        for i in range(count):
            n = len(out)
            # Each kind starts the copy at a place of its own.
            c = pool[(i + k * 3) % len(pool)]
            tid = f"animated-{kind}-{i + 1}"
            rng = seeded(tid)
            layout = layouts[i % len(layouts)]
            colours = PALETTES[rng.randrange(len(PALETTES))][1]
            style = ["bold", "playful", "elegant", "minimal", "corporate"][rng.randrange(5)]
            pool_pairs = PAIRS["elegant" if kind == "invite" else style]
            pair = pool_pairs[rng.randrange(len(pool_pairs))]
            pal = roles(colours, dark=rng.random() < 0.6)
            photo = "asset:" + STILLS[rng.randrange(len(STILLS))] if layout != "split" and i % 2 == 1 else None
            if layout == "split" and not c["points"]:
                layout = "centered"
            p = laid_out(size_id, pal, pair, False, layout, c, photo)
            page = {"background": motion_background(rng) if i % 3 != 2 else {"kind": "color", "color": p.pal["bg"]},
                    "elements": animate(p.els, n), "duration": 6 if kind != "intro" else 5}
            if i % 4 == 3:
                page["pageAnimation"] = {"kind": PAGE_MOTION[n % len(PAGE_MOTION)], "mode": "exit"}
            # Its one page under "pages", as a page's duration and
            # animation are said there.
            name = c["name"] if kind == "invite" else f"{c['name']} {SIZE_WORDS[size_id]}"
            t = {"id": tid, "name": name, "category": category, "sizeId": size_id, "style": style,
                 "topic": "animated", "pages": [page]}
            if i % 2 == 0:
                t["soundtrack"] = "sfx:" + ["whoosh", "riser", "sparkle", "chime", "swoosh", "drop"][n % 6]
            out.append(t)
    for d, deck in enumerate(DECKS):
        tid = f"animated-deck-{d + 1}"
        rng = seeded(tid)
        colours = PALETTES[rng.randrange(len(PALETTES))][1]
        style = ["corporate", "playful", "minimal"][d]
        pair = PAIRS[style][rng.randrange(len(PAIRS[style]))]
        pages = []
        for k, c in enumerate(deck["copy"]):
            layout = "centered" if k in (0, 4) else "split"
            p = laid_out("presentation", roles(colours, dark=k in (0, 4)), pair, k % 2 == 1, layout,
                         {**c, "name": deck["name"]}, None)
            page = {"background": motion_background(rng) if k in (0, 4) else {"kind": "color", "color": p.pal["bg"]},
                    "elements": animate(p.els, d * 5 + k, pace=0.8),
                    "title": c["title"], "transition": SET_TRANSITIONS[(d + k) % len(SET_TRANSITIONS)],
                    "duration": 8}
            if k == 2:
                page["pageAnimation"] = {"kind": PAGE_MOTION[d % len(PAGE_MOTION)], "mode": "both"}
            pages.append(page)
        out.append({"id": tid, "name": deck["name"], "category": "Business" if d != 1 else "Education",
                    "sizeId": "presentation", "style": style, "topic": "animated", "pages": pages,
                    "soundtrack": "sfx:chime"})
    return out


def write(path, templates):
    with open(path, "w") as fh:
        json.dump(templates, fh, indent=1, ensure_ascii=False)
        fh.write("\n")
    print(f"wrote {os.path.relpath(path, ROOT)} ({len(templates)} templates)")


def main():
    write(VARIANTS_OUT, variants())
    write(ANIMATED_OUT, animated())


if __name__ == "__main__":
    main()
