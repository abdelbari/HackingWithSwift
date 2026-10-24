#!/usr/bin/env python3
"""Write the spreadsheet both phones' XlsxReader tests read.

    tools/generate_xlsx_fixture.py [path/to/ios/Tests/Fixtures]

Writes core/src/test/resources/com/canvia/core/content/sheets.xlsx and,
given a folder, the same file there: a tiny workbook written by hand, as
Excel writes one, so both phones read the same grid out of it. Every entry
is deflated and stamped 1980-01-01 00:00, so the bytes are the same on any
machine.

Its first sheet, "Sales", holds shared strings, whole and decimal numbers,
a date (style 1, number format 14), booleans, a formula with its cached
value, an inline string, a merged cell (A5:B5) and a cell given no "r" of
its own; its second, "Notes", one shared string. The grid both phones
read from "Sales" is:

    Month | Sales  | Date       | Paid
    Jan   | 1200   | 2024-01-15 | TRUE
    Feb   | 950.5  | 2024-02-29 | FALSE
    Total | 2150.5 |            |
    Merged note |  | inline     | x
"""
import pathlib
import sys
import zipfile

REPO = pathlib.Path(__file__).resolve().parent.parent
FIXTURE = REPO / 'core/src/test/resources/com/canvia/core/content/sheets.xlsx'

NS = 'xmlns="http://schemas.openxmlformats.org/spreadsheetml/2006/main"'
RNS = 'xmlns:r="http://schemas.openxmlformats.org/officeDocument/2006/relationships"'

FILES = [
    ('[Content_Types].xml',
     '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
     '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
     '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
     '<Default Extension="xml" ContentType="application/xml"/>'
     '<Override PartName="/xl/workbook.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
     '<Override PartName="/xl/worksheets/sheet1.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
     '<Override PartName="/xl/worksheets/sheet2.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
     '<Override PartName="/xl/sharedStrings.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
     '<Override PartName="/xl/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
     '</Types>'),
    ('_rels/.rels',
     '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
     '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
     '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="xl/workbook.xml"/>'
     '</Relationships>'),
    ('xl/workbook.xml',
     '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
     '<workbook ' + NS + ' ' + RNS + '><sheets>'
     '<sheet name="Sales" sheetId="1" r:id="rId1"/>'
     '<sheet name="Notes" sheetId="2" r:id="rId2"/>'
     '</sheets></workbook>'),
    ('xl/_rels/workbook.xml.rels',
     '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
     '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
     '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet1.xml"/>'
     '<Relationship Id="rId2" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/worksheet" Target="worksheets/sheet2.xml"/>'
     '<Relationship Id="rId3" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/sharedStrings" Target="sharedStrings.xml"/>'
     '<Relationship Id="rId4" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/styles" Target="styles.xml"/>'
     '</Relationships>'),
    ('xl/sharedStrings.xml',
     '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
     '<sst ' + NS + ' count="9" uniqueCount="9">'
     '<si><t>Month</t></si><si><t>Sales</t></si><si><t>Date</t></si><si><t>Paid</t></si>'
     '<si><t>Jan</t></si><si><t>Feb</t></si><si><t xml:space="preserve">Total </t></si>'
     '<si><r><rPr><b/></rPr><t>Merged</t></r><r><t xml:space="preserve"> note</t></r></si>'
     '<si><t>Remember the milk</t></si>'
     '</sst>'),
    ('xl/styles.xml',
     '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
     '<styleSheet ' + NS + '><cellXfs count="2">'
     '<xf numFmtId="0" fontId="0" fillId="0" borderId="0" xfId="0"/>'
     '<xf numFmtId="14" fontId="0" fillId="0" borderId="0" xfId="0" applyNumberFormat="1"/>'
     '</cellXfs></styleSheet>'),
    ('xl/worksheets/sheet1.xml',
     '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
     '<worksheet ' + NS + ' ' + RNS + '><sheetData>'
     '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c>'
     '<c r="D1" t="s"><v>3</v></c></row>'
     '<row r="2"><c r="A2" t="s"><v>4</v></c><c r="B2"><v>1200</v></c><c r="C2" s="1"><v>45306</v></c>'
     '<c r="D2" t="b"><v>1</v></c></row>'
     '<row r="3"><c r="A3" t="s"><v>5</v></c><c r="B3" t="n"><v>950.5</v></c><c r="C3" s="1"><v>45351</v></c>'
     '<c r="D3" t="b"><v>0</v></c></row>'
     '<row r="4"><c r="A4" t="s"><v>6</v></c><c r="B4"><f>SUM(B2:B3)</f><v>2150.5</v></c></row>'
     '<row r="5"><c r="A5" t="s"><v>7</v></c><c r="B5"/><c r="C5" t="inlineStr"><is><t>inline</t></is></c>'
     '<c t="str"><f>LOWER("X")</f><v>x</v></c></row>'
     '</sheetData><mergeCells count="1"><mergeCell ref="A5:B5"/></mergeCells></worksheet>'),
    ('xl/worksheets/sheet2.xml',
     '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
     '<worksheet ' + NS + '><sheetData><row r="1"><c r="A1" t="s"><v>8</v></c></row></sheetData></worksheet>'),
]


def main():
    if len(sys.argv) not in (1, 2):
        sys.exit(__doc__)
    targets = [FIXTURE] + ([pathlib.Path(sys.argv[1]) / 'sheets.xlsx'] if len(sys.argv) == 2 else [])
    for target in targets:
        target.parent.mkdir(parents=True, exist_ok=True)
        with zipfile.ZipFile(target, 'w') as z:
            for name, text in FILES:
                info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
                info.compress_type = zipfile.ZIP_DEFLATED
                info.external_attr = 0o644 << 16
                z.writestr(info, text.encode('utf-8'), compresslevel=9)
        print('wrote', target, target.stat().st_size, 'bytes')


if __name__ == '__main__':
    main()
