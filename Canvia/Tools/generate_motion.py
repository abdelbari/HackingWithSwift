#!/usr/bin/env python3
"""Regenerate both phones' generated motion loops and still textures.

    tools/generate_motion.py [path/to/ios/Content] [path/to/ios/Tests/Fixtures]

Writes core/src/main/resources/com/canvia/core/content/Motion.json, the
library both phones draw from, and
core/src/test/resources/com/canvia/core/content/motion-frames.json, the
frame hashes both phones' tests check their drawing against; given the
folders, the same files there for the iOS twin. Nothing is downloaded or
drawn ahead: each entry is a recipe, and both phones draw any frame of it
with the same seeded maths as `frame` below — this file is the reference.

Motion.json is one object:

  "loops"   about thirty motion backgrounds, each {"id", "name", "category",
            "kind", "colours": [...], "seed", "period", "tags": [...]};
            "period" is the seconds one loop takes. On a page a loop is a
            picture whose source is "motion:<id>".
  "stills"  sixty more still pictures — marble, paper, linen, terrazzo,
            skies, halftone, bokeh and grain — the same shape with a
            "period" of 0, each the frame at t = 0 of its kind. On a page
            a still is "asset:<id>", as the drawn pictures are.

A frame of an entry at t seconds, W x H pixels, is computed per pixel in
doubles, in this order, and rounded to bytes at the end (see `frame`):

  p    = t / period, wrapped into 0..1 (0 for a still); ang = 2 pi p
  X, Y = ((x + 0.5) / W) * (W / H), (y + 0.5) / H — the pixel's centre in
         units of the frame's height; A = W / H
  rng  = the LCG every seeded drawing shares (SeededRandom): state = seed
         mod 2^32, then state = state * 1664525 + 1013904223 mod 2^32, a
         draw being state / 2^32 — drawn once per frame before any pixel
  hash(i, j, s) = h = i*374761393 + j*668265263 + s*2246822519 mod 2^32;
         h = (h ^ h >> 13) * 1274126177 mod 2^32; h ^= h >> 16; h / 2^32
  noise(x, y, s) = the four hashes round (floor x, floor y), mixed by
         smoothstep f*f*(3 - 2f) of the fractions, x first
  fbm(x, y, s) = (noise(x, y, s) + noise(2x, 2y, s+1) / 2 + noise(4x, 4y,
         s+2) / 4) / 1.75
  grad(cs, f) = the colours cs spread evenly over 0..1, f kept in it
  mix(a, b, f) = a + (b - a) * f, per channel; colours 0..1 from "#rrggbb"
  c[i] = colours[i mod count]
  each byte = floor(v * 255 + 0.5), kept within 0..255

and each kind as `kind_*` below says. The fixture hashes are FNV-1a 32 over
each pixel's red, green and blue bytes, row by row, of a 48 x 36 frame at
t = 0 and t = period / 2 (a still has the first alone), as eight hex digits.
"""
import json
import math
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCE = REPO / 'core/src/main/resources/com/canvia/core/content/Motion.json'
FIXTURE = REPO / 'core/src/test/resources/com/canvia/core/content/motion-frames.json'

TAU = 2 * math.pi
HASH_W, HASH_H = 48, 36

PALETTES = {
    'sunset': ['#ff9a8b', '#ff6a88', '#ff99ac', '#fbc2eb', '#f6d365'],
    'ocean': ['#2b5876', '#4e4376', '#00c6fb', '#005bea', '#43e97b'],
    'candy': ['#a18cd1', '#fbc2eb', '#fad0c4', '#ff9a9e', '#fecfef'],
    'forest': ['#134e5e', '#71b280', '#2af598', '#009efd', '#0f3443'],
    'ember': ['#1a1a2e', '#e94560', '#903749', '#53354a', '#ff7b54'],
    'gold': ['#f8b500', '#fceabb', '#e96443', '#904e95', '#ffd194'],
    'night': ['#0b1026', '#2b3a67', '#ffffff', '#ffe8a3'],
    'dusk': ['#2c3e50', '#fd746c', '#ff9068', '#ffd3a5'],
    'mint': ['#e0f7ef', '#7ee8c7', '#2bb3a0', '#0d5c63'],
    'berry': ['#3a0ca3', '#f72585', '#7209b7', '#4cc9f0'],
    'party': ['#fff8f0', '#ff595e', '#ffca3a', '#8ac926', '#1982c4', '#6a4c93'],
    'mono': ['#111111', '#444444', '#bbbbbb'],
}

