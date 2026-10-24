// A Doc as a Microsoft Word document (.docx) — the export sheet's "Word
// document" — written the same on both phones: `documentXml` is byte for
// byte the Android twin's DocxWriter's for the same Doc (the shared fixture,
// Tests/Fixtures/doc-document.xml, checks it).
//
//  - h1–h3 as paragraphs in the Heading1–Heading3 styles, a quote in Quote,
//    a paragraph in Normal; each RichText run its own w:r, bold, italic,
//    underlined or struck as marked, and coloured, highlighted (a w:shd
//    fill) or linked (a w:hyperlink, in the link colour and underlined
//    unless coloured) as its block's spans say; a block's alignment its
//    w:jc.
//  - bullets and numbers as list paragraphs (numbering.xml: numId 1
//    bullets, numId 2 decimal), a checklist item behind ☐ or ☑.
//  - a divider as an empty paragraph with a bottom border, a page break as
//    a w:br of type page.
//  - a table as w:tbl, its columns sharing the text's width, the header
//    row's cells bold and repeated on each page, then an empty paragraph.
//  - an image or a chart as a PNG in word/media — imageN.png, N counting
//    them from 1 in order — drawn inline the text's width across and 0.6 of
//    that tall (Docs.pictureRatio), its descr the alt text (a chart's
//    summary when it has none); an image block with no picture is left out.
//  - the page's size (A4 11906 × 16838 or Letter 12240 × 15840 twips) and
//    its margins (points × 20) in the section.
//
// The parts go into a ZIP as the PowerPoint export's do (ZipWriter).

import Foundation

enum DocxWriter {

    static let fileExtension = "docx"
    static let mime = "application/vnd.openxmlformats-officedocument.wordprocessingml.document"

    private static let w = "http://schemas.openxmlformats.org/wordprocessingml/2006/main"
    private static let r = "http://schemas.openxmlformats.org/officeDocument/2006/relationships"
    private static let wp = "http://schemas.openxmlformats.org/drawingml/2006/wordprocessingDrawing"
    private static let a = "http://schemas.openxmlformats.org/drawingml/2006/main"
    private static let pic = "http://schemas.openxmlformats.org/drawingml/2006/picture"
    private static let head = "<?xml version=\"1.0\" encoding=\"UTF-8\" standalone=\"yes\"?>\n"

    /// EMU in a page pixel at 96 dpi.
    private static let emuPerPx = 9525.0

    /// The blocks drawn as pictures, in order: images with a picture, and
    /// charts.
    static func pictures(_ design: Design) -> [DocBlock] {
        Docs.blocks(design).filter { ($0.type == Docs.image && $0.src != nil) || ($0.type == Docs.chart && Docs.chartSpec($0) != nil) }
    }

    private static func twips(_ setup: DocPage) -> (w: Int, h: Int) {
        setup.size == Docs.a4 ? (11906, 16838) : (12240, 15840)
    }

    private static func esc(_ s: String) -> String { SVGExporter.escape(s) }

    /// Rounds half away from zero, as Kotlin's roundToLong rounds half up
    /// for the positive numbers written here.
    private static func whole(_ v: Double) -> Int { Int((v).rounded(.toNearestOrAwayFromZero)) }

    /// A colour as w:val and w:fill take it: six hex digits, upper case,
    /// its alpha dropped.
    private static func hex(_ colour: String) -> String {
        String(RecentColors.normalise(colour).dropFirst().prefix(6)).uppercased()
    }

