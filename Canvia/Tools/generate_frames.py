#!/usr/bin/env python3
"""Regenerate both phones' photo grids and decorative photo frames.

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
                the double both phones' literals give.
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
                Grids made of slanted or round cells carry "clip": one entry
                a cell, null for a plain rectangle or the polygon the cell's
                photo shows through, [[x, y], ...] in the cell's own unit
                box (0…1 across and down its rectangle). Their cells may
                overlap, each the bounding box of its polygon on the lattice.
  "photoMasks"  mask frames a photo is clipped to, each {"id", "name",
                "category": "brush|torn|blob|arch|badge|ticket", "path",
                "fillRule"}: "path" SVG path data in the unit square (0…1,
                absolute M, L, C and Z, to the ten-thousandth), made from
                seeded noise and simple geometry, nothing downloaded; a hole
                is wound against its outline, so "nonzero" and "evenodd"
                draw it alike. A photo takes one as its maskShapeId,
                "mask:<id>".
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
"""
import json
import math
import pathlib
import random
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
    ('mosaicFiveBig', '5 mosaic', 3, 3, [(0, 0, 2, 2), (2, 0, 1, 1), (2, 1, 1, 1), (0, 2, 1, 1), (1, 2, 2, 1)]),
    ('mosaicSix', '6 mosaic', 4, 3, [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 1, 1), (3, 1, 1, 2), (0, 2, 1, 1), (1, 2, 2, 1)]),
    ('mosaicSeven', '7 mosaic', 4, 4, [(0, 0, 2, 2), (2, 0, 2, 1), (2, 1, 1, 1), (3, 1, 1, 1), (0, 2, 1, 2), (1, 2, 3, 1),
                                       (1, 3, 3, 1)]),
    ('mosaicNine', '9 mosaic', 4, 4, [(0, 0, 2, 2), (2, 0, 1, 1), (3, 0, 1, 1), (2, 1, 2, 1), (0, 2, 1, 1), (1, 2, 1, 1),
                                      (2, 2, 2, 2), (0, 3, 1, 1), (1, 3, 1, 1)]),
    ('brick', 'Offset brick', 4, 2, [(0, 0, 2, 1), (2, 0, 2, 1), (0, 1, 1, 1), (1, 1, 2, 1), (3, 1, 1, 1)]),
    ('brickWall', 'Brick wall', 6, 3, [(0, 0, 2, 1), (2, 0, 2, 1), (4, 0, 2, 1), (0, 1, 1, 1), (1, 1, 2, 1), (3, 1, 2, 1),
                                       (5, 1, 1, 1), (0, 2, 3, 1), (3, 2, 3, 1)]),
]

# Grids of slanted or round cells: id, name, columns, rows, and each cell's
# polygon in the grid's unit square. A cell is the polygon's bounding box,
# which must sit on the lattice's lines; its "clip" is the polygon again in
# that box's own unit square.
CLIPPED_GRIDS = [
    ('diagonalTwo', '2 diagonal', 1, 1, [[(0, 0), (1, 0), (0, 1)], [(1, 0), (1, 1), (0, 1)]]),
    ('diagonalTwoBack', '2 diagonal, the other way', 1, 1, [[(0, 0), (1, 0), (1, 1)], [(0, 0), (1, 1), (0, 1)]]),
    ('slantedTwo', '2 slanted', 5, 1, [[(0, 0), (0.6, 0), (0.4, 1), (0, 1)], [(0.6, 0), (1, 0), (1, 1), (0.4, 1)]]),
    ('slantedThree', '3 slanted', 15, 1, [[(0, 0), (0.4, 0), (4 / 15, 1), (0, 1)],
                                          [(0.4, 0), (11 / 15, 0), (0.6, 1), (4 / 15, 1)],
                                          [(11 / 15, 0), (1, 0), (1, 1), (0.6, 1)]]),
    ('diagonalFour', '4 diagonal', 2, 2, [[(0, 0), (1, 0), (0.5, 0.5)], [(0, 0), (0.5, 0.5), (0, 1)],
                                          [(1, 0), (1, 1), (0.5, 0.5)], [(0.5, 0.5), (1, 1), (0, 1)]]),
]


