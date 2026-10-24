#!/usr/bin/env python3
"""Write the Word document both phones open as a Doc in their tests.

    tools/generate_docx_fixture.py [path/to/ios/Tests/fixtures]

Writes core/src/test/resources/fixtures/word.docx — and, given a folder, the
same bytes there — the document DocxReader reads into the blocks of
fixtures/word-blocks.json. The iOS repo keeps a byte-identical copy of this
script in Canvia/Tools, which writes to Canvia/Tests/Fixtures when run there.
It is made to use what the reader handles:

- styles by id (Title, Heading1, Heading2, Quote, Caption) and by name (a
  style "MySub" named "heading 3"); numbering.xml with a bullet list and a
  numbered one whose second level is lowercase letters;
- runs bold, italic, underlined (and one "none"), struck, coloured,
  highlighted by name and by shading, and inside an external hyperlink;
  a tab and a line break;
- list items at levels 0 and 1, a checklist line ("☑ "), a page break run
  between two paragraphs' words, pageBreakBefore, an empty paragraph (left
  out) and one with a bottom border (a divider), a structured document tag;
- a table whose first row is a header, with a cell spanning two columns;
- an inline picture (a 1x1 PNG) with alt text;
- an A4 section with 1134-twip margins.

Every zip entry is stored with the same date, so the bytes never change.
"""
import base64
import pathlib
import shutil
import sys
import zipfile

REPO = pathlib.Path(__file__).resolve().parent.parent
OUT = (REPO / 'core/src/test/resources/fixtures/word.docx' if (REPO / 'core').is_dir()
       else REPO / 'Tests/Fixtures/word.docx')

W = 'http://schemas.openxmlformats.org/wordprocessingml/2006/main'
R = 'http://schemas.openxmlformats.org/officeDocument/2006/relationships'
HEAD = '<?xml version="1.0" encoding="UTF-8" standalone="yes"?>\n'

PNG = base64.b64decode('iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=')

CONTENT_TYPES = HEAD + (
    '<Types xmlns="http://schemas.openxmlformats.org/package/2006/content-types">'
    '<Default Extension="rels" ContentType="application/vnd.openxmlformats-package.relationships+xml"/>'
    '<Default Extension="xml" ContentType="application/xml"/>'
    '<Default Extension="png" ContentType="image/png"/>'
    '<Override PartName="/word/document.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml"/>'
    '<Override PartName="/word/styles.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml"/>'
    '<Override PartName="/word/numbering.xml" ContentType="application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml"/>'
    '</Types>'
)

RELS = HEAD + (
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    '<Relationship Id="rId1" Type="http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument" Target="word/document.xml"/>'
    '</Relationships>'
)

DOC_RELS = HEAD + (
    '<Relationships xmlns="http://schemas.openxmlformats.org/package/2006/relationships">'
    f'<Relationship Id="rId1" Type="{R}/styles" Target="styles.xml"/>'
    f'<Relationship Id="rId2" Type="{R}/numbering" Target="numbering.xml"/>'
    f'<Relationship Id="rId7" Type="{R}/image" Target="media/image1.png"/>'
    f'<Relationship Id="rId9" Type="{R}/hyperlink" Target="https://example.com/menu?a=1&amp;b=2" TargetMode="External"/>'
    '</Relationships>'
)

STYLES = HEAD + (
    f'<w:styles xmlns:w="{W}">'
    '<w:style w:type="paragraph" w:default="1" w:styleId="Normal"><w:name w:val="Normal"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Title"><w:name w:val="Title"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading1"><w:name w:val="heading 1"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Heading2"><w:name w:val="heading 2"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="MySub"><w:name w:val="heading 3"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Quote"><w:name w:val="Quote"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="Caption"><w:name w:val="caption"/></w:style>'
    '<w:style w:type="paragraph" w:styleId="ListParagraph"><w:name w:val="List Paragraph"/></w:style>'
    '</w:styles>'
)

NUMBERING = HEAD + (
    f'<w:numbering xmlns:w="{W}">'
    '<w:abstractNum w:abstractNumId="3"><w:lvl w:ilvl="0"><w:numFmt w:val="bullet"/><w:lvlText w:val="•"/></w:lvl>'
    '<w:lvl w:ilvl="1"><w:numFmt w:val="bullet"/><w:lvlText w:val="o"/></w:lvl></w:abstractNum>'
    '<w:abstractNum w:abstractNumId="4"><w:lvl w:ilvl="0"><w:numFmt w:val="decimal"/><w:lvlText w:val="%1."/></w:lvl>'
    '<w:lvl w:ilvl="1"><w:numFmt w:val="lowerLetter"/><w:lvlText w:val="%2)"/></w:lvl></w:abstractNum>'
    '<w:num w:numId="5"><w:abstractNumId w:val="3"/></w:num>'
    '<w:num w:numId="6"><w:abstractNumId w:val="4"/></w:num>'
    '</w:numbering>'
)


def p(body, style=None, num=None, extra=''):
    props = ''
    if style:
        props += f'<w:pStyle w:val="{style}"/>'
    if num:
        props += f'<w:numPr><w:ilvl w:val="{num[1]}"/><w:numId w:val="{num[0]}"/></w:numPr>'
    props += extra
    return '<w:p>' + (f'<w:pPr>{props}</w:pPr>' if props else '') + body + '</w:p>'