# id prefix, kind, name stem, category, tags, then each (name, palette or
# colours, period) — the seed is the entry's place in the whole list.
LOOPS = [
    ('mesh', 'mesh', 'Drift', 'Gradients', ['gradient', 'mesh', 'abstract', 'background'], [
        ('Sunset', 'sunset', 8), ('Ocean', 'ocean', 10), ('Candy', 'candy', 8), ('Forest', 'forest', 12),
        ('Ember', 'ember', 10)]),
    ('waves', 'waves', 'Waves', 'Waves', ['waves', 'water', 'flow', 'layers'], [
        ('Deep sea', ['#03045e', '#0077b6', '#00b4d8', '#90e0ef', '#caf0f8'], 6),
        ('Sunset', ['#2d1e2f', '#c33c54', '#f08a4b', '#f7c59f'], 6),
        ('Mint', 'mint', 8), ('Berry', 'berry', 6)]),
    ('bokeh', 'bokeh', 'Bokeh', 'Bokeh', ['bokeh', 'lights', 'blur', 'sparkle', 'rising'], [
        ('Golden', ['#1b1b2f', '#3b2f4f', '#ffd166', '#f8961e', '#fff1c1'], 8),
        ('Night', 'night', 10), ('Rose', ['#2b0f1f', '#5c1a3a', '#ff8fab', '#ffc2d1', '#fb6f92'], 8),
        ('Teal', ['#062925', '#044a42', '#3a9188', '#b8e1dd', '#ffffff'], 10)]),
    ('confetti', 'confetti', 'Confetti', 'Confetti', ['confetti', 'party', 'celebration', 'falling'], [
        ('Party', 'party', 6), ('Night', ['#14213d', '#fca311', '#e5e5e5', '#ff006e', '#3a86ff'], 6),
        ('Pastel', ['#fdf6ec', '#ffadad', '#ffd6a5', '#caffbf', '#9bf6ff', '#bdb2ff'], 8)]),
    ('rays', 'rays', 'Rays', 'Rays', ['rays', 'sunburst', 'rotating', 'retro'], [
        ('Sunburst', ['#f77f00', '#fcbf49', '#fff3b0'], 12), ('Retro', ['#e63946', '#f1faee', '#ffd166'], 12),
        ('Blue', ['#03045e', '#0077b6', '#caf0f8'], 16)]),
    ('grain', 'grain', 'Grain', 'Grain', ['grain', 'gradient', 'noise', 'film'], [
        ('Peach', ['#ffb199', '#ff0844', '#ffd3a5'], 10), ('Lagoon', ['#13547a', '#80d0c7', '#e0f7fa'], 12),
        ('Violet', ['#43cea2', '#185a9d', '#6a3093'], 10), ('Ember', ['#1a1a2e', '#e94560', '#ff7b54'], 12)]),
    ('dots', 'dots', 'Dots', 'Dots', ['dots', 'pulse', 'grid', 'pattern'], [
        ('Pop', ['#fff8e7', '#ff595e', '#1982c4', '#ffca3a'], 4), ('Night', ['#0b132b', '#5bc0be', '#6fffe9'], 4),
        ('Mono', 'mono', 4)]),
    ('stars', 'stars', 'Starfield', 'Stars', ['stars', 'night', 'space', 'twinkle', 'sky'], [
        ('Midnight', 'night', 6), ('Aurora', ['#001219', '#005f73', '#e9d8a6'], 8)]),
    ('paper', 'paper', 'Paper light', 'Paper', ['paper', 'texture', 'light', 'warm'], [
        ('Cream', ['#f4ecdc', '#fff9ee'], 12), ('Kraft', ['#c8a27a', '#f1d7b8'], 12)]),
]

