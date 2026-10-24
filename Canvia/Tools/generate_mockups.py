#!/usr/bin/env python3
"""Regenerate both phones' mockup scenes.

    tools/generate_mockups.py [path/to/ios/Content]

Writes templates/mockups.json and the same bytes to
core/src/main/resources/com/canvia/core/content/Mockups.json, which the app
reads, and, given a folder, Mockups.json there for the iOS twin to bundle.
Every scene is drawn here in vectors — no photograph is downloaded — so the
same script writes the same file on any machine.

The file is a JSON array of scenes, each:

  id, name     what it is ("phone-tilt", "Phone, tilted").
  category     Devices, Print, Apparel or Home.
  size         [width, height] of the scene in its own pixels.
  background   the paint behind everything: a design's Paint,
               {"kind": "solid", "color"} or {"kind": "gradient", "angle",
               "stops": [{"color", "position"}]}.
  layers       drawn in order under the design: each {"path", "fill"} —
               path data in scene pixels, absolute M, L, C and Z, filled
               with the nonzero rule — and optionally "blur" (a soft shadow,
               its radius in scene pixels), "opacity" (0…1, else 1) and
               "tinted": true, filled with the scene's tint instead.
  screen       where the design goes: "quad", its four corners in scene
               pixels — top left, top right, bottom right, bottom left; the
               corner "radius" of its window, in scene pixels; and "aspect",
               the window's width over its height when seen flat. The page
               is cut to that aspect (MockupGeometry.cover) and its corners
               pinned to the quad's. A scene with "cylinder" {"angle",
               "sag"} wraps it round a cylinder instead (a mug): "angle" is
               the half-turn the print spans either side of its middle, in
               radians, and "sag" how far its top and bottom edges bow down
               at the middle, in scene pixels (MockupGeometry.mesh).
  overlay      drawn over the design, inside its window: {"fill", "opacity"}
               — the glass's glare, the paper's sheen.
  tint         optional: the colour "tinted" layers take until one is
               chosen (a T-shirt's, a mug's).
"""
import json
import math
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
TEMPLATES = REPO / 'templates/mockups.json'
RESOURCE = REPO / 'core/src/main/resources/com/canvia/core/content/Mockups.json'


def num(v):
    s = '%.1f' % v
    if s.endswith('.0'):
        s = s[:-2]
    return '0' if s in ('-0', '-0.0') else s


def pt(p):
    return num(p[0]) + ' ' + num(p[1])


def solid(c):
    return {'kind': 'solid', 'color': c}


def gradient(angle, *stops):
    return {'kind': 'gradient', 'angle': angle, 'stops': [{'color': c, 'position': p} for c, p in stops]}


def poly(points):
    return 'M' + pt(points[0]) + ''.join('L' + pt(p) for p in points[1:]) + 'Z'


def rounded_poly(points, r):
    """A closed outline through [points] with each corner rounded by [r]."""
    n = len(points)
    out = ''
    for i in range(n):
        prev, here, nxt = points[i - 1], points[i], points[(i + 1) % n]

        def toward(a, b, d):
            dx, dy = b[0] - a[0], b[1] - a[1]
            length = math.hypot(dx, dy) or 1.0
            d = min(d, length / 2)
            return (a[0] + dx * d / length, a[1] + dy * d / length)
        a = toward(here, prev, r)
        b = toward(here, nxt, r)
        out += ('M' if i == 0 else 'L') + pt(a)
        c1 = (a[0] + (here[0] - a[0]) * 0.55, a[1] + (here[1] - a[1]) * 0.55)
        c2 = (b[0] + (here[0] - b[0]) * 0.55, b[1] + (here[1] - b[1]) * 0.55)
        out += 'C' + pt(c1) + ' ' + pt(c2) + ' ' + pt(b)
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


def grow(quad, d):
    """[quad] pushed out from its middle by about [d] at each corner."""
    cx = sum(p[0] for p in quad) / 4
    cy = sum(p[1] for p in quad) / 4
    out = []
    for x, y in quad:
        dx, dy = x - cx, y - cy
        length = math.hypot(dx, dy) or 1.0
        out.append((x + dx / length * d, y + dy / length * d))
    return out


def shift(points, dx, dy):
    return [(x + dx, y + dy) for x, y in points]


