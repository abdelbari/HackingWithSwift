#!/usr/bin/env python3
"""Regenerate both phones' photo grids, decorative photo frames and masks.

    tools/generate_frames.py [path/to/ios/Resources]

Writes core/src/main/resources/com/canvia/core/content/PhotoFrames.json and,
given a folder, the same file there for the iOS twin to bundle, so the two
apps lay out every grid and draw every frame from the same bytes.

The file is one object:

  "photoGrids"  the grid layouts, each {"id", "name", "columns", "rows",
                "cells": [[column, row, columns spanned, rows spanned], ...]}
                on a columns x rows lattice, cells in reading order (top to
                bottom, then left to right). A cell's unit rectangle is its
                lattice numbers over the lattice's — so 0.6 is 3/5, exactly
                the double both phones' literals give. A grid whose cells
                are not rectangles — diagonal splits, circles — also has
                "clip": one entry a cell, a polygon [[x, y], ...] in the
                cell's own unit square (to the ten-thousandth, clockwise on
                a y-down page) the picture is cut to, or null for the whole
                cell; its cells may overlap or leave gaps, and none has a
                divider to drag. A clipped cell's photo frame is the grid's
                cell with maskShapeId "gridclip:<grid id>:<cell index>".
  "photoFrames" the decorative frames, each {"id", "name", "width",
                "height", "elements": [...]}: a group of ordinary elements in
                a width x height box, bottom to top — shapes drawn from
                `pathData` in their own 0…100 box (absolute M, L, C and Z
                only, to the hundredth, a hole wound against its outline so
                the nonzero rule both renderers use leaves it open), at most
                one caption text, and exactly one empty image: the window a
                photo goes in. Original artwork made of simple shapes here,
                nothing traced or copied. The window is drawn above
                anything whose box would hold its middle, so a tap on the
                photo there picks the photo: hit testing on both phones goes
                by an element's box, not its outline.
  "glyphFrames" the letter and number frames, A to Z then 0 to 9, each
                {"id": "glyph-A", "frameGlyph": "A", "name": "A", "width",
                "height", "path"}: the glyph's outline from Bebas Neue
                (app/src/main/assets/fonts/bebas-neue-400.ttf, OFL) traced
                into its own 0…100 box as absolute M, L, C and Z (each
                quadratic raised to a cubic), its "width" by "height" the
                glyph's own proportions with the taller side 100 — a
                ShapeLibrary-style path entry a photo is clipped to, as it is
                to any library shape, through an empty photo frame whose
                maskShapeId is the entry's id (GlyphFrames in :core).
  "photoMasks"  the mask frames, each {"id", "name", "category", "path",
                "fillRule"}: category one of brush, torn, blob, arch,
                badge and ticket; path an SVG d in the unit square (absolute
                M, L, C and Z, to the ten-thousandth), made from seeded
                procedural outlines — noisy offset polylines for the brush
                strokes, jittered edges for torn paper, wobbling radii for
                the blobs — nothing downloaded; fillRule "nonzero", or
                "evenodd" for one with a hole (the ring), whose hole is also
                wound against its outline so either rule cuts it. A photo is
                clipped to one through an empty photo frame whose
                maskShapeId is "mask:<id>", scaled from the unit square to
                the frame's box as a library shape's 0…100 box is.
"""
import json
import math
import pathlib
import random
import re
import shutil
import struct
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCE = REPO / 'core/src/main/resources/com/canvia/core/content/PhotoFrames.json'

# id, name, columns, rows, cells. The first six are the grids every earlier
# build has, ids unchanged; every layout is 2 to 9 cells.
GRIDS = [
    ('two', '2 across', 2, 1, [(0, 0, 1, 1), (1, 0, 1, 1)]),
    ('three', '3 across', 3, 1, [(0, 0, 1, 1), (1, 0, 1, 1), (2, 0, 1, 1)]),
    ('four', '2 by 2', 2, 2, [(0, 0, 1, 1), (1, 0, 1, 1), (0, 1, 1, 1), (1, 1, 1, 1)]),
    ('onePlusTwo', '1 + 2', 5, 2, [(0, 0, 3, 2), (3, 0, 2, 1), (3, 1, 2, 1)]),
    ('bigTop', '1 over 3', 3, 5, [(0, 0, 3, 3), (0, 3, 1, 2), (1, 3, 1, 2), (2, 3, 1, 2)]),
    ('nine', '3 by 3', 3, 3, [(c, r, 1, 1) for r in range(3) for c in range(3)]),
    ('twoStack', '2 stacked', 1, 2, [(0, 0, 1, 1), (0, 1, 1, 1)]),
    ('threeStack', '3 stacked', 1, 3, [(0, 0, 1, 1), (0, 1, 1, 1), (0, 2, 1, 1)]),
    ('twoByThree', '2 by 3', 2, 3, [(c, r, 1, 1) for r in range(3) for c in range(2)]),
    ('threeByTwo', '3 by 2', 3, 2, [(c, r, 1, 1) for r in range(2) for c in range(3)]),
    ('oneLeftTwoRight', '1 left, 2 right', 2, 2, [(0, 0, 1, 2), (1, 0, 1, 1), (1, 1, 1, 1)]),
    ('oneRightTwoLeft', '2 left, 1 right', 2, 2, [(0, 0, 1, 1), (1, 0, 1, 2), (0, 1, 1, 1)]),
    ('twoOverOne', '2 over 1', 2, 2, [(0, 0, 1, 1), (1, 0, 1, 1), (0, 1, 2, 1)]),
    ('bigLeftThree', '1 + 3', 3, 3, [(0, 0, 2, 3), (2, 0, 1, 1), (2, 1, 1, 1), (2, 2, 1, 1)]),
    ('mosaicFive', '2 over 3', 6, 2, [(0, 0, 3, 1), (3, 0, 3, 1), (0, 1, 2, 1), (2, 1, 2, 1), (4, 1, 2, 1)]),
    ('sixMixed', '1 + 5', 3, 3, [(0, 0, 2, 2), (2, 0, 1, 1), (2, 1, 1, 1), (0, 2, 1, 1), (1, 2, 1, 1), (2, 2, 1, 1)]),
    ('fourAcross', '4 across', 4, 1, [(c, 0, 1, 1) for c in range(4)]),
    ('fourStack', '4 stacked', 1, 4, [(0, r, 1, 1) for r in range(4)]),
    ('eightMixed', '1 + 7', 4, 3, [(0, 0, 2, 2), (2, 0, 1, 1), (3, 0, 1, 1), (2, 1, 1, 1), (3, 1, 1, 1),
                                   (0, 2, 1, 1), (1, 2, 1, 1), (2, 2, 2, 1)]),
]


def circle_clip(n=48):
    """A circle filling its cell, as an n-gon, clockwise from the top."""
    return [(0.5 + 0.5 * math.sin(2 * math.pi * i / n), 0.5 - 0.5 * math.cos(2 * math.pi * i / n)) for i in range(n)]


