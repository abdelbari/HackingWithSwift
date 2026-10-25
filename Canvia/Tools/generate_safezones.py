#!/usr/bin/env python3
"""Write the platform safe zones both phones mark on vertical social pages.

    tools/generate_safezones.py [folder ...]

Writes SafeZones.json into core/src/main/resources/com/canvia/core/content/
in the Android repo, or Canvia/Canvia/Content/ when this byte-identical copy
runs from the iOS repo's Canvia/Tools — and, given folders, the same bytes
into each of them — so a story or a reel shows the same covered bands, snaps
to the same lines and flags the same text on both phones.

The file is a JSON array, one zone a line, in the order the Snapping and
guides sheet offers them — the first a page's size matches is the one it
shows by default:

    {"id", "label", "sizes": [[width, height], ...],
     "insets": {"top", "bottom", "left", "right"},
     "rails": [{"x", "y", "w", "h"}, ...]}

"sizes" are the page sizes, in pixels, the zone is for; "insets" the bands
along each edge that the platform's profile row, caption and progress bar
cover; "rails" the like, comment and share columns, each a rectangle — all
as fractions of the page's width (left, right, x, w) and height (top,
bottom, y, h). "label" is the platform's own name, drawn on the band as it
is. The values are this app's own reading of where each platform draws over
a full-screen 9:16 post: nothing is downloaded.
"""
import json
import pathlib
import sys

HERE = pathlib.Path(__file__).resolve().parent
ANDROID = HERE.parent / 'core/src/main/resources/com/canvia/core/content'
IOS = HERE.parent / 'Canvia/Content'

VERTICAL = [[1080, 1920]]


def zone(id, label, top, bottom, left=0.0, right=0.0, rails=()):
    return {
        'id': id, 'label': label, 'sizes': VERTICAL,
        'insets': {'top': top, 'bottom': bottom, 'left': left, 'right': right},
        'rails': [{'x': x, 'y': y, 'w': w, 'h': h} for (x, y, w, h) in rails],
    }


ZONES = [
    zone('instagram-story', 'Instagram Story', 0.14, 0.18),
    # A reel's like, comment, share and audio column runs up the right side
    # above its caption.
    zone('instagram-reel', 'Instagram Reel', 0.14, 0.18, rails=[(0.86, 0.42, 0.14, 0.4)]),
    zone('tiktok', 'TikTok', 0.1, 0.2, right=0.12),
    zone('youtube-short', 'YouTube Shorts', 0.12, 0.22, right=0.1),
    zone('facebook-story', 'Facebook Story', 0.14, 0.2),
    zone('whatsapp-status', 'WhatsApp Status', 0.12, 0.16),
]


def check(z):
    insets = z['insets']
    for side in ('top', 'bottom', 'left', 'right'):
        if not 0 <= insets[side] < 0.5:
            sys.exit(f"{z['id']}: {side} inset out of range")
    if insets['top'] + insets['bottom'] >= 1 or insets['left'] + insets['right'] >= 1:
        sys.exit(f"{z['id']}: nothing left uncovered")
    for rail in z['rails']:
        if rail['x'] < 0 or rail['y'] < 0 or rail['x'] + rail['w'] > 1 or rail['y'] + rail['h'] > 1:
            sys.exit(f"{z['id']}: a rail runs off the page")


def main():
    for z in ZONES:
        check(z)
    ids = [z['id'] for z in ZONES]
    if len(set(ids)) != len(ids) or 'none' in ids:
        sys.exit('an id is listed twice, or is "none"')
    lines = [json.dumps(z, ensure_ascii=False, separators=(',', ':')) for z in ZONES]
    text = '[\n' + ',\n'.join(lines) + '\n]\n'
    json.loads(text)
    folders = [ANDROID if ANDROID.is_dir() else IOS] + [pathlib.Path(p) for p in sys.argv[1:]]
    for folder in folders:
        folder.mkdir(parents=True, exist_ok=True)
        (folder / 'SafeZones.json').write_text(text, encoding='utf-8')
        print(f'{len(ZONES)} safe zones written to {folder / "SafeZones.json"}')


if __name__ == '__main__':
    main()