def circle_points(n=48):
    """A circle through the middle of each side of the unit square, as a
    polygon of [n] corners from three o'clock, clockwise on the page."""
    return [(0.5 + 0.5 * math.cos(2 * math.pi * i / n), 0.5 + 0.5 * math.sin(2 * math.pi * i / n)) for i in range(n)]


# Three round cells in a row: rectangular cells, each clipped to a circle.
ROUND_GRIDS = [
    ('threeCircles', '3 circles', 3, 1, [(0, 0, 1, 1), (1, 0, 1, 1), (2, 0, 1, 1)]),
]


def r4(v):
    """To the ten-thousandth, -0 as 0."""
    v = round(v, 4)
    return 0.0 if v == 0 else v


def clipped_grid(gid, name, columns, rows, polygons):
    """A grid of polygon cells as the file has it: each cell the polygon's
    bounding box on the lattice, its clip the polygon in that box."""
    cells, clips = [], []
    for poly in polygons:
        xs = [x for x, _ in poly]
        ys = [y for _, y in poly]
        left, right, top, bottom = min(xs), max(xs), min(ys), max(ys)
        cell = (round(left * columns), round(top * rows), round((right - left) * columns), round((bottom - top) * rows))
        for v, want in ((left, cell[0] / columns), (top, cell[1] / rows), (right, (cell[0] + cell[2]) / columns), (bottom, (cell[1] + cell[3]) / rows)):
            if abs(v - want) > 1e-9:
                sys.exit(f'{gid}: a cell is off the lattice')
        cells.append(cell)
        clips.append([[r4((x - left) / (right - left)), r4((y - top) / (bottom - top))] for x, y in poly])
    return {'id': gid, 'name': name, 'columns': columns, 'rows': rows, 'cells': [list(c) for c in cells], 'clip': clips}


def check_grid(gid, columns, rows, cells):
    """Every lattice square covered exactly once, cells in reading order."""
    if not 2 <= len(cells) <= 9:
        sys.exit(f'{gid}: {len(cells)} cells')
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


def window(x, y, w, h, radius=0, mask=None, rotation=None):
    el = {'type': 'image', 'x': x, 'y': y, 'w': w, 'h': h, 'radius': radius}
    if mask:
        el['maskShapeId'] = mask
    if rotation is not None:
        el['rotation'] = rotation
    return el, None


