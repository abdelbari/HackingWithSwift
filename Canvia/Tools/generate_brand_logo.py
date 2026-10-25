#!/usr/bin/env python3
"""Regenerate the brand-logo fixture both phones' tests read.

    tools/generate_brand_logo.py [path/to/ios/fixtures/folder]

Writes core/src/test/resources/fixtures/brand_logo.png, a 64 by 64 RGBA
logo drawn with hard edges so every pixel is one of a few exact colours:
a clear background, a navy disc, an orange band across it, a small white
mark, a one-pixel black ring round the disc, and a faint red haze (alpha
16) in the corners that a logo's colours must not count. The colours
PhotoPalette.logo takes from it are in brand_logo_palette.json. Given a
folder, the PNG is written there too for the iOS twin.

Every byte is the same on any machine: no clock, no randomness, and zlib at
its fixed level 9.
"""
import pathlib
import struct
import sys
import zlib

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = REPO / 'core/src/test/resources/fixtures/brand_logo.png'

SIZE = 64
CLEAR = (0, 0, 0, 0)
HAZE = (255, 0, 0, 16)
NAVY = (0x1a, 0x2b, 0x6d, 255)
ORANGE = (0xff, 0x7a, 0x00, 255)
WHITE = (255, 255, 255, 255)
BLACK = (0, 0, 0, 255)


def pixel(x, y):
    """The colour at pixel (x, y), its middle measured from the logo's."""
    dx = x + 0.5 - SIZE / 2
    dy = y + 0.5 - SIZE / 2
    d2 = dx * dx + dy * dy
    if d2 <= 26 * 26:
        if 12 <= x < 20 and 28 <= y < 36:
            return WHITE
        if 26 <= y < 38:
            return ORANGE
        return NAVY
    if d2 <= 27 * 27:
        return BLACK
    if (x < 8 or x >= SIZE - 8) and (y < 8 or y >= SIZE - 8):
        return HAZE
    return CLEAR


def png(rows):
    def chunk(kind, data):
        return struct.pack('>I', len(data)) + kind + data + struct.pack('>I', zlib.crc32(kind + data) & 0xffffffff)
    raw = b''.join(b'\x00' + bytes(v for p in row for v in p) for row in rows)
    head = struct.pack('>IIBBBBB', SIZE, SIZE, 8, 6, 0, 0, 0)
    return b'\x89PNG\r\n\x1a\n' + chunk(b'IHDR', head) + chunk(b'IDAT', zlib.compress(raw, 9)) + chunk(b'IEND', b'')


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    rows = [[pixel(x, y) for x in range(SIZE)] for y in range(SIZE)]
    data = png(rows)
    OUT.write_bytes(data)
    if len(sys.argv) == 2:
        (pathlib.Path(sys.argv[1]) / OUT.name).write_bytes(data)
    counts = {}
    for row in rows:
        for p in row:
            counts[p] = counts.get(p, 0) + 1
    for p, n in sorted(counts.items(), key=lambda kv: -kv[1]):
        print('#%02x%02x%02x alpha %d: %d' % (p[0], p[1], p[2], p[3], n))


if __name__ == '__main__':
    main()
