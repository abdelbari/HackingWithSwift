#!/usr/bin/env python3
"""Write the spreadsheet both phones' tests import into a chart or a table.

    tools/generate_xlsx_fixture.py [path/to/ios/Tests/Fixtures]

Writes core/src/test/resources/fixtures/sheet.xlsx and fixtures/sheet.json
and, given a folder, copies both there for the iOS twin's tests, so the two
XlsxReaders are held to the same bytes and the same expectation: each must
read the workbook to the sheets in sheet.json, each {"name", "cells"} with
its rows as strings. The iOS repo keeps a byte-identical copy of this script
in Canvia/Tools, which writes to Canvia/Tests/Fixtures when run there.

The workbook is written by hand rather than by Excel, small enough to read,
with what Import data must get right: two sheets named in workbook.xml whose
files are found through its relationships (and out of file order), shared
strings — one in rich-text runs, one with a phonetic reading left out —
numbers as written, a date and a date-and-time in a date format (ISO, from
the 1900 date system's serials), a day before 1 March 1900 a day later (as
Excel counts 1900 a leap year), a time under a day as the time alone in a
built-in time format, a date format and a format of its own with an h, an
elapsed-time format and one with an escaped d left as their numbers, a
formula whose cached value is kept, a string formula, a boolean, an inline
string, an error, a merged cell (its value in its top-left cell only, as the
file keeps it), cells skipped within a row, and an empty row. The zip's
dates are fixed, so the file is the same each time it is written.
"""
import json
import pathlib
import shutil
import sys
import zipfile

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = (REPO / 'core/src/test/resources/fixtures/sheet.xlsx' if (REPO / 'core').is_dir()
       else REPO / 'Tests/Fixtures/sheet.xlsx')
EXPECTED = OUT.with_name('sheet.json')

DECL = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'
MAIN = 'http://schemas.openxmlformats.org/spreadsheetml/2006/main'
RELS = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
PKG = 'http://schemas.openxmlformats.org/package/2006/relationships'

CONTENT_TYPES = DECL + (
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Override PartName="/xl/workbook.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sheet.main+xml"/>'
    '<Override PartName="/xl/worksheets/sheet1.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/worksheets/sheet2.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.worksheet+xml"/>'
    '<Override PartName="/xl/sharedStrings.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.sharedStrings+xml"/>'
    '<Override PartName="/xl/styles.xml" '
    'ContentType="application/vnd.openxmlformats-officedocument.spreadsheetml.styles+xml"/>'
    '</Types>')

PACKAGE_RELS = DECL + (
    f'<Relationships xmlns="{PKG}">'
    f'<Relationship Id="rId1" Type="{RELS}/officeDocument" Target="xl/workbook.xml"/>'
    '</Relationships>')

# The second sheet in the file is the first in the workbook.
WORKBOOK = DECL + (
    f'<workbook xmlns="{MAIN}" xmlns:r="{RELS}">'
    '<workbookPr/>'
    '<sheets>'
    '<sheet name="Sales &amp; costs" sheetId="1" r:id="rId2"/>'
    '<sheet name="Notes" sheetId="2" r:id="rId1"/>'
    '</sheets></workbook>')

WORKBOOK_RELS = DECL + (
    f'<Relationships xmlns="{PKG}">'
    f'<Relationship Id="rId1" Type="{RELS}/worksheet" Target="worksheets/sheet1.xml"/>'
    f'<Relationship Id="rId2" Type="{RELS}/worksheet" Target="/xl/worksheets/sheet2.xml"/>'
    f'<Relationship Id="rId3" Type="{RELS}/sharedStrings" Target="sharedStrings.xml"/>'
    f'<Relationship Id="rId4" Type="{RELS}/styles" Target="styles.xml"/>'
    '</Relationships>')

SHARED = DECL + (
    f'<sst xmlns="{MAIN}" count="7" uniqueCount="7">'
    '<si><t>Month</t></si>'
    '<si><t>Sales</t></si>'
    '<si><r><rPr><b/></rPr><t>Cos</t></r><r><t xml:space="preserve">ts </t></r></si>'
    '<si><t>January</t></si>'
    '<si><t>February</t><rPh sb="0" eb="1"><t>フェブ</t></rPh></si>'
    '<si><t>Total &lt;all&gt;</t></si>'
    '<si><t>Merged across</t></si>'
    '</sst>')

