#!/usr/bin/env python3
"""Regenerate both phones' illustrated graphics pack.

    tools/generate_graphics.py [path/to/ios/Content]

Writes core/src/main/resources/com/canvia/core/content/Graphics.json and,
given a folder, the same file there for the iOS twin to bundle, so the two
apps draw every graphic from the same bytes. Nothing is downloaded: every
graphic is drawn here, from seeded random paths given a jitter pass for a
hand-drawn look, so the same script writes the same file on any machine.

The file is one object:

  "categories"  the twelve categories, in the order Add shows them.
  "graphics"    each {"id", "name", "category", "tags": [...], "svg",
                "colours": [...]}, category by category. "svg" is a whole
                SVG document of filled <path>s only — no strokes, text or
                gradients — so it comes onto a page as any SVG graphic does
                (SvgImport.graphic): a group of shapes, each in its own
                colour. "colours" are its fills in the order they are first
                used, at most four, lower-case "#rrggbb", as Colour swap
                lists them.
                A graphic that moves also has "motion": "draw" (its
                lines draw themselves on, path after path), "twinkle"
                (its paths pulse in turn) or "float" (it bobs gently).
                Every arrow, underline and circle, and scribble draws on
                and every sparkle twinkles, by kind (MOTIONS); "float" is
                read by both phones but no graphic here has it yet.

Paths are absolute M, L, C and Z, numbers to a tenth. A hand-drawn line is a
filled ribbon round its centre line, tapering at its ends, so it scales with
its graphic as a stroke would not. Each kind of graphic has its own seed, so
changing one kind leaves every other kind's bytes as they were.
"""
import json
import math
import pathlib
import random
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCE = REPO / 'core/src/main/resources/com/canvia/core/content/Graphics.json'

CATEGORIES = [
    'Doodle arrows', 'Underlines & circles', 'Sparkles', 'Starbursts & badges',
    'Ribbons', 'Blobs', 'Confetti', 'Dividers', 'Speech bubbles',
    'Hand-drawn frames', 'Scribbles', 'Patterns',
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


# What each category is drawn by, its names and words. One graphic a name,
# in this order; its variant is its place in the list.
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
]

# How each kind of graphic moves when it is put on a page; a kind not
# here stays still.
MOTIONS = {
    'arrow': 'draw',
    'underline': 'draw',
    'scribble': 'draw',
    'sparkle': 'twinkle',
}

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
}


def colours_of(parts):
    out = []
    for fill, _ in parts:
        if fill not in out:
            out.append(fill)
    return out


def svg_of(width, height, parts):
    paths = ''.join('<path fill="%s" d="%s"/>' % (fill, d) for fill, d in parts)
    return '<svg xmlns="http://www.w3.org/2000/svg" viewBox="0 0 %d %d">%s</svg>' % (width, height, paths)


def build():
    graphics = []
    for seed, (category, key, draw, count, noun, words) in enumerate(KINDS):
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
            }
            if key in MOTIONS:
                graphic['motion'] = MOTIONS[key]
            graphics.append(graphic)
    return graphics


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    graphics = build()
    lines = [json.dumps(g, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for g in graphics]
    text = ('{\n"categories":' + json.dumps(CATEGORIES, ensure_ascii=False, separators=(',', ':')) + ',\n'
            + '"graphics":[\n' + ',\n'.join(lines) + '\n]\n}\n')
    RESOURCE.write_text(text, encoding='utf-8')
    print('%d graphics in %d categories, %d bytes' % (len(graphics), len(CATEGORIES), len(text.encode('utf-8'))))
    if len(sys.argv) == 2:
        out = pathlib.Path(sys.argv[1]) / 'Graphics.json'
        out.write_text(text, encoding='utf-8')
        print('and', out)


if __name__ == '__main__':
    main()