STILLS = [
    ('marble', 'marble', 'Marble', 'Textures', ['marble', 'stone', 'texture', 'veins'], [
        ('White', ['#f3f1ee', '#8c8a86', '#c9b28a']), ('Grey', ['#d9d9d9', '#4a4a4a', '#ffffff']),
        ('Black', ['#1b1b1d', '#d6d2c4', '#9b8a5b']), ('Rose', ['#f6e3e1', '#b7787a', '#ffffff']),
        ('Green', ['#0f3d33', '#b9d7c9', '#d4af37']), ('Blue', ['#e6eef5', '#46637f', '#ffffff']),
        ('Sand', ['#efe3cf', '#a98f6b', '#ffffff']), ('Onyx', ['#26262b', '#e0b973', '#888888'])]),
    ('paper', 'paper', 'Paper', 'Textures', ['paper', 'texture', 'fibre', 'background'], [
        ('Cream', ['#f4ecdc', '#fff9ee']), ('White', ['#f8f8f5', '#ffffff']), ('Kraft', ['#c8a27a', '#f1d7b8']),
        ('Grey', ['#cfcfcc', '#eeeeea']), ('Blush', ['#f3d9d6', '#fff0ee']), ('Sage', ['#d5dfcf', '#f2f7ee']),
        ('Charcoal', ['#3a3a3c', '#5a5a5e'])]),
    ('linen', 'linen', 'Linen', 'Textures', ['linen', 'fabric', 'cloth', 'texture', 'weave'], [
        ('Natural', ['#e9dfcf', '#fff7ea']), ('White', ['#f2f0eb', '#ffffff']), ('Blue', ['#c9d6e3', '#eef4fa']),
        ('Olive', ['#b8b58f', '#e4e2c4']), ('Rose', ['#e6c7c2', '#fbe9e6']), ('Slate', ['#56606b', '#7d8895']),
        ('Mustard', ['#d9a441', '#f3d58a'])]),
    ('terrazzo', 'terrazzo', 'Terrazzo', 'Textures', ['terrazzo', 'chips', 'stone', 'speckle', 'texture'], [
        ('Classic', ['#f2ede6', '#d1495b', '#edae49', '#00798c', '#30638e']),
        ('Pastel', ['#fbf7f2', '#f7a1a1', '#a1c6f7', '#b5e7a0', '#f7d9a1']),
        ('Dark', ['#2b2d42', '#ef233c', '#edf2f4', '#8d99ae']),
        ('Earth', ['#efe6d8', '#a0522d', '#556b2f', '#cd853f']),
        ('Mono', ['#e8e8e8', '#222222', '#777777', '#bbbbbb']),
        ('Pink', ['#ffe5ec', '#fb6f92', '#ffb3c6', '#c9184a']),
        ('Mint', ['#eafaf1', '#2a9d8f', '#e9c46a', '#264653']),
        ('Night', ['#14213d', '#fca311', '#e5e5e5', '#ffffff'])]),
    ('sky', 'sky', 'Sky', 'Skies', ['sky', 'clouds', 'gradient', 'weather'], [
        ('Morning', ['#a1c4fd', '#c2e9fb', '#ffffff']), ('Noon', ['#2980b9', '#6dd5fa', '#ffffff']),
        ('Sunset', ['#355c7d', '#c06c84', '#f67280', '#f8b195']), ('Dusk', ['#0f2027', '#203a43', '#2c5364']),
        ('Dawn', ['#ffecd2', '#fcb69f', '#ff9a8b']), ('Golden', ['#f7971e', '#ffd200', '#fff6c8']),
        ('Lilac', ['#654ea3', '#eaafc8', '#fbe3ef']), ('Storm', ['#232526', '#414345', '#7a7d80']),
        ('Arctic', ['#e0eafc', '#cfdef3', '#ffffff']), ('Tropic', ['#00c9ff', '#92fe9d', '#e9fff0'])]),
    ('halftone', 'halftone', 'Halftone', 'Textures', ['halftone', 'dots', 'print', 'comic', 'pattern'], [
        ('Black', ['#ffffff', '#111111']), ('Red', ['#fff5f0', '#e63946']), ('Blue', ['#f0f7ff', '#1d3557']),
        ('Yellow', ['#1d1d1d', '#ffd60a']), ('Pink', ['#fff0f6', '#d6336c']), ('Teal', ['#e6fcf5', '#0b7285']),
        ('Orange', ['#2b2d42', '#f77f00']), ('Grey', ['#f1f3f5', '#495057'])]),
    ('bokeh', 'bokeh', 'Bokeh', 'Bokeh', ['bokeh', 'lights', 'blur', 'sparkle'], [
        ('Gold', ['#1b1b2f', '#3b2f4f', '#ffd166', '#f8961e', '#fff1c1']), ('Night', 'night'),
        ('Rose', ['#2b0f1f', '#5c1a3a', '#ff8fab', '#ffc2d1', '#fb6f92']),
        ('Teal', ['#062925', '#044a42', '#3a9188', '#b8e1dd', '#ffffff']),
        ('Fairy', ['#0d1b2a', '#1b263b', '#ffe066', '#ffffff', '#f4a261']),
        ('Lilac', ['#231942', '#5e548e', '#e0b1cb', '#be95c4', '#ffffff'])]),
    ('grain', 'grain', 'Grain', 'Gradients', ['grain', 'gradient', 'noise'], [
        ('Peach', ['#ffb199', '#ff0844', '#ffd3a5']), ('Lagoon', ['#13547a', '#80d0c7', '#e0f7fa']),
        ('Violet', ['#43cea2', '#185a9d', '#6a3093']), ('Mono', ['#232526', '#666666', '#d7d7d7']),
        ('Citrus', ['#f7971e', '#ffd200', '#a8e063']), ('Rose', ['#ee9ca7', '#ffdde1', '#c06c84'])]),
]


