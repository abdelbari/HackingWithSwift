// A Word document (.docx) opened as a Doc — the Android twin's DocxReader,
// rule for rule, with the same fixture (Tests/Fixtures/word.docx, written by
// Tools/generate_docx_fixture.py). DocxWriter goes the other way, and a Doc
// it wrote reads back as the same blocks.
//
// What is read, and how, where the format left a choice:
//
//  - word/document.xml through the package's relationships, its styles,
//    numbering and its own relationships beside it;
//  - a paragraph's type by its w:pStyle — the style's id or name, letters
//    and digits only, case aside: Title a title, Heading1 h1, Heading2 h2,
//    Heading3 to Heading9 h3, Quote and IntenseQuote a quote, Caption a
//    caption; any other a paragraph;
//  - a paragraph with a w:numPr (a numId other than 0) a list item,
//    numbered unless numbering.xml gives its level the "bullet" format (a
//    level it does not know is a bullet), its w:ilvl its level, held to 0
//    to TextLists.maxLevel; a paragraph that starts "☐ " or "☑ " a
//    checklist item, ticked for ☑;
//  - runs: w:b, w:i, w:u (but "none") and w:strike — each but a w:val of
//    "0", "false" or "off" — as RichText's markers; w:color (but "auto") a
//    span's colour, w:highlight's named colour or w:shd's fill (but "auto")
//    its highlight, a w:hyperlink's external target its link (a run's
//    character style, w:rStyle, such as the Hyperlink look DocxWriter gives
//    a link, is not read: only its own properties are); a w:t its words,
//    w:tab a tab, w:br and w:cr a line break; spans alike side by side
//    joined (Spans.normalised);
//  - a w:br of type "page", or w:pageBreakBefore, a page break, the words
//    either side of it blocks of their own; a w:drawing's a:blip an image
//    block — its picture "media:<name>" (ImportedDoc.media) — its alt text
//    wp:docPr's descr, the words before it a block of their own;
//  - an empty paragraph is left out, but one with a bottom border, which is
//    a divider;
//  - a w:tbl a table: a row per w:tr, a cell per w:tc — its paragraphs'
//    plain words joined by line breaks, and blank cells after it for its
//    w:gridSpan — the first row the header when it has w:tblHeader;
//  - a w:sdt's content as if it stood there; anything else in the body a
//    paragraph of its plain words, when it has any;
//  - the last w:sectPr's page size the nearer of A4 and Letter, by how far
//    its width and height are from each, and its left margin the margins,
//    in points (twips ÷ 20), held to 0 to 216.

import Foundation
import UniformTypeIdentifiers

enum DocxReader {

    static let fileExtension = "docx"

    /// The Word document type, for Import and Open in.
    static var contentType: UTType {
        UTType("org.openxmlformats.wordprocessingml.document") ?? UTType(filenameExtension: fileExtension) ?? .data
    }

    /// The most of a file that is opened, as a deck is held to.
    static let maxFileBytes = PptxReader.maxFileBytes

    static var notADocument: String { tr("That file isn't a Word document.") }
    static var tooBig: String { tr("That Word document is too big to open.") }

    private static let mediaPrefix = "media:"

    /// A document read: the Doc, and each picture it shows as
    /// "media:<name>" with the part of the file its bytes are in.
    struct ImportedDoc {
        var design: Design
        var media: [String: String]
    }