    /// A paragraph's runs: each stretch alike — its RichText run's style
    /// and its span's (Spans, `spans` over the words as they read) colour,
    /// highlight and link — as a w:r, a line break in it a w:br: a colour a
    /// w:color, a highlight a w:shd fill, a linked stretch inside a
    /// w:hyperlink to its relationship in `links`, drawn in the link colour
    /// and underlined unless it has a colour of its own.
    private static func runs(_ markup: String, bold: Bool = false, spans: [TextSpan] = [],
                             links: [String: String] = [:]) -> String {
        let parsed = RichText.parse(markup)
        let plain = parsed.plain as NSString
        let length = plain.length
        var edges = [0, length]
        for run in parsed.runs { edges += [run.range.location, run.range.location + run.range.length] }
        for span in spans { edges += [span.start, span.end] }
        let cuts = Array(Set(edges.filter { $0 >= 0 && $0 <= length })).sorted()
        var out = ""
        for k in 0..<max(0, cuts.count - 1) {
            let from = cuts[k], to = cuts[k + 1]
            guard from < to else { continue }
            let style = parsed.runs.first { from >= $0.range.location && to <= $0.range.location + $0.range.length }?.style
                ?? RichText.Style()
            let span = spans.first { from >= $0.start && to <= $0.end }
            let link = span?.link.flatMap { links[$0] }
            out += run(plain.substring(with: NSRange(location: from, length: to - from)),
                       props: props(style, bold: bold, span: span, linked: link != nil), link: link)
        }
        return out
    }

    /// A stretch's w:rPr: bold, italic, its colour — the link colour for a
    /// link with none of its own — underline, strike and highlight.
    private static func props(_ style: RichText.Style, bold: Bool, span: TextSpan?, linked: Bool) -> String {
        var props = ""
        if bold || style.bold { props += "<w:b/>" }
        if style.italic { props += "<w:i/>" }
        if let colour = span?.color ?? (linked ? Spans.linkColour : nil) { props += "<w:color w:val=\"\(hex(colour))\"/>" }
        if style.underline || (linked && span?.color == nil) { props += "<w:u w:val=\"single\"/>" }
        if style.strike { props += "<w:strike/>" }
        if let highlight = span?.highlight {
            props += "<w:shd w:val=\"clear\" w:color=\"auto\" w:fill=\"\(hex(highlight))\"/>"
        }
        return props
    }

    /// One w:r of `words` — a w:br for each line break — inside a
    /// w:hyperlink to relationship `link` when it has one.
    private static func run(_ words: String, props: String, link: String?) -> String {
        var out = link.map { "<w:hyperlink r:id=\"\($0)\">" } ?? ""
        out += "<w:r>"
        if !props.isEmpty { out += "<w:rPr>" + props + "</w:rPr>" }
        for (i, line) in words.components(separatedBy: "\n").enumerated() {
            if i > 0 { out += "<w:br/>" }
            out += "<w:t xml:space=\"preserve\">" + esc(line) + "</w:t>"
        }
        out += "</w:r>"
        if link != nil { out += "</w:hyperlink>" }
        return out
    }

    /// A block's words as runs, after `prefix` (a checklist's box), its
    /// spans moved past it.
    private static func runs(_ block: DocBlock, prefix: String = "", links: [String: String]) -> String {
        let spans = Docs.moved(Docs.spansOf(block), by: (prefix as NSString).length)
        return runs(prefix + block.text, spans: spans, links: links)
    }

    private static func paragraph(_ style: String?, _ body: String, numId: Int? = nil, align: String? = nil) -> String {
        var props = ""
        if let style { props += "<w:pStyle w:val=\"\(style)\"/>" }
        if let numId { props += "<w:numPr><w:ilvl w:val=\"0\"/><w:numId w:val=\"\(numId)\"/></w:numPr>" }
        if let jc = jc(align) { props += "<w:jc w:val=\"\(jc)\"/>" }
        return "<w:p>" + (props.isEmpty ? "" : "<w:pPr>" + props + "</w:pPr>") + body + "</w:p>"
    }

    /// A block's alignment as w:jc says it; none for left.
    private static func jc(_ align: String?) -> String? {
        switch align {
        case "center": return "center"
        case "right": return "right"
        case "justify": return "both"
        default: return nil
        }
    }

