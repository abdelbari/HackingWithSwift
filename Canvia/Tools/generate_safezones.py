#!/usr/bin/env python3
"""Write both phones' platform safe zones.

    tools/generate_safezones.py [folder ...]

Writes SafeZones.json into each folder given — the iOS twin passes
Canvia/Canvia/Content — or, with none, into
core/src/main/resources/com/canvia/core/content/, so both apps draw and
check the same zones from the same bytes.

The file is a JSON array, one zone a line, each

  {"id", "label", "sizes": [[width, height], ...],
   "insets": {"top", "bottom", "left", "right"},
   "rails": [{"x", "y", "w", "h"}, ...]}

"sizes" are the page sizes, in pixels, the zone is for; "insets" the bands
along each edge that the platform's profile row, caption and progress bar
cover, and "rails" the like and comment buttons, each a rectangle — all as
fractions of the page's width (left, right, x, w) and height (top, bottom,
y, h). The first zone a page's size matches is the one shown by default.
The values are this app's own reading of where each platform draws over a
full-screen 9:16 post: nothing is downloaded.
"""
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
DEFAULT = REPO / 'core/src/main/resources/com/canvia/core/content'

VERTICAL = [[1080, 1920]]

ZONES = [
    ('instagram-story', 'Instagram Story', {'top': 0.14, 'bottom': 0.18, 'left': 0.0, 'right': 0.0}, []),
    ('instagram-reel', 'Instagram Reel', {'top': 0.14, 'bottom': 0.18, 'left': 0.0, 'right': 0.0},
     [{'x': 0.86, 'y': 0.42, 'w': 0.14, 'h': 0.4}]),
    ('tiktok', 'TikTok', {'top': 0.1, 'bottom': 0.2, 'left': 0.0, 'right': 0.12}, []),
    ('youtube-short', 'YouTube Shorts', {'top': 0.12, 'bottom': 0.22, 'left': 0.0, 'right': 0.1}, []),
    ('facebook-story', 'Facebook Story', {'top': 0.14, 'bottom': 0.2, 'left': 0.0, 'right': 0.0}, []),
]


def check(zone):
    insets = zone['insets']
    for side in ('top', 'bottom', 'left', 'right'):
        if not 0 <= insets[side] < 0.5:
            sys.exit(f"{zone['id']}: {side} inset out of range")
    if insets['top'] + insets['bottom'] >= 1 or insets['left'] + insets['right'] >= 1:
        sys.exit(f"{zone['id']}: nothing left uncovered")
    for rail in zone['rails']:
        if rail['x'] < 0 or rail['y'] < 0 or rail['x'] + rail['w'] > 1 or rail['y'] + rail['h'] > 1:
            sys.exit(f"{zone['id']}: a rail runs off the page")


def main():
    zones = []
    for zid, label, insets, rails in ZONES:
        zone = {'id': zid, 'label': label, 'sizes': VERTICAL, 'insets': insets, 'rails': rails}
        check(zone)
        zones.append(zone)
    if len({z['id'] for z in zones}) != len(zones):
        sys.exit('zone ids repeat')
    lines = ['[']
    lines += [json.dumps(z, ensure_ascii=False, separators=(',', ':')) + (',' if i < len(zones) - 1 else '')
              for i, z in enumerate(zones)]
    lines += [']']
    text = '\n'.join(lines) + '\n'
    folders = [pathlib.Path(p) for p in sys.argv[1:]] or [DEFAULT]
    for folder in folders:
        (folder / 'SafeZones.json').write_text(text, encoding='utf-8')
        print(f'{len(zones)} safe zones written to {folder / "SafeZones.json"}')


if __name__ == '__main__':
    main()
