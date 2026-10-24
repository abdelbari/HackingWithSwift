// A tagged PDF's structure — the shared rule both phones write it by, so the
// same design gives the same outline on either (the Android twin's
// PdfTags): each shown page a /Sect, and in it, in reading order
// (CanvasAccessibility.readingOrder, the master's elements too), each
// element's role.
//
//  - Text, and a shape's words: the Text panel's Read as ("a11yRole") when
//    set — "artifact" leaves it out — else its role (TextRoles): a title and
//    a first-level heading /H1, then /H2, /H3, body /P, a quote /BlockQuote
//    and a caption /Caption. A box with list paragraphs and no Read as is an
//    /L, an /LI with an /LBody for each item.
//  - A table: /Table, a /TR a row, its cells /TD — the first row's /TH when
//    the table has a header row (DataGraphics.tableHasHeader).
//  - A chart: one /Figure for all its parts, its /Alt the chart's summary
//    (ChartSpeech). A photo, sticker or icon with alt text: a /Figure with
//    it as /Alt.
//  - Everything else — shapes without words, lines, decorative pictures and
//    a picture with no alt text, which has nothing to say — is an /Artifact.
//
// Neither phone's drawing can tag as it goes — here every page is one
// SwiftUI picture (DesignExporter) — so the exporter draws a sentinel before
// each element (`sentinelComponents`) and `mark` turns each into the marked
// content it opens; PDFUpdate writes the structure tree, as the twin's
// PdfLinks does.

import Foundation

enum PdfTags {

    static let h1 = "H1"
    static let h2 = "H2"
    static let h3 = "H3"
    static let p = "P"
    static let blockQuote = "BlockQuote"
    static let caption = "Caption"
    static let l = "L"
    static let li = "LI"
    static let lBody = "LBody"
    static let table = "Table"
    static let tr = "TR"
    static let th = "TH"
    static let td = "TD"
    static let figure = "Figure"
    static let sect = "Sect"
    static let document = "Document"

    /// One structure element: its role, the elements whose drawing it owns
    /// (each sentinel's marked content becomes one of its kids), its /Alt
    /// (a figure's) and its /ActualText (a list item's or a cell's words,
    /// where the drawing belongs to the element above it), and its children.
    struct StructNode: Equatable {
        var role: String
        var ids: [String] = []
        var alt: String? = nil
        var text: String? = nil
        var kids: [StructNode] = []
    }

    /// The structure role `el`'s words take, or nil for an artifact.
    static func textRole(_ el: Element, in design: Design) -> String? {
        if let read = TextRoles.readAs(el) {
            switch read {
            case TextRoles.h1: return h1
            case TextRoles.h2: return h2
            case TextRoles.h3: return h3
            case TextRoles.readP: return p
            default: return nil
            }
        }
        if el.type == .text && TextLists.isList(el) { return l }
        guard let role = TextRoles.of(el, in: design) else { return nil }
        switch role {
        case TextRoles.title, TextRoles.h1: return h1
        case TextRoles.h2: return h2
        case TextRoles.h3: return h3
        case TextRoles.quote: return blockQuote
        case TextRoles.caption: return caption
        default: return p
        }
    }