    /// The web addresses the Doc's words link to, each once in the order
    /// first met, with its relationship id: after the styles, the numbering
    /// and the pictures.
    static func links(_ design: Design) -> [String: String] {
        var urls: [String] = []
        for block in Docs.blocks(design) where Docs.textTypes.contains(block.type) {
            for url in Docs.spansOf(block).compactMap(\.link) where !urls.contains(url) { urls.append(url) }
        }
        let first = pictures(design).count + 3
        var out: [String: String] = [:]
        for (i, url) in urls.enumerated() { out[url] = "rId\(first + i)" }
        return out
    }

    /// The same links in the order their relationships are written.
    private static func orderedLinks(_ links: [String: String]) -> [(url: String, id: String)] {
        links.map { (url: $0.key, id: $0.value) }.sorted { (Int($0.id.dropFirst(3)) ?? 0) < (Int($1.id.dropFirst(3)) ?? 0) }
    }

    /// The document's body, as word/document.xml holds it.
    static func documentXml(_ design: Design) -> String {
        let setup = Docs.pageSetup(design)
        let page = twips(setup)
        let margin = whole(setup.margins * 20)
        let textPx = Double(Docs.pageSize(setup).width) - 2 * Docs.margin(setup)
        let cx = whole(textPx * emuPerPx)
        let cy = whole(textPx * Docs.pictureRatio * emuPerPx)
        let textTwips = page.w - 2 * margin
        var out = head
        out += "<w:document xmlns:w=\"\(w)\" xmlns:r=\"\(r)\" xmlns:wp=\"\(wp)\" xmlns:a=\"\(a)\" xmlns:pic=\"\(pic)\"><w:body>"
        var picture = 0
        let linked = links(design)
        for b in Docs.blocks(design) {
            switch b.type {
            case Docs.h1: out += paragraph("Heading1", runs(b, links: linked), align: b.align)
            case Docs.h2: out += paragraph("Heading2", runs(b, links: linked), align: b.align)
            case Docs.h3: out += paragraph("Heading3", runs(b, links: linked), align: b.align)
            case Docs.quote: out += paragraph("Quote", runs(b, links: linked), align: b.align)
            case Docs.p: out += paragraph(nil, runs(b, links: linked), align: b.align)
            case Docs.bullet: out += paragraph("ListParagraph", runs(b, links: linked), numId: 1, align: b.align)
            case Docs.number: out += paragraph("ListParagraph", runs(b, links: linked), numId: 2, align: b.align)
            case Docs.checklist:
                let box = b.checked == true ? "☑ " : "☐ "
                out += paragraph(nil, runs(b, prefix: box, links: linked), align: b.align)
            case Docs.divider:
                out += "<w:p><w:pPr><w:pBdr><w:bottom w:val=\"single\" w:sz=\"6\" w:space=\"1\" w:color=\"C9CCD3\"/></w:pBdr></w:pPr></w:p>"
            case Docs.pagebreak: out += "<w:p><w:r><w:br w:type=\"page\"/></w:r></w:p>"
            case Docs.table: out += tableXml(b, textTwips: textTwips)
            case Docs.image, Docs.chart:
                if b.type == Docs.image && b.src == nil { continue }
                if b.type == Docs.chart && Docs.chartSpec(b) == nil { continue }
                picture += 1
                out += drawing(picture, descr: esc(Docs.altOf(b) ?? ""), cx: cx, cy: cy)
            default: break
            }
        }
        out += "<w:sectPr><w:pgSz w:w=\"\(page.w)\" w:h=\"\(page.h)\"/><w:pgMar w:top=\"\(margin)\" w:right=\"\(margin)\" "
            + "w:bottom=\"\(margin)\" w:left=\"\(margin)\" w:header=\"720\" w:footer=\"720\" w:gutter=\"0\"/></w:sectPr>"
        out += "</w:body></w:document>"
        return out
    }

