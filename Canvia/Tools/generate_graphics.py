#!/usr/bin/env python3
"""Regenerate both phones' illustrated graphics pack.

    tools/generate_graphics.py [path/to/ios/Content]

Writes core/src/main/resources/com/canvia/core/content/Graphics.json and,
given a folder, the same file there for the iOS twin to bundle, so the two
apps draw every graphic from the same bytes. Nothing is downloaded: every
graphic is drawn here, from seeded random paths given a jitter pass for a
hand-drawn look, so the same script writes the same file on any machine.

The file is one object:

  "categories"  the fourteen categories, in the order Add shows them.
  "graphics"    each {"id", "name", "category", "tags": [...], "svg",
                "colours": [...]}, category by category, and a moving one's
                "motion". "svg" is a whole SVG document of filled <path>s —
                no text or gradients — so it comes onto a page as any SVG
                graphic does (SvgImport.graphic): a group of shapes, each in
                its own colour. "colours" are its fills (a drawn line's
                stroke) in the order they are first used, at most four,
                lower-case "#rrggbb", as Colour swap lists them. "hues"
                are its dominant colours for the search's colour filter
                (ElementSearch.filtered), at most three: the fill (or
                stroke) that covers the most first — each path's area by
                its outline, a drawn line's as its length times its width —
                and a tie in the order first used.
  "motion"      on the Animated category's graphics: "draw" — its
                lines, stroked <path>s with no fill, draw themselves on in
                turn; "twinkle" — its sparkles and stars grow and glow one
                after another, looping; or "float" — it bobs gently, looping.
                On every third of the Stickers (the first, the fourth…),
                in turn: "wiggle" — it rocks, looping; "pop" — it pops in;
                or "float". Putting one on a page gives each of its shapes
                that animation (ElementAnimation.motioned).
  "stickerHues" each curated sticker's dominant colours, glyph to up to
                three "#rrggbb", most of the picture first, from the emoji
                palette below ([EMOJI]) — what the search's colour filter
                matches a sticker by.

The Stickers are die-cut: their art over a white outline that is their
silhouette grown DIECUT (8) units out, in the first, white <path> (see
offset); their "hues" are their art's, the white left out.

Paths are absolute M, L, C and Z, numbers to a tenth. A hand-drawn line is a
filled ribbon round its centre line, tapering at its ends, so it scales with
its graphic as a stroke would not. Each kind of graphic has its own seed, so
changing one kind leaves every other kind's bytes as they were.
"""
import json
import math
import pathlib
import random
import re
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCE = REPO / 'core/src/main/resources/com/canvia/core/content/Graphics.json'

CATEGORIES = [
    'Doodle arrows', 'Underlines & circles', 'Sparkles', 'Starbursts & badges',
    'Ribbons', 'Blobs', 'Confetti', 'Dividers', 'Speech bubbles',
    'Hand-drawn frames', 'Scribbles', 'Patterns', 'Animated', 'Stickers',
]

# Four colours each; a graphic takes what it needs from one.
PALETTES = [
    ['#ff6b6b', '#ffd93d', '#6bcb77', '#4d96ff'],
    ['#f72585', '#7209b7', '#3a0ca3', '#4cc9f0'],
    ['#264653', '#2a9d8f', '#e9c46a', '#f4a261'],
    ['#e63946', '#a8dadc', '#457b9d', '#1d3557'],
    ['#ff006e', '#fb5607', '#ffbe0b', '#3a86ff'],
    ['#ff595e', '#ffca3a', '#8ac926', '#1982c4'],
    ['#2b2d42', '#8d99ae', '#ef233c', '#ffb703'],
    ['#9b5de5', '#f15bb5', '#fee440', '#00bbf9'],
]
INK = '#222222'


def num(v):
    """A coordinate as written: to a tenth, no trailing zero, never -0."""
    s = '%.1f' % v
    if s.endswith('.0'):
        s = s[:-2]
    return '0' if s in ('-0', '-0.0') else s


def pt(p):
    return num(p[0]) + ' ' + num(p[1])


def polygon(points):
    """A closed outline through [points] in straight lines."""
    return 'M' + pt(points[0]) + ''.join('L' + pt(p) for p in points[1:]) + 'Z'


def smooth_closed(points):
    """A closed curve through [points], Catmull-Rom as cubic Béziers."""
    n = len(points)
    out = 'M' + pt(points[0])
    for i in range(n):
        p0, p1, p2, p3 = points[i - 1], points[i], points[(i + 1) % n], points[(i + 2) % n]
        c1 = (p1[0] + (p2[0] - p0[0]) / 6, p1[1] + (p2[1] - p0[1]) / 6)
        c2 = (p2[0] - (p3[0] - p1[0]) / 6, p2[1] - (p3[1] - p1[1]) / 6)
        out += 'C' + pt(c1) + ' ' + pt(c2) + ' ' + pt(p2)
    return out + 'Z'


def ellipse(cx, cy, rx, ry):
    k = 0.5522847498307936
    return ('M%sC%s %s %sC%s %s %sC%s %s %sC%s %s %sZ' % (
        pt((cx + rx, cy)),
        pt((cx + rx, cy + ry * k)), pt((cx + rx * k, cy + ry)), pt((cx, cy + ry)),
        pt((cx - rx * k, cy + ry)), pt((cx - rx, cy + ry * k)), pt((cx - rx, cy)),
        pt((cx - rx, cy - ry * k)), pt((cx - rx * k, cy - ry)), pt((cx, cy - ry)),
        pt((cx + rx * k, cy - ry)), pt((cx + rx, cy - ry * k)), pt((cx + rx, cy)),
    ))


def annulus(cx, cy, outer, inner, steps=36):
    """A ring: the outer circle one way round, the inner the other, so the
    nonzero rule leaves the middle open."""
    out = [(cx + outer * math.cos(2 * math.pi * i / steps), cy + outer * math.sin(2 * math.pi * i / steps)) for i in range(steps)]
    hole = [(cx + inner * math.cos(-2 * math.pi * i / steps), cy + inner * math.sin(-2 * math.pi * i / steps)) for i in range(steps)]
    return polygon(out) + polygon(hole)


def jitter(points, rng, amount):
    """The hand-drawn pass: each point nudged by up to [amount]."""
    return [(x + rng.uniform(-amount, amount), y + rng.uniform(-amount, amount)) for x, y in points]


def resample(points, count):
    """[count] points spread evenly along a polyline."""
    lengths = [0.0]
    for a, b in zip(points, points[1:]):
        lengths.append(lengths[-1] + math.hypot(b[0] - a[0], b[1] - a[1]))
    total = lengths[-1] or 1.0
    out = []
    j = 0
    for i in range(count):
        at = total * i / (count - 1)
        while j < len(points) - 2 and lengths[j + 1] < at:
            j += 1
        span = (lengths[j + 1] - lengths[j]) or 1.0
        t = min(1.0, max(0.0, (at - lengths[j]) / span))
        a, b = points[j], points[j + 1]
        out.append((a[0] + (b[0] - a[0]) * t, a[1] + (b[1] - a[1]) * t))
    return out


def catmull(points, steps=6):
    """An open polyline smoothed through [points]."""
    out = []
    n = len(points)
    for i in range(n - 1):
        p0 = points[max(0, i - 1)]
        p1, p2 = points[i], points[i + 1]
        p3 = points[min(n - 1, i + 2)]
        for s in range(steps):
            t = s / steps
            t2, t3 = t * t, t * t * t
            out.append(tuple(0.5 * (2 * p1[k] + (-p0[k] + p2[k]) * t + (2 * p0[k] - 5 * p1[k] + 4 * p2[k] - p3[k]) * t2
                                    + (-p0[k] + 3 * p1[k] - 3 * p2[k] + p3[k]) * t3) for k in (0, 1)))
    out.append(points[-1])
    return out


def ribbon(points, width, taper=True, rng=None, wobble=0.0):
    """A hand-drawn line: a filled outline round [points], [width] across,
    thinning to its ends when [taper]."""
    pts = resample(catmull(points), max(8, min(48, len(points) * 6)))
    left, right = [], []
    n = len(pts)
    for i, p in enumerate(pts):
        a = pts[max(0, i - 1)]
        b = pts[min(n - 1, i + 1)]
        dx, dy = b[0] - a[0], b[1] - a[1]
        d = math.hypot(dx, dy) or 1.0
        nx, ny = -dy / d, dx / d
        f = math.sin(math.pi * (0.08 + 0.84 * i / (n - 1))) if taper else 1.0
        w = width / 2 * (0.35 + 0.65 * f)
        if rng is not None and wobble:
            w *= 1 + rng.uniform(-wobble, wobble)
        left.append((p[0] + nx * w, p[1] + ny * w))
        right.append((p[0] - nx * w, p[1] - ny * w))
    return polygon(left + right[::-1])


