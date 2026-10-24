#!/usr/bin/env python3
"""Write the table designs both phones offer in Add > Table and the Table panel.

    tools/generate_tables.py [path/to/ios/staging]

Writes core/src/main/resources/com/canvia/core/content/tables.json — and,
given a folder, the same bytes there as tables.json, for the iOS twin to
bundle — so a design is the same look on both phones. The iOS repo keeps a
byte-identical copy of this script in Canvia/Tools, which writes to
Canvia/Content/tables.json when run there.

The file is a list of designs, one a line, in the order the gallery shows
them:

    {"id", "name", "headerFill", "headerInk", "headerWeight", "bodyFill",
     "bandFill" (or null), "ink", "border", "borderWidth",
     "borders" ("all", "outer", "inner", "horizontal" or "none"),
     "radius", "pad", "font" (a font family's id, or null)}

Colours are "#rrggbb" or the tokens "accent" and "accent2", which each phone
resolves to the brand kit's colours or the design's own (DataGraphics
.paletteFor). "pad" is the cells' inset as a share of their type, as
DataGraphics.PAD (0.6) is; "radius" every cell's corner radius in px;
"borderWidth" in px. Every field is written out, so neither phone falls
back on a default of its own.
"""
import json
import pathlib
import sys

REPO = pathlib.Path(__file__).resolve().parent.parent
RESOURCE = (REPO / 'core/src/main/resources/com/canvia/core/content/tables.json' if (REPO / 'core').is_dir()
            else REPO / 'Canvia/Content/tables.json')

INK = '#1f2430'
WHITE = '#ffffff'
HAIRLINE = '#00000022'


def design(id, name, header_fill, header_ink, body_fill=WHITE, band_fill=None, ink=INK, border=HAIRLINE,
           border_width=1, borders='all', radius=0, pad=0.6, font=None, header_weight=700):
    return {
        'id': id, 'name': name,
        'headerFill': header_fill, 'headerInk': header_ink, 'headerWeight': header_weight,
        'bodyFill': body_fill, 'bandFill': band_fill, 'ink': ink,
        'border': border, 'borderWidth': border_width, 'borders': borders,
        'radius': radius, 'pad': pad, 'font': font,
    }


DESIGNS = [
    # The look Add > Table always made: an accent header, banded rows, hairlines.
    design('classic', 'Classic', 'accent', WHITE, band_fill='#f3f4f6'),
    design('minimal', 'Minimal', WHITE, INK, border='#d1d5db', borders='horizontal'),
    design('striped', 'Striped', WHITE, INK, band_fill='#eef2f7', border=HAIRLINE, borders='none'),
    design('dark-header', 'Dark header', '#16181d', WHITE, band_fill='#f3f4f6', borders='horizontal', border='#e5e7eb'),
    design('bordered', 'Bordered', '#f3f4f6', INK, border='#1f2430', border_width=2),
    design('card', 'Card', 'accent', WHITE, body_fill='#f8fafc', border=WHITE, border_width=4, radius=8, pad=0.8),
    design('outline', 'Outline', WHITE, 'accent', border='accent', border_width=2, borders='outer'),
    design('grid-lines', 'Grid lines', WHITE, INK, border='#9ca3af', borders='inner'),
    design('accent-bands', 'Accent bands', 'accent', WHITE, band_fill='#fef3c7', borders='none'),
    design('second-colour', 'Second colour', 'accent2', WHITE, band_fill='#f1f5f9', border='#cbd5e1'),
    design('night', 'Night', '#0f172a', '#f8fafc', body_fill='#1e293b', ink='#e2e8f0', border='#334155'),
    design('paper', 'Paper', '#f5efe6', '#3f2d1f', body_fill='#fffaf2', ink='#3f2d1f', border='#d6c7b2',
           borders='horizontal', font='lora'),
    design('mono', 'Mono', '#111111', WHITE, band_fill='#f4f4f5', border='#111111', font='roboto-mono'),
    design('soft', 'Soft', '#e0e7ff', '#312e81', body_fill='#f5f7ff', ink='#312e81', border=WHITE, border_width=2,
           radius=6, pad=0.7),
    design('bold', 'Bold', 'accent', WHITE, ink=INK, border='accent', border_width=3, font='montserrat', header_weight=800),
    design('light-header', 'Light header', '#f3f4f6', INK, border='#e5e7eb', borders='horizontal', header_weight=600),
]


def main():
    if len(sys.argv) > 2:
        sys.exit(__doc__)
    ids = [d['id'] for d in DESIGNS]
    if len(set(ids)) != len(ids) or 'table' in ids:
        sys.exit('an id is listed twice, or is "table"')
    lines = [json.dumps(d, ensure_ascii=False, separators=(',', ':')) for d in DESIGNS]
    text_out = '[\n' + ',\n'.join(lines) + '\n]\n'
    json.loads(text_out)
    RESOURCE.write_text(text_out, encoding='utf-8')
    print(f'{len(DESIGNS)} table designs written to {RESOURCE}')
    if len(sys.argv) == 2:
        staging = pathlib.Path(sys.argv[1])
        staging.mkdir(parents=True, exist_ok=True)
        (staging / 'tables.json').write_text(text_out, encoding='utf-8')
        print(f'tables.json written to {staging}')


if __name__ == '__main__':
    main()