    /// "Café menu" for "Café menu.docx"; an untitled design's name for none.
    static func title(fromFile fileName: String?) -> String {
        let name = String((fileName ?? "").split(separator: "/", omittingEmptySubsequences: false).last ?? "")
            .trimmingCharacters(in: .whitespacesAndNewlines)
        let ending = ".\(fileExtension)"
        var bare = name
        if name.lowercased().hasSuffix(ending) {
            bare = String(name.dropLast(ending.count)).trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return bare.isEmpty ? Design().title : bare
    }

    static func read(_ data: Data, title: String) -> ImportedDoc? {
        PptxReader.Parts.of(data).flatMap { read(parts: $0, title: title) }
    }

    /// The document `parts` hold as a Doc called `title`; nil when they
    /// hold no Word document.
    static func read(parts: PptxReader.Parts, title: String) -> ImportedDoc? {
        WordReader(parts: parts).read(title: title)
    }

    /// `imported`'s Doc with its pictures where the phone stored them:
    /// "media:<name>" as `stored` gives it; an image block whose picture was
    /// not stored is left out.
    static func placed(_ imported: ImportedDoc, stored: [String: String]) -> ImportedDoc {
        let blocks = Docs.blocks(imported.design).compactMap { b -> DocBlock? in
            guard b.type == Docs.image, let src = b.src, src.hasPrefix(mediaPrefix) else { return b }
            guard let to = stored[String(src.dropFirst(mediaPrefix.count))] else { return nil }
            var out = b
            out.src = to
            return out
        }
        return ImportedDoc(design: Docs.withBlocks(imported.design, blocks), media: imported.media)
    }

    // MARK: the XML

    /// `node`'s attribute `key`, written with its prefix or without.
    fileprivate static func attr(_ node: SvgImport.Node?, _ key: String) -> String? {
        guard let node else { return nil }
        if let exact = node.attributes[key] { return exact }
        return node.attributes.first { $0.key.split(separator: ":").last.map(String.init) == key }?.value
    }

    fileprivate static func child(_ node: SvgImport.Node?, _ name: String) -> SvgImport.Node? {
        node?.children.first { $0.name == name }
    }

    fileprivate static func all(_ node: SvgImport.Node?, _ name: String) -> [SvgImport.Node] {
        node?.children.filter { $0.name == name } ?? []
    }

    /// A w:val that does not turn the property off.
    fileprivate static func on(_ node: SvgImport.Node?) -> Bool {
        guard let node else { return false }
        guard let v = attr(node, "val")?.lowercased() else { return true }
        return v != "0" && v != "false" && v != "off" && v != "none"
    }

    fileprivate static let highlights: [String: String] = [
        "yellow": "#ffff00", "green": "#00ff00", "cyan": "#00ffff", "magenta": "#ff00ff", "blue": "#0000ff",
        "red": "#ff0000", "darkblue": "#000080", "darkcyan": "#008080", "darkgreen": "#008000",
        "darkmagenta": "#800080", "darkred": "#800000", "darkyellow": "#808000", "darkgray": "#808080",
        "lightgray": "#c0c0c0", "black": "#000000", "white": "#ffffff",
    ]

    /// Six hex digits as "#rrggbb"; nil for "auto" or anything else.
    fileprivate static func hex(_ v: String?) -> String? {
        guard let v, v.count == 6, v.allSatisfy({ $0.isLetter || $0.isNumber }), v.lowercased() != "auto" else { return nil }
        let out = "#" + v.lowercased()
        return ColorTools.rgb255(out) == nil ? nil : out
    }

    /// A style's id or name as a block type, or nil for none.
    fileprivate static func typeOf(_ style: String) -> String? {
        let key = String(style.lowercased().filter { $0.isLetter || $0.isNumber })
        switch key {
        case "title": return Docs.title
        case "heading1": return Docs.h1
        case "heading2": return Docs.h2
        case "heading3", "heading4", "heading5", "heading6", "heading7", "heading8", "heading9": return Docs.h3
        case "quote", "intensequote": return Docs.quote
        case "caption": return Docs.caption
        default: return nil
        }
    }
}

/// One paragraph's words as they are gathered: the plain words, each
/// character's style, and the spans over them.
private struct GatheredWords {
    var plain = ""
    /// UTF-16 units in `plain`, as spans count.
    var units = 0
    var styles: [RichText.Style] = []
    var spans: [TextSpan] = []

    var isEmpty: Bool { plain.isEmpty }
}

/// A document's parts read into blocks.
private final class WordReader {
    let parts: PptxReader.Parts
    var blocks: [DocBlock] = []
    var media: [String: String] = [:]
    var rels: [String: (target: String, mode: String?)] = [:]
    var styles: [String: String] = [:]
    var formats: [String: [Int: String]] = [:]
    var setup = DocPage()
    var folder = "word/"