def ring(cx, cy, rx, ry, width, rng, turns=1.08, start=0.0, wobble=3.0):
    """A hand-drawn loop round an ellipse, its ends overlapping."""
    steps = 28
    pts = []
    for i in range(steps + 1):
        a = start + 2 * math.pi * turns * i / steps
        r = 1 + rng.uniform(-0.04, 0.04)
        pts.append((cx + rx * r * math.cos(a), cy + ry * r * math.sin(a)))
    return ribbon(jitter(pts, rng, wobble), width)


def star(cx, cy, points, outer, inner, turn=-math.pi / 2):
    out = []
    for i in range(points * 2):
        r = outer if i % 2 == 0 else inner
        a = turn + math.pi * i / points
        out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


def sparkle(cx, cy, r, waist=0.18):
    """A four-pointed sparkle with curved sides."""
    out = 'M' + pt((cx, cy - r))
    tips = [(cx, cy - r), (cx + r, cy), (cx, cy + r), (cx - r, cy)]
    for i in range(4):
        a, b = tips[i], tips[(i + 1) % 4]
        c = (cx + (a[0] - cx + b[0] - cx) * waist, cy + (a[1] - cy + b[1] - cy) * waist)
        out += 'C' + pt(c) + ' ' + pt(c) + ' ' + pt(b)
    return out + 'Z'


def rect(x, y, w, h):
    return polygon([(x, y), (x + w, y), (x + w, y + h), (x, y + h)])


def rounded(x, y, w, h, r):
    k = 0.5522847498307936 * r
    return ('M%sL%sC%s %s %sL%sC%s %s %sL%sC%s %s %sL%sC%s %s %sZ' % (
        pt((x + r, y)), pt((x + w - r, y)),
        pt((x + w - r + k, y)), pt((x + w, y + r - k)), pt((x + w, y + r)),
        pt((x + w, y + h - r)),
        pt((x + w, y + h - r + k)), pt((x + w - r + k, y + h)), pt((x + w - r, y + h)),
        pt((x + r, y + h)),
        pt((x + r - k, y + h)), pt((x, y + h - r + k)), pt((x, y + h - r)),
        pt((x, y + r)),
        pt((x, y + r - k)), pt((x + r - k, y)), pt((x + r, y)),
    ))


def rotate(points, cx, cy, a):
    c, s = math.cos(a), math.sin(a)
    return [(cx + (x - cx) * c - (y - cy) * s, cy + (x - cx) * s + (y - cy) * c) for x, y in points]


# ------------------------------------------------------------------ kinds
# Each returns (width, height, [(fill, d), ...]) for variant [v].

def doodle_arrow(rng, v, pal):
    ink = INK if v % 3 else pal[3]
    shape = v % 6
    if shape == 0:      # a gentle arc
        line = [(30, 150), (70, 90), (130, 70), (170, 80)]
    elif shape == 1:    # a loop on its way
        line = [(25, 160), (80, 120), (110, 60), (80, 50), (75, 90), (120, 110), (175, 70)]
    elif shape == 2:    # a zigzag
        line = [(25, 150), (65, 110), (90, 140), (130, 95), (175, 60)]
    elif shape == 3:    # nearly straight
        line = [(25, 120), (90, 108), (175, 96)]
    elif shape == 4:    # a hook down
        line = [(40, 40), (130, 40), (165, 90), (140, 160)]
    else:               # a spiral in
        line = [(30, 170), (40, 90), (100, 40), (160, 70), (150, 130), (110, 120)]
    line = jitter(line, rng, 6)
    width = 9 + (v % 4) * 1.5
    parts = [(ink, ribbon(line, width, rng=rng, wobble=0.15))]
    tip, before = line[-1], line[-2]
    a = math.atan2(tip[1] - before[1], tip[0] - before[0])
    head = 34
    for side in (-1, 1):
        b = a + math.pi + side * 0.55
        end = (tip[0] + head * math.cos(b), tip[1] + head * math.sin(b))
        parts.append((ink, ribbon(jitter([end, tip], rng, 2), width, rng=rng, wobble=0.1)))
    if v >= 8:   # an accent dot where it starts
        s = line[0]
        parts.insert(0, (pal[v % 3], ellipse(s[0], s[1], 12, 12)))
    return 200, 200, parts


def underline(rng, v, pal):
    colour = pal[v % 4]
    kind = v % 6
    if kind == 0:   # a single swash
        pts = jitter([(15, 60), (100, 50), (190, 45), (285, 55)], rng, 4)
        return 300, 100, [(colour, ribbon(pts, 14, rng=rng, wobble=0.1))]
    if kind == 1:   # two lines
        a = jitter([(20, 40), (150, 36), (280, 42)], rng, 3)
        b = jitter([(40, 66), (160, 62), (270, 68)], rng, 3)
        return 300, 100, [(colour, ribbon(a, 10)), (colour, ribbon(b, 8))]
    if kind == 2:   # a wave
        pts = [(15 + i * 27, 50 + 14 * math.sin(i * 1.4)) for i in range(11)]
        return 300, 100, [(colour, ribbon(jitter(pts, rng, 2), 11))]
    if kind == 3:   # a circle drawn round something
        return 240, 160, [(colour, ring(120, 80, 100, 60, 9, rng, start=rng.uniform(0, 6.28)))]
    if kind == 4:   # a highlighter stroke behind, a line under it
        hi = rounded(10, 20, 280, 52, 20)
        line = jitter([(20, 80), (150, 78), (285, 82)], rng, 3)
        return 300, 100, [(pal[(v + 2) % 4], hi), (colour, ribbon(line, 7))]
    # a double loop round
    return 240, 160, [(colour, ring(120, 80, 104, 58, 7, rng, turns=1.9, start=rng.uniform(0, 6.28), wobble=4))]


def sparkles(rng, v, pal):
    parts = []
    count = 1 + v % 3
    spots = [(100, 100, 70), (155, 55, 30), (55, 150, 24)]
    for i in range(count):
        cx, cy, r = spots[i]
        cx += rng.uniform(-6, 6)
        cy += rng.uniform(-6, 6)
        parts.append((pal[(v + i) % 4] if v % 4 else INK, sparkle(cx, cy, r * rng.uniform(0.9, 1.1), waist=0.12 + 0.04 * (v % 3))))
    if v >= 6:   # dots round it
        dots = ''.join(ellipse(x, y, 5, 5) for x, y in [(40, 50), (165, 150), (150, 115)])
        parts.append((pal[(v + 3) % 4], dots))
    if v >= 12:  # a glow behind
        parts.insert(0, (pal[(v + 1) % 4], smooth_closed(jitter(star(100, 100, 8, 60, 50), rng, 3))))
    return 200, 200, parts


def starburst(rng, v, pal):
    points = [12, 16, 20, 24, 10, 8, 14, 18][v % 8]
    outer = 92
    inner = outer * (0.78 if points >= 16 else 0.62)
    burst = polygon(jitter(star(100, 100, points, outer, inner, turn=rng.uniform(0, 1)), rng, 1.5))
    parts = [(pal[v % 4], burst)]
    if v % 2 == 0:   # a badge: a disc in the middle, a ring round it
        parts.append((pal[(v + 1) % 4], ellipse(100, 100, 58, 58)))
        parts.append((pal[(v + 2) % 4], annulus(100, 100, 50, 46)))
    if v % 3 == 0:   # tails hanging from it
        tail = polygon([(70, 150), (95, 150), (90, 195), (80, 182), (68, 192)])
        tail2 = polygon([(105, 150), (130, 150), (132, 192), (120, 182), (110, 195)])
        parts.insert(0, (pal[(v + 3) % 4], tail + tail2))
    return 200, 200, parts


def banner(rng, v, pal):
    main, dark, end = pal[v % 4], pal[(v + 2) % 4], pal[(v + 1) % 4]
    kind = v % 4
    if kind == 0:    # a flat banner, notched ends behind
        ends = polygon([(5, 50), (60, 50), (60, 100), (5, 100), (22, 75)]) + polygon([(295, 50), (240, 50), (240, 100), (295, 100), (278, 75)])
        folds = polygon([(40, 85), (60, 85), (60, 100)]) + polygon([(260, 85), (240, 85), (240, 100)])
        body = rect(40, 30, 220, 55)
        return 300, 120, [(end, ends), (dark, folds), (main, body)]
    if kind == 1:    # a curved banner
        top = [(30 + i * 24, 40 - 18 * math.sin(math.pi * i / 10)) for i in range(11)]
        bottom = [(x, y + 50) for x, y in top][::-1]
        body = polygon(top + bottom)
        ends = polygon([(5, 60), (40, 50), (40, 100), (5, 110), (18, 82)]) + polygon([(295, 60), (260, 50), (260, 100), (295, 110), (282, 82)])
        return 300, 120, [(end, ends), (main, body)]
    if kind == 2:    # a ribbon tag, pointed end
        body = polygon([(10, 30), (250, 30), (290, 60), (250, 90), (10, 90), (30, 60)])
        stripe = rect(10, 38, 240, 6) + rect(10, 76, 240, 6)
        return 300, 120, [(main, body), (end, stripe)]
    # a bow
    left = smooth_closed(jitter([(150, 60), (100, 20), (60, 35), (70, 85), (110, 90)], rng, 3))
    right = smooth_closed(jitter([(150, 60), (200, 20), (240, 35), (230, 85), (190, 90)], rng, 3))
    tails = polygon([(140, 70), (110, 115), (125, 112), (148, 75)]) + polygon([(160, 70), (190, 115), (175, 112), (152, 75)])
    knot = ellipse(150, 62, 16, 14)
    return 300, 120, [(dark, tails), (main, left + right), (end, knot)]


