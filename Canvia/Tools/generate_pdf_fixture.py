#!/usr/bin/env python3
"""Write the PDF both phones read as editable text in their tests.

    tools/generate_pdf_fixture.py [path/to/ios/Tests/fixtures]

Writes core/src/test/resources/fixtures/pdf-text.pdf — and, given a folder,
the same bytes there — the document PdfText reads into the golden runs of
fixtures/pdf-text.json. The iOS repo keeps a byte-identical copy of
this script in Canvia/Tools, which writes to Canvia/Tests/Fixtures when run
there. It is made to use what the reader handles:

- page 1 (612 x 792): Helvetica-Bold in WinAnsiEncoding with widths, a
  title in an rg colour with é and an en dash; Times-Roman with a
  /Differences encoding and no widths (the default 500), in g grey, three
  lines through TL, TJ with a word gap, T* and ', inside q/cm/Q; and a
  note in a k colour;
- page 2 (595 x 842): a Type0 font with Identity-H two-byte codes and a
  ToUnicode CMap of bfchar entries, sized through Tm; a TrueType subset
  ("ABCDEF+Lora-Italic") whose codes mean nothing but through its
  ToUnicode CMap's bfrange (a start and an array) and bfchar entries,
  with Tc, on two lines through Td;
- every content stream FlateDecode; page 2's fonts packed in an object
  stream; the cross-reference table a stream with PNG predictor 12.
"""
import pathlib
import shutil
import sys
import zlib

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = (REPO / 'core/src/test/resources/fixtures/pdf-text.pdf' if (REPO / 'core').is_dir()
       else REPO / 'Tests/Fixtures/pdf-text.pdf')


def flate(data):
    return zlib.compress(data, 9)


def stream(dict_body, data):
    return b'<< ' + dict_body + b' /Length ' + str(len(data)).encode() + b' >>\nstream\n' + data + b'\nendstream'


PAGE1 = b"""BT /F1 24 Tf 0.12 0.14 0.19 rg 72 720 Td (Caf\\351 \\226 Menu) Tj ET
q 1 0 0 1 0 -20 cm
BT /F2 12 Tf 14 TL 0.4 g 72 660 Td [(Fresh coffee) -300 (every day)] TJ T* (Open until \\200 5 \\(pm\\)) Tj (Smith\\201s Bakery) ' ET
Q
BT /F2 12 Tf 0 0 1 0 k 300 500 Td (Yellow note) Tj ET
"""

PAGE2 = b"""BT /F4 1 Tf 30 0 0 30 56 760 Tm 0.8 0.1 0.1 rg <00010002000300030004> Tj ET
BT /F3 14 Tf 56 700 Td 2 Tc <0102030405> Tj 0 -18 Td <060708> Tj ET
"""

CMAP_F3 = b"""/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
/CMapName /Canvia-F3 def
1 begincodespacerange
<00> <FF>
endcodespacerange
2 beginbfrange
<01> <03> <0061>
<06> <08> [<0078> <0079> <007A>]
endbfrange
2 beginbfchar
<04> <00E9>
<05> <0020>
endbfchar
endcmap
CMapName currentdict /CMap defineresource pop
end
end
"""

CMAP_F4 = b"""/CIDInit /ProcSet findresource begin
12 dict begin
begincmap
1 begincodespacerange
<0000> <FFFF>
endcodespacerange
4 beginbfchar
<0001> <0048>
<0002> <0065>
<0003> <006C>
<0004> <006F>
endbfchar
endcmap
end
end
"""