# Mosaics, a brick wall and cut cells: id, name, columns, rows, cells, and
# for cut ones a clip a cell. A diagonal cut leaves a 0.02 gap either side.
WHOLE = (0, 0, 1, 1)
GRIDS += [
    ('diagonalTwo', '2 diagonal', 1, 1, [WHOLE, WHOLE],
     [[(0, 0), (0.98, 0), (0, 0.98)], [(1, 0.02), (1, 1), (0.02, 1)]]),
    ('diagonalTwoOther', '2 diagonal, other way', 1, 1, [WHOLE, WHOLE],
     [[(0, 0), (1, 0), (1, 0.98), (0.02, 0)], [(0, 0.02), (0.98, 1), (0, 1)]]),
    ('diagonalThree', '3 diagonal', 1, 1, [WHOLE, WHOLE, WHOLE],
     [[(0, 0), (0.64, 0), (0, 0.64)], [(0.68, 0), (1, 0), (1, 0.32), (0.32, 1), (0, 1), (0, 0.68)],
      [(1, 0.36), (1, 1), (0.36, 1)]]),
    ('slantThree', '3 slanted', 1, 1, [WHOLE, WHOLE, WHOLE],
     [[(0, 0), (0.38, 0), (0.28, 1), (0, 1)], [(0.4, 0), (0.71, 0), (0.61, 1), (0.3, 1)],
      [(0.73, 0), (1, 0), (1, 1), (0.63, 1)]]),
    ('diagonalFour', '4 triangles', 1, 1, [WHOLE, WHOLE, WHOLE, WHOLE],
     [[(0.02, 0), (0.98, 0), (0.5, 0.48)], [(1, 0.02), (1, 0.98), (0.52, 0.5)],
      [(0.98, 1), (0.02, 1), (0.5, 0.52)], [(0, 0.98), (0, 0.02), (0.48, 0.5)]]),
    ('circlesThree', '3 circles', 3, 3, [(0, 1, 1, 1), (1, 1, 1, 1), (2, 1, 1, 1)],
     [circle_clip(), circle_clip(), circle_clip()]),
    ('mosaic5', 'Mosaic of 5', 4, 4, [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 2, 1), (0, 2, 3, 2), (3, 2, 1, 2)]),
    ('mosaic6', 'Mosaic of 6', 3, 4, [(0, 0, 2, 2), (2, 0, 1, 1), (2, 1, 1, 1), (0, 2, 1, 2), (1, 2, 1, 2),
                                      (2, 2, 1, 2)]),
    ('mosaic7', 'Mosaic of 7', 4, 3, [(0, 0, 1, 1), (1, 0, 2, 2), (3, 0, 1, 1), (0, 1, 1, 2), (3, 1, 1, 1),
                                      (1, 2, 2, 1), (3, 2, 1, 1)]),
    ('mosaic9', 'Mosaic of 9', 4, 4, [(0, 0, 2, 2), (2, 0, 1, 1), (3, 0, 1, 1), (2, 1, 1, 1), (3, 1, 1, 1),
                                      (0, 2, 1, 1), (1, 2, 1, 1), (2, 2, 2, 2), (0, 3, 2, 1)]),
    ('brick', 'Offset brick', 4, 2, [(0, 0, 2, 1), (2, 0, 2, 1), (0, 1, 1, 1), (1, 1, 2, 1), (3, 1, 1, 1)]),
    ('brickSix', 'Offset brick of 6', 4, 3, [(0, 0, 2, 1), (2, 0, 2, 1), (0, 1, 1, 1), (1, 1, 2, 1),
                                            (3, 1, 1, 1), (0, 2, 4, 1)]),
]


def check_grid(gid, columns, rows, cells, clip=None):
    """Every lattice square covered exactly once, cells in reading order —
    or, for a grid with clips, every cell on the lattice and every clip a
    polygon of three points or more inside its cell."""
    if not 2 <= len(cells) <= 9:
        sys.exit(f'{gid}: {len(cells)} cells')
    if clip is not None:
        if len(clip) != len(cells):
            sys.exit(f'{gid}: a clip a cell')
        for i, (c, r, cw, rh) in enumerate(cells):
            if not (0 <= c and c + cw <= columns and 0 <= r and r + rh <= rows):
                sys.exit(f'{gid}: cell {i} leaves the lattice')
            if clip[i] is not None and (len(clip[i]) < 3 or not all(0 <= x <= 1 and 0 <= y <= 1 for x, y in clip[i])):
                sys.exit(f'{gid}: clip {i} is not a polygon in its cell')
        return
    seen = {}
    for i, (c, r, cw, rh) in enumerate(cells):
        for x in range(c, c + cw):
            for y in range(r, r + rh):
                if not (0 <= x < columns and 0 <= y < rows) or (x, y) in seen:
                    sys.exit(f'{gid}: cell {i} overlaps or leaves the lattice')
                seen[(x, y)] = i
    if len(seen) != columns * rows:
        sys.exit(f'{gid}: the cells leave a gap')
    if [(r, c) for c, r, _, _ in cells] != sorted((r, c) for c, r, _, _ in cells):
        sys.exit(f'{gid}: cells not in reading order')


# MARK: path data

def num(v):
    s = '%.2f' % v
    s = s.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


class Path:
    """Absolute M, L, C and Z in the 0…100 box, and the signed area of each
    closed loop (positive is clockwise on a y-down page) for the winding
    checks."""

    def __init__(self):
        self.parts = []
        self.loops = []
        self.points = []

    def move(self, x, y):
        self.parts.append(f'M{num(x)} {num(y)}')
        self.points = [(x, y)]
        return self

    def line(self, x, y):
        self.parts.append(f'L{num(x)} {num(y)}')
        self.points.append((x, y))
        return self

    def curve(self, x1, y1, x2, y2, x, y):
        self.parts.append(f'C{num(x1)} {num(y1)} {num(x2)} {num(y2)} {num(x)} {num(y)}')
        # The control points stand in for the curve in the area check.
        self.points += [(x1, y1), (x2, y2), (x, y)]
        return self

    def close(self):
        self.parts.append('Z')
        pts = self.points
        area = sum(pts[i][0] * pts[(i + 1) % len(pts)][1] - pts[(i + 1) % len(pts)][0] * pts[i][1] for i in range(len(pts))) / 2
        self.loops.append(area)
        return self

    def text(self):
        return ''.join(self.parts)


K = 0.5522847498  # a quarter circle's control distance, over its radius


def rect(p, x, y, w, h, clockwise=True):
    pts = [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]
    if not clockwise:
        pts = [pts[0]] + pts[:0:-1]
    p.move(*pts[0])
    for q in pts[1:]:
        p.line(*q)
    return p.close()


def rounded(p, x, y, w, h, rx, ry=None, clockwise=True, top=True, bottom=True):
    """A rectangle with quarter-ellipse corners rx by ry (in box units, which
    differ across and down when the box is not square)."""
    ry = rx if ry is None else ry
    tx, ty = (rx, ry) if top else (0, 0)
    bx, by = (rx, ry) if bottom else (0, 0)
    if clockwise:
        p.move(x + tx, y)
        p.line(x + w - tx, y)
        if top:
            p.curve(x + w - tx + tx * K, y, x + w, y + ty - ty * K, x + w, y + ty)
        p.line(x + w, y + h - by)
        if bottom:
            p.curve(x + w, y + h - by + by * K, x + w - bx + bx * K, y + h, x + w - bx, y + h)
        p.line(x + bx, y + h)
        if bottom:
            p.curve(x + bx - bx * K, y + h, x, y + h - by + by * K, x, y + h - by)
        p.line(x, y + ty)
        if top:
            p.curve(x, y + ty - ty * K, x + tx - tx * K, y, x + tx, y)
    else:
        p.move(x + tx, y)
        if top:
            p.curve(x + tx - tx * K, y, x, y + ty - ty * K, x, y + ty)
        p.line(x, y + h - by)
        if bottom:
            p.curve(x, y + h - by + by * K, x + bx - bx * K, y + h, x + bx, y + h)
        p.line(x + w - bx, y + h)
        if bottom:
            p.curve(x + w - bx + bx * K, y + h, x + w, y + h - by + by * K, x + w, y + h - by)
        p.line(x + w, y + ty)
        if top:
            p.curve(x + w, y + ty - ty * K, x + w - tx + tx * K, y, x + w - tx, y)
    return p.close()