def entries():
    loops, stills = [], []
    seed = 0
    for prefix, kind, stem, category, tags, variants in LOOPS:
        for n, (label, colours, period) in enumerate(variants):
            seed += 1
            loops.append({
                'id': 'motion-%s-%d' % (prefix, n + 1), 'name': '%s %s' % (label, stem.lower()) if stem != 'Drift' else '%s drift' % label,
                'category': category, 'kind': kind,
                'colours': PALETTES[colours] if isinstance(colours, str) else colours,
                'seed': 1000 + seed * 37, 'period': period, 'tags': tags + [label.lower()],
            })
    for prefix, kind, stem, category, tags, variants in STILLS:
        for n, (label, colours) in enumerate(variants):
            seed += 1
            stills.append({
                'id': 'still-%s-%d' % (prefix, n + 1), 'name': '%s %s' % (label, stem.lower()),
                'category': category, 'kind': kind,
                'colours': PALETTES[colours] if isinstance(colours, str) else colours,
                'seed': 1000 + seed * 37, 'period': 0, 'tags': tags + [label.lower()],
            })
    return loops, stills


# --- the maths both phones share -------------------------------------------

M32 = 0xffffffff


class Lcg:
    def __init__(self, seed):
        self.state = int(seed) & M32

    def next(self):
        self.state = (self.state * 1664525 + 1013904223) & M32
        return self.state / 4294967296


def hash01(i, j, s):
    h = (i * 374761393 + j * 668265263 + s * 2246822519) & M32
    h = ((h ^ (h >> 13)) * 1274126177) & M32
    h ^= h >> 16
    return h / 4294967296


def smooth(f):
    return f * f * (3 - 2 * f)


def noise(x, y, s):
    ix, iy = math.floor(x), math.floor(y)
    fx, fy = x - ix, y - iy
    a, b = hash01(ix, iy, s), hash01(ix + 1, iy, s)
    c, d = hash01(ix, iy + 1, s), hash01(ix + 1, iy + 1, s)
    sx, sy = smooth(fx), smooth(fy)
    top = a + (b - a) * sx
    bottom = c + (d - c) * sx
    return top + (bottom - top) * sy


def fbm(x, y, s):
    return (noise(x, y, s) + noise(2 * x, 2 * y, s + 1) / 2 + noise(4 * x, 4 * y, s + 2) / 4) / 1.75


def rgb(hex_):
    return (int(hex_[1:3], 16) / 255, int(hex_[3:5], 16) / 255, int(hex_[5:7], 16) / 255)


def mix(a, b, f):
    return (a[0] + (b[0] - a[0]) * f, a[1] + (b[1] - a[1]) * f, a[2] + (b[2] - a[2]) * f)


def clamp01(v):
    return 0.0 if v < 0 else 1.0 if v > 1 else v


def grad(cs, f):
    f = clamp01(f)
    if len(cs) == 1:
        return cs[0]
    pos = f * (len(cs) - 1)
    i = min(int(math.floor(pos)), len(cs) - 2)
    return mix(cs[i], cs[i + 1], pos - i)


def lighten(col, k):
    return (col[0] + k, col[1] + k, col[2] + k)


WHITE = (1.0, 1.0, 1.0)


def kind_mesh(c, rng, A, p, ang, seed):
    """A gradient from c0 to c1 along the diagonal, under a soft blob of each
    next colour (c[i+1], i in 0..count-1) that drifts round a small circle
    once a loop: drawn bx = r*A, by = r, radius 0.35 + 0.3 r, phase r; centre
    (bx + 0.12 sin(ang + 2 pi phase), by + 0.12 cos(ang + 2 pi phase)); weight
    0.85 (1 - d / radius)^2 inside it."""
    blobs = []
    for i in range(len(c)):
        bx, by = rng.next() * A, rng.next()
        r, ph = 0.35 + 0.3 * rng.next(), rng.next()
        blobs.append((bx + 0.12 * math.sin(ang + TAU * ph), by + 0.12 * math.cos(ang + TAU * ph), r, c[(i + 1) % len(c)]))

    def px(X, Y, x, y, u, v):
        col = grad([c[0], c[1 % len(c)]], (u + v) / 2)
        for cx, cy, r, bc in blobs:
            d = math.hypot(X - cx, Y - cy) / r
            if d < 1:
                col = mix(col, bc, 0.85 * (1 - d) ** 2)
        return col
    return px