    /// A table block as w:tbl, then an empty paragraph; nothing for one
    /// with no cells.
    private static func tableXml(_ b: DocBlock, textTwips: Int) -> String {
        let (rows, header) = Docs.tableRows(b)
        let columns = rows.map(\.count).max() ?? 0
        guard columns > 0 else { return "" }
        let col = textTwips / columns
        var out = "<w:tbl><w:tblPr><w:tblStyle w:val=\"TableGrid\"/><w:tblW w:w=\"\(col * columns)\" w:type=\"dxa\"/></w:tblPr><w:tblGrid>"
        for _ in 0..<columns { out += "<w:gridCol w:w=\"\(col)\"/>" }
        out += "</w:tblGrid>"
        for (r, row) in rows.enumerated() {
            let head = header && r == 0
            out += "<w:tr>"
            if head { out += "<w:trPr><w:tblHeader/></w:trPr>" }
            for c in 0..<columns {
                out += "<w:tc><w:tcPr><w:tcW w:w=\"\(col)\" w:type=\"dxa\"/></w:tcPr>"
                out += paragraph(nil, runs(RichText.escapeLiteral(c < row.count ? row[c] : ""), bold: head))
                out += "</w:tc>"
            }
            out += "</w:tr>"
        }
        return out + "</w:tbl><w:p/>"
    }

    /// Picture `n` drawn inline, `cx` × `cy` EMU, its descr the alt text.
    private static func drawing(_ n: Int, descr: String, cx: Int, cy: Int) -> String {
        "<w:p><w:r><w:drawing><wp:inline distT=\"0\" distB=\"0\" distL=\"0\" distR=\"0\"><wp:extent cx=\"\(cx)\" cy=\"\(cy)\"/>"
            + "<wp:docPr id=\"\(n)\" name=\"Picture \(n)\" descr=\"\(descr)\"/>"
            + "<a:graphic><a:graphicData uri=\"\(pic)\"><pic:pic><pic:nvPicPr><pic:cNvPr id=\"\(n)\" name=\"image\(n).png\" "
            + "descr=\"\(descr)\"/><pic:cNvPicPr/></pic:nvPicPr>"
            + "<pic:blipFill><a:blip r:embed=\"rId\(n + 2)\"/><a:stretch><a:fillRect/></a:stretch></pic:blipFill>"
            + "<pic:spPr><a:xfrm><a:off x=\"0\" y=\"0\"/><a:ext cx=\"\(cx)\" cy=\"\(cy)\"/></a:xfrm>"
            + "<a:prstGeom prst=\"rect\"><a:avLst/></a:prstGeom></pic:spPr>"
            + "</pic:pic></a:graphicData></a:graphic></wp:inline></w:drawing></w:r></w:p>"
    }

    private static func contentTypes(_ pictures: Int) -> String {
        var out = head + "<Types xmlns=\"http://schemas.openxmlformats.org/package/2006/content-types\">"
        out += "<Default Extension=\"rels\" ContentType=\"application/vnd.openxmlformats-package.relationships+xml\"/>"
        out += "<Default Extension=\"xml\" ContentType=\"application/xml\"/>"
        if pictures > 0 { out += "<Default Extension=\"png\" ContentType=\"image/png\"/>" }
        out += "<Override PartName=\"/word/document.xml\" "
            + "ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.document.main+xml\"/>"
        out += "<Override PartName=\"/word/styles.xml\" "
            + "ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.styles+xml\"/>"
        out += "<Override PartName=\"/word/numbering.xml\" "
            + "ContentType=\"application/vnd.openxmlformats-officedocument.wordprocessingml.numbering+xml\"/>"
        out += "<Override PartName=\"/docProps/core.xml\" "
            + "ContentType=\"application/vnd.openxmlformats-package.core-properties+xml\"/>"
        return out + "</Types>"
    }

    private static var rels: String {
        head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
            + "<Relationship Id=\"rId1\" Type=\"http://schemas.openxmlformats.org/officeDocument/2006/relationships/officeDocument\" "
            + "Target=\"word/document.xml\"/>"
            + "<Relationship Id=\"rId2\" Type=\"http://schemas.openxmlformats.org/package/2006/relationships/metadata/core-properties\" "
            + "Target=\"docProps/core.xml\"/>"
            + "</Relationships>"
    }