def tilted_window(cx0, cy0, cw, ch, dx, dy, w, h, rotation):
    """A window [dx], [dy] into a card at [cx0], [cy0] of [cw] x [ch], both
    turned [rotation] degrees about the card's middle: the window's own box
    placed so its middle lands where the turned card carries it, and turned
    the same."""
    a = math.radians(rotation)
    mx, my = cx0 + cw / 2, cy0 + ch / 2
    wx, wy = cx0 + dx + w / 2 - mx, cy0 + dy + h / 2 - my
    tx = mx + wx * math.cos(a) - wy * math.sin(a)
    ty = my + wx * math.sin(a) + wy * math.cos(a)
    return window(round(tx - w / 2, 2), round(ty - h / 2, 2), w, h, rotation=rotation)


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

    # A polaroid laid down at a slant: card and window turned together
    # about the same middle.
    frame('tiltedPolaroid', 'Tilted polaroid', 760, 860, [
        shape(80, 70, 600, 720, rect(Path(), 0, 0, 100, 100), '#ffffff', '#e2e2e2', 2, rotation=-6),
        tilted_window(80, 70, 600, 720, 36, 36, 528, 528, -6),
    ])

    frame('tapedPhoto', 'Taped photo', 700, 760, [
        shape(40, 60, 620, 660, rect(Path(), 0, 0, 100, 100), '#fdfcf8', '#e4e0d6', 2),
        window(70, 90, 560, 600),
        shape(20, 30, 160, 50, rect(Path(), 0, 0, 100, 100), '#e8dcb0', opacity=0.85, rotation=-30),
        shape(520, 30, 160, 50, rect(Path(), 0, 0, 100, 100), '#e8dcb0', opacity=0.85, rotation=30),
    ])

    stamp_line = Path()
    for i in range(4):
        rect(stamp_line, 0, i * 30, 100, 4)
    frame('postcard', 'Postcard', 1000, 640, [
        shape(0, 0, 1000, 640, rect(Path(), 0, 0, 100, 100), '#fbf6ec', '#d8cfbd', 2),
        window(32, 32, 560, 576),
        shape(860, 40, 100, 120, rect(Path(), 0, 0, 100, 100), '#ffffff', '#c9bfa8', 2),
        shape(640, 300, 320, 160, stamp_line, '#c9bfa8'),
        caption(620, 520, 360, 72, 'Wish you were here', 'script', 34, 400, '#5a4a36'),
    ])

    perforated = Path()
    holes_per_side = 10
    perforated.move(0, 0)
    pitch = 100 / holes_per_side
    rad = pitch * 0.28
    for side in range(4):
        for i in range(holes_per_side):
            c = (i + 0.5) * pitch
            a, b = c - rad, c + rad
            if side == 0:
                perforated.line(a, 0).curve(a, rad * 1.33, b, rad * 1.33, b, 0)
            elif side == 1:
                perforated.line(100, a).curve(100 - rad * 1.33, a, 100 - rad * 1.33, b, 100, b)
            elif side == 2:
                perforated.line(100 - a, 100).curve(100 - a, 100 - rad * 1.33, 100 - b, 100 - rad * 1.33, 100 - b, 100)
            else:
                perforated.line(0, 100 - a).curve(rad * 1.33, 100 - a, rad * 1.33, 100 - b, 0, 100 - b)
        perforated.line(*[(100, 0), (100, 100), (0, 100), (0, 0)][side])
    perforated.close()
    frame('postageStamp', 'Postage stamp', 600, 720, [
        shape(0, 0, 600, 720, perforated, '#ffffff', '#d9d9d9', 2),
        window(50, 50, 500, 540),
        caption(50, 610, 500, 70, '25c', 'serif', 40, 700, '#7a2e2e'),
    ])

    frame('tablet', 'Tablet', 900, 680, [
        shape(0, 0, 900, 680, rounded(Path(), 0, 0, 100, 100, 5, 6.62), '#1d2026'),
        window(40, 40, 820, 600, 14),
        shape(872, 330, 12, 20, ellipse(Path(), 50, 50, 50, 50), '#3a3f48'),
    ])

    frame('watch', 'Watch', 520, 860, [
        shape(110, 0, 300, 220, rounded(Path(), 0, 0, 100, 100, 18, 24, bottom=False), '#2a2d33'),
        shape(110, 640, 300, 220, rounded(Path(), 0, 0, 100, 100, 18, 24, top=False), '#2a2d33'),
        shape(0, 160, 520, 540, rounded(Path(), 0, 0, 100, 100, 26, 25), '#121418'),
        shape(500, 330, 20, 120, rounded(Path(), 0, 0, 100, 100, 50, 10), '#5a5f68'),
        window(40, 200, 440, 460, 80),
    ])

    def side_holes(count, height):
        p = Path()
        pitch = 100 / count
        for i in range(count):
            rounded(p, 0, i * pitch + (pitch - height) / 2, 100, height, 25, height * 0.25)
        return p
    frame('verticalFilm', 'Vertical film', 440, 1000, [
        shape(0, 0, 440, 1000, rect(Path(), 0, 0, 100, 100), '#1b1b1d'),
        shape(14, 10, 26, 980, side_holes(20, 2.4), '#f4f1ea'),
        shape(400, 10, 26, 980, side_holes(20, 2.4), '#f4f1ea'),
        window(60, 48, 320, 904, 6),
    ])

    # A hand-drawn border: two wobbly rectangles of pencil, each a thin
    # ring made of a seeded polyline and its inset.
    def sketch_ring(seed, inset):
        rng = random.Random(seed)
        outer, inner = [], []
        steps = 16
        for side in range(4):
            for i in range(steps):
                t = i / steps * 100
                j = rng.uniform(-0.6, 0.6)
                pt = [(t, inset + j), (100 - inset - j, t), (100 - t, 100 - inset - j), (inset + j, 100 - t)][side]
                outer.append(pt)
        for x, y in outer:
            inner.append((50 + (x - 50) * 0.985, 50 + (y - 50) * 0.985))
        p = Path().move(*outer[0])
        for q in outer[1:]:
            p.line(*q)
        p.close()
        p.move(*inner[0])
        for q in inner[:0:-1]:
            p.line(*q)
        return p.close()
    frame('sketchBorder', 'Sketch border', 800, 800, [
        shape(0, 0, 800, 800, rect(Path(), 0, 0, 100, 100), '#ffffff'),
        shape(20, 20, 760, 760, sketch_ring(331, 1.5), '#3b3b3b'),
        window(60, 60, 680, 680),
    ])

    double = Path()
    rect(double, 0, 0, 100, 100)
    rect(double, 2.5, 2.5, 95, 95, clockwise=False)
    rect(double, 5, 5, 90, 90)
    rect(double, 6, 6, 88, 88, clockwise=False)
    frame('doubleBorder', 'Double border', 800, 1000, [
        shape(0, 0, 800, 1000, double, '#1f2430'),
        window(60, 70, 680, 860),
    ])

    mat = Path()
    scallop_count = 14
    mat.move(0, 0)
    for side in range(4):
        for i in range(scallop_count):
            a = i * 100 / scallop_count
            b = (i + 1) * 100 / scallop_count
            bump = 100 / scallop_count * 0.6
            if side == 0:
                mat.curve(a + (b - a) * 0.2, bump, b - (b - a) * 0.2, bump, b, 0)
            elif side == 1:
                mat.curve(100 - bump, a + (b - a) * 0.2, 100 - bump, b - (b - a) * 0.2, 100, b)
            elif side == 2:
                mat.curve(100 - a - (b - a) * 0.2, 100 - bump, 100 - b + (b - a) * 0.2, 100 - bump, 100 - b, 100)
            else:
                mat.curve(bump, 100 - a - (b - a) * 0.2, bump, 100 - b + (b - a) * 0.2, 0, 100 - b)
    mat.close()
    frame('scallopedMat', 'Scalloped mat', 800, 800, [
        shape(0, 0, 800, 800, mat, '#f6e3e1', '#e2c4c0', 2),
        window(90, 90, 620, 620, 12),
    ])

    frame('instantSquare', 'Instant square', 640, 760, [
        shape(0, 0, 640, 760, rounded(Path(), 0, 0, 100, 100, 2, 1.68), '#f7f4ee', '#dedad2', 2),
        window(40, 40, 560, 560),
        caption(40, 630, 560, 80, 'Hello', 'sans', 40, 600, '#2d2d2d'),
    ])

    frame('roundedCard', 'Rounded card', 760, 900, [
        shape(0, 0, 760, 900, rounded(Path(), 0, 0, 100, 100, 8, 6.76), '#ffffff', '#e0e3e8', 2),
        window(40, 40, 680, 680, 36),
        caption(40, 760, 680, 90, 'Our story', 'serif', 46, 700, '#1f2430'),
    ])
    return out