def ellipse(p, cx, cy, rx, ry, clockwise=True):
    s = 1 if clockwise else -1
    p.move(cx + rx, cy)
    p.curve(cx + rx, cy + s * ry * K, cx + rx * K, cy + s * ry, cx, cy + s * ry)
    p.curve(cx - rx * K, cy + s * ry, cx - rx, cy + s * ry * K, cx - rx, cy)
    p.curve(cx - rx, cy - s * ry * K, cx - rx * K, cy - s * ry, cx, cy - s * ry)
    p.curve(cx + rx * K, cy - s * ry, cx + rx, cy - s * ry * K, cx + rx, cy)
    return p.close()


def scallops(p, n, inner, outer):
    """A disc edged with n round bumps, as a stamp or a seal is: from radius
    inner between bumps to outer at their tops, centred in the box."""
    c = 50
    pts = []
    for i in range(n):
        a0 = 2 * math.pi * i / n
        a1 = 2 * math.pi * (i + 0.5) / n
        a2 = 2 * math.pi * (i + 1) / n
        pts.append((a0, a1, a2))
    p.move(c + inner * math.cos(0), c + inner * math.sin(0))
    for a0, a1, a2 in pts:
        lift = outer * 1.08
        p.curve(c + lift * math.cos(a0 + (a1 - a0) * 0.35), c + lift * math.sin(a0 + (a1 - a0) * 0.35),
                c + lift * math.cos(a2 - (a2 - a1) * 0.35), c + lift * math.sin(a2 - (a2 - a1) * 0.35),
                c + inner * math.cos(a2), c + inner * math.sin(a2))
    return p.close()


def torn(p, seed_offsets):
    """Paper with a torn edge all round: a run of small zigzags just inside
    the box, their depths from a fixed list so the file never changes."""
    pts = []
    k = 0

    def depth():
        nonlocal k
        d = seed_offsets[k % len(seed_offsets)]
        k += 1
        return d
    steps = 25
    for i in range(steps):          # top, left to right
        pts.append((i * 100 / steps, depth()))
    for i in range(steps):          # right, top to bottom
        pts.append((100 - depth(), i * 100 / steps))
    for i in range(steps):          # bottom, right to left
        pts.append((100 - i * 100 / steps, 100 - depth()))
    for i in range(steps):          # left, bottom to top
        pts.append((depth(), 100 - i * 100 / steps))
    p.move(*pts[0])
    for q in pts[1:]:
        p.line(*q)
    return p.close()


# MARK: masks

def unum(v):
    """A unit-square coordinate to the ten-thousandth."""
    s = '%.4f' % v
    s = s.rstrip('0').rstrip('.')
    return '0' if s in ('-0', '') else s


class UnitPath:
    """Absolute M, L, C and Z in the unit square, to the ten-thousandth."""

    def __init__(self):
        self.parts = []

    def move(self, x, y):
        self.parts.append(f'M{unum(x)} {unum(y)}')
        return self

    def line(self, x, y):
        self.parts.append(f'L{unum(x)} {unum(y)}')
        return self

    def curve(self, x1, y1, x2, y2, x, y):
        self.parts.append(f'C{unum(x1)} {unum(y1)} {unum(x2)} {unum(y2)} {unum(x)} {unum(y)}')
        return self

    def close(self):
        self.parts.append('Z')
        return self

    def polygon(self, pts):
        self.move(*pts[0])
        for q in pts[1:]:
            self.line(*q)
        return self.close()

    def smooth(self, pts, tension=1.0):
        """A closed curve through `pts` (each inside the square): Catmull-Rom,
        as cubics."""
        n = len(pts)
        self.move(*pts[0])
        for i in range(n):
            p0, p1, p2, p3 = pts[(i - 1) % n], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
            # Held to the square, so the curve stays inside it.
            c1 = (held(p1[0] + (p2[0] - p0[0]) / 6 * tension), held(p1[1] + (p2[1] - p0[1]) / 6 * tension))
            c2 = (held(p2[0] - (p3[0] - p1[0]) / 6 * tension), held(p2[1] - (p3[1] - p1[1]) / 6 * tension))
            self.curve(c1[0], c1[1], c2[0], c2[1], p2[0], p2[1])
        return self.close()

    def circle(self, cx, cy, r, clockwise=True):
        s = 1 if clockwise else -1
        self.move(cx + r, cy)
        self.curve(cx + r, cy + s * r * K, cx + r * K, cy + s * r, cx, cy + s * r)
        self.curve(cx - r * K, cy + s * r, cx - r, cy + s * r * K, cx - r, cy)
        self.curve(cx - r, cy - s * r * K, cx - r * K, cy - s * r, cx, cy - s * r)
        self.curve(cx + r * K, cy - s * r, cx + r, cy - s * r * K, cx + r, cy)
        return self.close()

    def text(self):
        return ''.join(self.parts)


def held(v):
    return min(max(v, 0.0), 1.0)


def brush(seed, slant, wave, thickness):
    """A brush stroke: a centre line across the square that waves and
    slants, offset either side by a width that tapers at both ends, every
    point jittered — a noisy offset polyline — then smoothed, the ends
    ragged with a few bristle spikes."""
    rng = random.Random(seed)
    n = 18
    top, bottom = [], []
    for i in range(n + 1):
        t = i / n
        x = 0.04 + 0.92 * t
        y = 0.5 + slant * (t - 0.5) + wave * math.sin(t * math.pi * 2 + seed)
        taper = math.sin(math.pi * (0.06 + 0.88 * t)) ** 0.45
        half = thickness / 2 * taper * (1 + rng.uniform(-0.12, 0.12))
        top.append((held(x + rng.uniform(-0.006, 0.006)), held(y - half + rng.uniform(-0.009, 0.009))))
        bottom.append((held(x + rng.uniform(-0.006, 0.006)), held(y + half + rng.uniform(-0.009, 0.009))))
    # Bristles at either end: a point pulled out between top and bottom.
    tail = [(held(top[-1][0] + 0.03), held((top[-1][1] * 2 + bottom[-1][1]) / 3)),
            (held(top[-1][0] - 0.01), held((top[-1][1] + bottom[-1][1]) / 2)),
            (held(bottom[-1][0] + 0.025), held((top[-1][1] + bottom[-1][1] * 2) / 3))]
    head = [(held(bottom[0][0] - 0.03), held((top[0][1] + bottom[0][1] * 2) / 3)),
            (held(bottom[0][0] + 0.01), held((top[0][1] + bottom[0][1]) / 2)),
            (held(top[0][0] - 0.025), held((top[0][1] * 2 + bottom[0][1]) / 3))]
    return UnitPath().smooth(top + tail + bottom[::-1] + head, tension=0.9)