    /// `page`'s structure, in reading order: what goes in its /Sect.
    static func page(_ design: Design, _ page: Page) -> [StructNode] {
        let elements = design.drawnElements(on: page)
        let byId = Dictionary(elements.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var done: Set<String> = []
        var out: [StructNode] = []
        let order = CanvasAccessibility.readingOrder(elements, pageHeight: Double(design.size(for: page).height))
        for id in order {
            guard let el = byId[id] else { continue }
            if let cell = el.table {
                if done.insert("table:" + cell.id).inserted { out.append(tableNode(elements, id: cell.id)) }
                continue
            }
            if let chart = el.chart, el.chartPart != nil {
                guard done.insert("chart:" + chart.id).inserted else { continue }
                let parts = elements.filter { $0.chart?.id == chart.id }.map(\.id)
                out.append(StructNode(role: figure, ids: parts, alt: ChartSpeech.summary(of: el)))
                continue
            }
            if el.decorative == true { continue }
            if AccessibilityAudit.hasWords(el) {
                guard let role = textRole(el, in: design) else { continue }
                out.append(role == l ? listNode(el) : StructNode(role: role, ids: [el.id]))
                continue
            }
            if AccessibilityAudit.isPicture(el) {
                let alt = (el.altText ?? "").trimmingCharacters(in: .whitespacesAndNewlines)
                guard !alt.isEmpty else { continue }
                out.append(StructNode(role: figure, ids: [el.id], alt: alt))
            }
        }
        return out
    }

    /// A box's list: the /L owns the drawing, each item an /LI whose /LBody
    /// says its words.
    private static func listNode(_ el: Element) -> StructNode {
        let lines = RichText.strip(el.text ?? "").components(separatedBy: "\n")
        let items = TextLists.items(el)
        let kids = lines.indices.filter { $0 < items.count && items[$0] != nil }.map { i in
            StructNode(role: li, kids: [StructNode(role: lBody, text: lines[i].trimmingCharacters(in: .whitespaces))])
        }
        return StructNode(role: l, ids: [el.id], kids: kids)
    }

    /// A table: a /TR a row, top to bottom, its cells left to right, each
    /// cell owning its own drawing.
    private static func tableNode(_ elements: [Element], id: String) -> StructNode {
        // A cell is its words and the shape behind them: the words are the
        // cell, the shape an artifact.
        let members = DataGraphics.tableMembers(elements, id: id).filter { $0.type == .text }
        let header = DataGraphics.tableHasHeader(elements, id: id)
        let cells = members.compactMap { el in el.table.map { (cell: $0, el: el) } }
        let rows = Dictionary(grouping: cells, by: { $0.cell.row })
        let kids = rows.keys.sorted().map { row -> StructNode in
            let cells = (rows[row] ?? []).sorted { $0.cell.col < $1.cell.col }
            return StructNode(role: tr, kids: cells.map { pair in
                StructNode(role: header && row == 0 ? th : td, ids: [pair.el.id],
                     text: RichText.strip(pair.el.text ?? "").trimmingCharacters(in: .whitespacesAndNewlines))
            })
        }
        return StructNode(role: table, kids: kids)
    }

    /// Every element id a page's structure owns; anything else drawn is an
    /// artifact.
    static func owned(_ nodes: [StructNode]) -> Set<String> {
        var out: Set<String> = []
        func walk(_ n: StructNode) {
            out.formUnion(n.ids)
            n.kids.forEach(walk)
        }
        nodes.forEach(walk)
        return out
    }

    /// The structure role of each element a page's `nodes` own, by id — what
    /// a sentinel's marked content is tagged with.
    static func roles(_ nodes: [StructNode]) -> [String: String] {
        var out: [String: String] = [:]
        func walk(_ n: StructNode) {
            for id in n.ids where out[id] == nil { out[id] = n.role }
            n.kids.forEach(walk)
        }
        nodes.forEach(walk)
        return out
    }

    /// The structure outline of the shown pages among `pageIndices` — the
    /// parity tests' fixture text, the same on both phones: one role a line,
    /// indented a space a level, under "Document" and a "Sect" a page.
    static func outline(_ design: Design, pageIndices: [Int]? = nil) -> String {
        var lines = [document]
        func walk(_ n: StructNode, _ depth: Int) {
            lines.append(String(repeating: " ", count: depth) + n.role)
            for kid in n.kids { walk(kid, depth + 1) }
        }
        for i in pageIndices ?? Array(design.pages.indices) {
            guard design.pages.indices.contains(i), design.pages[i].hidden != true else { continue }
            lines.append(" " + sect)
            for node in page(design, design.pages[i]) { walk(node, 2) }
        }
        return lines.joined(separator: "\n")
    }

    // MARK: sentinels

    /// The colour of the sentinel drawn before the `index`th element on a
    /// page (from 1), as 0…255 components: red 1, and the index in green
    /// and blue — at most 65535 a page. The Android twin's sentinelColour.
    static func sentinelComponents(_ index: Int) -> (red: Int, green: Int, blue: Int) {
        (1, (index >> 8) & 0xFF, index & 0xFF)
    }

    /// The sentinel's side, in page units: too small to see, but no
    /// smaller than the export's layout grid (DesignExporter.vectorScale's
    /// sixteenth of a unit), which would round it away.
    static let sentinelSize = 1.0 / 16

    /// One marked-content sequence: its MCID and the element it draws.
    struct Marked: Equatable {
        var mcid: Int
        var elementId: String
    }

    /// A content stream with its sentinels turned into marked content, and
    /// each sequence's MCID.
    struct MarkedStream {
        var content: String
        var marked: [Marked]
    }

    /// A fill colour of three components: Android's `rg`, and Core
    /// Graphics' `sc` / `scn` in the page's RGB colour space.
    private static let colourOp = try? NSRegularExpression(pattern: #"(-?[\d.]+)\s+(-?[\d.]+)\s+(-?[\d.]+)\s+(?:rg|scn|sc)\b"#)
    private static let fillOp = try? NSRegularExpression(pattern: #"(?<![\w*])(f\*?|F|B\*?|b\*?)(?![\w*])"#)

    /// `content` (a page's content stream, read one character a byte) with
    /// each sentinel's run — its colour, its path and its fill — taken out
    /// and replaced by the close of the sequence before (EMC) and the open
    /// of the next: `/<Role> <</MCID n>> BDC` for an element `roleOf` gives
    /// a role, `/Artifact BMC` for one it does not. Sentinel k is
    /// `drawn[k - 1]`; one whose index is not there opens an artifact. What
    /// comes before the first sentinel — the background — is an artifact,
    /// and the last sequence closes at the end. MCIDs count from
    /// `firstMcid`. A run with anything but a path in it is left drawn, as
    /// on the Android twin.
    static func mark(_ content: String, drawn: [String], roleOf: (String) -> String?, firstMcid: Int = 0) -> MarkedStream {
        let ns = content as NSString
        var out = "/Artifact BMC\n"
        var marked: [Marked] = []
        var mcid = firstMcid
        var at = 0
        guard let colourOp, let fillOp else { return MarkedStream(content: content, marked: []) }
        for colour in colourOp.matches(in: content, range: NSRange(location: 0, length: ns.length)) {
            // A colour inside a run already taken is passed over.
            guard colour.range.location >= at else { continue }
            let parts = (1...3).map { ns.substring(with: colour.range(at: $0)) }
            guard let code = sentinelCode(parts[0], parts[1], parts[2]) else { continue }
            let after = colour.range.location + colour.range.length
            guard let fill = fillOp.firstMatch(in: content, range: NSRange(location: after, length: ns.length - after)) else { continue }
            let between = ns.substring(with: NSRange(location: after, length: fill.range.location - after))
            guard isPath(between) else { continue }
            out += ns.substring(with: NSRange(location: at, length: colour.range.location - at))
            out += "\nEMC\n"
            let id = code - 1 < drawn.count ? drawn[code - 1] : nil
            if let id, let role = roleOf(id) {
                out += "/\(role) <</MCID \(mcid)>> BDC\n"
                marked.append(Marked(mcid: mcid, elementId: id))
                mcid += 1
            } else {
                out += "/Artifact BMC\n"
            }
            at = fill.range.location + fill.range.length
        }
        out += ns.substring(from: at)
        out += "\nEMC\n"
        return MarkedStream(content: out, marked: marked)
    }

    /// The sentinel index three colour components say, or nil when they
    /// are not one's: red 1/255, read as a byte as the writer rounded it.
    static func sentinelCode(_ r: String, _ g: String, _ b: String) -> Int? {
        func byte(_ s: String) -> Int? {
            guard let v = Double(s), v >= 0, v <= 1 else { return nil }
            return Int((v * 255).rounded())
        }
        guard byte(r) == 1, let hi = byte(g), let lo = byte(b) else { return nil }
        let code = hi << 8 | lo
        return code > 0 ? code : nil
    }

    /// Whether the operators between a sentinel's colour and its fill are a
    /// path and nothing else: numbers and path operators, with a rectangle
    /// (`re`, as Android writes it) or a move (`m`, which Core Graphics may
    /// write a rectangle as) among them.
    private static func isPath(_ ops: String) -> Bool {
        let tokens = ops.split(whereSeparator: { $0 == " " || $0 == "\n" || $0 == "\r" || $0 == "\t" }).map(String.init)
        let pathOps: Set<String> = ["re", "m", "l", "c", "v", "y", "h"]
        return (tokens.contains("re") || tokens.contains("m"))
            && tokens.allSatisfy { Double($0) != nil || pathOps.contains($0) }
    }
}