def main():
    if len(sys.argv) > 2:
        sys.exit(__doc__)
    widths = b'[' + b' '.join(b'278' if c == 32 else b'556' for c in range(32, 256)) + b']'
    objects = {
        1: b'<< /Type /Catalog /Pages 2 0 R >>',
        2: b'<< /Type /Pages /Kids [3 0 R 4 0 R] /Count 2 /MediaBox [0 0 612 792] >>',
        3: b'<< /Type /Page /Parent 2 0 R /Resources << /Font << /F1 5 0 R /F2 6 0 R >> >> /Contents 7 0 R >>',
        4: b'<< /Type /Page /Parent 2 0 R /MediaBox [0 0 595 842] /Resources << /Font << /F3 8 0 R /F4 9 0 R >> >> /Contents 10 0 R >>',
        5: b'<< /Type /Font /Subtype /Type1 /BaseFont /Helvetica-Bold /Encoding /WinAnsiEncoding /FirstChar 32 /LastChar 255 /Widths ' + widths + b' >>',
        6: b'<< /Type /Font /Subtype /Type1 /BaseFont /Times-Roman /Encoding << /BaseEncoding /WinAnsiEncoding /Differences [128 /Euro /quoteright] >> >>',
        7: stream(b'/Filter /FlateDecode', flate(PAGE1)),
        10: stream(b'/Filter /FlateDecode', flate(PAGE2)),
        11: stream(b'/Filter /FlateDecode', flate(CMAP_F3)),
        13: stream(b'/Filter /FlateDecode', flate(CMAP_F4)),
    }
    packed = {
        8: b'<< /Type /Font /Subtype /TrueType /BaseFont /ABCDEF+Lora-Italic /FirstChar 1 /LastChar 8 '
           b'/Widths [500 520 440 480 250 500 480 430] /ToUnicode 11 0 R >>',
        9: b'<< /Type /Font /Subtype /Type0 /BaseFont /GHIJKL+Montserrat-Bold /Encoding /Identity-H '
           b'/DescendantFonts [12 0 R] /ToUnicode 13 0 R >>',
        12: b'<< /Type /Font /Subtype /CIDFontType2 /BaseFont /GHIJKL+Montserrat-Bold /CIDSystemInfo << /Registry (Adobe) /Ordering (Identity) /Supplement 0 >> '
            b'/DW 1000 /W [1 [720 600 280] 4 4 620] >>',
    }
    # The object stream: its pairs, then its objects.
    bodies = b''
    pairs = []
    for num in sorted(packed):
        pairs.append(f'{num} {len(bodies)}'.encode())
        bodies += packed[num] + b'\n'
    header = b' '.join(pairs) + b'\n'
    objects[14] = stream(
        f'/Type /ObjStm /N {len(packed)} /First {len(header)} /Filter /FlateDecode'.encode(),
        flate(header + bodies),
    )

    out = bytearray(b'%PDF-1.5\n%\xe2\xe3\xcf\xd3\n')
    offsets = {}
    for num in sorted(objects):
        offsets[num] = len(out)
        out += f'{num} 0 obj\n'.encode() + objects[num] + b'\nendobj\n'

    # The cross-reference stream: type, 2-byte field, 1-byte field; PNG Up.
    xref_num = 15
    offsets[xref_num] = len(out)
    size = xref_num + 1
    rows = []
    index_in_stream = {num: i for i, num in enumerate(sorted(packed))}
    for num in range(size):
        if num == 0:
            rows.append(bytes([0, 0, 0, 0]))
        elif num in packed:
            rows.append(bytes([2, 0, 14, index_in_stream[num]]))
        else:
            off = offsets[num]
            rows.append(bytes([1]) + off.to_bytes(2, 'big') + bytes([0]))
    raw = bytearray()
    prior = bytes(4)
    for row in rows:
        raw.append(2)
        raw += bytes((row[i] - prior[i]) & 0xff for i in range(4))
        prior = row
    data = flate(bytes(raw))
    xref = stream(
        f'/Type /XRef /Size {size} /W [1 2 1] /Root 1 0 R /Filter /FlateDecode /DecodeParms << /Predictor 12 /Columns 4 >>'.encode(),
        data,
    )
    out += f'{xref_num} 0 obj\n'.encode() + xref + b'\nendobj\n'
    out += f'startxref\n{offsets[xref_num]}\n%%EOF\n'.encode()
    assert max(offsets.values()) < 65536
    OUT.write_bytes(bytes(out))
    print(f'{len(out)} bytes written to {OUT}')
    if len(sys.argv) == 2:
        folder = pathlib.Path(sys.argv[1])
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(OUT, folder / 'pdf-text.pdf')
        print(f'pdf-text.pdf copied to {folder}')


if __name__ == '__main__':
    main()