def ragged(seed, depth, steps, sides='tlbr'):
    """A sheet with ragged edges on `sides` (top, left, bottom, right):
    each edge a run of points pulled in by up to `depth`, seeded."""
    rng = random.Random(seed)

    def d(side):
        return rng.uniform(0.15, 1.0) * depth if side in sides else 0.0
    pts = []
    for i in range(steps):
        pts.append((i / steps, d('t')))
    for i in range(steps):
        pts.append((1 - d('r'), i / steps))
    for i in range(steps):
        pts.append((1 - i / steps, 1 - d('b')))
    for i in range(steps):
        pts.append((d('l'), 1 - i / steps))
    return UnitPath().polygon(pts)


def deckled(seed):
    """Deckled paper: small soft waves all round, smoothed."""
    rng = random.Random(seed)
    steps = 22
    pts = []
    for i in range(steps):
        pts.append((i / steps, 0.02 + rng.uniform(0, 0.025)))
    for i in range(steps):
        pts.append((0.98 - rng.uniform(0, 0.025), i / steps))
    for i in range(steps):
        pts.append((1 - i / steps, 0.98 - rng.uniform(0, 0.025)))
    for i in range(steps):
        pts.append((0.02 + rng.uniform(0, 0.025), 1 - i / steps))
    return UnitPath().smooth(pts, tension=0.6)


def blob(seed, points=9):
    """A blob: a radius that wobbles round the centre with three seeded
    harmonics, smoothed through `points` points."""
    rng = random.Random(seed)
    waves = [(k, rng.uniform(0.03, 0.07), rng.uniform(0, 2 * math.pi)) for k in (2, 3, 4)]
    pts = []
    for i in range(points):
        a = 2 * math.pi * i / points - math.pi / 2
        r = 0.36 + sum(amp * math.sin(k * a + ph) for k, amp, ph in waves)
        pts.append((held(0.5 + r * math.cos(a)), held(0.5 + r * math.sin(a))))
    return UnitPath().smooth(pts)


def arch(top_ratio):
    """An arch: a flat foot and straight sides under a half ellipse
    `top_ratio` of the height tall."""
    h = top_ratio
    p = UnitPath().move(0, 1).line(0, h)
    p.curve(0, h - h * K, 0.5 - 0.5 * K, 0, 0.5, 0)
    p.curve(0.5 + 0.5 * K, 0, 1, h - h * K, 1, h)
    return p.line(1, 1).close()


def pointed_arch():
    p = UnitPath().move(0, 1).line(0, 0.45)
    p.curve(0, 0.2, 0.3, 0.06, 0.5, 0)
    p.curve(0.7, 0.06, 1, 0.2, 1, 0.45)
    return p.line(1, 1).close()


def double_arch():
    p = UnitPath()
    for left in (0.0, 0.52):
        w = 0.48
        p.move(left, 1).line(left, 0.3)
        p.curve(left, 0.3 - 0.3 * K, left + w / 2 - w / 2 * K, 0, left + w / 2, 0)
        p.curve(left + w / 2 + w / 2 * K, 0, left + w, 0.3 - 0.3 * K, left + w, 0.3)
        p.line(left + w, 1).close()
    return p


def rounded_arch():
    """An arch whose foot is rounded too: a window."""
    p = UnitPath().move(0, 0.85).line(0, 0.5)
    p.curve(0, 0.5 - 0.5 * K, 0.5 - 0.5 * K, 0, 0.5, 0)
    p.curve(0.5 + 0.5 * K, 0, 1, 0.5 - 0.5 * K, 1, 0.5)
    p.line(1, 0.85).curve(1, 0.85 + 0.15 * K, 0.85 + 0.15 * K, 1, 0.85, 1)
    p.line(0.15, 1).curve(0.15 - 0.15 * K, 1, 0, 0.85 + 0.15 * K, 0, 0.85)
    return p.close()


def ticket():
    """A ticket: corners rounded, a round notch halfway down each side."""
    r, n = 0.05, 0.08
    p = UnitPath().move(r, 0.1).line(1 - r, 0.1)
    p.curve(1 - r + r * K, 0.1, 1, 0.1 + r - r * K, 1, 0.1 + r)
    p.line(1, 0.5 - n).curve(1 - n * K, 0.5 - n, 1 - n, 0.5 - n * K, 1 - n, 0.5)
    p.curve(1 - n, 0.5 + n * K, 1 - n * K, 0.5 + n, 1, 0.5 + n)
    p.line(1, 0.9 - r).curve(1, 0.9 - r + r * K, 1 - r + r * K, 0.9, 1 - r, 0.9)
    p.line(r, 0.9).curve(r - r * K, 0.9, 0, 0.9 - r + r * K, 0, 0.9 - r)
    p.line(0, 0.5 + n).curve(n * K, 0.5 + n, n, 0.5 + n * K, n, 0.5)
    p.curve(n, 0.5 - n * K, n * K, 0.5 - n, 0, 0.5 - n)
    p.line(0, 0.1 + r).curve(0, 0.1 + r - r * K, r - r * K, 0.1, r, 0.1)
    return p.close()


def stamp_edge(bites=14):
    """A postage stamp's edge: half-round bites all round a square."""
    p = UnitPath()
    pitch = 1 / bites
    r = pitch * 0.32
    pts = []

    def side(start, step, inward, count):
        for i in range(count):
            mid = (start[0] + step[0] * (i + 0.5), start[1] + step[1] * (i + 0.5))
            a = (mid[0] - step[0] * r / pitch, mid[1] - step[1] * r / pitch)
            b = (mid[0] + step[0] * r / pitch, mid[1] + step[1] * r / pitch)
            dip = (mid[0] + inward[0] * r, mid[1] + inward[1] * r)
            pts.append(('L', a))
            pts.append(('Q', dip, b))
    side((0, 0), (pitch, 0), (0, 1), bites)
    side((1, 0), (0, pitch), (-1, 0), bites)
    side((1, 1), (-pitch, 0), (0, -1), bites)
    side((0, 1), (0, -pitch), (1, 0), bites)
    p.move(0, 0)
    corner = [(1, 0), (1, 1), (0, 1)]
    k = 0
    for i, part in enumerate(pts):
        if part[0] == 'L':
            p.line(*part[1])
        else:
            _, c, b = part
            cur = pts[i - 1][1]
            # The quadratic dip raised to a cubic.
            c1 = (cur[0] + 2 / 3 * (c[0] - cur[0]), cur[1] + 2 / 3 * (c[1] - cur[1]))
            c2 = (b[0] + 2 / 3 * (c[0] - b[0]), b[1] + 2 / 3 * (c[1] - b[1]))
            p.curve(c1[0], c1[1], c2[0], c2[1], b[0], b[1])
            if (i + 1) % (2 * bites) == 0 and k < 3:
                p.line(*corner[k])
                k += 1
    return p.close()


def stub():
    """A ticket stub: each corner bitten round."""
    r = 0.12
    p = UnitPath().move(r, 0).line(1 - r, 0)
    p.curve(1 - r, r * K, 1 - r * K, r, 1, r)
    p.line(1, 1 - r).curve(1 - r * K, 1 - r, 1 - r, 1 - r * K, 1 - r, 1)
    p.line(r, 1).curve(r, 1 - r * K, r * K, 1 - r, 0, 1 - r)
    p.line(0, r).curve(r * K, r, r, r * K, r, 0)
    return p.close()


def radial(n, radius):
    """A closed polygon of `n` points round the centre, each at radius(i)."""
    pts = []
    for i in range(n):
        a = 2 * math.pi * i / n - math.pi / 2
        r = radius(i, a)
        pts.append((0.5 + r * math.cos(a), 0.5 + r * math.sin(a)))
    return pts