def blob(rng, v, pal):
    def one(cx, cy, r, n=8):
        pts = []
        for i in range(n):
            a = 2 * math.pi * i / n
            k = r * rng.uniform(0.72, 1.08)
            pts.append((cx + k * math.cos(a), cy + k * math.sin(a)))
        return smooth_closed(pts)
    parts = [(pal[v % 4], one(100, 100, 80, 7 + v % 4))]
    if v % 3 >= 1:
        parts.append((pal[(v + 1) % 4], one(70 + rng.uniform(0, 60), 70 + rng.uniform(0, 60), 34, 6)))
    if v % 3 == 2:
        parts.append((pal[(v + 2) % 4], one(140, 140, 20, 6)))
    if v >= 10:  # speckles
        parts.append((pal[(v + 3) % 4], ''.join(ellipse(rng.uniform(40, 160), rng.uniform(40, 160), 4, 4) for _ in range(6))))
    return 200, 200, parts


def confetti(rng, v, pal):
    bits = {c: '' for c in pal}
    count = 26 + (v % 4) * 6
    for i in range(count):
        c = pal[i % 4]
        x, y = rng.uniform(15, 185), rng.uniform(15, 185)
        kind = (i + v) % 4
        a = rng.uniform(0, math.pi)
        if kind == 0:
            bits[c] += polygon(rotate([(x - 7, y - 3), (x + 7, y - 3), (x + 7, y + 3), (x - 7, y + 3)], x, y, a))
        elif kind == 1:
            bits[c] += ellipse(x, y, 4, 4)
        elif kind == 2:
            bits[c] += polygon(rotate([(x, y - 6), (x + 6, y + 5), (x - 6, y + 5)], x, y, a))
        else:
            curl = rotate([(x - 10, y), (x - 4, y - 5), (x + 2, y + 4), (x + 9, y - 2)], x, y, a)
            bits[c] += ribbon(curl, 3.5, taper=False)
    return 200, 200, [(c, d) for c, d in bits.items() if d]


def divider(rng, v, pal):
    colour = INK if v % 2 else pal[v % 4]
    accent = pal[(v + 1) % 4]
    kind = v % 6
    line_l = jitter([(10, 40), (90, 39), (165, 40)], rng, 1.5)
    line_r = jitter([(235, 40), (310, 41), (390, 40)], rng, 1.5)
    lines = ribbon(line_l, 4) + ribbon(line_r, 4)
    if kind == 0:     # a diamond between two lines
        mid = polygon([(200, 22), (218, 40), (200, 58), (182, 40)])
    elif kind == 1:   # three dots
        mid = ellipse(180, 40, 6, 6) + ellipse(200, 40, 8, 8) + ellipse(220, 40, 6, 6)
    elif kind == 2:   # a sparkle
        mid = sparkle(200, 40, 24)
    elif kind == 3:   # a heart
        mid = 'M200 58C170 38 180 18 200 30C220 18 230 38 200 58Z'
    elif kind == 4:   # a flourish
        mid = ribbon(jitter([(170, 40), (185, 22), (200, 40), (215, 58), (230, 40)], rng, 1), 5)
    else:             # a wave all the way across
        pts = [(10 + i * 19, 40 + 9 * math.sin(i * 1.1)) for i in range(21)]
        return 400, 80, [(colour, ribbon(jitter(pts, rng, 1), 6))]
    return 400, 80, [(colour, lines), (accent, mid)]


def bubble(rng, v, pal):
    fill = pal[v % 4]
    edge = INK if v % 2 else pal[(v + 2) % 4]
    kind = v % 5
    if kind == 0:     # rounded, tail down left
        body = rounded(20, 20, 160, 110, 26)
        tail = polygon([(50, 125), (40, 175), (90, 128)])
    elif kind == 1:   # oval, tail down right
        body = ellipse(100, 80, 85, 60)
        tail = polygon([(125, 128), (165, 178), (145, 120)])
    elif kind == 2:   # a thought cloud
        pts = []
        for i in range(10):
            a = 2 * math.pi * i / 10
            r = 70 if i % 2 == 0 else 58
            pts.append((100 + r * math.cos(a) * 1.2, 80 + r * math.sin(a) * 0.85))
        body = smooth_closed(jitter(pts, rng, 2))
        tail = ellipse(55, 150, 12, 10) + ellipse(38, 175, 7, 6)
    elif kind == 3:   # a shout
        body = polygon(jitter(star(100, 85, 11, 88, 62), rng, 3))
        tail = polygon([(60, 140), (35, 190), (90, 145)])
    else:             # a square note, tail up
        body = rounded(20, 50, 160, 120, 10)
        tail = polygon([(130, 55), (160, 12), (155, 55)])
    shadow = []
    if v >= 5:   # the same bubble behind, nudged down and right
        shadow = [(edge, _shift(body, 6, 6) + _shift(tail, 6, 6))]
    return 200, 200, shadow + [(fill, body + tail)]


def _shift(d, dx, dy):
    """Path data [d] moved by dx, dy — every coordinate pair in it."""
    out, word, nums = [], '', []
    tokens = []
    for ch in d:
        if ch.isalpha():
            if word:
                tokens.append(word)
                word = ''
            tokens.append(ch)
        elif ch == ' ':
            if word:
                tokens.append(word)
                word = ''
        else:
            word += ch
    if word:
        tokens.append(word)
    values = []
    for t in tokens:
        if t.isalpha():
            if values:
                out.append(' '.join(values))
                values = []
            out.append(t)
        else:
            values.append(t)
    if values:
        out.append(' '.join(values))
    text = ''
    for t in out:
        if t.isalpha():
            text += t
        else:
            v = [float(x) for x in t.split(' ')]
            text += ' '.join(num(v[i] + (dx if i % 2 == 0 else dy)) for i in range(len(v)))
    return text


def hand_frame(rng, v, pal):
    colour = INK if v % 3 == 0 else pal[v % 4]
    accent = pal[(v + 1) % 4]
    kind = v % 4
    if kind == 0:     # a rectangle, its corners overshot
        sides = [[(18, 25), (182, 22)], [(178, 15), (182, 185)], [(185, 178), (15, 182)], [(22, 188), (18, 12)]]
        parts = [(colour, ''.join(ribbon(jitter(s, rng, 2), 6) for s in sides))]
    elif kind == 1:   # a loose oval
        parts = [(colour, ring(100, 100, 82, 88, 7, rng, turns=1.12, start=rng.uniform(0, 6.28)))]
    elif kind == 2:   # a double rectangle
        a = [(20, 20), (180, 22), (178, 180), (22, 178), (20, 20)]
        b = [(28, 30), (172, 28), (174, 172), (30, 170), (28, 30)]
        parts = [(colour, ribbon(jitter(a, rng, 2), 5, taper=False) + ribbon(jitter(b, rng, 2), 3, taper=False))]
    else:             # a frame of dashes
        dashes = ''
        for i in range(7):
            x = 20 + i * 24
            dashes += ribbon(jitter([(x, 20), (x + 14, 20)], rng, 1), 5) + ribbon(jitter([(x, 180), (x + 14, 180)], rng, 1), 5)
            dashes += ribbon(jitter([(20, x), (20, x + 14)], rng, 1), 5) + ribbon(jitter([(180, x), (180, x + 14)], rng, 1), 5)
        parts = [(colour, dashes)]
    if v >= 4:   # a corner sparkle or leaf
        parts.append((accent, sparkle(178, 22, 18) if v % 2 else sparkle(24, 178, 16)))
    if v >= 10:  # a tape at the top
        parts.insert(0, (pal[(v + 2) % 4], polygon(rotate([(75, 8), (125, 8), (125, 30), (75, 30)], 100, 19, -0.08))))
    return 200, 200, parts