# MARK: mask frames

class Unit:
    """Absolute M, L, C and Z in the unit square, to the ten-thousandth."""

    def __init__(self):
        self.parts = []

    @staticmethod
    def n(v):
        s = '%.4f' % v
        s = s.rstrip('0').rstrip('.')
        return '0' if s in ('-0', '') else s

    def move(self, x, y):
        self.parts.append(f'M{self.n(x)} {self.n(y)}')
        return self

    def line(self, x, y):
        self.parts.append(f'L{self.n(x)} {self.n(y)}')
        return self

    def curve(self, x1, y1, x2, y2, x, y):
        self.parts.append(f'C{self.n(x1)} {self.n(y1)} {self.n(x2)} {self.n(y2)} {self.n(x)} {self.n(y)}')
        return self

    def close(self):
        self.parts.append('Z')
        return self

    def polygon(self, pts):
        self.move(*pts[0])
        for q in pts[1:]:
            self.line(*q)
        return self.close()

    def smooth(self, pts):
        """A closed Catmull-Rom curve through [pts], as cubics, each control
        point held inside the square so the curve stays in it."""
        n = len(pts)
        self.move(*pts[0])
        for i in range(n):
            p0, p1, p2, p3 = pts[i - 1], pts[i], pts[(i + 1) % n], pts[(i + 2) % n]
            self.curve(clamp(p1[0] + (p2[0] - p0[0]) / 6), clamp(p1[1] + (p2[1] - p0[1]) / 6),
                       clamp(p2[0] - (p3[0] - p1[0]) / 6), clamp(p2[1] - (p3[1] - p1[1]) / 6), p2[0], p2[1])
        return self.close()

    def ellipse(self, cx, cy, rx, ry, clockwise=True):
        s = 1 if clockwise else -1
        self.move(cx + rx, cy)
        self.curve(cx + rx, cy + s * ry * K, cx + rx * K, cy + s * ry, cx, cy + s * ry)
        self.curve(cx - rx * K, cy + s * ry, cx - rx, cy + s * ry * K, cx - rx, cy)
        self.curve(cx - rx, cy - s * ry * K, cx - rx * K, cy - s * ry, cx, cy - s * ry)
        self.curve(cx + rx * K, cy - s * ry, cx + rx, cy - s * ry * K, cx + rx, cy)
        return self.close()

    def text(self):
        return ''.join(self.parts)