    init(parts: PptxReader.Parts) {
        self.parts = parts
    }

    func xml(_ path: String) -> SvgImport.Node? {
        parts.bytes(path).flatMap { SvgImport.parse(String(decoding: $0, as: UTF8.self)) }
    }

    func read(title: String) -> DocxReader.ImportedDoc? {
        let officeDocument = DocxReader.all(xml("_rels/.rels"), "Relationship")
            .first { (DocxReader.attr($0, "Type") ?? "").hasSuffix("/officeDocument") }
        var main = DocxReader.attr(officeDocument, "Target") ?? "word/document.xml"
        if main.hasPrefix("/") { main.removeFirst() }
        if let slash = main.lastIndex(of: "/") { folder = String(main[...slash]) } else { folder = "" }
        guard let document = xml(main), document.name == "document" else { return nil }
        let name = main.split(separator: "/").last.map(String.init) ?? main
        for r in DocxReader.all(xml("\(folder)_rels/\(name).rels"), "Relationship") {
            guard let id = DocxReader.attr(r, "Id"), let target = DocxReader.attr(r, "Target") else { continue }
            rels[id] = (target, DocxReader.attr(r, "TargetMode"))
        }
        for s in DocxReader.all(xml("\(folder)styles.xml"), "style") {
            guard let id = DocxReader.attr(s, "styleId") else { continue }
            if let type = DocxReader.typeOf(id) ?? DocxReader.attr(DocxReader.child(s, "name"), "val").flatMap(DocxReader.typeOf) {
                styles[id] = type
            }
        }
        formats = numbering()
        guard let body = DocxReader.child(document, "body") else { return nil }
        walk(body.children)
        let design = Docs.withPageSetup(Docs.withBlocks(Docs.started(title, setup: setup), blocks), setup)
        return DocxReader.ImportedDoc(design: design, media: media)
    }

    /// Each numId's levels' formats, through its abstractNum.
    func numbering() -> [String: [Int: String]] {
        guard let root = xml("\(folder)numbering.xml") else { return [:] }
        var abstract: [String: [Int: String]] = [:]
        for a in DocxReader.all(root, "abstractNum") {
            var levels: [Int: String] = [:]
            for l in DocxReader.all(a, "lvl") {
                guard let level = DocxReader.attr(l, "ilvl").flatMap({ Int($0) }) else { continue }
                levels[level] = DocxReader.attr(DocxReader.child(l, "numFmt"), "val") ?? "bullet"
            }
            abstract[DocxReader.attr(a, "abstractNumId") ?? ""] = levels
        }
        var out: [String: [Int: String]] = [:]
        for n in DocxReader.all(root, "num") {
            let to = DocxReader.attr(DocxReader.child(n, "abstractNumId"), "val")
            out[DocxReader.attr(n, "numId") ?? ""] = to.flatMap { abstract[$0] } ?? [:]
        }
        return out
    }

    func walk(_ children: [SvgImport.Node]) {
        for node in children {
            switch node.name {
            case "p": paragraph(node)
            case "tbl": table(node)
            case "sdt": if let content = DocxReader.child(node, "sdtContent") { walk(content.children) }
            case "sectPr": section(node)
            case "bookmarkStart", "bookmarkEnd", "proofErr", "commentRangeStart", "commentRangeEnd": break
            default:
                let words = plain(node).trimmingCharacters(in: .whitespacesAndNewlines)
                if !words.isEmpty { blocks.append(DocBlock(type: Docs.p, text: RichText.escapeLiteral(words))) }
            }
        }
    }

    func section(_ node: SvgImport.Node) {
        let size = DocxReader.child(node, "pgSz")
        var paper = setup.size
        if let w = DocxReader.attr(size, "w").flatMap({ Double($0) }), let h = DocxReader.attr(size, "h").flatMap({ Double($0) }) {
            paper = abs(w - 11906) + abs(h - 16838) < abs(w - 12240) + abs(h - 15840) ? Docs.a4 : Docs.letter
        }
        let margins = DocxReader.attr(DocxReader.child(node, "pgMar"), "left").flatMap { Double($0) }
            .map { min(max($0 / 20, 0), 216) } ?? setup.margins
        setup = DocPage(size: paper, margins: margins)
    }