    private static func documentRels(_ pictures: Int, links: [String: String] = [:]) -> String {
        var out = head + "<Relationships xmlns=\"http://schemas.openxmlformats.org/package/2006/relationships\">"
        out += "<Relationship Id=\"rId1\" Type=\"\(r)/styles\" Target=\"styles.xml\"/>"
        out += "<Relationship Id=\"rId2\" Type=\"\(r)/numbering\" Target=\"numbering.xml\"/>"
        for n in stride(from: 1, through: pictures, by: 1) {
            out += "<Relationship Id=\"rId\(n + 2)\" Type=\"\(r)/image\" Target=\"media/image\(n).png\"/>"
        }
        for link in orderedLinks(links) {
            out += "<Relationship Id=\"\(link.id)\" Type=\"\(r)/hyperlink\" Target=\"\(esc(link.url))\" TargetMode=\"External\"/>"
        }
        return out + "</Relationships>"
    }

    private static func core(_ design: Design) -> String {
        head + "<cp:coreProperties xmlns:cp=\"http://schemas.openxmlformats.org/package/2006/metadata/core-properties\" "
            + "xmlns:dc=\"http://purl.org/dc/elements/1.1/\">"
            + "<dc:title>\(esc(design.title))</dc:title><dc:creator>\(PDFMetadata.creator)</dc:creator></cp:coreProperties>"
    }

    /// The styles: Normal, Heading1–3 at the Doc's sizes (Docs.fontSize, in
    /// half-points at 72 dpi), Quote, ListParagraph and TableGrid, in
    /// `heading` and `body`'s faces.
    static func stylesXml(heading: String, body: String) -> String {
        func font(_ face: String) -> String {
            "<w:rFonts w:ascii=\"\(esc(face))\" w:hAnsi=\"\(esc(face))\" w:cs=\"\(esc(face))\"/>"
        }
        func half(_ type: String) -> Int { whole(Docs.fontSize(type) * 72 / 96 * 2) }
        func headingStyle(_ n: Int, _ type: String) -> String {
            "<w:style w:type=\"paragraph\" w:styleId=\"Heading\(n)\"><w:name w:val=\"heading \(n)\"/><w:basedOn w:val=\"Normal\"/>"
                + "<w:next w:val=\"Normal\"/><w:qFormat/><w:pPr><w:keepNext/><w:spacing w:before=\"240\" w:after=\"120\"/>"
                + "<w:outlineLvl w:val=\"\(n - 1)\"/></w:pPr><w:rPr>\(font(heading))<w:b/><w:sz w:val=\"\(half(type))\"/></w:rPr></w:style>"
        }
        let borders = ["top", "left", "bottom", "right", "insideH", "insideV"]
            .map { "<w:\($0) w:val=\"single\" w:sz=\"4\" w:space=\"0\" w:color=\"C9CCD3\"/>" }.joined()
        var out = head + "<w:styles xmlns:w=\"\(w)\">"
        out += "<w:docDefaults><w:rPrDefault><w:rPr>\(font(body))<w:sz w:val=\"\(half(Docs.p))\"/></w:rPr></w:rPrDefault>"
            + "<w:pPrDefault><w:pPr><w:spacing w:after=\"160\" w:line=\"324\" w:lineRule=\"auto\"/></w:pPr></w:pPrDefault></w:docDefaults>"
        out += "<w:style w:type=\"paragraph\" w:default=\"1\" w:styleId=\"Normal\"><w:name w:val=\"Normal\"/><w:qFormat/></w:style>"
        out += headingStyle(1, Docs.h1) + headingStyle(2, Docs.h2) + headingStyle(3, Docs.h3)
        out += "<w:style w:type=\"paragraph\" w:styleId=\"Quote\"><w:name w:val=\"Quote\"/><w:basedOn w:val=\"Normal\"/><w:qFormat/>"
            + "<w:pPr><w:ind w:left=\"720\" w:right=\"720\"/></w:pPr><w:rPr><w:i/><w:sz w:val=\"\(half(Docs.quote))\"/></w:rPr></w:style>"
        out += "<w:style w:type=\"paragraph\" w:styleId=\"ListParagraph\"><w:name w:val=\"List Paragraph\"/><w:basedOn w:val=\"Normal\"/>"
            + "<w:pPr><w:ind w:left=\"720\"/><w:contextualSpacing/></w:pPr></w:style>"
        out += "<w:style w:type=\"table\" w:styleId=\"TableGrid\"><w:name w:val=\"Table Grid\"/><w:tblPr><w:tblBorders>"
            + borders + "</w:tblBorders><w:tblCellMar><w:left w:w=\"108\" w:type=\"dxa\"/><w:right w:w=\"108\" w:type=\"dxa\"/>"
            + "</w:tblCellMar></w:tblPr></w:style>"
        return out + "</w:styles>"
    }