def masks():
    out = []

    def mask(mid, name, category, path, rule='nonzero'):
        out.append({'id': mid, 'name': name, 'category': category, 'path': path.text(), 'fillRule': rule})

    for i, (slant, wave, thick) in enumerate([(0.0, 0.03, 0.4), (-0.2, 0.02, 0.34), (0.16, 0.05, 0.32),
                                              (0.0, 0.07, 0.28), (-0.1, 0.0, 0.5), (0.25, 0.04, 0.36)]):
        mask(f'brush{i + 1}', f'Brush stroke {i + 1}', 'brush', brush(300 + i, slant, wave, thick))
    mask('tornEdges', 'Torn edges', 'torn', ragged(401, 0.045, 18))
    mask('deckled', 'Deckled edges', 'torn', deckled(402))
    mask('tornTop', 'Torn top and bottom', 'torn', ragged(403, 0.07, 20, 'tb'))
    mask('tornSide', 'Torn side', 'torn', ragged(404, 0.08, 22, 'r'))
    for i in range(6):
        mask(f'blob{i + 1}', f'Blob {i + 1}', 'blob', blob(500 + i, 8 + i % 3))
    mask('arch', 'Arch', 'arch', arch(0.5))
    mask('pointedArch', 'Pointed arch', 'arch', pointed_arch())
    mask('doubleArch', 'Double arch', 'arch', double_arch())
    mask('archWindow', 'Arched window', 'arch', rounded_arch())
    mask('ticket', 'Ticket', 'ticket', ticket())
    mask('stampEdge', 'Stamp edge', 'ticket', stamp_edge())
    mask('ticketStub', 'Ticket stub', 'ticket', stub())
    mask('ring', 'Ring', 'badge', UnitPath().circle(0.5, 0.5, 0.5).circle(0.5, 0.5, 0.32, clockwise=False), 'evenodd')
    mask('seal', 'Seal', 'badge', UnitPath().smooth(radial(48, lambda i, a: 0.5 if i % 2 == 0 else 0.45)))
    mask('starburst', 'Starburst', 'badge', UnitPath().polygon(radial(40, lambda i, a: 0.5 if i % 2 == 0 else 0.41)))
    mask('hexagon', 'Hexagon', 'badge', UnitPath().polygon([(0.5 + 0.5 * math.sin(math.pi / 3 * i), 0.5 - 0.5 * math.cos(math.pi / 3 * i))
                                                            for i in range(6)]))
    mask('octagon', 'Octagon', 'badge', UnitPath().polygon([(0.5 + 0.5 * math.sin(math.pi / 4 * i + math.pi / 8),
                                                             0.5 - 0.5 * math.cos(math.pi / 4 * i + math.pi / 8)) for i in range(8)]))
    shield = UnitPath().move(0.5, 0).line(1, 0.12).line(1, 0.45)
    shield.curve(1, 0.75, 0.75, 0.92, 0.5, 1).curve(0.25, 0.92, 0, 0.75, 0, 0.45).line(0, 0.12)
    mask('shield', 'Shield', 'badge', shield.close())
    mask('flower', 'Flower', 'badge', UnitPath().smooth(radial(32, lambda i, a: 0.4 + 0.1 * math.cos(8 * (a + math.pi / 2)))))
    return out


def check_masks(made):
    categories = {'brush', 'torn', 'blob', 'arch', 'badge', 'ticket'}
    if len({m['id'] for m in made}) != len(made):
        sys.exit('mask ids repeat')
    for m in made:
        if m['category'] not in categories or m['fillRule'] not in ('nonzero', 'evenodd'):
            sys.exit(f'{m["id"]}: category or fill rule')
        numbers = [float(v) for v in re.findall(r'-?\d+(?:\.\d+)?', m['path'])]
        if not numbers or min(numbers) < 0 or max(numbers) > 1:
            sys.exit(f'{m["id"]}: leaves the unit square')


# MARK: elements

def shape(x, y, w, h, path, fill, stroke=None, stroke_width=None, opacity=None, rotation=None):
    el = {'type': 'shape', 'x': x, 'y': y, 'w': w, 'h': h, 'pathData': path.text(), 'fill': fill}
    if stroke:
        el['stroke'] = stroke
        el['strokeWidth'] = stroke_width
    if opacity is not None:
        el['opacity'] = opacity
    if rotation is not None:
        el['rotation'] = rotation
    return el, path


def window(x, y, w, h, radius=0, mask=None):
    el = {'type': 'image', 'x': x, 'y': y, 'w': w, 'h': h, 'radius': radius}
    if mask:
        el['maskShapeId'] = mask
    return el, None


def caption(x, y, w, h, text, family, size, weight, colour):
    return {'type': 'text', 'x': x, 'y': y, 'w': w, 'h': h, 'text': text, 'fontFamily': family,
            'fontSize': size, 'fontWeight': weight, 'color': colour, 'align': 'center'}, None


def frames():
    out = []

    def frame(fid, name, width, height, parts):
        out.append((fid, name, width, height, parts))

    frame('polaroid', 'Polaroid', 600, 720, [
        shape(0, 0, 600, 720, rect(Path(), 0, 0, 100, 100), '#ffffff', '#e2e2e2', 2),
        window(36, 36, 528, 528),
        caption(36, 600, 528, 72, 'Good times', 'script', 44, 400, '#3d3d3d'),
    ])

    def holes(count, width):
        # Sprocket holes across a strip, each a rounded slot.
        p = Path()
        pitch = 100 / count
        for i in range(count):
            rounded(p, i * pitch + (pitch - width) / 2, 0, width, 100, width * 0.25, 25)
        return p
    frame('filmStrip', 'Film strip', 1000, 420, [
        shape(0, 0, 1000, 420, rect(Path(), 0, 0, 100, 100), '#1b1b1d'),
        shape(10, 14, 980, 26, holes(20, 2.4), '#f4f1ea'),
        shape(10, 380, 980, 26, holes(20, 2.4), '#f4f1ea'),
        window(48, 60, 904, 300, 6),
    ])

    frame('phone', 'Phone', 440, 880, [
        shape(0, 0, 440, 880, rounded(Path(), 0, 0, 100, 100, 15, 7.5), '#14171c'),
        window(22, 22, 396, 836, 46),
        shape(165, 40, 110, 30, rounded(Path(), 0, 0, 100, 100, 13.64, 50), '#14171c'),
    ])

    frame('laptop', 'Laptop', 1000, 640, [
        shape(90, 0, 820, 556, rounded(Path(), 0, 0, 100, 100, 3, 4.42, bottom=False), '#22262c'),
        window(116, 26, 768, 480),
        shape(0, 556, 1000, 60, Path().move(0, 0).line(100, 0).line(100, 40)
              .curve(100, 80, 98, 100, 94, 100).line(6, 100).curve(2, 100, 0, 80, 0, 40).close(), '#c8cbd0'),
        shape(430, 556, 140, 14, rounded(Path(), 0, 0, 100, 100, 10, 50, top=False), '#a6aab1'),
    ])

    dots = []
    for i, colour in enumerate(['#ff5f57', '#febc2e', '#28c840']):
        dots.append(shape(26 + i * 32, 22, 20, 20, ellipse(Path(), 50, 50, 50, 50), colour))
    frame('browserWindow', 'Browser window', 1000, 700, [
        shape(0, 0, 1000, 700, rounded(Path(), 0, 0, 100, 100, 1.6, 2.29), '#ffffff', '#d3d7dd', 2),
        shape(0, 0, 1000, 64, rounded(Path(), 0, 0, 100, 100, 1.6, 25, bottom=False), '#eceff3'),
        *dots,
        shape(150, 16, 700, 32, rounded(Path(), 0, 0, 100, 100, 2.29, 50), '#ffffff'),
        window(0, 64, 1000, 636),
    ])

    tears = [1.2, 2.6, 0.6, 3.1, 1.8, 0.9, 2.9, 1.4, 2.2, 0.4, 3.3, 1.1, 2.4, 0.8, 1.9, 2.8, 0.5, 1.6, 3.0, 1.3]
    frame('tornPaper', 'Torn paper', 700, 800, [
        shape(0, 0, 700, 800, torn(Path(), tears), '#fbf7ef'),
        window(56, 64, 588, 672),
        shape(260, 14, 180, 54, rect(Path(), 0, 0, 100, 100), '#e9dcb4', opacity=0.85, rotation=-4),
    ])

    # The ring under the window, whose box it would cover: its hole is 520
    # across, and the round window 524 laps its inner edge so no seam shows.
    ring = Path()
    ellipse(ring, 50, 50, 50, 50)
    ellipse(ring, 50, 50, 46.43, 46.43, clockwise=False)
    frame('circleStamp', 'Circle stamp', 700, 700, [
        shape(0, 0, 700, 700, scallops(Path(), 36, 46, 49), '#ffffff', '#ddd5c4', 2),
        shape(70, 70, 560, 560, ring, '#b23b3b'),
        window(88, 88, 524, 524, mask='circle'),
    ])

    # The mat, under the window, and over it only the two corners above the
    # arch: a half circle 240 across the window's top. Below them, the
    # photo is the topmost thing under a finger.
    corners = Path()
    corners.move(0, 0).line(50, 0)
    corners.curve(50 - 50 * K, 0, 0, 100 - 100 * K, 0, 100)
    corners.close()
    corners.move(50, 0).line(100, 0).line(100, 100)
    corners.curve(100, 100 - 100 * K, 50 + 50 * K, 0, 50, 0)
    corners.close()
    frame('arch', 'Arch', 600, 800, [
        shape(0, 0, 600, 800, rect(Path(), 0, 0, 100, 100), '#efe4d4'),
        window(60, 60, 480, 680),
        shape(60, 60, 480, 240, corners, '#efe4d4'),
    ])
    more_frames(frame)
    return out