def rect_quad(x, y, w, h):
    return [(x, y), (x + w, y), (x + w, y + h), (x, y + h)]


def tilt_quad(cx, cy, w, h, lean, skew):
    """A rectangle w x h seen turned: its right side shorter by [lean] of
    its height, and slid down by [skew]."""
    top = cy - h / 2
    bottom = cy + h / 2
    return [
        (cx - w / 2, top),
        (cx + w / 2, top + h * lean / 2 + skew),
        (cx + w / 2, bottom - h * lean / 2 + skew),
        (cx - w / 2, bottom),
    ]


def quad_json(q):
    return [[round(x, 1), round(y, 1)] for x, y in q]


GLARE = {'fill': gradient(135, ('#ffffff', 0.0), ('#ffffff00', 0.55)), 'opacity': 0.22}
SHEEN = {'fill': gradient(160, ('#ffffff', 0.0), ('#ffffff00', 0.7)), 'opacity': 0.12}
DESK = gradient(180, ('#f3efe9', 0.0), ('#ddd5ca', 1.0))
WALL = gradient(180, ('#eef0f2', 0.0), ('#d9dde2', 1.0))
STUDIO = gradient(180, ('#f7f7f8', 0.0), ('#e4e6ea', 1.0))


def scene(id, name, category, size, background, layers, quad, radius, aspect, overlay, tint=None, cylinder=None):
    s = {
        'id': id, 'name': name, 'category': category, 'size': list(size),
        'background': background, 'layers': layers,
        'screen': {'quad': quad_json(quad), 'radius': radius, 'aspect': aspect},
        'overlay': overlay,
    }
    if cylinder:
        s['screen']['cylinder'] = cylinder
    if tint:
        s['tint'] = tint
    return s


def shadow(path, blur, opacity=0.35, colour='#000000'):
    return {'path': path, 'fill': solid(colour), 'blur': blur, 'opacity': opacity}


def device(id, name, size, background, quad, bezel, body, radius, screen_radius, aspect, extra=()):
    outer = grow(quad, bezel)
    layers = [
        shadow(rounded_poly(shift(outer, 18, 30), radius), 40),
        {'path': rounded_poly(outer, radius), 'fill': body},
        {'path': rounded_poly(grow(quad, bezel * 0.35), screen_radius + bezel * 0.2), 'fill': solid('#0b0b0d')},
    ] + list(extra)
    return scene(id, name, 'Devices', size, background, layers, quad, screen_radius, aspect, GLARE)