def scribble(rng, v, pal):
    colour = INK if v % 2 else pal[v % 4]
    kind = v % 5
    if kind == 0:     # a zigzag fill
        pts = []
        for i in range(9):
            pts.append((30 + i * 18, 40 if i % 2 == 0 else 160))
        pts = jitter(pts, rng, 8)
    elif kind == 1:   # a spiral
        pts = [(100 + (8 + i * 4.2) * math.cos(i * 0.55), 100 + (8 + i * 4.2) * math.sin(i * 0.55)) for i in range(20)]
        pts = jitter(pts, rng, 2)
    elif kind == 2:   # loops along a line
        pts = [(20 + i * 8 + 18 * math.cos(i * 0.9), 100 + 24 * math.sin(i * 0.9)) for i in range(21)]
        pts = jitter(pts, rng, 2)
    elif kind == 3:   # a tangle
        pts = [(rng.uniform(40, 160), rng.uniform(40, 160)) for _ in range(9)]
    else:             # a crossing-out
        pts = jitter([(30, 60), (170, 80), (30, 100), (170, 120), (30, 140)], rng, 5)
    parts = [(colour, ribbon(pts, 6 + v % 3, taper=True, rng=rng, wobble=0.1))]
    if v >= 10:
        parts.insert(0, (pal[(v + 1) % 4], blob_disc(rng)))
    return 200, 200, parts


def blob_disc(rng):
    pts = []
    for i in range(8):
        a = 2 * math.pi * i / 8
        k = 70 * rng.uniform(0.85, 1.05)
        pts.append((100 + k * math.cos(a), 100 + k * math.sin(a)))
    return smooth_closed(pts)


def pattern(rng, v, pal):
    a, b = pal[v % 4], pal[(v + 1) % 4]
    kind = v % 6
    back = rect(0, 0, 200, 200)
    marks = ''
    if kind == 0:     # polka dots
        for row in range(5):
            for col in range(5):
                x = 20 + col * 40 + (20 if row % 2 else 0)
                if x < 200:
                    marks += ellipse(x, 20 + row * 40, 7, 7)
    elif kind == 1:   # stripes
        for i in range(5):
            marks += rect(0, i * 40 + 10, 200, 18)
    elif kind == 2:   # checks
        for row in range(5):
            for col in range(5):
                if (row + col) % 2 == 0:
                    marks += rect(col * 40, row * 40, 40, 40)
    elif kind == 3:   # waves
        for row in range(5):
            pts = [(i * 20, 20 + row * 40 + 7 * math.sin(i * 1.2)) for i in range(11)]
            marks += ribbon(pts, 6, taper=False)
    elif kind == 4:   # little crosses
        for row in range(4):
            for col in range(4):
                x, y = 25 + col * 50, 25 + row * 50
                marks += rect(x - 9, y - 2.5, 18, 5) + rect(x - 2.5, y - 9, 5, 18)
    else:             # triangles
        for row in range(4):
            for col in range(4):
                x, y = 25 + col * 50, 25 + row * 50
                marks += polygon([(x, y - 12), (x + 12, y + 9), (x - 12, y + 9)])
    parts = [(b, back), (a, marks)]
    if v >= 12:
        parts.append((pal[(v + 2) % 4], ''.join(sparkle(x, y, 9) for x, y in [(45, 45), (155, 105), (75, 165)])))
    return 200, 200, parts


# ------------------------------------------------------------ animated
# Lines here are stroked centre lines, not filled ribbons, so they can draw
# themselves on: each returns parts of (colour, d, stroke width).

def open_path(points):
    """An open line through [points], smoothed, in straight steps."""
    pts = catmull(points)
    return 'M' + pt(pts[0]) + ''.join('L' + pt(p) for p in pts[1:])


def drawn_arrow(rng, v, pal):
    ink = INK if v % 3 == 0 else pal[v % 4]
    shape = v % 6
    if shape == 0:      # a gentle arc
        line = [(30, 150), (70, 90), (130, 70), (170, 80)]
    elif shape == 1:    # a loop on its way
        line = [(25, 160), (80, 120), (110, 60), (80, 50), (75, 90), (120, 110), (175, 70)]
    elif shape == 2:    # a zigzag
        line = [(25, 150), (65, 110), (90, 140), (130, 95), (175, 60)]
    elif shape == 3:    # a swoop down
        line = [(30, 40), (90, 60), (140, 110), (165, 165)]
    elif shape == 4:    # a wave
        line = [(20, 110), (60, 80), (100, 120), (140, 80), (180, 100)]
    else:               # a spiral in
        line = [(30, 170), (40, 90), (100, 40), (160, 70), (150, 130), (110, 120)]
    line = jitter(line, rng, 5)
    width = 7 + (v % 3) * 1.5
    smooth = catmull(line)
    tip, before = smooth[-1], smooth[-3]
    a = math.atan2(tip[1] - before[1], tip[0] - before[0])
    head = 30
    ends = [(tip[0] + head * math.cos(a + math.pi + side * 0.55), tip[1] + head * math.sin(a + math.pi + side * 0.55)) for side in (-1, 1)]
    parts = [(ink, open_path(line), width), (ink, 'M' + pt(ends[0]) + 'L' + pt(tip) + 'L' + pt(ends[1]), width)]
    return 200, 200, parts


def drawn_underline(rng, v, pal):
    colour = pal[v % 4]
    kind = v % 5
    if kind == 0:   # a single swash
        return 300, 100, [(colour, open_path(jitter([(15, 60), (100, 50), (190, 45), (285, 55)], rng, 4)), 10)]
    if kind == 1:   # two lines
        a = jitter([(20, 40), (150, 36), (280, 42)], rng, 3)
        b = jitter([(40, 66), (160, 62), (270, 68)], rng, 3)
        return 300, 100, [(colour, open_path(a), 8), (colour, open_path(b), 6)]
    if kind == 2:   # a wave
        pts = [(15 + i * 27, 50 + 14 * math.sin(i * 1.4)) for i in range(11)]
        return 300, 100, [(colour, open_path(jitter(pts, rng, 2)), 8)]
    if kind == 3:   # a zigzag
        pts = [(15 + i * 30, 40 if i % 2 == 0 else 64) for i in range(10)]
        return 300, 100, [(colour, open_path(jitter(pts, rng, 2)), 7)]
    # a swash with a loop at its end
    pts = [(15, 60), (120, 52), (230, 50), (270, 30), (250, 15), (235, 40), (285, 62)]
    return 300, 100, [(colour, open_path(jitter(pts, rng, 3)), 8)]


def drawn_circle(rng, v, pal):
    colour = pal[(v + 1) % 4] if v % 2 else INK
    turns = 1.12 if v % 2 == 0 else 1.9
    start = rng.uniform(0, 6.28)
    steps = 32
    pts = []
    for i in range(steps + 1):
        a = start + 2 * math.pi * turns * i / steps
        r = 1 + rng.uniform(-0.04, 0.04)
        pts.append((120 + 100 * r * math.cos(a), 80 + 60 * r * math.sin(a)))
    return 240, 160, [(colour, open_path(jitter(pts, rng, 2.5)), 6 + v % 3)]


def drawn_scribble(rng, v, pal):
    colour = INK if v % 2 else pal[v % 4]
    kind = v % 4
    if kind == 0:     # a zigzag fill
        pts = jitter([(30 + i * 18, 40 if i % 2 == 0 else 160) for i in range(9)], rng, 8)
    elif kind == 1:   # a spiral
        pts = jitter([(100 + (8 + i * 4.2) * math.cos(i * 0.55), 100 + (8 + i * 4.2) * math.sin(i * 0.55)) for i in range(20)], rng, 2)
    elif kind == 2:   # loops along a line
        pts = jitter([(20 + i * 8 + 18 * math.cos(i * 0.9), 100 + 24 * math.sin(i * 0.9)) for i in range(21)], rng, 2)
    else:             # a crossing-out
        pts = jitter([(30, 60), (170, 80), (30, 100), (170, 120), (30, 140)], rng, 5)
    return 200, 200, [(colour, open_path(pts), 5 + v % 3)]


def twinkle_sparkle(rng, v, pal):
    parts = []
    spots = [(95, 105, 62), (158, 50, 30), (52, 158, 24), (160, 150, 18)]
    for i in range(2 + v % 3):
        cx, cy, r = spots[i]
        cx += rng.uniform(-5, 5)
        cy += rng.uniform(-5, 5)
        parts.append((pal[(v + i) % 4] if v % 3 else INK, sparkle(cx, cy, r * rng.uniform(0.9, 1.1), waist=0.12 + 0.03 * (v % 3))))
    return 200, 200, parts


def twinkle_star(rng, v, pal):
    parts = []
    spots = [(100, 100, 60), (40, 45, 20), (165, 155, 22), (160, 40, 14)]
    points = 5 if v % 2 == 0 else 6
    for i in range(2 + v % 3):
        cx, cy, r = spots[i]
        parts.append((pal[(v + i) % 4], polygon(star(cx + rng.uniform(-4, 4), cy + rng.uniform(-4, 4), points, r, r * 0.45))))
    return 200, 200, parts