def kind_waves(c, rng, A, p, ang, seed):
    """c0, then band i (1..count-1) below the line i/count + 0.05 sin(2 pi
    (f u + phase) + ang * (1 for an even i, -1 for an odd)), f = 1 + floor(r
    * 3) and phase r drawn in that order for each band."""
    n = len(c)
    bands = []
    for i in range(1, n):
        ph = rng.next()
        f = 1 + math.floor(rng.next() * 3)
        bands.append((i, ph, f))

    def px(X, Y, x, y, u, v):
        col = c[0]
        for i, ph, f in bands:
            edge = i / n + 0.05 * math.sin(TAU * (f * u + ph) + ang * (1 if i % 2 == 0 else -1))
            if v > edge:
                col = c[i]
        return col
    return px


def kind_bokeh(c, rng, A, p, ang, seed):
    """c0 to c1 down the frame, under 24 soft discs, each in c[2 + k]: drawn
    x0 = r*A, y0 = r, radius 0.03 + 0.07 r, speed 1 + floor(r * 2); centre
    (x0 + 0.03 sin(ang*speed + 2 pi y0), fract(y0 - p*speed) * 1.3 - 0.15),
    rising a whole frame or two a loop; alpha 0.5 * min(1, (1 - d/radius) /
    0.3) inside it."""
    discs = []
    for k in range(24):
        x0, y0 = rng.next() * A, rng.next()
        r = 0.03 + 0.07 * rng.next()
        speed = 1 + math.floor(rng.next() * 2)
        cy = (y0 - p * speed) - math.floor(y0 - p * speed)
        discs.append((x0 + 0.03 * math.sin(ang * speed + TAU * y0), cy * 1.3 - 0.15, r, c[(2 + k) % len(c)]))

    def px(X, Y, x, y, u, v):
        col = grad([c[0], c[1 % len(c)]], v)
        for cx, cy, r, dc in discs:
            d = math.hypot(X - cx, Y - cy)
            if d < r:
                col = mix(col, dc, 0.5 * min(1.0, (1 - d / r) / 0.3))
        return col
    return px


def kind_confetti(c, rng, A, p, ang, seed):
    """c0 under 70 pieces, piece k in c[1 + k mod (count - 1)]: drawn x0 =
    r*A, y0 = r, size 0.012 + 0.014 r, turn r, spin (r < 0.5: 1, else -1);
    centre (x0 + 0.02 sin(ang + 2 pi turn), fract(y0 + p * (1 + k mod 2)) *
    1.1 - 0.05), falling; turned 2 pi (turn + p * spin); a pixel is the
    piece's where |lx| <= size and |ly| <= 0.45 size in its turned frame."""
    pieces = []
    for k in range(70):
        x0, y0 = rng.next() * A, rng.next()
        s = 0.012 + 0.014 * rng.next()
        turn = rng.next()
        spin = 1 if rng.next() < 0.5 else -1
        fall = y0 + p * (1 + k % 2)
        cy = (fall - math.floor(fall)) * 1.1 - 0.05
        th = TAU * (turn + p * spin)
        pieces.append((x0 + 0.02 * math.sin(ang + TAU * turn), cy, s, math.cos(th), math.sin(th),
                       c[1 + k % (len(c) - 1)] if len(c) > 1 else c[0]))

    def px(X, Y, x, y, u, v):
        col = c[0]
        for cx, cy, s, co, si, pc in pieces:
            dx, dy = X - cx, Y - cy
            lx = dx * co + dy * si
            ly = -dx * si + dy * co
            if abs(lx) <= s and abs(ly) <= s * 0.45:
                col = pc
        return col
    return px


def kind_rays(c, rng, A, p, ang, seed):
    """Twelve rays round the centre, turning one ray a loop: turn = atan2(Y -
    0.5, X - A/2) / 2 pi + 0.5 - p / 12; every other twenty-fourth of it is
    mix(c0, c1, 0.6), the rest c0; then mix towards c2 by 0.7 (1 - d/0.45)^2
    within 0.45 of the centre."""
    m = 12

    def px(X, Y, x, y, u, v):
        turn = math.atan2(Y - 0.5, X - A / 2) / TAU + 0.5 - p / m
        f = turn - math.floor(turn)
        col = mix(c[0], c[1 % len(c)], 0.6) if int(math.floor(f * 2 * m)) % 2 == 1 else c[0]
        d = math.hypot(X - A / 2, Y - 0.5)
        if d < 0.45:
            col = mix(col, c[2 % len(c)], 0.7 * (1 - d / 0.45) ** 2)
        return col
    return px