def clamp(v):
    return min(1.0, max(0.0, v))


def turned(pts, degrees):
    """[pts] turned about the square's middle."""
    a = math.radians(degrees)
    c, s = math.cos(a), math.sin(a)
    return [(0.5 + (x - 0.5) * c - (y - 0.5) * s, 0.5 + (x - 0.5) * s + (y - 0.5) * c) for x, y in pts]


def fitted(pts, margin=0.0):
    """[pts] stretched to fill the square, less [margin] each side."""
    xs = [x for x, _ in pts]
    ys = [y for _, y in pts]
    left, right, top, bottom = min(xs), max(xs), min(ys), max(ys)
    return [(margin + (x - left) / (right - left) * (1 - 2 * margin), margin + (y - top) / (bottom - top) * (1 - 2 * margin)) for x, y in pts]


def brush(seed, thickness, wobble, angle, taper):
    """A brush stroke: a wavy centre line across the square, its two edges
    offset by a thickness that swells and thins, each edge roughened by
    seeded noise, the ends ragged as bristles leave them."""
    rng = random.Random(seed)
    steps = 48
    phase = rng.uniform(0, math.tau)
    top, bottom = [], []
    for i in range(steps + 1):
        x = i / steps
        y = 0.5 + wobble * math.sin(phase + x * math.pi * 1.6)
        swell = thickness * (0.75 + 0.25 * math.sin(phase * 1.7 + x * math.pi * 3))
        ends = min(1.0, (x / taper) if x < taper else ((1 - x) / taper) if x > 1 - taper else 1.0)
        half = swell / 2 * (0.35 + 0.65 * ends)
        top.append((x, y - half + rng.uniform(-0.012, 0.012)))
        bottom.append((x, y + half + rng.uniform(-0.012, 0.012)))
    # Bristle teeth at each end.
    tail = [(rng.uniform(-0.02, 0.03), 0.5 + k * 0.03) for k in (-1, 0, 1)]
    head = [(1 - rng.uniform(-0.02, 0.03), 0.5 + k * 0.03) for k in (1, 0, -1)]
    pts = top + head + bottom[::-1] + tail
    return Unit().polygon(fitted(turned(pts, angle), 0.01)).text()


def torn_edge(seed, sides, depth):
    """A rectangle torn along [sides] ("t", "r", "b", "l"): each torn side a
    run of seeded jags up to [depth] deep; the others straight."""
    rng = random.Random(seed)
    steps = 28
    pts = []

    def d(side):
        return rng.uniform(0.2, 1.0) * depth if side in sides else 0.0
    for i in range(steps):
        pts.append((i / steps, d('t')))
    for i in range(steps):
        pts.append((1 - d('r'), i / steps))
    for i in range(steps):
        pts.append((1 - i / steps, 1 - d('b')))
    for i in range(steps):
        pts.append((d('l'), 1 - i / steps))
    return Unit().polygon([(clamp(x), clamp(y)) for x, y in pts]).text()


def deckled(seed, bumps, depth):
    """A deckled card: every edge a row of small soft waves."""
    rng = random.Random(seed)
    pts = []
    for side in range(4):
        for i in range(bumps * 2):
            t = i / (bumps * 2)
            off = depth * (0.5 + 0.5 * math.sin(i * math.pi)) * rng.uniform(0.6, 1.0) if i % 2 else 0.0
            if side == 0:
                pts.append((t, off))
            elif side == 1:
                pts.append((1 - off, t))
            elif side == 2:
                pts.append((1 - t, 1 - off))
            else:
                pts.append((off, 1 - t))
    return Unit().polygon(pts).text()