def float_shape(rng, v, pal):
    kind = v % 3
    if kind == 0:     # a heart
        heart = [(100 + 16 * math.sin(t) ** 3 * 5, 95 - (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) * 5)
                 for t in [2 * math.pi * i / 40 for i in range(40)]]
        return 200, 200, [(pal[v % 4], polygon(heart))]
    if kind == 1:     # a balloon on its string
        return 200, 200, [(pal[(v + 1) % 4], ellipse(100, 80, 50, 60)), (pal[(v + 2) % 4], polygon([(92, 146), (108, 146), (100, 134)]))]
    return 200, 200, [(pal[(v + 3) % 4], blob_disc(rng))]


# ------------------------------------------------------------------ stickers
# Die-cut stickers: each a silhouette of simple outlines (polygons, a circle
# as a 48-gon), the white die-cut its every outline offset DIECUT units out —
# round at the corners that stick out, mitred at the ones that go in — all
# one white path under the art. Every outline goes the same way round, so the
# nonzero rule fills their union. Each returns (silhouettes, parts) in a
# 200-unit box, the art kept 16 units in so the die-cut fits.

DIECUT = 8
WHITE = '#ffffff'
STICKER_INK = '#2b2d42'


def circle_pts(cx, cy, r, steps=48, ry=None):
    ry = r if ry is None else ry
    return [(cx + r * math.cos(2 * math.pi * i / steps), cy + ry * math.sin(2 * math.pi * i / steps)) for i in range(steps)]


def signed_area(points):
    return sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(points, points[1:] + points[:1])) / 2


def clockwise(points):
    """[points] going clockwise on the page (y down): positive area."""
    return points if signed_area(points) > 0 else points[::-1]


def offset(points, d):
    """The outline [points] grown [d] out: an arc round each corner that
    sticks out, the two grown edges meeting at each one that goes in."""
    pts = clockwise(points)
    n = len(pts)
    out = []
    for i in range(n):
        p, v, q = pts[i - 1], pts[i], pts[(i + 1) % n]
        e1 = (v[0] - p[0], v[1] - p[1])
        e2 = (q[0] - v[0], q[1] - v[1])
        l1 = math.hypot(*e1) or 1.0
        l2 = math.hypot(*e2) or 1.0
        # Clockwise on a y-down page, the outside is to the left of travel.
        n1 = (e1[1] / l1, -e1[0] / l1)
        n2 = (e2[1] / l2, -e2[0] / l2)
        turn = e1[0] * e2[1] - e1[1] * e2[0]
        if turn >= 0:
            a1 = math.atan2(n1[1], n1[0])
            a2 = math.atan2(n2[1], n2[0])
            while a2 < a1:
                a2 += 2 * math.pi
            steps = max(1, int(math.ceil((a2 - a1) / (math.pi / 8))))
            for k in range(steps + 1):
                a = a1 + (a2 - a1) * k / steps
                out.append((v[0] + d * math.cos(a), v[1] + d * math.sin(a)))
        else:
            dot = n1[0] * n2[0] + n1[1] * n2[1]
            k = d / max(0.2, 1 + dot)
            out.append((v[0] + (n1[0] + n2[0]) * k, v[1] + (n1[1] + n2[1]) * k))
    return out


def diecut(silhouettes):
    """The white die-cut under a sticker: each outline grown DIECUT out."""
    return (WHITE, ''.join(polygon(offset(s, DIECUT)) for s in silhouettes))


def polyline(points):
    """An open line through [points] in straight steps."""
    return 'M' + pt(points[0]) + ''.join('L' + pt(p) for p in points[1:])


def heart_pts(cx, cy, size, steps=40):
    """A heart [size] across, centred on (cx, cy)."""
    k = size / 34
    return [(cx + 16 * math.sin(t) ** 3 * k, cy + 2 * k - (13 * math.cos(t) - 5 * math.cos(2 * t) - 2 * math.cos(3 * t) - math.cos(4 * t)) * k)
            for t in [2 * math.pi * i / steps for i in range(steps)]]


def rounded_pts(x, y, w, h, r, steps=6):
    out = []
    for cx, cy, a0 in ((x + w - r, y + r, -math.pi / 2), (x + w - r, y + h - r, 0), (x + r, y + h - r, math.pi / 2), (x + r, y + r, math.pi)):
        for k in range(steps + 1):
            a = a0 + math.pi / 2 * k / steps
            out.append((cx + r * math.cos(a), cy + r * math.sin(a)))
    return out


# Hand-lettered capitals for the badges' words, strokes on a 10 by 14 grid.
LETTERS = {
    'A': [[(0, 14), (5, 0), (10, 14)], [(2.2, 8.5), (7.8, 8.5)]],
    'E': [[(8, 0), (0, 0), (0, 14), (8, 14)], [(0, 7), (6, 7)]],
    'G': [[(9, 2.5), (7, 0), (3, 0), (0, 3), (0, 11), (3, 14), (7, 14), (9.5, 11.5), (9.5, 7.5), (5.5, 7.5)]],
    'H': [[(0, 0), (0, 14)], [(9, 0), (9, 14)], [(0, 7), (9, 7)]],
    'K': [[(0, 0), (0, 14)], [(9, 0), (0, 8)], [(3, 5.5), (9, 14)]],
    'L': [[(0, 0), (0, 14), (8, 14)]],
    'M': [[(0, 14), (0, 0), (5.5, 8), (11, 0), (11, 14)]],
    'N': [[(0, 14), (0, 0), (9, 14), (9, 0)]],
    'O': [[(5, 0), (8.5, 1.5), (10, 7), (8.5, 12.5), (5, 14), (1.5, 12.5), (0, 7), (1.5, 1.5), (5, 0)]],
    'S': [[(9, 2), (7, 0), (3, 0), (0.5, 2), (0.5, 5), (9, 9), (9, 12), (7, 14), (3, 14), (0.5, 12)]],
    'T': [[(0, 0), (10, 0)], [(5, 0), (5, 14)]],
    'U': [[(0, 0), (0, 10), (3, 14), (6, 14), (9, 10), (9, 0)]],
    'V': [[(0, 0), (5, 14), (10, 0)]],
    'W': [[(0, 0), (3, 14), (6, 4), (9, 14), (12, 0)]],
    'Y': [[(0, 0), (5, 7), (10, 0)], [(5, 7), (5, 14)]],
}


def word_parts(word, cx, cy, height, colour):
    """[word] in hand-lettered capitals [height] tall, centred on (cx, cy),
    each stroke a line a seventh of the height thick."""
    k = height / 14
    gap = 3.5
    widths = [max(x for line in LETTERS[c] for x, _ in line) if c != ' ' else 6 for c in word]
    total = sum(widths) + gap * (len(word) - 1)
    x = cx - total * k / 2
    parts = []
    for c, w in zip(word, widths):
        for line in LETTERS.get(c, []):
            parts.append((colour, polyline([(x + px * k, cy - height / 2 + py * k) for px, py in line]), height / 7))
        x += (w + gap) * k
    return parts


def sticker_badge(rng, v, pal):
    words = ['WOW', 'SALE', 'NEW', 'LOVE', 'OMG', 'THANK YOU']
    word = words[v % 6]
    base = v // 6
    fill, ink = pal[v % 4], STICKER_INK
    if base == 0:       # a round badge with a ring
        outline = circle_pts(100, 100, 80)
        parts = [(fill, polygon(outline)), (ink, annulus(100, 100, 70, 65))]
    elif base == 1:     # a starburst seal
        outline = star(100, 100, 16, 84, 70)
        parts = [(fill, polygon(outline))]
    else:               # a ticket, rounded
        outline = rounded_pts(18, 52, 164, 96, 22)
        parts = [(fill, polygon(outline)), (ink, polyline([(34, 66), (166, 66)]), 3), (ink, polyline([(34, 134), (166, 134)]), 3)]
    if word == 'THANK YOU':
        parts += word_parts('THANK', 100, 84, 22, ink) + word_parts('YOU', 100, 118, 22, ink)
    else:
        parts += word_parts(word, 100, 100, 34 if len(word) <= 3 else 28, ink)
    return [outline], parts