def scenes():
    out = []
    # ---------------------------------------------------------- Devices
    q = rect_quad(800 - 225, 600 - 400, 450, 800)
    out.append(device('phone-front', 'Phone, front', (1600, 1200), STUDIO, q, 26, solid('#1c1c1f'), 80, 52, 0.5625))
    q = tilt_quad(800, 600, 440, 800, 0.12, 30)
    q = [(x + (y - 600) * -0.12, y) for x, y in q]
    out.append(device('phone-tilt', 'Phone, tilted', (1600, 1200), gradient(160, ('#e8ecf5', 0.0), ('#c9d3e6', 1.0)), q, 26, solid('#26262a'), 70, 48, 0.5625))
    q = rect_quad(800 - 230, 640 - 400, 460, 800)
    out.append(device('phone-silver', 'Phone, silver', (1600, 1200), DESK, q, 24, gradient(90, ('#d9dce1', 0.0), ('#b8bcc4', 1.0)), 78, 52, 0.5625))
    # A laptop: the lid's screen, and its base below.
    q = [(430, 210), (1170, 210), (1170, 680), (430, 680)]
    base = [(300, 720), (1300, 720), (1380, 800), (220, 800)]
    lid = grow(q, 28)
    out.append(scene('laptop', 'Laptop', 'Devices', (1600, 1000), STUDIO, [
        shadow(poly(shift(base, 0, 26)), 30, 0.3),
        {'path': rounded_poly(lid, 24), 'fill': solid('#2a2b2f')},
        {'path': rounded_poly(base, 10), 'fill': gradient(180, ('#d6d8dc', 0.0), ('#a9adb4', 1.0))},
        {'path': poly([(720, 720), (880, 720), (870, 736), (730, 736)]), 'fill': solid('#8e9299')},
    ], q, 6, 1.6, GLARE))
    q = rect_quad(800 - 300, 600 - 410, 600, 820)
    out.append(device('tablet-portrait', 'Tablet', (1600, 1200), DESK, q, 40, solid('#222226'), 60, 20, 0.75))
    q = rect_quad(800 - 440, 600 - 320, 880, 640)
    out.append(device('tablet-landscape', 'Tablet, landscape', (1600, 1200), STUDIO, q, 40, gradient(90, ('#e1e3e6', 0.0), ('#c3c6cc', 1.0)), 60, 20, 1.375))
    q = [(380, 170), (1220, 170), (1220, 640), (380, 640)]
    out.append(scene('monitor', 'Desktop monitor', 'Devices', (1600, 1100), WALL, [
        shadow(poly([(620, 900), (980, 900), (1000, 930), (600, 930)]), 20, 0.3),
        {'path': poly([(760, 660), (840, 660), (860, 880), (740, 880)]), 'fill': gradient(90, ('#b9bdc4', 0.0), ('#d8dbe0', 1.0))},
        {'path': rounded_poly([(620, 870), (980, 870), (980, 905), (620, 905)], 12), 'fill': solid('#c5c8ce')},
        {'path': rounded_poly(grow(q, 26), 18), 'fill': solid('#1d1e21')},
    ], q, 2, 1.7872, GLARE))
    # ------------------------------------------------------------ Print
    def framed(id, name, size, quad, frame_colour, mat, aspect, background):
        outer = grow(quad, 110)
        mat_q = grow(quad, 70)
        return scene(id, name, 'Print', size, background, [
            shadow(poly(shift(outer, 12, 22)), 30, 0.3),
            {'path': poly(outer), 'fill': frame_colour},
            {'path': poly(mat_q), 'fill': solid(mat)},
            {'path': poly(grow(quad, 4)), 'fill': solid('#d8d3ca'), 'opacity': 0.8},
        ], quad, 0, aspect, SHEEN)
    out.append(framed('frame-portrait', 'Framed print', (1200, 1600), rect_quad(600 - 300, 800 - 400, 600, 800), gradient(135, ('#3b2f25', 0.0), ('#5a4636', 1.0)), '#fbfaf7', 0.75, WALL))
    out.append(framed('frame-landscape', 'Framed print, landscape', (1600, 1200), rect_quad(800 - 400, 600 - 280, 800, 560), solid('#1f1f1f'), '#ffffff', 1.4286, gradient(180, ('#f4efe6', 0.0), ('#e2d9cb', 1.0))))
    q = tilt_quad(800, 560, 620, 860, 0.0, 0)
    out.append(scene('poster-wall', 'Poster on a wall', 'Print', (1600, 1200), gradient(180, ('#e9e4dc', 0.0), ('#d6cec2', 1.0)), [
        {'path': poly([(0, 1040), (1600, 1040), (1600, 1200), (0, 1200)]), 'fill': solid('#b89c7e')},
        shadow(poly(shift(q, 10, 16)), 22, 0.25),
        {'path': ellipse(800, 140, 9, 9), 'fill': solid('#9a9a9a')},
    ], q, 0, 0.7209, SHEEN))
    q = [(560, 420), (1140, 470), (1080, 800), (500, 750)]
    back = [(470, 470), (1050, 500), (1010, 830), (430, 800)]
    out.append(scene('business-card', 'Business card', 'Print', (1600, 1200), DESK, [
        shadow(poly(shift(back, 8, 14)), 16, 0.25),
        {'path': poly(back), 'fill': solid('#ffffff')},
        shadow(poly(shift(q, 8, 14)), 16, 0.3),
        {'path': poly(q), 'fill': solid('#ffffff')},
    ], q, 0, 1.75, SHEEN))
    q = [(460, 300), (1180, 340), (1140, 860), (420, 820)]
    out.append(scene('postcard', 'Postcard on a table', 'Print', (1600, 1200), gradient(200, ('#d9c7b0', 0.0), ('#bfa588', 1.0)), [
        shadow(poly(shift(q, 10, 18)), 20, 0.3),
    ], q, 0, 1.4, SHEEN))
    q = [(520, 180), (1100, 220), (1060, 1000), (480, 960)]
    pages = [shift(q, 26, 20), shift(q, 14, 10)]
    out.append(scene('flyer-stack', 'Stack of flyers', 'Print', (1600, 1200), DESK, [
        shadow(poly(shift(pages[0], 6, 14)), 18, 0.25),
        {'path': poly(pages[0]), 'fill': solid('#f4f4f2')},
        {'path': poly(pages[1]), 'fill': solid('#fafaf8')},
    ], q, 0, 0.7071, SHEEN))
    q = rect_quad(800 - 260, 600 - 380, 520, 760)
    spine = [(q[0][0] - 46, q[0][1] + 6), q[0], q[3], (q[3][0] - 46, q[3][1] - 6)]
    out.append(scene('book-cover', 'Book cover', 'Print', (1600, 1200), STUDIO, [
        shadow(poly(shift(q, 22, 26)), 30, 0.35),
        {'path': poly([(q[1][0], q[1][1] + 10), (q[1][0] + 14, q[1][1] + 18), (q[2][0] + 14, q[2][1] - 4), (q[2][0], q[2][1])]), 'fill': solid('#f1efe9')},
        {'path': poly(spine), 'fill': solid('#3d3d44')},
    ], q, 4, 0.6842, SHEEN))
    # ---------------------------------------------------------- Apparel
    shirt = [(560, 160), (700, 120), (760, 170), (840, 170), (900, 120), (1040, 160), (1240, 330), (1140, 450),
             (1060, 390), (1060, 1080), (540, 1080), (540, 390), (460, 450), (360, 330)]
    q = rect_quad(800 - 190, 330, 380, 470)
    out.append(scene('tshirt', 'T-shirt', 'Apparel', (1600, 1200), STUDIO, [
        shadow(rounded_poly(shift(shirt, 10, 18), 30), 30, 0.25),
        {'path': rounded_poly(shirt, 30), 'fill': solid('#ffffff'), 'tinted': True},
        {'path': ellipse(800, 172, 62, 26), 'fill': solid('#000000'), 'opacity': 0.12},
    ], q, 0, 0.8085, {'fill': gradient(90, ('#00000014', 0.0), ('#00000000', 0.5), ('#00000014', 1.0)), 'opacity': 1.0}, tint='#ffffff'))
    hoodie = [(540, 200), (680, 110), (920, 110), (1060, 200), (1260, 420), (1180, 520), (1080, 460), (1080, 1100),
              (520, 1100), (520, 460), (420, 520), (340, 420)]
    q = rect_quad(800 - 180, 380, 360, 300)
    out.append(scene('hoodie', 'Hoodie', 'Apparel', (1600, 1200), gradient(180, ('#eceef1', 0.0), ('#d5d9df', 1.0)), [
        shadow(rounded_poly(shift(hoodie, 10, 18), 40), 30, 0.25),
        {'path': rounded_poly(hoodie, 40), 'fill': solid('#2f3a4a'), 'tinted': True},
        {'path': ellipse(800, 190, 120, 70), 'fill': solid('#000000'), 'opacity': 0.18},
        {'path': rounded_poly([(640, 760), (960, 760), (980, 900), (620, 900)], 20), 'fill': solid('#000000'), 'opacity': 0.1},
    ], q, 0, 1.2, {'fill': gradient(90, ('#00000014', 0.0), ('#00000000', 0.5), ('#00000014', 1.0)), 'opacity': 1.0}, tint='#2f3a4a'))
    bag = [(500, 380), (1100, 380), (1140, 1120), (460, 1120)]
    q = rect_quad(800 - 230, 520, 460, 460)
    handle = 'M640 380C640 140 960 140 960 380L930 380C930 180 670 180 670 380Z'
    out.append(scene('tote-bag', 'Tote bag', 'Apparel', (1600, 1200), DESK, [
        {'path': handle, 'fill': solid('#efe6d3'), 'tinted': True},
        shadow(poly(shift(bag, 10, 16)), 24, 0.25),
        {'path': poly(bag), 'fill': solid('#efe6d3'), 'tinted': True},
    ], q, 0, 1.0, SHEEN, tint='#efe6d3'))
    # ------------------------------------------------------------- Home
    body = [(560, 300), (1040, 300), (1040, 900), (560, 900)]
    q = [(600, 380), (1000, 380), (1000, 820), (600, 820)]
    out.append(scene('mug', 'Mug', 'Home', (1600, 1200), DESK, [
        shadow(ellipse(800, 920, 280, 40), 26, 0.3),
        {'path': 'M1040 420C1200 420 1200 760 1040 760L1040 700C1130 700 1130 480 1040 480Z', 'fill': solid('#ffffff'), 'tinted': True},
        {'path': rounded_poly(body, 16) + ellipse(800, 900, 240, 34), 'fill': solid('#ffffff'), 'tinted': True},
        {'path': ellipse(800, 300, 240, 34), 'fill': solid('#e6e6e6')},
        {'path': ellipse(800, 306, 222, 26), 'fill': solid('#6b4a32')},
        {'path': poly([(560, 330), (640, 330), (640, 880), (560, 880)]), 'fill': solid('#000000'), 'opacity': 0.06},
    ], q, 0, 0.9091, {'fill': gradient(90, ('#00000026', 0.0), ('#ffffff00', 0.3), ('#ffffff33', 0.45), ('#00000026', 1.0)), 'opacity': 1.0},
        tint='#ffffff', cylinder={'angle': 1.05, 'sag': 18}))
    pillow = [(470, 300), (800, 330), (1130, 300), (1110, 600), (1130, 900), (800, 870), (470, 900), (490, 600)]
    q = [(540, 370), (1060, 370), (1060, 830), (540, 830)]
    out.append(scene('pillow', 'Cushion', 'Home', (1600, 1200), gradient(180, ('#d9e2dc', 0.0), ('#b9c7bd', 1.0)), [
        shadow(rounded_poly(shift(pillow, 12, 20), 60), 30, 0.3),
        {'path': rounded_poly(pillow, 60), 'fill': solid('#f5f2ec'), 'tinted': True},
    ], q, 30, 1.1304, {'fill': gradient(135, ('#ffffff33', 0.0), ('#00000000', 0.5), ('#0000001f', 1.0)), 'opacity': 1.0}, tint='#f5f2ec'))
    q = rect_quad(800 - 420, 560 - 300, 840, 600)
    out.append(scene('canvas-wall', 'Canvas on a wall', 'Home', (1600, 1200), gradient(180, ('#f2ede6', 0.0), ('#e0d6c8', 1.0)), [
        shadow(poly(shift(q, 18, 26)), 30, 0.3),
        {'path': poly([(q[1][0], q[1][1]), (q[1][0] + 16, q[1][1] + 10), (q[2][0] + 16, q[2][1] + 10), (q[2][0], q[2][1])]), 'fill': solid('#cfc6b8')},
        {'path': poly([(0, 1060), (1600, 1060), (1600, 1200), (0, 1200)]), 'fill': solid('#a88d73')},
        {'path': rounded_poly([(240, 1000), (1360, 1000), (1360, 1060), (240, 1060)], 10), 'fill': solid('#6f5b4a')},
    ], q, 0, 1.4, SHEEN))
    q = rect_quad(800 - 300, 600 - 300, 600, 600)
    out.append(scene('coaster', 'Coaster', 'Home', (1600, 1200), gradient(200, ('#8a6a50', 0.0), ('#6b4f3a', 1.0)), [
        shadow(ellipse(812, 622, 310, 310), 24, 0.35),
        {'path': ellipse(800, 600, 316, 316), 'fill': solid('#d8c3a5')},
    ], q, 300, 1.0, SHEEN))
    return out


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    all_scenes = scenes()
    lines = [json.dumps(s, ensure_ascii=False, sort_keys=True, separators=(',', ':')) for s in all_scenes]
    text = '[\n' + ',\n'.join(lines) + '\n]\n'
    TEMPLATES.write_text(text, encoding='utf-8')
    RESOURCE.write_text(text, encoding='utf-8')
    print('%d scenes, %d bytes' % (len(all_scenes), len(text.encode('utf-8'))))
    if len(sys.argv) == 2:
        out = pathlib.Path(sys.argv[1]) / 'Mockups.json'
        out.write_text(text, encoding='utf-8')
        print('and', out)


if __name__ == '__main__':
    main()