    /// Every w:t's words under `node`, tabs and breaks as they read.
    func plain(_ node: SvgImport.Node) -> String {
        var out = ""
        func go(_ n: SvgImport.Node) {
            switch n.name {
            case "t": out += n.text
            case "tab": out += "\t"
            case "br", "cr": out += "\n"
            case "p":
                if !out.isEmpty && !out.hasSuffix("\n") { out += "\n" }
                n.children.forEach(go)
            default: n.children.forEach(go)
            }
        }
        go(node)
        return out
    }

    func paragraph(_ p: SvgImport.Node) {
        let props = DocxReader.child(p, "pPr")
        if let sect = DocxReader.child(props, "sectPr") { section(sect) }
        let styleId = DocxReader.attr(DocxReader.child(props, "pStyle"), "val")
        var type = styleId.flatMap { styles[$0] ?? DocxReader.typeOf($0) } ?? Docs.p
        var level: Int?
        let num = DocxReader.child(props, "numPr")
        if let numId = DocxReader.attr(DocxReader.child(num, "numId"), "val"), numId != "0" {
            let ilvl = DocxReader.attr(DocxReader.child(num, "ilvl"), "val").flatMap { Int($0) } ?? 0
            type = (formats[numId]?[ilvl] ?? "bullet") == "bullet" ? Docs.bullet : Docs.number
            let held = min(max(ilvl, 0), TextLists.maxLevel)
            level = held > 0 ? held : nil
        }
        if let before = DocxReader.child(props, "pageBreakBefore"), DocxReader.on(before) { pageBreak() }
        var words = GatheredWords()
        func flush() {
            guard !words.isEmpty else { return }
            emit(type, level, words)
            words = GatheredWords()
        }
        func run(_ r: SvgImport.Node, link: String?) {
            let rp = DocxReader.child(r, "rPr")
            let style = RichText.Style(bold: DocxReader.on(DocxReader.child(rp, "b")),
                                       italic: DocxReader.on(DocxReader.child(rp, "i")),
                                       underline: DocxReader.on(DocxReader.child(rp, "u")),
                                       strike: DocxReader.on(DocxReader.child(rp, "strike")))
            let color = DocxReader.hex(DocxReader.attr(DocxReader.child(rp, "color"), "val"))
            let highlight = DocxReader.attr(DocxReader.child(rp, "highlight"), "val").flatMap { DocxReader.highlights[$0.lowercased()] }
                ?? DocxReader.hex(DocxReader.attr(DocxReader.child(rp, "shd"), "fill"))
            func add(_ s: String) {
                let start = words.units
                words.plain += s
                words.units += (s as NSString).length
                words.styles += Array(repeating: style, count: s.count)
                if color != nil || highlight != nil || link != nil {
                    words.spans.append(TextSpan(start: start, end: words.units, color: color, link: link, highlight: highlight))
                }
            }
            for c in r.children {
                switch c.name {
                case "t": add(c.text)
                case "tab": add("\t")
                case "noBreakHyphen": add("-")
                case "cr": add("\n")
                case "br":
                    if DocxReader.attr(c, "type") == "page" {
                        flush()
                        pageBreak()
                    } else {
                        add("\n")
                    }
                case "drawing", "pict":
                    flush()
                    image(c)
                default:
                    break
                }
            }
        }
        func inline(_ children: [SvgImport.Node], link: String?) {
            for c in children {
                switch c.name {
                case "r": run(c, link: link)
                case "hyperlink":
                    let target = DocxReader.attr(c, "id").flatMap { rels[$0] }
                        .flatMap { $0.mode?.lowercased() == "external" ? $0.target : nil }
                    inline(c.children, link: target ?? link)
                case "ins", "smartTag", "fldSimple", "sdtContent", "customXml": inline(c.children, link: link)
                case "sdt": if let content = DocxReader.child(c, "sdtContent") { inline(content.children, link: link) }
                default: break
                }
            }
        }
        inline(p.children, link: nil)
        if words.isEmpty {
            // An empty paragraph with a line under it is a divider.
            let bordered = DocxReader.child(DocxReader.child(props, "pBdr"), "bottom") != nil
            if bordered && !p.children.contains(where: { $0.name == "r" && !plain($0).isEmpty }) {
                blocks.append(DocBlock(type: Docs.divider))
            }
            return
        }
        flush()
    }