def kind_grain(c, rng, A, p, ang, seed):
    """Every colour along a line that turns once a loop: f = 0.5 + ((X - A/2)
    cos ang + (Y - 0.5) sin ang) / (A + 1); then each channel moved by
    (hash(x, y, seed + floor(p * 24)) - 0.5) * 0.1 — grain that changes 24
    times a loop, on the pixel's own x and y."""
    frame = int(math.floor(p * 24))
    co, si = math.cos(ang), math.sin(ang)

    def px(X, Y, x, y, u, v):
        col = grad(c, 0.5 + ((X - A / 2) * co + (Y - 0.5) * si) / (A + 1))
        return lighten(col, (hash01(x, y, seed + frame) - 0.5) * 0.1)
    return px


def kind_dots(c, rng, A, p, ang, seed):
    """c0, and a dot in each cell of a 1/14 grid, its radius 0.32 cell *
    (0.65 + 0.35 sin(ang + (gx + gy) * 0.7)), in c[1 + (gx + gy) mod (count
    - 1)]."""
    S = 1 / 14

    def px(X, Y, x, y, u, v):
        gx, gy = math.floor(X / S), math.floor(Y / S)
        r = S * 0.32 * (0.65 + 0.35 * math.sin(ang + (gx + gy) * 0.7))
        if math.hypot(X - (gx + 0.5) * S, Y - (gy + 0.5) * S) < r:
            return c[1 + (gx + gy) % (len(c) - 1)] if len(c) > 1 else c[0]
        return c[0]
    return px


def kind_stars(c, rng, A, p, ang, seed):
    """c0 to c1 down the frame; a star in a cell of a 1/36 grid where hash(gx,
    gy, seed) < 0.3, at (gx + 0.2 + 0.6 hash(.., seed+1), gy + 0.2 + 0.6
    hash(.., seed+2)) cells, radius (0.05 + 0.05 hash(.., seed+4)) cells,
    twinkling at 0.55 + 0.45 sin(ang * (1 + floor(hash(.., seed+3) * 3)) +
    2 pi * 3.3 h); mixed towards c2 (white for two colours) by that times
    (1 - d / 2 radius) within twice its radius."""
    C = 1 / 36
    star = c[2] if len(c) > 2 else WHITE

    def px(X, Y, x, y, u, v):
        col = grad([c[0], c[1 % len(c)]], v)
        gx, gy = math.floor(X / C), math.floor(Y / C)
        h = hash01(gx, gy, seed)
        if h < 0.3:
            sx = (gx + 0.2 + 0.6 * hash01(gx, gy, seed + 1)) * C
            sy = (gy + 0.2 + 0.6 * hash01(gx, gy, seed + 2)) * C
            r = C * (0.05 + 0.05 * hash01(gx, gy, seed + 4))
            b = 0.55 + 0.45 * math.sin(ang * (1 + math.floor(hash01(gx, gy, seed + 3) * 3)) + TAU * 3.3 * h)
            d = math.hypot(X - sx, Y - sy)
            if d < 2 * r:
                col = mix(col, star, b * (1 - d / (2 * r)))
        return col
    return px


def kind_paper(c, rng, A, p, ang, seed):
    """c0 with fibres, (fbm(24X + 64, 24Y + 64, seed) - 0.5) * 0.08 +
    (noise(160X + 64, 160Y + 64, seed + 7) - 0.5) * 0.04 on each channel,
    and a light in c1 going round once a loop: centre (A/2 + 0.35 A cos ang,
    0.45 + 0.2 sin ang), mixed in by 0.4 (1 - d / 0.8)^2 within 0.8."""
    lx, ly = A / 2 + 0.35 * A * math.cos(ang), 0.45 + 0.2 * math.sin(ang)

    def px(X, Y, x, y, u, v):
        k = (fbm(24 * X + 64, 24 * Y + 64, seed) - 0.5) * 0.08 + (noise(160 * X + 64, 160 * Y + 64, seed + 7) - 0.5) * 0.04
        col = lighten(c[0], k)
        d = math.hypot(X - lx, Y - ly) / 0.8
        if d < 1:
            col = mix(col, c[1 % len(c)], 0.4 * (1 - d) ** 2)
        return col
    return px