# Style 1 is a built-in date (14), 2 a custom date and time, 3 an elapsed
# time (no date: its h is in brackets), 4 a built-in time (20, h:mm), 5 a
# number with an escaped d (no date), 6 a time of its own (h:mm AM/PM).
STYLES = DECL + (
    f'<styleSheet xmlns="{MAIN}">'
    '<numFmts count="4">'
    '<numFmt numFmtId="164" formatCode="yyyy\\-mm\\-dd\\ hh:mm"/>'
    '<numFmt numFmtId="165" formatCode="[h]:mm:ss"/>'
    '<numFmt numFmtId="166" formatCode="0.0\\d"/>'
    '<numFmt numFmtId="167" formatCode="h:mm AM/PM"/>'
    '</numFmts>'
    '<cellXfs count="7">'
    '<xf numFmtId="0"/>'
    '<xf numFmtId="14" applyNumberFormat="1"/>'
    '<xf numFmtId="164" applyNumberFormat="1"/>'
    '<xf numFmtId="165" applyNumberFormat="1"/>'
    '<xf numFmtId="20" applyNumberFormat="1"/>'
    '<xf numFmtId="166" applyNumberFormat="1"/>'
    '<xf numFmtId="167" applyNumberFormat="1"/>'
    '</cellXfs></styleSheet>')

SALES = DECL + (
    f'<worksheet xmlns="{MAIN}"><sheetData>'
    '<row r="1"><c r="A1" t="s"><v>0</v></c><c r="B1" t="s"><v>1</v></c><c r="C1" t="s"><v>2</v></c>'
    '<c r="D1" t="inlineStr"><is><t>Day</t></is></c></row>'
    '<row r="2"><c r="A2" t="s"><v>3</v></c><c r="B2"><v>1200.5</v></c><c r="C2"><v>-300</v></c>'
    '<c r="D2" s="1"><v>45306</v></c></row>'
    '<row r="3"><c r="A3" t="s"><v>4</v></c><c r="B3"><v>980</v></c>'
    '<c r="D3" s="2"><v>45337.75</v></c><c r="E3" s="3"><v>0.5</v></c></row>'
    '<row r="5"><c r="A5" t="s"><v>5</v></c><c r="B5"><f>SUM(B2:B3)</f><v>2180.5</v></c>'
    '<c r="C5" t="str"><f>"x"&amp;"y"</f><v>xy</v></c><c r="D5" t="b"><v>1</v></c>'
    '<c r="E5" t="e"><v>#DIV/0!</v></c></row>'
    '<row r="6"><c r="A6" t="s"><v>6</v></c><c r="B6"/><c r="C6"><f>B6*2</f></c></row>'
    '<row r="7"><c r="A7" s="1"><v>1</v></c><c r="B7" s="4"><v>0.75</v></c><c r="C7" s="5"><v>3</v></c>'
    '<c r="D7" s="2"><v>0.25</v></c><c r="E7" s="6"><v>0.5</v></c></row>'
    '</sheetData>'
    '<mergeCells count="1"><mergeCell ref="A6:B6"/></mergeCells>'
    '</worksheet>')

NOTES = DECL + (
    f'<worksheet xmlns="{MAIN}"><sheetData>'
    '<row r="1"><c r="B1" t="inlineStr"><is><r><t>Kept </t></r><r><t>for later</t></r></is></c></row>'
    '<row r="2"><c r="A2" t="b"><v>0</v></c></row>'
    '</sheetData></worksheet>')

PARTS = [
    ('[Content_Types].xml', CONTENT_TYPES),
    ('_rels/.rels', PACKAGE_RELS),
    ('xl/workbook.xml', WORKBOOK),
    ('xl/_rels/workbook.xml.rels', WORKBOOK_RELS),
    ('xl/sharedStrings.xml', SHARED),
    ('xl/styles.xml', STYLES),
    ('xl/worksheets/sheet1.xml', NOTES),
    ('xl/worksheets/sheet2.xml', SALES),
]

EXPECTATION = [
    {
        'name': 'Sales & costs',
        'cells': [
            ['Month', 'Sales', 'Costs ', 'Day', ''],
            ['January', '1200.5', '-300', '2024-01-15', ''],
            ['February', '980', '', '2024-02-15T18:00:00', '0.5'],
            ['', '', '', '', ''],
            ['Total <all>', '2180.5', 'xy', 'TRUE', '#DIV/0!'],
            ['Merged across', '', '', '', ''],
            ['1900-01-01', '18:00:00', '3', '06:00:00', '12:00:00'],
        ],
    },
    {
        'name': 'Notes',
        'cells': [
            ['', 'Kept for later'],
            ['FALSE', ''],
        ],
    },
]


def main():
    OUT.parent.mkdir(parents=True, exist_ok=True)
    with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in PARTS:
            info = zipfile.ZipInfo(name, date_time=(1980, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data.encode('utf-8'))
    EXPECTED.write_text(json.dumps(EXPECTATION, ensure_ascii=False, indent=2) + '\n', encoding='utf-8')
    print(f'wrote {OUT.relative_to(REPO)} and {EXPECTED.relative_to(REPO)}')
    if len(sys.argv) > 1:
        for source in (OUT, EXPECTED):
            target = pathlib.Path(sys.argv[1]) / source.name
            shutil.copyfile(source, target)
            print(f'wrote {target}')


if __name__ == '__main__':
    main()