    func emit(_ type: String, _ level: Int?, _ words: GatheredWords) {
        var plain = words.plain
        var styles = words.styles
        var spans = words.spans
        var kind = type
        var checked: Bool?
        if kind == Docs.p && (plain.hasPrefix("☐ ") || plain.hasPrefix("☑ ")) {
            kind = Docs.checklist
            checked = plain.hasPrefix("☑")
            plain = String(plain.dropFirst(2))
            styles = Array(styles.dropFirst(2))
            spans = spans.compactMap { s -> TextSpan? in
                let out = s.over(max(0, s.start - 2), s.end - 2)
                return out.end > out.start ? out : nil
            }
        }
        let listed = kind == Docs.bullet || kind == Docs.number
        let block = DocBlock(type: kind, text: RichText.written(plain, styles: styles), checked: checked,
                             level: listed ? level : nil)
        blocks.append(Docs.withSpans(block, Spans.normalised(spans)))
    }

    func pageBreak() {
        blocks.append(DocBlock(type: Docs.pagebreak))
    }

    func image(_ drawing: SvgImport.Node) {
        func find(_ n: SvgImport.Node, _ name: String) -> SvgImport.Node? {
            if n.name == name { return n }
            for c in n.children {
                if let hit = find(c, name) { return hit }
            }
            return nil
        }
        guard let blip = find(drawing, "blip"), let id = DocxReader.attr(blip, "embed"),
              let rel = rels[id], rel.mode == nil else { return }
        let target = rel.target
        let path = target.hasPrefix("/") ? String(target.dropFirst())
            : folder + (target.hasPrefix("./") ? String(target.dropFirst(2)) : target)
        guard parts.has(path) else { return }
        let file = path.split(separator: "/").last.map(String.init) ?? path
        var key = media.first { $0.value == path }?.key
        if key == nil {
            var candidate = file
            var n = 2
            while media[candidate] != nil {
                candidate = "\(n)-\(file)"
                n += 1
            }
            media[candidate] = path
            key = candidate
        }
        let alt = DocxReader.attr(find(drawing, "docPr"), "descr")?.trimmingCharacters(in: .whitespacesAndNewlines)
        blocks.append(DocBlock(type: Docs.image, src: "media:" + (key ?? file), alt: alt?.isEmpty == false ? alt : nil))
    }

    func table(_ tbl: SvgImport.Node) {
        let rows = DocxReader.all(tbl, "tr")
        guard let firstRow = rows.first else { return }
        let cells = rows.map { tr -> [String] in
            DocxReader.all(tr, "tc").flatMap { tc -> [String] in
                let span = DocxReader.attr(DocxReader.child(DocxReader.child(tc, "tcPr"), "gridSpan"), "val")
                    .flatMap { Int($0) }.map { min(max($0, 1), TableCell.maxSpan) } ?? 1
                let words = DocxReader.all(tc, "p").map { para -> String in
                    var w = plain(para)
                    while w.hasSuffix("\n") { w.removeLast() }
                    return w
                }.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
                return [words] + Array(repeating: "", count: span - 1)
            }
        }
        let width = cells.map(\.count).max() ?? 0
        guard width > 0 else { return }
        let padded = cells.map { $0 + Array(repeating: "", count: width - $0.count) }
        let header = DocxReader.child(DocxReader.child(firstRow, "trPr"), "tblHeader").map(DocxReader.on) == true
        blocks.append(DocBlock(type: Docs.table, table: DocTable(rows: padded, header: header)))
    }
}