def turned(cx, cy, x, y, w, h, degrees):
    """The box (x, y, w, h) moved as its centre turns `degrees` round
    (cx, cy): where a part of a turned frame goes, itself turned as much."""
    a = math.radians(degrees)
    mx, my = x + w / 2 - cx, y + h / 2 - cy
    nx = cx + mx * math.cos(a) - my * math.sin(a)
    ny = cy + mx * math.sin(a) + my * math.cos(a)
    return round(nx - w / 2, 2), round(ny - h / 2, 2)


def ring(p, outer, inner):
    """A rectangle with a rectangular hole: `outer` and `inner` as (x, y,
    w, h) in the 0…100 box, the hole wound against the outline."""
    rect(p, *outer)
    return rect(p, *inner, clockwise=False)


def sketchy(seed, inset, jitter):
    """A hand-drawn rectangle outline, two strokes wide: each side a few
    jittered points, the inner edge wound against the outer."""
    rng = random.Random(seed)
    p = Path()

    def loop(off, clockwise):
        pts = []
        for i in range(6):
            pts.append((off + (100 - 2 * off) * i / 6, off + rng.uniform(-jitter, jitter)))
        for i in range(6):
            pts.append((100 - off + rng.uniform(-jitter, jitter), off + (100 - 2 * off) * i / 6))
        for i in range(6):
            pts.append((100 - off - (100 - 2 * off) * i / 6, 100 - off + rng.uniform(-jitter, jitter)))
        for i in range(6):
            pts.append((off + rng.uniform(-jitter, jitter), 100 - off - (100 - 2 * off) * i / 6))
        pts = [(min(max(x, 0), 100), min(max(y, 0), 100)) for x, y in pts]
        if not clockwise:
            pts = [pts[0]] + pts[:0:-1]
        p.move(*pts[0])
        for q in pts[1:]:
            p.line(*q)
        p.close()
    loop(jitter, True)
    loop(inset, False)
    return p


def scalloped_rect(p, bumps_x, bumps_y, depth):
    """A rectangle edged with round bumps, `depth` deep, in the 0…100 box."""
    def edge(x0, y0, x1, y1, count, ox, oy):
        for i in range(count):
            ax, ay = x0 + (x1 - x0) * i / count, y0 + (y1 - y0) * i / count
            bx, by = x0 + (x1 - x0) * (i + 1) / count, y0 + (y1 - y0) * (i + 1) / count
            p.curve(ax + ox * depth * 1.3, ay + oy * depth * 1.3, bx + ox * depth * 1.3, by + oy * depth * 1.3, bx, by)
    d = depth
    p.move(d, d)
    edge(d, d, 100 - d, d, bumps_x, 0, -1)
    edge(100 - d, d, 100 - d, 100 - d, bumps_y, 1, 0)
    edge(100 - d, 100 - d, d, 100 - d, bumps_x, 0, 1)
    edge(d, 100 - d, d, d, bumps_y, -1, 0)
    return p.close()