    /// Bullets (numId 1) and decimal numbers (numId 2), one level each.
    static var numbering: String {
        head + "<w:numbering xmlns:w=\"\(w)\">"
            + "<w:abstractNum w:abstractNumId=\"0\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/>"
            + "<w:numFmt w:val=\"bullet\"/><w:lvlText w:val=\"•\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"720\" w:hanging=\"360\"/>"
            + "</w:pPr></w:lvl></w:abstractNum>"
            + "<w:abstractNum w:abstractNumId=\"1\"><w:multiLevelType w:val=\"singleLevel\"/><w:lvl w:ilvl=\"0\"><w:start w:val=\"1\"/>"
            + "<w:numFmt w:val=\"decimal\"/><w:lvlText w:val=\"%1.\"/><w:lvlJc w:val=\"left\"/><w:pPr><w:ind w:left=\"720\" w:hanging=\"360\"/>"
            + "</w:pPr></w:lvl></w:abstractNum>"
            + "<w:num w:numId=\"1\"><w:abstractNumId w:val=\"0\"/></w:num><w:num w:numId=\"2\"><w:abstractNumId w:val=\"1\"/></w:num>"
            + "</w:numbering>"
    }

    /// A white pixel, for a picture that could not be drawn: the file still
    /// opens, and document.xml stays the same.
    static let blankPNG = Data(base64Encoded:
        "iVBORw0KGgoAAAANSUhEUgAAAAEAAAABCAYAAAAfFcSJAAAADUlEQVR42mP8/x8AAwMCAO+ip1sAAAAASUVORK5CYII=") ?? Data()

    /// The whole .docx, a part at a time into `sink`: document.xml
    /// (`documentXml`), the styles in `heading` and `body`'s faces, the
    /// numbering, and each picture (`pictures`, in order) as the PNG `png`
    /// draws of it — the text's width across, 0.6 of it tall — or a blank
    /// pixel when it cannot.
    static func write(_ design: Design, heading: String = "Calibri", body: String = "Calibri",
                      png: (DocBlock) -> Data?, sink: @escaping (Data) throws -> Void) throws {
        let pictures = pictures(design)
        let zip = ZipWriter(sink: sink)
        try zip.add("[Content_Types].xml", Data(contentTypes(pictures.count).utf8))
        try zip.add("_rels/.rels", Data(rels.utf8))
        try zip.add("docProps/core.xml", Data(core(design).utf8))
        try zip.add("word/document.xml", Data(documentXml(design).utf8))
        try zip.add("word/styles.xml", Data(stylesXml(heading: heading, body: body).utf8))
        try zip.add("word/numbering.xml", Data(numbering.utf8))
        try zip.add("word/_rels/document.xml.rels", Data(documentRels(pictures.count, links: links(design)).utf8))
        for (i, block) in pictures.enumerated() {
            try zip.add("word/media/image\(i + 1).png", png(block) ?? blankPNG)
        }
        try zip.finish()
    }
}