def torn_circle(seed, jags, depth):
    """A disc with a torn edge: its radius jagged by seeded amounts."""
    rng = random.Random(seed)
    pts = []
    for i in range(jags):
        a = math.tau * i / jags
        r = 0.5 - rng.uniform(0, depth)
        pts.append((0.5 + r * math.cos(a), 0.5 + r * math.sin(a)))
    return Unit().polygon(pts).text()


def blob(seed, lumps):
    """A soft blob: a radius about the middle made of a few seeded waves,
    sampled round and joined by a smooth curve, filling the square."""
    rng = random.Random(seed)
    waves = [(k, rng.uniform(0.04, 0.12) / k ** 0.5, rng.uniform(0, math.tau)) for k in range(2, 2 + lumps)]
    pts = []
    n = 16
    for i in range(n):
        a = math.tau * i / n
        r = 0.42 + sum(amp * math.sin(k * a + ph) for k, amp, ph in waves)
        pts.append((0.5 + r * math.cos(a), 0.5 + r * math.sin(a)))
    return Unit().smooth(fitted(pts, 0.02)).text()


def arch(kind):
    u = Unit()
    if kind == 'round':
        # A half circle on a rectangle: the top is a half ellipse as wide as
        # the square and a third as high.
        u.move(0, 1).line(0, 0.5)
        u.curve(0, 0.5 - 0.5 * K, 0.5 - 0.5 * K, 0, 0.5, 0)
        u.curve(0.5 + 0.5 * K, 0, 1, 0.5 - 0.5 * K, 1, 0.5)
        return u.line(1, 1).close().text()
    if kind == 'pointed':
        u.move(0, 1).line(0, 0.45)
        u.curve(0, 0.2, 0.3, 0.05, 0.5, 0)
        u.curve(0.7, 0.05, 1, 0.2, 1, 0.45)
        return u.line(1, 1).close().text()
    if kind == 'window':
        r = 0.18
        u.move(r, 0).line(1 - r, 0).curve(1 - r + r * K, 0, 1, r - r * K, 1, r).line(1, 1).line(0, 1).line(0, r)
        return u.curve(0, r - r * K, r - r * K, 0, r, 0).close().text()
    # 'double': two arches side by side, joined at the foot.
    u.move(0, 1).line(0, 0.3)
    u.curve(0, 0.3 - 0.3 * K, 0.25 - 0.25 * K, 0, 0.25, 0)
    u.curve(0.25 + 0.25 * K, 0, 0.5, 0.3 - 0.3 * K, 0.5, 0.3)
    u.curve(0.5, 0.3 - 0.3 * K, 0.75 - 0.25 * K, 0, 0.75, 0)
    u.curve(0.75 + 0.25 * K, 0, 1, 0.3 - 0.3 * K, 1, 0.3)
    return u.line(1, 1).close().text()


def ticket(kind):
    u = Unit()
    if kind == 'notched':
        # Half-round bites from the middle of each short side.
        r = 0.12
        u.move(0, 0).line(1, 0).line(1, 0.5 - r)
        u.curve(1 - r * K, 0.5 - r, 1 - r, 0.5 - r * K, 1 - r, 0.5)
        u.curve(1 - r, 0.5 + r * K, 1 - r * K, 0.5 + r, 1, 0.5 + r)
        u.line(1, 1).line(0, 1).line(0, 0.5 + r)
        u.curve(r * K, 0.5 + r, r, 0.5 + r * K, r, 0.5)
        u.curve(r, 0.5 - r * K, r * K, 0.5 - r, 0, 0.5 - r)
        return u.close().text()
    if kind == 'corners':
        # Quarter-round bites from each corner.
        r = 0.14
        u.move(r, 0).line(1 - r, 0).curve(1 - r, r * K, 1 - r * K, r, 1, r)
        u.line(1, 1 - r).curve(1 - r * K, 1 - r, 1 - r, 1 - r * K, 1 - r, 1)
        u.line(r, 1).curve(r, 1 - r * K, r * K, 1 - r, 0, 1 - r)
        u.line(0, r).curve(r * K, r, r, r * K, r, 0)
        return u.close().text()
    # 'zigzag': a coupon's pinked ends.
    teeth = 8
    pts = [(0.06, 0), (0.94, 0)]
    for i in range(teeth * 2 + 1):
        pts.append((1 - (0.06 if i % 2 == 0 else 0), i / (teeth * 2)))
    pts += [(0.94, 1), (0.06, 1)]
    for i in range(teeth * 2 + 1):
        pts.append((0.06 if i % 2 == 0 else 0, 1 - i / (teeth * 2)))
    return u.polygon(pts).text()