def r(text, props=''):
    return '<w:r>' + (f'<w:rPr>{props}</w:rPr>' if props else '') + f'<w:t xml:space="preserve">{text}</w:t></w:r>'


def tc(text, span=1):
    pr = f'<w:tcPr><w:gridSpan w:val="{span}"/></w:tcPr>' if span > 1 else ''
    return f'<w:tc>{pr}' + p(r(text)) + '</w:tc>'


DRAWING = (
    '<w:r><w:drawing><wp:inline><wp:extent cx="952500" cy="952500"/>'
    '<wp:docPr id="1" name="Picture 1" descr="A cup of coffee"/>'
    '<a:graphic><a:graphicData uri="http://schemas.openxmlformats.org/drawingml/2006/picture"><pic:pic>'
    '<pic:blipFill><a:blip r:embed="rId7"/></pic:blipFill></pic:pic></a:graphicData></a:graphic>'
    '</wp:inline></w:drawing></w:r>'
)

BODY = ''.join([
    p(r('Café menu'), 'Title'),
    p(r('Breakfast'), 'Heading1'),
    p(
        r('Plain, ') + r('bold', '<w:b/>') + r(', ') + r('italic', '<w:i/>') + r(' and ') +
        r('under', '<w:u w:val="single"/>') + r(' not', '<w:u w:val="none"/>') + r(' ') + r('gone', '<w:strike/>') +
        r(' ') + r('red', '<w:color w:val="C00000"/>') + r(' ') + r('marked', '<w:highlight w:val="yellow"/>') +
        r(' ') + r('shaded', '<w:shd w:val="clear" w:color="auto" w:fill="DDEEFF"/>') + r(' ') +
        '<w:hyperlink r:id="rId9">' + r('our site', '<w:u w:val="single"/>') + '</w:hyperlink>' + r('.')
    ),
    p(r('Fresh') + '<w:r><w:tab/></w:r>' + r('daily') + '<w:r><w:br/></w:r>' + r('since 1990'), 'Heading2'),
    p(r('Toast'), 'ListParagraph', num=(5, 0)),
    p(r('Butter'), 'ListParagraph', num=(5, 1)),
    p(r('Coffee'), 'ListParagraph', num=(6, 0)),
    p(r('Oat milk'), 'ListParagraph', num=(6, 1)),
    p(r('☑ Open the doors')),
    p(r('Small print'), 'MySub'),
    p(r('Good food, good mood.'), 'Quote'),
    p(''),
    p('', extra='<w:pBdr><w:bottom w:val="single" w:sz="6" w:space="1" w:color="C9CCD3"/></w:pBdr>'),
    p(r('Before the break') + '<w:r><w:br w:type="page"/></w:r>' + r('after the break')),
    p(r('Starts a page'), extra='<w:pageBreakBefore/>'),
    '<w:sdt><w:sdtPr/><w:sdtContent>' + p(r('Inside a content control')) + '</w:sdtContent></w:sdt>',
    '<w:tbl><w:tblPr/><w:tblGrid><w:gridCol w:w="3000"/><w:gridCol w:w="3000"/><w:gridCol w:w="3000"/></w:tblGrid>'
    '<w:tr><w:trPr><w:tblHeader/></w:trPr>' + tc('Item') + tc('Size') + tc('Price') + '</w:tr>'
    '<w:tr>' + tc('Latte') + tc('Large &amp; hot', 2) + '</w:tr>'
    '</w:tbl>',
    p(r('A photo:') + DRAWING),
    p(r('Figure 1: our café'), 'Caption'),
    '<w:sectPr><w:pgSz w:w="11906" w:h="16838"/><w:pgMar w:top="1134" w:right="1134" w:bottom="1134" w:left="1134"/></w:sectPr>',
])

DOCUMENT = HEAD + (
    f'<w:document xmlns:w="{W}" xmlns:r="{R}" '
    'xmlns:wp="http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing" '
    'xmlns:a="http://schemas.openxmlformats.org/drawingml/2006/main" '
    'xmlns:pic="http://schemas.openxmlformats.org/drawingml/2006/picture">'
    f'<w:body>{BODY}</w:body></w:document>'
)


def main():
    if len(sys.argv) > 2:
        sys.exit(__doc__)
    entries = [
        ('[Content_Types].xml', CONTENT_TYPES.encode()),
        ('_rels/.rels', RELS.encode()),
        ('word/document.xml', DOCUMENT.encode()),
        ('word/styles.xml', STYLES.encode()),
        ('word/numbering.xml', NUMBERING.encode()),
        ('word/_rels/document.xml.rels', DOC_RELS.encode()),
        ('word/media/image1.png', PNG),
    ]
    with zipfile.ZipFile(OUT, 'w', zipfile.ZIP_DEFLATED) as z:
        for name, data in entries:
            info = zipfile.ZipInfo(name, date_time=(2026, 1, 1, 0, 0, 0))
            info.compress_type = zipfile.ZIP_DEFLATED
            info.external_attr = 0o644 << 16
            z.writestr(info, data)
    print(f'{OUT.stat().st_size} bytes written to {OUT}')
    if len(sys.argv) == 2:
        folder = pathlib.Path(sys.argv[1])
        folder.mkdir(parents=True, exist_ok=True)
        shutil.copyfile(OUT, folder / 'word.docx')
        print(f'word.docx copied to {folder}')


if __name__ == '__main__':
    main()