def more_frames(frame):
    """Round 33's frames: turned and taped prints, a postcard and a stamp,
    devices, film and drawn, double, scalloped and gallery borders."""
    # A polaroid turned 6 degrees, in a box with room for its corners.
    w, h, box = 560, 672, 760
    left, top = (box - w) / 2, (box - h) / 2
    cx, cy = box / 2, box / 2
    wx, wy = turned(cx, cy, left + 34, top + 34, 492, 492, -6)
    tx, ty = turned(cx, cy, left + 34, top + 560, 492, 70, -6)
    photo = window(wx, wy, 492, 492)
    photo[0]['rotation'] = -6
    words = caption(tx, ty, 492, 70, 'Memories', 'script', 40, 400, '#3d3d3d')
    words[0]['rotation'] = -6
    frame('tiltedPolaroid', 'Tilted polaroid', box, box, [
        shape(left, top, w, h, rect(Path(), 0, 0, 100, 100), '#ffffff', '#e2e2e2', 2, rotation=-6),
        photo,
        words,
    ])

    tape = rect(Path(), 0, 0, 100, 100)
    frame('tapedPhoto', 'Taped photo', 700, 560, [
        shape(20, 30, 660, 510, rect(Path(), 0, 0, 100, 100), '#fdfdfb', '#e5e1d8', 2),
        window(44, 54, 612, 462),
        shape(10, 14, 150, 44, tape, '#e9dcb4', opacity=0.85, rotation=-28),
        shape(540, 14, 150, 44, rect(Path(), 0, 0, 100, 100), '#e9dcb4', opacity=0.85, rotation=28),
    ])

    lines = Path()
    for i in range(4):
        rect(lines, 0, i * 30, 100, 4)
    stamp = Path()
    scallops(stamp, 28, 44, 49)
    frame('postcard', 'Postcard', 900, 600, [
        shape(0, 0, 900, 600, rect(Path(), 0, 0, 100, 100), '#fbf6ea', '#e4dcc8', 2),
        shape(462, 40, 4, 520, rect(Path(), 0, 0, 100, 100), '#d9cfb8'),
        shape(700, 44, 150, 150, stamp, '#d65a4a'),
        shape(510, 300, 340, 160, lines, '#cbbf9f'),
        caption(510, 220, 340, 60, 'Wish you were here', 'script', 34, 400, '#5b4a36'),
        window(36, 36, 400, 528, 6),
    ])

    frame('stamp', 'Stamp', 600, 720, [
        shape(0, 0, 600, 720, scalloped_rect(Path(), 12, 14, 3.5), '#ffffff', '#ddd5c4', 2),
        window(48, 48, 504, 560),
        caption(48, 620, 504, 60, '50c', 'serif', 40, 700, '#7a2e2e'),
    ])

    frame('tablet', 'Tablet', 760, 1000, [
        shape(0, 0, 760, 1000, rounded(Path(), 0, 0, 100, 100, 7.9, 6), '#1f2228'),
        window(40, 56, 680, 888, 14),
        shape(372, 22, 16, 16, ellipse(Path(), 50, 50, 50, 50), '#3a3f47'),
    ])

    strap = rounded(Path(), 0, 0, 100, 100, 18, 8)
    frame('watch', 'Watch', 440, 760, [
        shape(110, 0, 220, 230, strap, '#2b2f36'),
        shape(110, 530, 220, 230, rounded(Path(), 0, 0, 100, 100, 18, 8), '#2b2f36'),
        shape(40, 170, 360, 420, rounded(Path(), 0, 0, 100, 100, 22, 19), '#5d636d'),
        shape(400, 330, 22, 70, rounded(Path(), 0, 0, 100, 100, 40, 14), '#5d636d'),
        window(64, 196, 312, 368, 56),
    ])

    def column(count, height):
        p = Path()
        pitch = 100 / count
        for i in range(count):
            rounded(p, 0, i * pitch + (pitch - height) / 2, 100, height, 25, height * 0.25)
        return p
    frame('filmVertical', 'Vertical film', 440, 1000, [
        shape(0, 0, 440, 1000, rect(Path(), 0, 0, 100, 100), '#1b1b1d'),
        shape(14, 10, 26, 980, column(22, 2.2), '#f4f1ea'),
        shape(400, 10, 26, 980, column(22, 2.2), '#f4f1ea'),
        window(60, 48, 320, 904, 4),
    ])

    frame('sketchBorder', 'Sketch border', 700, 700, [
        shape(0, 0, 700, 700, sketchy(601, 4, 1.2), '#2d2d2d'),
        window(34, 34, 632, 632),
    ])

    frame('doubleBorder', 'Double border', 700, 700, [
        shape(0, 0, 700, 700, ring(Path(), (0, 0, 100, 100), (1.6, 1.6, 96.8, 96.8)), '#1f2430'),
        shape(28, 28, 644, 644, ring(Path(), (0, 0, 100, 100), (0.9, 0.9, 98.2, 98.2)), '#1f2430'),
        window(52, 52, 596, 596),
    ])

    frame('scallopedMat', 'Scalloped mat', 700, 860, [
        shape(0, 0, 700, 860, scalloped_rect(Path(), 9, 11, 3), '#f6e7e1'),
        window(70, 70, 560, 720, 280),
    ])

    frame('instantSquare', 'Instant square', 620, 740, [
        shape(0, 0, 620, 740, rect(Path(), 0, 0, 100, 100), '#ffffff', '#e2e2e2', 2),
        window(40, 40, 540, 540),
        caption(40, 610, 540, 80, 'Hello', 'script', 48, 400, '#3d3d3d'),
    ])

    frame('galleryFrame', 'Gallery frame', 800, 1000, [
        shape(0, 0, 800, 1000, ring(Path(), (0, 0, 100, 100), (7.5, 6, 85, 88)), '#6b4a2f'),
        shape(60, 60, 680, 880, ring(Path(), (0, 0, 100, 100), (11.76, 9.09, 76.47, 81.82)), '#f7f4ee'),
        window(140, 140, 520, 720),
    ])


# MARK: letter and number frames

FONT = REPO / 'app/src/main/assets/fonts/bebas-neue-400.ttf'
GLYPHS = [chr(c) for c in range(ord('A'), ord('Z') + 1)] + [str(d) for d in range(10)]


def truetype(data):
    """The tables of a TrueType file, by tag: (offset, length)."""
    count = struct.unpack('>H', data[4:6])[0]
    return {struct.unpack('>4s', data[12 + 16 * i:16 + 16 * i])[0].decode('latin-1'): struct.unpack('>II', data[20 + 16 * i:28 + 16 * i])
            for i in range(count)}


def cmap_lookup(data, tables):
    """Unicode code point to glyph index, from the first format 4 subtable."""
    base, _ = tables['cmap']
    count = struct.unpack('>H', data[base + 2:base + 4])[0]
    for i in range(count):
        platform, encoding, offset = struct.unpack('>HHI', data[base + 4 + 8 * i:base + 12 + 8 * i])
        sub = base + offset
        if struct.unpack('>H', data[sub:sub + 2])[0] != 4:
            continue
        segs = struct.unpack('>H', data[sub + 6:sub + 8])[0] // 2
        ends = struct.unpack(f'>{segs}H', data[sub + 14:sub + 14 + 2 * segs])
        starts = struct.unpack(f'>{segs}H', data[sub + 16 + 2 * segs:sub + 16 + 4 * segs])
        deltas = struct.unpack(f'>{segs}h', data[sub + 16 + 4 * segs:sub + 16 + 6 * segs])
        range_base = sub + 16 + 6 * segs
        ranges = struct.unpack(f'>{segs}H', data[range_base:range_base + 2 * segs])

        def lookup(cp):
            for k in range(segs):
                if starts[k] <= cp <= ends[k]:
                    if ranges[k] == 0:
                        return (cp + deltas[k]) & 0xFFFF
                    at = range_base + 2 * k + ranges[k] + 2 * (cp - starts[k])
                    g = struct.unpack('>H', data[at:at + 2])[0]
                    return (g + deltas[k]) & 0xFFFF if g else 0
            return 0
        return lookup
    sys.exit('no format 4 cmap')


def glyph_contours(data, tables, index, loca_long):
    """A glyph's contours, each a list of (x, y, on_curve) in font units; a
    composite glyph's parts placed by their offsets (scales left as 1)."""
    loca, _ = tables['loca']
    glyf, _ = tables['glyf']
    if loca_long:
        start, end = struct.unpack('>II', data[loca + 4 * index:loca + 4 * index + 8])
    else:
        start, end = (v * 2 for v in struct.unpack('>HH', data[loca + 2 * index:loca + 2 * index + 4]))
    if end <= start:
        return []
    g = glyf + start
    n = struct.unpack('>h', data[g:g + 2])[0]
    if n < 0:
        contours = []
        at = g + 10
        while True:
            flags, part = struct.unpack('>HH', data[at:at + 4])
            at += 4
            if flags & 1:
                dx, dy = struct.unpack('>hh', data[at:at + 4])
                at += 4
            else:
                dx, dy = struct.unpack('>bb', data[at:at + 2])
                at += 2
            if flags & 8:
                at += 2
            elif flags & 0x40:
                at += 4
            elif flags & 0x80:
                at += 8
            for c in glyph_contours(data, tables, part, loca_long):
                contours.append([(x + dx, y + dy, on) for x, y, on in c])
            if not flags & 0x20:
                break
        return contours
    ends = struct.unpack(f'>{n}H', data[g + 10:g + 10 + 2 * n])
    at = g + 10 + 2 * n
    instructions = struct.unpack('>H', data[at:at + 2])[0]
    at += 2 + instructions
    points = ends[-1] + 1 if n else 0
    flags = []
    while len(flags) < points:
        f = data[at]
        at += 1
        flags.append(f)
        if f & 8:
            repeat = data[at]
            at += 1
            flags += [f] * repeat
    xs, ys = [], []
    v = 0
    for f in flags:
        if f & 2:
            d = data[at]
            at += 1
            v += d if f & 16 else -d
        elif not f & 16:
            v += struct.unpack('>h', data[at:at + 2])[0]
            at += 2
        xs.append(v)
    v = 0
    for f in flags:
        if f & 4:
            d = data[at]
            at += 1
            v += d if f & 32 else -d
        elif not f & 32:
            v += struct.unpack('>h', data[at:at + 2])[0]
            at += 2
        ys.append(v)
    contours, first = [], 0
    for last in ends:
        contours.append([(xs[i], ys[i], bool(flags[i] & 1)) for i in range(first, last + 1)])
        first = last + 1
    return contours