def stamp_edge(holes):
    """A postage stamp: a square whose edges are bitten by [holes] half
    circles a side."""
    u = Unit()
    r = 0.5 / holes * 0.55
    step = 1 / holes
    u.move(0, 0)
    for side in range(4):
        for i in range(holes):
            c = (i + 0.5) * step
            a, b = c - r, c + r
            if side == 0:
                u.line(a, 0).curve(a, r * 1.33, b, r * 1.33, b, 0)
            elif side == 1:
                u.line(1, a).curve(1 - r * 1.33, a, 1 - r * 1.33, b, 1, b)
            elif side == 2:
                u.line(1 - a, 1).curve(1 - a, 1 - r * 1.33, 1 - b, 1 - r * 1.33, 1 - b, 1)
            else:
                u.line(0, 1 - a).curve(r * 1.33, 1 - a, r * 1.33, 1 - b, 0, 1 - b)
        u.line(*[(1, 0), (1, 1), (0, 1), (0, 0)][side])
    return u.close().text()


def seal(points, inner):
    """A rosette seal: a disc edged with [points] round bumps."""
    u = Unit()
    pts = []
    for i in range(points * 2):
        a = math.tau * i / (points * 2) - math.pi / 2
        r = 0.5 if i % 2 == 0 else 0.5 * inner
        pts.append((0.5 + r * math.cos(a), 0.5 + r * math.sin(a)))
    return u.smooth(pts).text()


def starburst(points, inner):
    u = Unit()
    pts = []
    for i in range(points * 2):
        a = math.tau * i / (points * 2) - math.pi / 2
        r = 0.5 if i % 2 == 0 else 0.5 * inner
        pts.append((0.5 + r * math.cos(a), 0.5 + r * math.sin(a)))
    return u.polygon(pts).text()


def shield():
    u = Unit()
    u.move(0, 0).line(1, 0).line(1, 0.45)
    u.curve(1, 0.75, 0.75, 0.9, 0.5, 1)
    u.curve(0.25, 0.9, 0, 0.75, 0, 0.45)
    return u.close().text()


def hexagon():
    return Unit().polygon([(0.5 + 0.5 * math.cos(math.radians(a)), 0.5 + 0.5 * math.sin(math.radians(a))) for a in range(-90, 270, 60)]).text()


def ring():
    """A ring: a disc with a round hole, the hole wound the other way."""
    u = Unit()
    u.ellipse(0.5, 0.5, 0.5, 0.5)
    u.ellipse(0.5, 0.5, 0.3, 0.3, clockwise=False)
    return u.text()