def kind_marble(c, rng, A, p, ang, seed):
    """c0 veined in c1 by (1 - |sin(2 pi (1.5X + 2.5Y) + 8 q)|)^10 * 0.85, q =
    fbm(2.5X + 64 + 0.3 cos ang, 2.5Y + 64 + 0.3 sin ang, seed); then in c2
    by (1 - |sin(2 pi (3X - 1.2Y) + 6 q2)|)^16 * 0.5, q2 = fbm(5X + 128, 5Y +
    128, seed + 3)."""
    ox, oy = 0.3 * math.cos(ang), 0.3 * math.sin(ang)

    def px(X, Y, x, y, u, v):
        q = fbm(2.5 * X + 64 + ox, 2.5 * Y + 64 + oy, seed)
        w = math.sin(TAU * (1.5 * X + 2.5 * Y) + 8 * q)
        col = mix(c[0], c[1 % len(c)], (1 - abs(w)) ** 10 * 0.85)
        q2 = fbm(5 * X + 128, 5 * Y + 128, seed + 3)
        w2 = math.sin(TAU * (3 * X - 1.2 * Y) + 6 * q2)
        return mix(col, c[2 % len(c)], (1 - abs(w2)) ** 16 * 0.5)
    return px


def kind_linen(c, rng, A, p, ang, seed):
    """c0 woven: tx = 0.5 + 0.5 sin(2 pi 110 X), ty = 0.5 + 0.5 sin(2 pi 110
    Y), each channel moved by (tx * noise(4X + 64, 220Y + 64, seed) + ty *
    noise(220X + 64, 4Y + 64, seed + 1) - 0.5) * 0.08; and a light in c1,
    centre (A/2 + 0.3 A cos ang, 0.5 + 0.2 sin ang), 0.25 (1 - d / 0.9)^2
    within 0.9."""
    lx, ly = A / 2 + 0.3 * A * math.cos(ang), 0.5 + 0.2 * math.sin(ang)

    def px(X, Y, x, y, u, v):
        tx = 0.5 + 0.5 * math.sin(TAU * 110 * X)
        ty = 0.5 + 0.5 * math.sin(TAU * 110 * Y)
        k = (tx * noise(4 * X + 64, 220 * Y + 64, seed) + ty * noise(220 * X + 64, 4 * Y + 64, seed + 1) - 0.5) * 0.08
        col = lighten(c[0], k)
        d = math.hypot(X - lx, Y - ly) / 0.9
        if d < 1:
            col = mix(col, c[1 % len(c)], 0.25 * (1 - d) ** 2)
        return col
    return px


def kind_terrazzo(c, rng, A, p, ang, seed):
    """c0, with a chip in each cell of a 1/9 grid and a fleck in each cell of
    a 1/23 grid where its h < 0.6 (seed + 10 on): centre (g + 0.3 + 0.4
    hash(.., s+1), ..+0.4 hash(.., s+2)) cells, half-width rx = (0.12 + 0.16
    hash(.., s+3)) cells for a chip, (0.08 + 0.1 hash(.., s+3)) for a fleck,
    half-height rx (0.5 + 0.5 hash(.., s+4)), turned 2 pi hash(.., s+5); a
    pixel inside the ellipse is c[1 + floor(h (count - 1))], the fleck over
    the chip."""
    n = len(c)

    def chip(X, Y, size, s, small):
        gx, gy = math.floor(X / size), math.floor(Y / size)
        h = hash01(gx, gy, s)
        if small and h >= 0.6:
            return None
        cx = (gx + 0.3 + 0.4 * hash01(gx, gy, s + 1)) * size
        cy = (gy + 0.3 + 0.4 * hash01(gx, gy, s + 2)) * size
        rx = size * ((0.08 + 0.1 * hash01(gx, gy, s + 3)) if small else (0.12 + 0.16 * hash01(gx, gy, s + 3)))
        ry = rx * (0.5 + 0.5 * hash01(gx, gy, s + 4))
        th = TAU * hash01(gx, gy, s + 5)
        dx, dy = X - cx, Y - cy
        lx = dx * math.cos(th) + dy * math.sin(th)
        ly = -dx * math.sin(th) + dy * math.cos(th)
        if (lx / rx) ** 2 + (ly / ry) ** 2 <= 1:
            return c[1 + int(math.floor(h * (n - 1)))] if n > 1 else c[0]
        return None

    def px(X, Y, x, y, u, v):
        col = c[0]
        big = chip(X, Y, 1 / 9, seed, False)
        if big is not None:
            col = big
        small = chip(X, Y, 1 / 23, seed + 10, True)
        if small is not None:
            col = small
        return col
    return px