def sticker_face(rng, v, pal):
    skin = ['#ffd93d', '#ffb3c7', '#9ee6a0'][v % 3]
    ink = STICKER_INK
    look = v % 5 if v < 5 else (v + v // 5) % 5
    outline = circle_pts(100, 100, 78)
    parts = [(skin, polygon(outline))]
    if look == 0:       # a smile
        parts += [(ink, ellipse(74, 82, 7, 10)), (ink, ellipse(126, 82, 7, 10)), (ink, polyline([(68, 118), (84, 134), (116, 134), (132, 118)]), 7)]
    elif look == 1:     # a wink
        parts += [(ink, polyline([(64, 84), (84, 84)]), 6), (ink, ellipse(126, 82, 7, 10)), (ink, polyline([(70, 120), (100, 138), (130, 120)]), 7)]
    elif look == 2:     # surprised
        parts += [(ink, ellipse(74, 80, 8, 11)), (ink, ellipse(126, 80, 8, 11)), (ink, ellipse(100, 128, 12, 15))]
    elif look == 3:     # heart eyes
        parts += [(pal[0], polygon(heart_pts(74, 84, 26))), (pal[0], polygon(heart_pts(126, 84, 26))),
                  (ink, polyline([(70, 118), (100, 138), (130, 118)]), 7)]
    else:               # cool, in sunglasses
        parts += [(ink, polygon(rounded_pts(52, 70, 42, 26, 10))), (ink, polygon(rounded_pts(106, 70, 42, 26, 10))),
                  (ink, polyline([(94, 80), (106, 80)]), 5), (ink, polyline([(76, 126), (100, 134), (124, 126)]), 7)]
    return [outline], parts


def sticker_heart(rng, v, pal):
    look = v % 5
    a, b = pal[v % 4], pal[(v + 1) % 4]
    if look == 0:       # one heart, a shine on it
        outline = heart_pts(100, 104, 160)
        return [outline], [(a, polygon(outline)), (WHITE, ellipse(70, 70, 10, 16))]
    if look == 1:       # two hearts
        big, small = heart_pts(88, 110, 130), heart_pts(140, 64, 70)
        return [big, small], [(a, polygon(big)), (b, polygon(small))]
    if look == 2:       # a heart in a heart
        outline = heart_pts(100, 104, 160)
        return [outline], [(a, polygon(outline)), (b, polygon(heart_pts(100, 102, 90)))]
    if look == 3:       # a broken heart
        whole = heart_pts(100, 104, 150)
        crack = [(100, 64), (90, 90), (108, 108), (94, 132), (100, 174)]
        left = [p for p in whole if p[0] <= 100] + crack[::-1]
        right = crack + [p for p in whole if p[0] > 100]
        left = [(x - 6, y) for x, y in left]
        right = [(x + 6, y) for x, y in right]
        return [left, right], [(a, polygon(left)), (a, polygon(right))]
    # a heart with a ribbon across it
    outline = heart_pts(100, 104, 160)
    band = [(30, 96), (170, 76), (170, 102), (30, 122)]
    return [outline, band], [(a, polygon(outline)), (b, polygon(band))]


def sticker_star(rng, v, pal):
    look = v % 5
    a, b = pal[v % 4], pal[(v + 2) % 4]
    if look == 0:       # a five-pointed star
        outline = star(100, 106, 5, 84, 38)
        return [outline], [(a, polygon(outline))]
    if look == 1:       # a star with a face
        outline = star(100, 106, 5, 84, 40)
        return [outline], [(a, polygon(outline)), (STICKER_INK, ellipse(86, 104, 5, 8)), (STICKER_INK, ellipse(114, 104, 5, 8)),
                           (STICKER_INK, polyline([(88, 124), (100, 132), (112, 124)]), 5)]
    if look == 2:       # a shooting star
        outline = star(132, 70, 5, 50, 22)
        trail = [(30, 150), (102, 76), (116, 96), (44, 168)]
        return [outline, trail], [(b, polygon(trail)), (a, polygon(outline))]
    if look == 3:       # an eight-pointed star
        outline = star(100, 100, 8, 82, 48)
        return [outline], [(a, polygon(outline)), (b, polygon(star(100, 100, 8, 44, 26)))]
    # a cluster of three
    s1, s2, s3 = star(84, 110, 5, 62, 28), star(150, 58, 5, 32, 14), star(156, 150, 5, 26, 12)
    return [s1, s2, s3], [(a, polygon(s1)), (b, polygon(s2)), (b, polygon(s3))]


def sticker_food(rng, v, pal):
    look = v % 5
    if look == 0:       # a slice of pizza
        outline = [(100, 178), (30, 44), (40, 30), (160, 30), (170, 44)]
        parts = [('#ffca3a', polygon(outline)), ('#c9772a', polygon(rounded_pts(26, 26, 148, 22, 11))),
                 ('#e63946', ellipse(80, 72, 12, 12)), ('#e63946', ellipse(120, 70, 11, 11)), ('#e63946', ellipse(100, 116, 11, 11))]
        return [outline], parts
    if look == 1:       # a doughnut
        outline = circle_pts(100, 100, 76)
        icing = ['#f15bb5', '#4cc9f0', '#9b5de5'][v % 3]
        return [outline], [('#d4a373', annulus(100, 100, 76, 24)), (icing, annulus(100, 100, 66, 30)),
                           (WHITE, polyline([(70, 60), (78, 66)]), 4), (WHITE, polyline([(124, 132), (134, 128)]), 4)]
    if look == 2:       # an ice cream cone
        cone = [(70, 104), (130, 104), (100, 182)]
        scoop = circle_pts(100, 80, 46)
        flavour = ['#ffb3c7', '#9ee6a0', '#8d6e63'][v % 3]
        return [cone, scoop], [('#e9c46a', polygon(cone)), (flavour, polygon(scoop)), ('#e63946', ellipse(100, 32, 9, 9))]
    if look == 3:       # two cherries
        c1, c2 = circle_pts(70, 136, 32), circle_pts(132, 140, 32)
        return [c1, c2, [(64, 104), (100, 30), (108, 34), (74, 108)]], [
            ('#43a047', polyline([(70, 106), (102, 34), (130, 108)]), 6), ('#e53935', polygon(c1)), ('#e53935', polygon(c2)),
            (WHITE, ellipse(60, 126, 6, 9))]
    # a slice of watermelon
    outline = [(100 + 84 * math.cos(math.pi * i / 24), 70 + 84 * math.sin(math.pi * i / 24)) for i in range(25)]
    flesh = [(100 + 72 * math.cos(math.pi * i / 24), 70 + 72 * math.sin(math.pi * i / 24)) for i in range(25)]
    seeds = ''.join(ellipse(x, y, 4, 6) for x, y in [(70, 92), (100, 104), (130, 92), (86, 118), (114, 118)])
    return [outline], [('#43a047', polygon(outline)), ('#ff595e', polygon(flesh)), (STICKER_INK, seeds)]


def sticker_weather(rng, v, pal):
    look = v % 5
    if look == 0:       # the sun
        rays = star(100, 100, 12, 86, 58)
        return [rays], [('#ffbe0b', polygon(rays)), ('#ffd93d', ellipse(100, 100, 50, 50))]
    if look == 1:       # a cloud
        puffs = [circle_pts(70, 112, 36), circle_pts(112, 90, 46), circle_pts(146, 118, 30), rounded_pts(40, 110, 130, 40, 20)]
        return puffs, [('#e9edf5', p) for p in [polygon(x) for x in puffs]] + [('#8d99ae', polyline([(58, 150), (152, 150)]), 3)]
    if look == 2:       # a rain cloud
        puffs = [circle_pts(70, 84, 32), circle_pts(110, 66, 40), circle_pts(144, 90, 28), rounded_pts(42, 80, 124, 38, 19)]
        drops = [(70, 140), (100, 152), (130, 140)]
        drop_pts = [[(x, y - 16), (x + 9, y + 2), (x, y + 12), (x - 9, y + 2)] for x, y in drops]
        return puffs + drop_pts, [('#8d99ae', polygon(x)) for x in puffs] + [('#4d96ff', polygon(d)) for d in drop_pts]
    if look == 3:       # a bolt of lightning
        bolt = [(118, 18), (56, 110), (96, 110), (78, 182), (146, 84), (106, 84)]
        return [bolt], [('#ffd93d', polygon(bolt)), ('#fb8c00', polyline([(112, 34), (70, 100)]), 4)]
    # a rainbow
    outline = [(100 + 86 * math.cos(math.pi + math.pi * i / 24), 140 + 86 * math.sin(math.pi + math.pi * i / 24)) for i in range(25)]
    bands = []
    for k, (r, c) in enumerate([(86, '#ff595e'), (70, '#ffca3a'), (54, '#8ac926')]):
        inner = r - 16
        arc = [(100 + r * math.cos(math.pi + math.pi * i / 24), 140 + r * math.sin(math.pi + math.pi * i / 24)) for i in range(25)]
        arc += [(100 + inner * math.cos(2 * math.pi - math.pi * i / 24), 140 + inner * math.sin(2 * math.pi - math.pi * i / 24)) for i in range(25)]
        bands.append((c, polygon(arc)))
    return [outline + [(14, 150), (186, 150)][::-1]], bands


def sticker_arrow(rng, v, pal):
    look = v % 5
    colour = pal[v % 4]
    if look == 0:       # a chunky arrow right
        outline = [(20, 78), (110, 78), (110, 40), (182, 100), (110, 160), (110, 122), (20, 122)]
    elif look == 1:     # up
        outline = rotate([(20, 78), (110, 78), (110, 40), (182, 100), (110, 160), (110, 122), (20, 122)], 100, 100, -math.pi / 2)
    elif look == 2:     # both ways
        outline = [(18, 100), (66, 50), (66, 80), (134, 80), (134, 50), (182, 100), (134, 150), (134, 120), (66, 120), (66, 150)]
    elif look == 3:     # a bend
        outline = [(24, 170), (24, 90), (40, 66), (120, 66), (120, 30), (182, 86), (120, 142), (120, 106), (64, 106), (64, 170)]
    else:               # a slanted arrow
        outline = rotate([(20, 82), (112, 82), (112, 46), (182, 100), (112, 154), (112, 118), (20, 118)], 100, 100, -math.pi / 4)
    return [outline], [(colour, polygon(outline))]


def sticker_speech(rng, v, pal):
    look = v % 5
    a, ink = pal[v % 4], STICKER_INK
    if look == 0:       # a rounded bubble, three dots
        body = rounded_pts(20, 30, 160, 110, 34)
        tail = [(54, 130), (90, 130), (44, 176)]
        return [body, tail], [(a, polygon(body)), (a, polygon(tail))] + [(ink, ellipse(x, 86, 9, 9)) for x in (66, 100, 134)]
    if look == 1:       # an oval bubble, a heart
        body = circle_pts(100, 88, 82, ry=60)
        tail = [(126, 136), (160, 180), (98, 144)]
        return [body, tail], [(a, polygon(body)), (a, polygon(tail)), ('#e63946', polygon(heart_pts(100, 90, 64)))]
    if look == 2:       # a thought cloud
        puffs = [circle_pts(cx, cy, r) for cx, cy, r in [(70, 76, 36), (112, 62, 42), (146, 88, 32), (100, 106, 40), (60, 108, 28)]]
        dots = [circle_pts(54, 158, 12, 24), circle_pts(36, 182, 7, 24)]
        return puffs + dots, [(a, polygon(p)) for p in puffs + dots]
    if look == 3:       # a shout
        body = star(100, 92, 12, 84, 60)
        tail = [(60, 140), (84, 146), (34, 188)]
        return [body, tail], [(a, polygon(body)), (a, polygon(tail)), (ink, polygon([(94, 50), (106, 50), (103, 110), (97, 110)])), (ink, ellipse(100, 126, 7, 7))]
    # a bubble with lines of writing
    body = rounded_pts(20, 26, 160, 116, 24)
    tail = [(130, 132), (162, 180), (106, 136)]
    return [body, tail], [(a, polygon(body)), (a, polygon(tail))] + [(ink, polyline([(48, y), (x, y)]), 7) for y, x in ((62, 152), (86, 140), (110, 120))]


# What each kind of sticker is drawn by, its name's noun and its words.
STICKER_KINDS = [
    ('badge', sticker_badge, 18, 'badge', ['badge', 'words', 'label']),
    ('face', sticker_face, 15, 'face', ['face', 'smiley', 'emoji', 'happy']),
    ('heart', sticker_heart, 15, 'heart', ['heart', 'love', 'valentine']),
    ('star', sticker_star, 15, 'star', ['star', 'shine', 'favourite']),
    ('food', sticker_food, 15, 'food', ['food', 'snack', 'treat']),
    ('weather', sticker_weather, 15, 'weather', ['weather', 'sky', 'nature']),
    ('arrow', sticker_arrow, 15, 'arrow', ['arrow', 'pointer', 'direction']),
    ('speech', sticker_speech, 15, 'speech bubble', ['speech', 'bubble', 'chat', 'talk']),
]

# A word for each sticker's look, so names and searches tell them apart.
STICKER_LOOKS = {
    'badge': ['wow', 'sale', 'new', 'love', 'omg', 'thank you'],
    'face': ['smiling', 'winking', 'surprised', 'heart-eyed', 'cool'],
    'heart': ['shiny', 'double', 'layered', 'broken', 'ribboned'],
    'star': ['gold', 'smiling', 'shooting', 'eight-pointed', 'cluster'],
    'food': ['pizza', 'doughnut', 'ice cream', 'cherry', 'watermelon'],
    'weather': ['sun', 'cloud', 'rain', 'lightning', 'rainbow'],
    'arrow': ['right', 'up', 'double', 'bent', 'slanted'],
    'speech': ['typing', 'love', 'thought', 'shout', 'note'],
}
STICKER_BASES = ['round', 'seal', 'ticket']

# The moves a third of the stickers make: every third, in turn.
STICKER_MOTIONS = ['wiggle', 'pop', 'float']


def face_look(v):
    return v % 5 if v < 5 else (v + v // 5) % 5


def sticker_name(key, v, noun):
    if key == 'badge':
        return '%s %s badge' % (STICKER_LOOKS[key][v % 6].upper(), STICKER_BASES[v // 6])
    look = STICKER_LOOKS[key][face_look(v) if key == 'face' else v % 5]
    turn = v // 5 + 1
    # Food and weather are named for what they show alone: "Pizza".
    name = look.capitalize() if key in ('food', 'weather') else '%s %s' % (look.capitalize(), noun)
    return name if turn == 1 else '%s %d' % (name, turn)


def build_stickers():
    out = []
    for seed, (key, draw, count, noun, words) in enumerate(STICKER_KINDS):
        rng = random.Random(4100 + seed)
        for v in range(count):
            pal = PALETTES[(v * 3 + seed) % len(PALETTES)]
            silhouettes, art = draw(rng, v, pal)
            parts = [diecut(silhouettes)] + art
            colours = colours_of(parts)
            assert len(colours) <= 4, (key, v, colours)
            look = sticker_name(key, v, noun).lower()
            graphic = {
                'id': 'sticker-%s-%02d' % (key, v + 1),
                'name': sticker_name(key, v, noun),
                'category': 'Stickers',
                'tags': ['sticker'] + words + [w for w in look.split(' ') if w not in words and not w.isdigit() and w != 'sticker'],
                'svg': svg_of(200, 200, parts),
                'colours': colours,
                # The art's colours, not the white die-cut round it.
                'hues': hues_of(art),
            }
            index = len(out)
            if index % 3 == 0:
                graphic['motion'] = STICKER_MOTIONS[(index // 3) % 3]
            out.append(graphic)
    return out


# What each category is drawn by, its names and words. One graphic a name,
# in this order; its variant is its place in the list. A seventh entry is
# the graphic's motion.
KINDS = [
    ('Doodle arrows', 'arrow', doodle_arrow, 17, 'Arrow', ['arrow', 'doodle', 'pointer', 'hand drawn']),
    ('Underlines & circles', 'underline', underline, 17, 'Underline', ['underline', 'circle', 'highlight', 'hand drawn']),
    ('Sparkles', 'sparkle', sparkles, 17, 'Sparkle', ['sparkle', 'shine', 'star', 'twinkle']),
    ('Starbursts & badges', 'burst', starburst, 17, 'Starburst', ['starburst', 'badge', 'sale', 'seal']),
    ('Ribbons', 'ribbon', banner, 16, 'Ribbon', ['ribbon', 'banner', 'label', 'bow']),
    ('Blobs', 'blob', blob, 17, 'Blob', ['blob', 'organic', 'shape', 'abstract']),
    ('Confetti', 'confetti', confetti, 16, 'Confetti', ['confetti', 'party', 'celebrate', 'celebration']),
    ('Dividers', 'divider', divider, 17, 'Divider', ['divider', 'line', 'separator', 'flourish']),
    ('Speech bubbles', 'bubble', bubble, 17, 'Speech bubble', ['speech', 'bubble', 'chat', 'talk', 'quote']),
    ('Hand-drawn frames', 'frame', hand_frame, 17, 'Hand-drawn frame', ['frame', 'border', 'hand drawn', 'doodle']),
    ('Scribbles', 'scribble', scribble, 17, 'Scribble', ['scribble', 'doodle', 'squiggle', 'hand drawn']),
    ('Patterns', 'pattern', pattern, 17, 'Pattern', ['pattern', 'texture', 'background', 'tile']),
    ('Animated', 'drawn-arrow', drawn_arrow, 12, 'Drawn arrow', ['animated', 'arrow', 'draw', 'hand drawn'], 'draw'),
    ('Animated', 'drawn-underline', drawn_underline, 10, 'Drawn underline', ['animated', 'underline', 'draw', 'hand drawn'], 'draw'),
    ('Animated', 'drawn-circle', drawn_circle, 8, 'Drawn circle', ['animated', 'circle', 'draw', 'highlight'], 'draw'),
    ('Animated', 'drawn-scribble', drawn_scribble, 8, 'Drawn scribble', ['animated', 'scribble', 'draw', 'doodle'], 'draw'),
    ('Animated', 'twinkle-sparkle', twinkle_sparkle, 10, 'Twinkling sparkle', ['animated', 'sparkle', 'twinkle', 'shine'], 'twinkle'),
    ('Animated', 'twinkle-star', twinkle_star, 6, 'Twinkling star', ['animated', 'star', 'twinkle', 'shine'], 'twinkle'),
    ('Animated', 'float', float_shape, 6, 'Floating shape', ['animated', 'float', 'shape'], 'float'),
]

# A word for each variant's look, so names and searches tell them apart.
LOOKS = {
    'arrow': ['curved', 'looped', 'zigzag', 'straight', 'hooked', 'spiral'],
    'underline': ['swash', 'double', 'wavy', 'circled', 'highlighted', 'looped'],
    'sparkle': ['single', 'pair', 'trio'],
    'burst': ['12-point', '16-point', '20-point', '24-point', '10-point', '8-point', '14-point', '18-point'],
    'ribbon': ['flat', 'curved', 'tag', 'bow'],
    'blob': ['single', 'double', 'triple'],
    'confetti': ['light', 'scattered', 'busy', 'full'],
    'divider': ['diamond', 'dotted', 'sparkle', 'heart', 'flourish', 'wavy'],
    'bubble': ['rounded', 'oval', 'thought', 'shout', 'note'],
    'frame': ['sketched', 'oval', 'double', 'dashed'],
    'scribble': ['zigzag', 'spiral', 'loopy', 'tangled', 'crossed-out'],
    'pattern': ['polka dot', 'striped', 'checked', 'wavy', 'crosses', 'triangles'],
    'drawn-arrow': ['curved', 'looped', 'zigzag', 'swooping', 'wavy', 'spiral'],
    'drawn-underline': ['swash', 'double', 'wavy', 'zigzag', 'looped'],
    'drawn-circle': ['circled', 'twice-circled'],
    'drawn-scribble': ['zigzag', 'spiral', 'loopy', 'crossed-out'],
    'twinkle-sparkle': ['pair', 'trio', 'cluster'],
    'twinkle-star': ['pair', 'trio', 'cluster'],
    'float': ['heart', 'balloon', 'blob'],
}


def area_of(part):
    """How much of its graphic a part covers: a filled path's area by the
    shoelace sum over each subpath's points (curves by their control
    points), or a stroked line's length times its width."""
    numbers = [float(t) for t in re.findall(r'-?\d+(?:\.\d+)?', part[1])]
    points = list(zip(numbers[0::2], numbers[1::2]))
    if len(part) == 3:
        return sum(math.dist(a, b) for a, b in zip(points, points[1:])) * part[2]
    total = 0.0
    for chunk in part[1].split('M')[1:]:
        values = [float(t) for t in re.findall(r'-?\d+(?:\.\d+)?', chunk)]
        pts = list(zip(values[0::2], values[1::2]))
        total += abs(sum(a[0] * b[1] - b[0] * a[1] for a, b in zip(pts, pts[1:] + pts[:1]))) / 2
    return total


def hues_of(parts):
    """A graphic's colours, the one that covers the most first (a tie in
    first-use order), at most three."""
    order = colours_of(parts)
    areas = {c: 0.0 for c in order}
    for part in parts:
        areas[part[0]] += area_of(part)
    return sorted(order, key=lambda c: (-round(areas[c], 1), order.index(c)))[:3]


# The emoji palette: the colours the phones' emoji are drawn in, by name.
EMOJI = {
    'red': '#e53935', 'orange': '#fb8c00', 'yellow': '#fdd835', 'face': '#fbc02d', 'gold': '#ffb300',
    'green': '#43a047', 'teal': '#26a69a', 'blue': '#1e88e5', 'sky': '#4fc3f7', 'purple': '#8e24aa',
    'pink': '#f06292', 'brown': '#8d6e63', 'black': '#212121', 'grey': '#9e9e9e', 'white': '#fafafa',
}

# Each curated sticker (Stickers.names) by the palette's names, most of the
# picture first.
STICKER_HUES = {
    '🎉': 'yellow red blue', '🎊': 'yellow red pink', '🎈': 'red', '🎂': 'pink brown white', '🎁': 'red yellow',
    '🥳': 'face pink blue', '🍾': 'green gold', '✨': 'yellow', '🎆': 'purple yellow blue', '🏆': 'gold',
    '🎖️': 'gold red blue', '💝': 'red pink yellow', '⭐': 'yellow', '🌟': 'yellow', '💫': 'yellow',
    '❤️': 'red', '🧡': 'orange', '💛': 'yellow', '💚': 'green', '💙': 'blue', '💜': 'purple', '🖤': 'black',
    '💥': 'red orange yellow', '🔥': 'orange red yellow', '😀': 'face', '😄': 'face', '😁': 'face white',
    '😊': 'face pink', '😍': 'face red', '😎': 'face black', '🤩': 'face gold', '😂': 'face sky',
    '😜': 'face red', '😇': 'face sky', '🤔': 'face', '😴': 'face sky', '🙃': 'face', '🌸': 'pink',
    '🌻': 'yellow brown green', '🌿': 'green', '🍀': 'green', '🌵': 'green', '🌴': 'green brown',
    '🌈': 'red yellow blue', '☀️': 'yellow orange', '🌙': 'yellow', '🌊': 'blue sky white', '🍁': 'red orange',
    '🦋': 'blue sky black', '🐝': 'yellow black', '🍕': 'yellow red brown', '🍔': 'brown yellow green',
    '🌮': 'yellow green red', '🍣': 'orange white', '🍩': 'pink brown', '🍪': 'brown', '🍓': 'red green',
    '🍉': 'red green', '🥑': 'green brown', '🍦': 'white brown', '☕': 'white brown', '🧁': 'pink brown',
    '🍰': 'white pink red', '🍇': 'purple green', '📷': 'grey black', '🎧': 'grey black', '🎨': 'brown red blue',
    '✏️': 'yellow pink', '📚': 'red blue green', '💻': 'grey', '📱': 'black grey', '🎸': 'brown orange',
    '⏰': 'red white', '💡': 'yellow', '🔑': 'gold', '✂️': 'red grey', '🧭': 'red grey', '🎬': 'black white',
    '📌': 'red', '📍': 'red', '✅': 'green', '❌': 'red', '❗': 'red', '❓': 'red', '🚀': 'grey red orange',
    '⚡': 'yellow', '🎯': 'red white', '💎': 'sky blue', '🎵': 'black', '🔔': 'gold', '💬': 'white grey',
    '👉': 'face',
}


def sticker_hues():
    return {glyph: [EMOJI[name] for name in names.split()] for glyph, names in STICKER_HUES.items()}


def colours_of(parts):
    out = []
    for part in parts:
        if part[0] not in out:
            out.append(part[0])
    return out


def svg_of(width, height, parts):
    """Each part a filled path, or — given a width, (colour, d, width) — a
    line stroked in its colour with round ends and no fill."""
    def path(part):
        if len(part) == 3:
            return ('<path fill="none" stroke="%s" stroke-width="%s" stroke-linecap="round" stroke-linejoin="round" d="%s"/>'
                    % (part[0], num(part[2]), part[1]))
        return '<path fill="%s" d="%s"/>' % (part[0], part[1])
    paths = ''.join(path(p) for p in parts)
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">%s</svg>' % (width, height, paths)


def build():
    graphics = []
    for seed, kind in enumerate(KINDS):
        category, key, draw, count, noun, words = kind[:6]
        motion = kind[6] if len(kind) > 6 else None
        rng = random.Random(3100 + seed)
        looks = LOOKS[key]
        for v in range(count):
            pal = PALETTES[(v * 3 + seed) % len(PALETTES)]
            width, height, parts = draw(rng, v, pal)
            colours = colours_of(parts)
            assert len(colours) <= 4, (key, v, colours)
            look = looks[v % len(looks)]
            name = '%s %s %d' % (look.capitalize(), noun.lower(), v // len(looks) + 1) if v >= len(looks) else '%s %s' % (look.capitalize(), noun.lower())
            graphic = {
                'id': '%s-%02d' % (key, v + 1),
                'name': name,
                'category': category,
                'tags': words + [w for w in look.split(' ') if w not in words],
                'svg': svg_of(width, height, parts),
                'colours': colours,
                'hues': hues_of(parts),
            }
            if motion:
                graphic['motion'] = motion
            graphics.append(graphic)
    return graphics + build_stickers()


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    graphics = build()
    lines = [json.dumps(g, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for g in graphics]
    text = ('{\n"categories":' + json.dumps(CATEGORIES, ensure_ascii=False, separators=(',', ':')) + ',\n'
            + '"graphics":[\n' + ',\n'.join(lines) + '\n],\n'
            + '"stickerHues":' + json.dumps(sticker_hues(), ensure_ascii=False, sort_keys=True, separators=(',', ':')) + '\n}\n')
    RESOURCE.write_text(text, encoding='utf-8')
    print('%d graphics in %d categories, %d bytes' % (len(graphics), len(CATEGORIES), len(text.encode('utf-8'))))
    if len(sys.argv) == 2:
        out = pathlib.Path(sys.argv[1]) / 'Graphics.json'
        out.write_text(text, encoding='utf-8')
        print('and', out)


if __name__ == '__main__':
    main()