def masks():
    """The mask frames, in the order the Frames tab lists them."""
    m = []

    def mask(mid, name, category, path, rule='nonzero'):
        m.append({'id': mid, 'name': name, 'category': category, 'path': path, 'fillRule': rule})
    mask('brush-swash', 'Brush swash', 'brush', brush(301, 0.62, 0.05, 0, 0.12))
    mask('brush-wave', 'Brush wave', 'brush', brush(302, 0.5, 0.1, 0, 0.18))
    mask('brush-dry', 'Dry brush', 'brush', brush(303, 0.7, 0.03, 0, 0.08))
    mask('brush-diagonal', 'Diagonal brush', 'brush', brush(304, 0.45, 0.06, -35, 0.15))
    mask('brush-upright', 'Upright brush', 'brush', brush(305, 0.6, 0.05, 90, 0.12))
    mask('brush-bold', 'Bold brush', 'brush', brush(306, 0.85, 0.02, 0, 0.1))
    mask('torn-all', 'Torn paper', 'torn', torn_edge(311, 'trbl', 0.035))
    mask('torn-top', 'Torn top', 'torn', torn_edge(312, 't', 0.06))
    mask('torn-sides', 'Torn sides', 'torn', torn_edge(313, 'lr', 0.05))
    mask('deckled', 'Deckled edge', 'torn', deckled(314, 18, 0.02))
    mask('torn-circle', 'Torn circle', 'torn', torn_circle(315, 72, 0.035))
    mask('blob-pebble', 'Pebble', 'blob', blob(321, 2))
    mask('blob-cloud', 'Cloud blob', 'blob', blob(322, 4))
    mask('blob-splash', 'Splash', 'blob', blob(323, 6))
    mask('blob-bean', 'Bean', 'blob', blob(324, 1))
    mask('blob-puddle', 'Puddle', 'blob', blob(325, 3))
    mask('blob-wobble', 'Wobble', 'blob', blob(326, 5))
    mask('arch-round', 'Round arch', 'arch', arch('round'))
    mask('arch-pointed', 'Pointed arch', 'arch', arch('pointed'))
    mask('arch-window', 'Rounded window', 'arch', arch('window'))
    mask('arch-double', 'Double arch', 'arch', arch('double'))
    mask('ticket-notched', 'Ticket', 'ticket', ticket('notched'))
    mask('ticket-corners', 'Admit one', 'ticket', ticket('corners'))
    mask('ticket-coupon', 'Coupon', 'ticket', ticket('zigzag'))
    mask('badge-stamp', 'Postage stamp', 'badge', stamp_edge(9))
    mask('badge-seal', 'Seal', 'badge', seal(14, 0.86))
    mask('badge-starburst', 'Starburst', 'badge', starburst(16, 0.78))
    mask('badge-shield', 'Shield', 'badge', shield())
    mask('badge-hexagon', 'Hexagon', 'badge', hexagon())
    mask('badge-ring', 'Ring', 'badge', ring(), 'evenodd')
    return m


MASK_CATEGORIES = ('brush', 'torn', 'blob', 'arch', 'badge', 'ticket')


def check_mask(m):
    if m['category'] not in MASK_CATEGORIES or m['fillRule'] not in ('nonzero', 'evenodd'):
        sys.exit(f'{m["id"]}: bad category or rule')
    nums = [float(v) for v in __import__('re').findall(r'-?\d+(?:\.\d+)?', m['path'])]
    if not nums or min(nums) < -0.0001 or max(nums) > 1.0001:
        sys.exit(f'{m["id"]}: leaves the unit square')


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
    for gid, name, columns, rows, cells in GRIDS:
        check_grid(gid, columns, rows, cells)
        grids.append({'id': gid, 'name': name, 'columns': columns, 'rows': rows, 'cells': [list(c) for c in cells]})
    for gid, name, columns, rows, cells in ROUND_GRIDS:
        check_grid(gid, columns, rows, cells)
        circle = [[r4(x), r4(y)] for x, y in circle_points()]
        grids.append({'id': gid, 'name': name, 'columns': columns, 'rows': rows, 'cells': [list(c) for c in cells], 'clip': [circle for _ in cells]})
    for gid, name, columns, rows, polygons in CLIPPED_GRIDS:
        grids.append(clipped_grid(gid, name, columns, rows, polygons))
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
    made_masks = masks()
    for m in made_masks:
        check_mask(m)
    if len({m['id'] for m in made_masks}) != len(made_masks):
        sys.exit('mask ids repeat')
    lines += ['],', '"photoMasks":[']
    lines += [json.dumps(m, ensure_ascii=False, separators=(',', ':')) + (',' if i < len(made_masks) - 1 else '') for i, m in enumerate(made_masks)]
    glyphs = glyph_frames()
    lines += ['],', '"glyphFrames":[']
    lines += [json.dumps(g, ensure_ascii=False, separators=(',', ':')) + (',' if i < len(glyphs) - 1 else '') for i, g in enumerate(glyphs)]
    lines += [']', '}']
    text = '\n'.join(lines) + '\n'
    RESOURCE.write_text(text, encoding='utf-8')
    print(f'{len(grids)} grids, {len(made)} frames, {len(made_masks)} masks and {len(glyphs)} glyph frames written to {RESOURCE.relative_to(REPO)}')
    if len(sys.argv) == 2:
        ios = pathlib.Path(sys.argv[1])
        shutil.copyfile(RESOURCE, ios / 'PhotoFrames.json')
        print(f'and copied to {ios}')


if __name__ == '__main__':
    main()