def kind_sky(c, rng, A, p, ang, seed):
    """Every colour top to bottom, and clouds: cl = fbm(2X + 64 + 0.5 cos ang,
    4Y + 64 + 0.5 sin ang, seed), white mixed in by min(1, max(0, (cl - 0.55)
    / 0.2)) * 0.45 * (1 - v)."""
    ox, oy = 0.5 * math.cos(ang), 0.5 * math.sin(ang)

    def px(X, Y, x, y, u, v):
        col = grad(c, v)
        cl = fbm(2 * X + 64 + ox, 4 * Y + 64 + oy, seed)
        return mix(col, WHITE, clamp01((cl - 0.55) / 0.2) * 0.45 * (1 - v))
    return px


def kind_halftone(c, rng, A, p, ang, seed):
    """c0, and c1 dots on a grid turned 45 degrees, 1/40 apart: rx = (X + Y) /
    sqrt 2, ry = (Y - X) / sqrt 2 + 64; a dot's radius 0.475 cell * tone,
    tone = 0.5 (u + v) + 0.15 sin(ang + 2 pi u), kept in 0..1."""
    S = 1 / 40
    root2 = math.sqrt(2)

    def px(X, Y, x, y, u, v):
        rx, ry = (X + Y) / root2, (Y - X) / root2 + 64
        gx, gy = math.floor(rx / S), math.floor(ry / S)
        tone = clamp01(0.5 * (u + v) + 0.15 * math.sin(ang + TAU * u))
        if math.hypot(rx - (gx + 0.5) * S, ry - (gy + 0.5) * S) < S * 0.475 * tone:
            return c[1 % len(c)]
        return c[0]
    return px


KINDS = {
    'mesh': kind_mesh, 'waves': kind_waves, 'bokeh': kind_bokeh, 'confetti': kind_confetti,
    'rays': kind_rays, 'grain': kind_grain, 'dots': kind_dots, 'stars': kind_stars, 'paper': kind_paper,
    'marble': kind_marble, 'linen': kind_linen, 'terrazzo': kind_terrazzo, 'sky': kind_sky,
    'halftone': kind_halftone,
}


def frame(entry, t, w, h):
    """The entry's frame at t seconds, w x h, as rows of (r, g, b) bytes."""
    period = entry['period']
    p = 0.0
    if period > 0:
        p = (t / period) - math.floor(t / period)
    ang = TAU * p
    A = w / h
    c = [rgb(x) for x in entry['colours']]
    px = KINDS[entry['kind']](c, Lcg(entry['seed']), A, p, ang, entry['seed'])
    out = []
    for y in range(h):
        row = []
        v = (y + 0.5) / h
        for x in range(w):
            u = (x + 0.5) / w
            col = px(u * A, v, x, y, u, v)
            row.append(tuple(min(255, max(0, int(math.floor(ch * 255 + 0.5)))) for ch in col))
        out.append(row)
    return out


def fnv(rows):
    h = 0x811c9dc5
    for row in rows:
        for px in row:
            for b in px:
                h = ((h ^ b) * 0x01000193) & M32
    return '%08x' % h


def main():
    if len(sys.argv) not in (1, 2, 3):
        sys.exit(__doc__)
    loops, stills = entries()
    text = ('{\n"loops":[\n' + ',\n'.join(json.dumps(e, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for e in loops)
            + '\n],\n"stills":[\n' + ',\n'.join(json.dumps(e, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for e in stills)
            + '\n]\n}\n')
    hashes = {}
    for e in loops:
        hashes[e['id']] = [fnv(frame(e, 0, HASH_W, HASH_H)), fnv(frame(e, e['period'] / 2, HASH_W, HASH_H))]
    for e in stills:
        hashes[e['id']] = [fnv(frame(e, 0, HASH_W, HASH_H))]
    fixture = json.dumps({'width': HASH_W, 'height': HASH_H, 'frames': hashes}, sort_keys=True, indent=1) + '\n'
    RESOURCE.parent.mkdir(parents=True, exist_ok=True)
    RESOURCE.write_text(text, encoding='utf-8')
    FIXTURE.parent.mkdir(parents=True, exist_ok=True)
    FIXTURE.write_text(fixture, encoding='utf-8')
    print('%d loops and %d stills, %d bytes' % (len(loops), len(stills), len(text.encode('utf-8'))))
    if len(sys.argv) >= 2:
        (pathlib.Path(sys.argv[1]) / 'Motion.json').write_text(text, encoding='utf-8')
    if len(sys.argv) == 3:
        (pathlib.Path(sys.argv[2]) / 'motion-frames.json').write_text(fixture, encoding='utf-8')


if __name__ == '__main__':
    main()