def contour_path(p, contour, place):
    """One TrueType contour as M, L and C on [p]: implied on-curve points
    between two off-curve ones, each quadratic raised to a cubic."""
    pts = list(contour)
    if not pts:
        return
    # Start on an on-curve point; make one between two off-curve ones.
    if not pts[0][2]:
        if pts[-1][2]:
            pts = [pts[-1]] + pts[:-1]
        else:
            mid = ((pts[0][0] + pts[-1][0]) / 2, (pts[0][1] + pts[-1][1]) / 2, True)
            pts = [mid] + pts
    start = place(pts[0][0], pts[0][1])
    p.move(*start)
    current = start
    prev_off = None
    for x, y, on in pts[1:] + [pts[0]]:
        q = place(x, y)
        if on:
            if prev_off is None:
                p.line(*q)
            else:
                c1 = (current[0] + 2 / 3 * (prev_off[0] - current[0]), current[1] + 2 / 3 * (prev_off[1] - current[1]))
                c2 = (q[0] + 2 / 3 * (prev_off[0] - q[0]), q[1] + 2 / 3 * (prev_off[1] - q[1]))
                p.curve(c1[0], c1[1], c2[0], c2[1], q[0], q[1])
                prev_off = None
            current = q
        else:
            if prev_off is not None:
                mid = ((prev_off[0] + q[0]) / 2, (prev_off[1] + q[1]) / 2)
                c1 = (current[0] + 2 / 3 * (prev_off[0] - current[0]), current[1] + 2 / 3 * (prev_off[1] - current[1]))
                c2 = (mid[0] + 2 / 3 * (prev_off[0] - mid[0]), mid[1] + 2 / 3 * (prev_off[1] - mid[1]))
                p.curve(c1[0], c1[1], c2[0], c2[1], mid[0], mid[1])
                current = mid
            prev_off = q
    p.close()


def glyph_frames():
    data = FONT.read_bytes()
    tables = truetype(data)
    head, _ = tables['head']
    loca_long = struct.unpack('>h', data[head + 50:head + 52])[0] == 1
    lookup = cmap_lookup(data, tables)
    out = []
    for glyph in GLYPHS:
        index = lookup(ord(glyph))
        if index == 0:
            sys.exit(f'{glyph}: not in the font')
        contours = glyph_contours(data, tables, index, loca_long)
        xs = [x for c in contours for x, _, _ in c]
        ys = [y for c in contours for _, y, _ in c]
        if not xs:
            sys.exit(f'{glyph}: no outline')
        left, right, bottom, top = min(xs), max(xs), min(ys), max(ys)
        bw, bh = right - left, top - bottom
        # Into its own 0…100 box, y down; the taller side is 100.
        side = max(bw, bh)
        width = round(bw / side * 100, 2)
        height = round(bh / side * 100, 2)

        def place(x, y):
            return ((x - left) / bw * 100, (top - y) / bh * 100)
        p = Path()
        for contour in contours:
            contour_path(p, contour, place)
        out.append({'id': f'glyph-{glyph}', 'frameGlyph': glyph, 'name': glyph, 'width': width, 'height': height, 'path': p.text()})
    return out


def check_frame(fid, width, height, parts):
    images = [el for el, _ in parts if el['type'] == 'image']
    if len(images) != 1:
        sys.exit(f'{fid}: {len(images)} windows')
    if sum(1 for el, _ in parts if el['type'] == 'text') > 1:
        sys.exit(f'{fid}: more than one caption')
    for el, path in parts:
        if el['x'] < 0 or el['y'] < 0 or el['x'] + el['w'] > width or el['y'] + el['h'] > height:
            sys.exit(f'{fid}: {el["type"]} leaves the box')
        # Holes wind against the outline they are cut from.
        if path is not None and len(path.loops) > 1 and fid == 'circleStamp':
            if (path.loops[0] > 0) == (path.loops[1] > 0):
                sys.exit(f'{fid}: hole wound the same way as its outline')


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    grids = []
    for gid, name, columns, rows, cells, *rest in GRIDS:
        clip = rest[0] if rest else None
        check_grid(gid, columns, rows, cells, clip)
        grid = {'id': gid, 'name': name, 'columns': columns, 'rows': rows, 'cells': [list(c) for c in cells]}
        if clip is not None:
            grid['clip'] = [None if poly is None else [[float(unum(x)), float(unum(y))] for x, y in poly] for poly in clip]
        grids.append(grid)
    if len({g['id'] for g in grids}) != len(grids):
        sys.exit('grid ids repeat')
    made = []
    for fid, name, width, height, parts in frames():
        check_frame(fid, width, height, parts)
        made.append({'id': fid, 'name': name, 'width': width, 'height': height, 'elements': [el for el, _ in parts]})
    # One grid or frame a line, so a change reads as one line of a diff.
    lines = ['{', '"photoGrids":[']
    lines += [json.dumps(g, ensure_ascii=False, separators=(',', ':')) + (',' if i < len(grids) - 1 else '') for i, g in enumerate(grids)]
    lines += ['],', '"photoFrames":[']
    lines += [json.dumps(f, ensure_ascii=False, separators=(',', ':')) + (',' if i < len(made) - 1 else '') for i, f in enumerate(made)]
    glyphs = glyph_frames()
    lines += ['],', '"glyphFrames":[']
    lines += [json.dumps(g, ensure_ascii=False, separators=(',', ':')) + (',' if i < len(glyphs) - 1 else '') for i, g in enumerate(glyphs)]
    shaped = masks()
    check_masks(shaped)
    lines += ['],', '"photoMasks":[']
    lines += [json.dumps(m, ensure_ascii=False, separators=(',', ':')) + (',' if i < len(shaped) - 1 else '') for i, m in enumerate(shaped)]
    lines += [']', '}']
    text = '\n'.join(lines) + '\n'
    RESOURCE.write_text(text, encoding='utf-8')
    print(f'{len(grids)} grids, {len(made)} frames, {len(glyphs)} glyph frames and {len(shaped)} masks written to '
          f'{RESOURCE.relative_to(REPO)}')
    if len(sys.argv) == 2:
        ios = pathlib.Path(sys.argv[1])
        shutil.copyfile(RESOURCE, ios / 'PhotoFrames.json')
        print(f'and copied to {ios}')


if __name__ == '__main__':
    main()
