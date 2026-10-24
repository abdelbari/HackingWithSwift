// A PDF's words as runs of text where they stand, for importing a PDF as
// editable text — the Android twin's PdfText, rule for rule, with the same
// golden runs (Fixtures/pdf-text.pdf, written by
// Tools/generate_pdf_fixture.py, and Fixtures/pdf-text.json).
//
// The reader finds its objects through the cross-reference tables and
// streams from `startxref` back along each /Prev, objects packed in object
// streams among them — or, when those do not read, by finding every
// "n g obj" in the file. Streams are decoded through FlateDecode (with the
// PNG predictors a cross-reference stream uses); a stream in any other
// filter has no words for it. A document with an /Encrypt entry is
// Outcome.encrypted.
//
// Each page's content streams are read in order: BT/ET, Tf, Tm, Td, TD,
// T*, TL, Tc, Tw, Tz, Ts, Tj, TJ, ' and ", q/Q and cm, and the fill colours
// rg, g and k; an inline image's bytes are passed over, and a form's words
// (Do) are not read. A code's words come from the font's ToUnicode CMap
// (bfchar and bfrange) or its encoding — WinAnsi, MacRoman or Standard,
// with /Differences by glyph name; a simple font names none and is
// Standard when it is Type1, WinAnsi otherwise. A Type0 font's codes are
// two bytes. A glyph's advance is its /Widths or /W entry, else the font's
// /MissingWidth or /DW, else 500 (1000 for a Type0 font) thousandths. A
// page that uses a Type3 font is marked `type3`, its words not read.
//
// A run is what one Tj, TJ, ' or " shows: its words, where its baseline
// starts — in points from the page box's left and down from its top — its
// size as drawn, the font's BaseFont without a subset prefix ("ABCDEF+"),
// bold when the name holds "Bold", italic when it holds "Italic" or
// "Oblique", and its fill colour. In a TJ, a gap of more than 250
// thousandths is a space.

import CoreGraphics
import Foundation

/// Where a page made from a PDF came from, its "pdfSource" key:
/// {"name": "menu.pdf", "page": 1}, the page counted from 1.
struct PdfSource: Codable, Equatable {
    var name: String
    var page: Int
}

enum PdfText {

    /// More pages than this are left out, as PDFImporter leaves them out.
    static let maxPages = 60

    struct PdfRun: Equatable {
        var text: String
        var x: Double
        var y: Double
        var size: Double
        var font: String
        var bold: Bool
        var italic: Bool
        var colour: String
        /// How far it reaches, in points: not part of the golden runs, but
        /// what lines are measured by.
        var width: Double = 0
    }

    /// A page: its box's size in points, its runs in the order they are
    /// shown, and whether it uses a Type3 font.
    struct TextPage: Equatable {
        var width: Double
        var height: Double
        var runs: [PdfRun]
        var type3 = false
    }

    enum Outcome {
        case document(pages: [TextPage], total: Int)
        case encrypted
        case unreadable
    }

    /// The document `data` holds, at most `limit` of its pages.
    static func read(_ data: Data, limit: Int = maxPages) -> Outcome {
        let doc = PdfDoc([UInt8](data))
        if doc.present(doc.trailer["Encrypt"]) { return .encrypted }
        let leaves = doc.pages()
        guard !leaves.isEmpty else { return .unreadable }
        return .document(pages: leaves.prefix(max(limit, 0)).map { doc.page($0) }, total: leaves.count)
    }

    // MARK: golden runs

    /// `pages` as the golden JSON both phones compare: a page a block, a run
    /// a line, its numbers to two places and written as whole numbers when
    /// they are, its words with only `"`, `\`, and control characters
    /// escaped.
    static func json(_ pages: [TextPage]) -> String {
        var out = "{\"pages\":[\n"
        for (i, page) in pages.enumerated() {
            out += "{\"width\":\(num(page.width)),\"height\":\(num(page.height)),\"type3\":\(page.type3),\"runs\":[\n"
            out += page.runs.map(runJson).joined(separator: ",\n")
            out += page.runs.isEmpty ? "]}" : "\n]}"
            out += i < pages.count - 1 ? ",\n" : "\n"
        }
        return out + "]}\n"
    }

    private static func runJson(_ r: PdfRun) -> String {
        let place = "\"x\":\(num(r.x)),\"y\":\(num(r.y)),\"size\":\(num(r.size))"
        let look = "\"font\":\(quote(r.font)),\"bold\":\(r.bold),\"italic\":\(r.italic),\"colour\":\(quote(r.colour))"
        return "{\"text\":\(quote(r.text))," + place + "," + look + "}"
    }

    /// `v` to two places, halves away from zero, as a whole number when it
    /// is one.
    static func num(_ v: Double) -> String {
        let r = (v >= 0 ? (v * 100 + 0.5).rounded(.down) : -(-v * 100 + 0.5).rounded(.down)) / 100
        if r == r.rounded(.down), abs(r) < 1e15 { return String(Int64(r)) }
        return String(r)
    }

    private static func quote(_ s: String) -> String {
        var out = "\""
        for c in s.unicodeScalars {
            switch c {
            case "\"": out += "\\\""
            case "\\": out += "\\\\"
            case "\n": out += "\\n"
            default:
                if c.value < 0x20 { out += String(format: "\\u%04x", c.value) } else { out.unicodeScalars.append(c) }
            }
        }
        return out + "\""
    }

    // MARK: lines and paragraphs

    /// A line of runs: its runs left to right, its baseline, where it
    /// starts and how far it reaches.
    struct PdfLine: Equatable {
        var runs: [PdfRun]
        var y: Double
        var x: Double
        var right: Double

        var first: PdfRun { runs[0] }
        var size: Double { first.size }

        /// Its words: the runs' joined, a space between two that leave a
        /// gap of more than a tenth of their size and have none at the
        /// joint.
        var text: String {
            var out = ""
            var end: Double?
            for run in runs {
                let gap = end.map { run.x - $0 } ?? 0
                let joint = (out.last?.isWhitespace ?? true) || (run.text.first?.isWhitespace ?? false)
                if !out.isEmpty && gap > run.size * 0.1 && !joint { out += " " }
                out += run.text
                end = run.x + run.width
            }
            return out.trimmingCharacters(in: .whitespacesAndNewlines)
        }
    }

    /// `runs` in lines: from the top of the page down and then from the
    /// left, a run joining the line whose baseline is within 0.3 of that
    /// line's first run's size of its own; blank runs left out.
    static func lines(_ runs: [PdfRun]) -> [PdfLine] {
        // Sorted as a stable sort sorts, as the Android twin's sortedWith.
        let sorted = runs.enumerated()
            .filter { !$0.element.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            .sorted { a, b in (a.element.y, a.element.x, a.offset) < (b.element.y, b.element.x, b.offset) }
            .map { $0.element }
        var groups: [[PdfRun]] = []
        for run in sorted {
            if let line = groups.last, let head = line.first, abs(run.y - head.y) <= 0.3 * head.size {
                groups[groups.count - 1].append(run)
            } else {
                groups.append([run])
            }
        }
        return groups.map { g in
            let inOrder = g.enumerated().sorted { ($0.element.x, $0.offset) < ($1.element.x, $1.offset) }.map { $0.element }
            return PdfLine(runs: inOrder, y: inOrder[0].y, x: inOrder[0].x,
                        right: inOrder.map { $0.x + $0.width }.max() ?? inOrder[0].x)
        }
    }

    /// `lines` (top to bottom) in paragraphs: a line joins the paragraph
    /// above when it is no more than 1.6 times that paragraph's last line's
    /// size below it and starts within 2 points of the same left edge.
    static func paragraphs(_ lines: [PdfLine]) -> [[PdfLine]] {
        var out: [[PdfLine]] = []
        for line in lines {
            if let last = out.last?.last, line.y - last.y <= 1.6 * last.size, abs(line.x - last.x) <= 2 {
                out[out.count - 1].append(line)
            } else {
                out.append([line])
            }
        }
        return out
    }

    // MARK: into a design

    /// How far above its baseline a line's box starts, as a share of its size.
    static let ascent = 0.9

    /// How far below its baseline a line's box reaches, as a share of its size.
    static let descent = 0.25

    /// Page `page`'s words as text boxes, a paragraph each, scaled by
    /// `scale` from points: its lines' words joined by line breaks, set left
    /// in the nearest of the families (`family`) at its first run's weight,
    /// slant, size (to a tenth) and colour; its box from its left edge and
    /// `ascent` above its first baseline, as wide as its longest line and
    /// half its size more; spaced as far apart as its lines are, on
    /// average, when it has more than one. Each box's height is
    /// `heightFor`'s.
    static func textElements(_ page: TextPage, scale: Double, heightFor: (Element) -> Double) -> [Element] {
        paragraphs(lines(page.runs)).map { para in
            let first = para[0].first
            let left = para.map(\.x).min() ?? 0
            let width = ((para.map(\.right).max() ?? left) - left + first.size * 0.5) * scale
            let gaps = zip(para, para.dropFirst()).map { $1.y - $0.y }
            var lineHeight: Double?
            if !gaps.isEmpty {
                let share = min(max(gaps.reduce(0, +) / Double(gaps.count) / first.size, 0.8), 3.0)
                lineHeight = (share * 100 + 0.5).rounded(.down) / 100
            }
            var el = Element.text(RichText.escapeLiteral(para.map(\.text).joined(separator: "\n")),
                                  fontSize: TypeReadouts.wholeSize(first.size * scale), w: width)
            el.x = left * scale
            el.y = (first.y - first.size * ascent) * scale
            el.align = "left"
            el.fontFamily = family(first.font)
            el.fontWeight = first.bold ? 700 : 400
            el.italic = first.italic ? true : nil
            el.color = first.colour
            el.lineHeight = lineHeight
            el.h = heightFor(el)
            return el
        }
    }

    /// Page `number` (from 1) of the PDF `name` as a design page `pageSize`
    /// big: its picture `src` — the page drawn with its words painted over —
    /// fitted whole and centred as a picture page is, locked and named
    /// `layerName`; then its words as text boxes over it (textElements),
    /// scaled and moved with it; and where it came from (`pdfSource`).
    static func editablePage(_ page: TextPage, src: String, name: String, number: Int, pageSize: CGSize,
                             layerName: String, heightFor: (Element) -> Double) -> Page {
        let scale = min(Double(pageSize.width) / max(page.width, 1), Double(pageSize.height) / max(page.height, 1))
        let w = (page.width * scale).rounded()
        let h = (page.height * scale).rounded()
        let left = ((Double(pageSize.width) - w) / 2).rounded()
        let top = ((Double(pageSize.height) - h) / 2).rounded()
        var picture = Element.image(src, w: w, h: h)
        picture.x = left
        picture.y = top
        picture.locked = true
        picture.layerName = LayerNames.kept(layerName)
        let words = textElements(page, scale: scale, heightFor: heightFor).map { el -> Element in
            var moved = el
            moved.x += left
            moved.y += top
            return moved
        }
        var out = Page(elements: [picture] + words)
        out.pdfSource = PdfSource(name: name, page: number)
        return out
    }

    /// Whether page `page` comes in as editable text: it has words, and no
    /// Type3 font.
    static func editable(_ page: TextPage) -> Bool {
        !page.type3 && page.runs.contains { !$0.text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
    }

    /// The boxes on page `page` its words cover, a line each, in points:
    /// from `ascent` above the baseline to `descent` below, a point wider
    /// every way — what the page's picture has painted over.
    static func lineBoxes(_ page: TextPage) -> [CGRect] {
        lines(page.runs).map { (line: PdfLine) -> CGRect in
            let top: Double = line.y - line.size * ascent - 1
            let tall: Double = line.size * (ascent + descent) + 2
            return CGRect(x: line.x - 1, y: top, width: line.right - line.x + 2, height: tall)
        }
    }

    /// The colour a box in a picture is painted over with: the median, a
    /// channel at a time, of the pixels in a ring `ring` pixels wide around
    /// `left`, `top`, `right`, `bottom` (right and bottom not included), as
    /// far as the picture reaches; white when the ring is off it. `pixels`
    /// are ARGB, a row at a time.
    static func ringMedian(_ pixels: [UInt32], width: Int, height: Int, left: Int, top: Int, right: Int, bottom: Int,
                           ring: Int = 3) -> UInt32 {
        var reds: [UInt32] = [], greens: [UInt32] = [], blues: [UInt32] = []
        let y0 = max(0, top - ring), y1 = min(height, bottom + ring)
        let x0 = max(0, left - ring), x1 = min(width, right + ring)
        if y0 < y1 && x0 < x1 {
            for y in y0..<y1 {
                for x in x0..<x1 {
                    if x >= left && x < right && y >= top && y < bottom { continue }
                    let i = y * width + x
                    guard i < pixels.count else { continue }
                    let p = pixels[i]
                    reds.append((p >> 16) & 0xff)
                    greens.append((p >> 8) & 0xff)
                    blues.append(p & 0xff)
                }
            }
        }
        guard !reds.isEmpty else { return 0xffffffff }
        func median(_ list: [UInt32]) -> UInt32 { list.sorted()[list.count / 2] }
        return 0xff00_0000 | (median(reds) << 16) | (median(greens) << 8) | median(blues)
    }

    /// The nearest of the families (FontLibrary) to a PDF font's `name` —
    /// its BaseFont without a subset prefix: the family whose name or id,
    /// letters only and case aside, is the name's family part (before its
    /// first "-" or ","), or that part with "MT", "PS", "Std" or "Pro" at
    /// its end taken off; else "serif" for a name with Times, Serif,
    /// Georgia, Garamond, Minion, Cambria, Book or Roman in it, "mono" for
    /// Courier, Mono or Consol, and "sans" for anything else.
    static func family(_ name: String) -> String {
        func letters(_ s: String) -> String { String(s.lowercased().filter { $0 >= "a" && $0 <= "z" }) }
        let head = name.split(separator: "-", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
        let part = letters(head.split(separator: ",", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? "")
        var bare = part
        for suffix in ["mt", "ps", "std", "pro"] where bare.hasSuffix(suffix) { bare = String(bare.dropLast(suffix.count)) }
        for key in [part, bare] where !key.isEmpty {
            if let found = FontLibrary.all.first(where: { letters($0.name) == key || letters($0.id) == key }) {
                return found.id
            }
        }
        let lower = name.lowercased()
        if ["times", "serif", "georgia", "garamond", "minion", "cambria", "book", "roman"].contains(where: { lower.contains($0) }) {
            return "serif"
        }
        if ["courier", "mono", "consol"].contains(where: { lower.contains($0) }) { return "mono" }
        return "sans"
    }

    /// A BaseFont without its subset prefix: six capitals and a plus.
    static func withoutSubset(_ name: String) -> String {
        let chars = Array(name)
        guard chars.count > 7, chars[6] == "+", chars.prefix(6).allSatisfy({ $0 >= "A" && $0 <= "Z" }) else { return name }
        return String(chars.dropFirst(7))
    }

    // MARK: glyph names

    /// A glyph name's words: "uniXXXX" and "uXXXX", a named letter with its
    /// accent ("eacute"), a name of the ASCII set or of `glyphs`; nothing
    /// for one not known.
    static func glyph(_ name: String) -> String? {
        let hex = Set("0123456789abcdefABCDEF")
        let tail = name.dropFirst(3)
        if name.hasPrefix("uni"), !tail.isEmpty, tail.count % 4 == 0, tail.allSatisfy({ hex.contains($0) }) {
            var units: [UInt16] = []
            var rest = Substring(tail)
            while !rest.isEmpty {
                units.append(UInt16(rest.prefix(4), radix: 16) ?? 0)
                rest = rest.dropFirst(4)
            }
            return String(decoding: units, as: UTF16.self)
        }
        let digits = name.dropFirst()
        if name.hasPrefix("u"), (4...6).contains(digits.count), digits.allSatisfy({ hex.contains($0) }) {
            guard let cp = UInt32(digits, radix: 16), let scalar = Unicode.Scalar(cp) else { return nil }
            return String(Character(scalar))
        }
        if let known = glyphs[name] { return known }
        if name.count == 1, name.first?.isLetter == true { return name }
        let marks: [String: String] = ["grave": "\u{300}", "acute": "\u{301}", "circumflex": "\u{302}", "tilde": "\u{303}",
                                       "dieresis": "\u{308}", "ring": "\u{30A}", "cedilla": "\u{327}", "caron": "\u{30C}"]
        if let base = name.first, base.isASCII, base.isLetter, let mark = marks[String(name.dropFirst())] {
            return (String(base) + mark).precomposedStringWithCanonicalMapping
        }
        return nil
    }

    static let glyphs: [String: String] = [
        "space": " ",
        "exclam": "!",
        "quotedbl": "\"",
        "numbersign": "#",
        "dollar": "$",
        "percent": "%",
        "ampersand": "&",
        "quotesingle": "'",
        "parenleft": "(",
        "parenright": ")",
        "asterisk": "*",
        "plus": "+",
        "comma": ",",
        "hyphen": "-",
        "period": ".",
        "slash": "/",
        "zero": "0",
        "one": "1",
        "two": "2",
        "three": "3",
        "four": "4",
        "five": "5",
        "six": "6",
        "seven": "7",
        "eight": "8",
        "nine": "9",
        "colon": ":",
        "semicolon": ";",
        "less": "<",
        "equal": "=",
        "greater": ">",
        "question": "?",
        "at": "@",
        "bracketleft": "[",
        "backslash": "\\",
        "bracketright": "]",
        "asciicircum": "^",
        "underscore": "_",
        "grave": "`",
        "braceleft": "{",
        "bar": "|",
        "braceright": "}",
        "asciitilde": "~",
        "quoteleft": "‘",
        "quoteright": "’",
        "quotedblleft": "“",
        "quotedblright": "”",
        "quotesinglbase": "‚",
        "quotedblbase": "„",
        "endash": "–",
        "emdash": "—",
        "bullet": "•",
        "ellipsis": "…",
        "fi": "ﬁ",
        "fl": "ﬂ",
        "ff": "ff",
        "ffi": "ffi",
        "ffl": "ffl",
        "AE": "Æ",
        "ae": "æ",
        "OE": "Œ",
        "oe": "œ",
        "Oslash": "Ø",
        "oslash": "ø",
        "germandbls": "ß",
        "dotlessi": "ı",
        "Lslash": "Ł",
        "lslash": "ł",
        "Eth": "Ð",
        "eth": "ð",
        "Thorn": "Þ",
        "thorn": "þ",
        "trademark": "™",
        "copyright": "©",
        "registered": "®",
        "degree": "°",
        "plusminus": "±",
        "multiply": "×",
        "divide": "÷",
        "Euro": "€",
        "sterling": "£",
        "yen": "¥",
        "cent": "¢",
        "currency": "¤",
        "section": "§",
        "paragraph": "¶",
        "periodcentered": "·",
        "guillemotleft": "«",
        "guillemotright": "»",
        "guilsinglleft": "‹",
        "guilsinglright": "›",
        "exclamdown": "¡",
        "questiondown": "¿",
        "nbspace": " ",
        "minus": "−",
        "dagger": "†",
        "daggerdbl": "‡",
        "perthousand": "‰",
        "florin": "ƒ",
        "fraction": "⁄",
        "onehalf": "½",
        "onequarter": "¼",
        "threequarters": "¾",
        "ordfeminine": "ª",
        "ordmasculine": "º",
        "mu": "µ",
        "logicalnot": "¬",
        "brokenbar": "¦",
        "macron": "¯",
        "acute": "´",
        "cedilla": "¸",
        "dieresis": "¨",
        "onesuperior": "¹",
        "twosuperior": "²",
        "threesuperior": "³",
        "Ydieresis": "Ÿ",
        "Scaron": "Š",
        "scaron": "š",
        "Zcaron": "Ž",
        "zcaron": "ž",
        "circumflex": "ˆ",
        "tilde": "˜",
        "ring": "˚",
        "caron": "ˇ",
        "breve": "˘",
        "dotaccent": "˙",
        "hungarumlaut": "˝",
        "ogonek": "˛",
        "softhyphen": "-",
        "sfthyphen": "-",
    ]

    // MARK: encodings

    /// An encoding's table: ASCII below 128 (Standard's two quotes its
    /// own), then `high` for 128 to 255, nil where it has nothing.
    fileprivate static func table(_ high: [UInt16], standard: Bool = false) -> [String?] {
        (0..<256).map { code -> String? in
            if code < 32 { return nil }
            if code < 127 {
                if standard && code == 0x27 { return "\u{2019}" }
                if standard && code == 0x60 { return "\u{2018}" }
                return String(UnicodeScalar(UInt8(code)))
            }
            if code < 128 { return nil }
            let v = high[code - 128]
            guard v != 0, let scalar = Unicode.Scalar(UInt32(v)) else { return nil }
            return String(Character(scalar))
        }
    }

    fileprivate static let winAnsi = table(winAnsiHigh)
    fileprivate static let macRoman = table(macRomanHigh)
    fileprivate static let standard = table(standardHigh, standard: true)

    private static let winAnsiHigh: [UInt16] = [
        0x20ac, 0x0000, 0x201a, 0x0192, 0x201e, 0x2026, 0x2020, 0x2021, 0x02c6, 0x2030, 0x0160, 0x2039, 0x0152, 0x0000, 0x017d, 0x0000,
        0x0000, 0x2018, 0x2019, 0x201c, 0x201d, 0x2022, 0x2013, 0x2014, 0x02dc, 0x2122, 0x0161, 0x203a, 0x0153, 0x0000, 0x017e, 0x0178,
        0x0020, 0x00a1, 0x00a2, 0x00a3, 0x00a4, 0x00a5, 0x00a6, 0x00a7, 0x00a8, 0x00a9, 0x00aa, 0x00ab, 0x00ac, 0x002d, 0x00ae, 0x00af,
        0x00b0, 0x00b1, 0x00b2, 0x00b3, 0x00b4, 0x00b5, 0x00b6, 0x00b7, 0x00b8, 0x00b9, 0x00ba, 0x00bb, 0x00bc, 0x00bd, 0x00be, 0x00bf,
        0x00c0, 0x00c1, 0x00c2, 0x00c3, 0x00c4, 0x00c5, 0x00c6, 0x00c7, 0x00c8, 0x00c9, 0x00ca, 0x00cb, 0x00cc, 0x00cd, 0x00ce, 0x00cf,
        0x00d0, 0x00d1, 0x00d2, 0x00d3, 0x00d4, 0x00d5, 0x00d6, 0x00d7, 0x00d8, 0x00d9, 0x00da, 0x00db, 0x00dc, 0x00dd, 0x00de, 0x00df,
        0x00e0, 0x00e1, 0x00e2, 0x00e3, 0x00e4, 0x00e5, 0x00e6, 0x00e7, 0x00e8, 0x00e9, 0x00ea, 0x00eb, 0x00ec, 0x00ed, 0x00ee, 0x00ef,
        0x00f0, 0x00f1, 0x00f2, 0x00f3, 0x00f4, 0x00f5, 0x00f6, 0x00f7, 0x00f8, 0x00f9, 0x00fa, 0x00fb, 0x00fc, 0x00fd, 0x00fe, 0x00ff,
    ]

    private static let macRomanHigh: [UInt16] = [
        0x00c4, 0x00c5, 0x00c7, 0x00c9, 0x00d1, 0x00d6, 0x00dc, 0x00e1, 0x00e0, 0x00e2, 0x00e4, 0x00e3, 0x00e5, 0x00e7, 0x00e9, 0x00e8,
        0x00ea, 0x00eb, 0x00ed, 0x00ec, 0x00ee, 0x00ef, 0x00f1, 0x00f3, 0x00f2, 0x00f4, 0x00f6, 0x00f5, 0x00fa, 0x00f9, 0x00fb, 0x00fc,
        0x2020, 0x00b0, 0x00a2, 0x00a3, 0x00a7, 0x2022, 0x00b6, 0x00df, 0x00ae, 0x00a9, 0x2122, 0x00b4, 0x00a8, 0x2260, 0x00c6, 0x00d8,
        0x221e, 0x00b1, 0x2264, 0x2265, 0x00a5, 0x00b5, 0x2202, 0x2211, 0x220f, 0x03c0, 0x222b, 0x00aa, 0x00ba, 0x03a9, 0x00e6, 0x00f8,
        0x00bf, 0x00a1, 0x00ac, 0x221a, 0x0192, 0x2248, 0x2206, 0x00ab, 0x00bb, 0x2026, 0x0020, 0x00c0, 0x00c3, 0x00d5, 0x0152, 0x0153,
        0x2013, 0x2014, 0x201c, 0x201d, 0x2018, 0x2019, 0x00f7, 0x25ca, 0x00ff, 0x0178, 0x2044, 0x00a4, 0x2039, 0x203a, 0xfb01, 0xfb02,
        0x2021, 0x00b7, 0x201a, 0x201e, 0x2030, 0x00c2, 0x00ca, 0x00c1, 0x00cb, 0x00c8, 0x00cd, 0x00ce, 0x00cf, 0x00cc, 0x00d3, 0x00d4,
        0x0000, 0x00d2, 0x00da, 0x00db, 0x00d9, 0x0131, 0x02c6, 0x02dc, 0x00af, 0x02d8, 0x02d9, 0x02da, 0x00b8, 0x02dd, 0x02db, 0x02c7,
    ]

    private static let standardHigh: [UInt16] = [
        0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
        0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
        0x0000, 0x00a1, 0x00a2, 0x00a3, 0x2044, 0x00a5, 0x0192, 0x00a7, 0x00a4, 0x0027, 0x201c, 0x00ab, 0x2039, 0x203a, 0xfb01, 0xfb02,
        0x0000, 0x2013, 0x2020, 0x2021, 0x00b7, 0x0000, 0x00b6, 0x2022, 0x201a, 0x201e, 0x201d, 0x00bb, 0x2026, 0x2030, 0x0000, 0x00bf,
        0x0000, 0x0060, 0x00b4, 0x02c6, 0x02dc, 0x00af, 0x02d8, 0x02d9, 0x00a8, 0x0000, 0x02da, 0x00b8, 0x0000, 0x02dd, 0x02db, 0x02c7,
        0x2014, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000, 0x0000,
        0x0000, 0x00c6, 0x0000, 0x00aa, 0x0000, 0x0000, 0x0000, 0x0000, 0x0141, 0x00d8, 0x0152, 0x00ba, 0x0000, 0x0000, 0x0000, 0x0000,
        0x0000, 0x00e6, 0x0000, 0x0000, 0x0000, 0x0131, 0x0000, 0x0000, 0x0142, 0x00f8, 0x0153, 0x00df, 0x0000, 0x0000, 0x0000, 0x0000,
    ]
}

// MARK: - objects

/// A PDF object as the lexer reads it; `op` is an operator or a stray
/// delimiter.
private indirect enum PdfObject {
    case number(Double)
    case name(String)
    case string([UInt8])
    case ref(Int, Int)
    case op(String)
    case array([PdfObject])
    case dict([String: PdfObject])
    case stream([String: PdfObject], [UInt8])
    case bool(Bool)
    case null
}

/// A whole number from a PDF's, held inside what an Int takes.
private func pdfWhole(_ v: Double) -> Int {
    guard v.isFinite else { return 0 }
    return Int(max(min(v, 2_000_000_000), -2_000_000_000))
}

/// Bytes as text, one character a byte.
private func pdfLatin1<S: Sequence>(_ bytes: S) -> String where S.Element == UInt8 {
    var out = String.UnicodeScalarView()
    for b in bytes { out.append(Unicode.Scalar(b)) }
    return String(out)
}

/// Bytes read as PDF objects from `pos` on.
private final class PdfLexer {
    let b: [UInt8]
    var pos: Int
    /// How deep in arrays and dictionaries it is, held so a hostile file
    /// cannot run the stack out.
    private var depth = 0

    init(_ b: [UInt8], _ pos: Int = 0) {
        self.b = b
        self.pos = max(0, pos)
    }

    var atEnd: Bool { pos >= b.count }

    static func white(_ c: Int) -> Bool { c == 0 || c == 9 || c == 10 || c == 12 || c == 13 || c == 32 }

    static func delim(_ c: Int) -> Bool {
        c == 0x28 || c == 0x29 || c == 0x3C || c == 0x3E || c == 0x5B || c == 0x5D || c == 0x7B || c == 0x7D
            || c == 0x2F || c == 0x25
    }

    func skip() {
        while pos < b.count {
            let c = Int(b[pos])
            if Self.white(c) {
                pos += 1
            } else if c == 0x25 {
                while pos < b.count && b[pos] != 10 && b[pos] != 13 { pos += 1 }
            } else {
                return
            }
        }
    }

    func peek() -> Int { pos < b.count ? Int(b[pos]) : -1 }

    /// The next bare word: a number or a keyword.
    func word() -> String {
        let start = pos
        while pos < b.count {
            let c = Int(b[pos])
            if Self.white(c) || Self.delim(c) { break }
            pos += 1
        }
        return pdfLatin1(b[start..<pos])
    }

    /// A name's "#xx" escapes read as their bytes.
    private static func unescaped(_ raw: String) -> String {
        guard raw.contains("#") else { return raw }
        let s = Array(raw.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        while i < s.count {
            if s[i] == "#", i + 2 < s.count, let v = UInt8(String(s[i + 1]) + String(s[i + 2]), radix: 16) {
                out.append(Unicode.Scalar(v))
                i += 3
            } else {
                out.append(s[i])
                i += 1
            }
        }
        return String(out)
    }

    /// The next object; with `refs`, "n g R" is a reference. Operators come
    /// back as .op; nil at the end.
    func next(refs: Bool = true) -> PdfObject? {
        skip()
        guard !atEnd else { return nil }
        let c = peek()
        switch c {
        case 0x2F:
            pos += 1
            return .name(Self.unescaped(word()))
        case 0x28:
            return .string(literal())
        case 0x3C:
            if pos + 1 < b.count && b[pos + 1] == 0x3C {
                pos += 2
                return .dict(dict(refs: refs))
            }
            return .string(hex())
        case 0x5B:
            pos += 1
            return .array(array(refs: refs))
        case 0x5D, 0x3E, 0x29, 0x7B, 0x7D:
            pos += 1
            return .op(String(UnicodeScalar(UInt8(c))))
        default:
            break
        }
        let w = word()
        if w.isEmpty {
            pos += 1
            return .op("")
        }
        if let n = number(w) {
            let digits = w.allSatisfy { $0 >= "0" && $0 <= "9" }
            if refs, digits, let num = Int(w) {
                let save = pos
                skip()
                let g = word()
                if !g.isEmpty, g.allSatisfy({ $0 >= "0" && $0 <= "9" }), let gen = Int(g) {
                    skip()
                    if peek() == 0x52 {
                        let at = pos
                        pos += 1
                        if atEnd || Self.white(peek()) || Self.delim(peek()) { return .ref(num, gen) }
                        pos = at
                    }
                }
                pos = save
            }
            return .number(n)
        }
        switch w {
        case "true": return .bool(true)
        case "false": return .bool(false)
        case "null": return .null
        default: return .op(w)
        }
    }

    func number(_ w: String) -> Double? {
        guard let first = w.first, first.isASCII, first.isNumber || first == "-" || first == "+" || first == "." else { return nil }
        // Hex floats, infinities and NaN are no PDF numbers.
        guard !w.lowercased().contains(where: { $0 == "x" || $0 == "p" || $0 == "n" }) else { return nil }
        return Double(w)
    }

    private func array(refs: Bool) -> [PdfObject] {
        var list: [PdfObject] = []
        depth += 1
        defer { depth -= 1 }
        guard depth < 200 else { return list }
        while true {
            skip()
            if atEnd { return list }
            if peek() == 0x5D {
                pos += 1
                return list
            }
            let item = next(refs: refs)
            if case .op(let o)? = item, o == "endobj" || o == "]" { return list }
            list.append(item ?? .null)
        }
    }

    func dict(refs: Bool) -> [String: PdfObject] {
        var out: [String: PdfObject] = [:]
        depth += 1
        defer { depth -= 1 }
        guard depth < 200 else { return out }
        while true {
            skip()
            if atEnd { return out }
            if peek() == 0x3E {
                pos += pos + 1 < b.count && b[pos + 1] == 0x3E ? 2 : 1
                return out
            }
            let key = next(refs: refs)
            guard case .name(let k)? = key else {
                if case .op(let o)? = key, o == "endobj" { return out }
                continue
            }
            out[k] = next(refs: refs) ?? .null
        }
    }

    func hex() -> [UInt8] {
        pos += 1
        var out: [UInt8] = []
        var hi = -1
        while pos < b.count {
            let c = b[pos]
            pos += 1
            if c == 0x3E { break }
            guard let v = Int(String(UnicodeScalar(c)), radix: 16) else { continue }
            if hi < 0 {
                hi = v
            } else {
                out.append(UInt8(hi * 16 + v))
                hi = -1
            }
        }
        if hi >= 0 { out.append(UInt8(hi * 16)) }
        return out
    }

    func literal() -> [UInt8] {
        pos += 1
        var out: [UInt8] = []
        var nesting = 1
        while pos < b.count {
            let c = b[pos]
            pos += 1
            switch c {
            case 0x28:
                nesting += 1
                out.append(c)
            case 0x29:
                nesting -= 1
                if nesting == 0 { return out }
                out.append(c)
            case 0x5C:
                guard pos < b.count else { return out }
                let e = b[pos]
                pos += 1
                switch e {
                case 0x6E: out.append(10)
                case 0x72: out.append(13)
                case 0x74: out.append(9)
                case 0x62: out.append(8)
                case 0x66: out.append(12)
                case 13: if pos < b.count && b[pos] == 10 { pos += 1 }
                case 10: break
                case 0x30...0x37:
                    var v = Int(e) - 0x30
                    var n = 1
                    while n < 3 && pos < b.count && (0x30...0x37).contains(b[pos]) {
                        v = v * 8 + Int(b[pos]) - 0x30
                        pos += 1
                        n += 1
                    }
                    out.append(UInt8(v & 0xff))
                default: out.append(e)
                }
            default:
                out.append(c)
            }
        }
        return out
    }
}

// MARK: - the document

private final class PdfDoc {
    let bytes: [UInt8]
    var offsets: [Int: Int] = [:]
    var packed: [Int: Int] = [:]
    var cache: [Int: PdfObject] = [:]
    var trailer: [String: PdfObject] = [:]
    private var packs: [Int: [Int: PdfObject]] = [:]

    init(_ bytes: [UInt8]) {
        self.bytes = bytes
        if !readXref() || !present(trailer["Root"]) { scan() }
    }

    /// Whether `v` is there and not the null object.
    func present(_ v: PdfObject?) -> Bool {
        guard let v else { return false }
        if case .null = v { return false }
        return true
    }

    /// Where `needle` first starts in the bytes from `from` on — or, going
    /// `backwards`, last starts at `from` or after — or nil.
    private func find(_ needle: [UInt8], from: Int, backwards: Bool = false) -> Int? {
        guard !needle.isEmpty, bytes.count >= needle.count else { return nil }
        let last = bytes.count - needle.count
        let low = max(from, 0)
        func matches(_ i: Int) -> Bool {
            var k = 0
            while k < needle.count && bytes[i + k] == needle[k] { k += 1 }
            return k == needle.count
        }
        if backwards {
            var i = last
            while i >= low {
                if matches(i) { return i }
                i -= 1
            }
        } else {
            var i = low
            while i <= last {
                if matches(i) { return i }
                i += 1
            }
        }
        return nil
    }

    /// The cross-reference sections, newest first, each entry kept from
    /// the newest section that has it.
    private func readXref() -> Bool {
        let tailStart = max(0, bytes.count - 2048)
        guard let at = find(Array("startxref".utf8), from: tailStart, backwards: true) else { return false }
        var p = at + 9
        var spaced = false
        while p < bytes.count, [9, 10, 11, 12, 13, 32].contains(bytes[p]) {
            p += 1
            spaced = true
        }
        var digits = ""
        while p < bytes.count, bytes[p] >= 0x30, bytes[p] <= 0x39 {
            digits.append(Character(UnicodeScalar(bytes[p])))
            p += 1
        }
        guard spaced, var offset = Int(digits) else { return false }
        var seen = Set<Int>()
        var first = true
        while offset >= 0 && offset < bytes.count && seen.insert(offset).inserted {
            let lex = PdfLexer(bytes, offset)
            lex.skip()
            let section: [String: PdfObject]
            if lex.word() == "xref" {
                section = table(lex)
            } else {
                guard let found = stream(at: offset) else { return false }
                section = found
            }
            if first { trailer = section }
            first = false
            guard case .number(let prev)? = section["Prev"] else { break }
            offset = pdfWhole(prev)
        }
        return !offsets.isEmpty || !packed.isEmpty
    }

    /// A classic table and the trailer after it.
    private func table(_ lex: PdfLexer) -> [String: PdfObject] {
        while true {
            lex.skip()
            let w = lex.word()
            if w == "trailer" {
                if case .dict(let d)? = lex.next() { return d }
                return [:]
            }
            // Held to 32 bits, as the Android twin reads them, so start + i
            // cannot overflow on a malformed header.
            guard let start32 = Int32(w) else { return [:] }
            lex.skip()
            guard let count32 = Int32(lex.word()) else { return [:] }
            let start = Int(start32), count = Int(count32)
            var i = 0
            while i < count {
                lex.skip()
                guard let off = Int(lex.word()) else { return [:] }
                lex.skip()
                _ = lex.word()
                lex.skip()
                let kind = lex.word()
                let num = start + i
                if kind == "n", offsets[num] == nil, packed[num] == nil, off > 0 { offsets[num] = off }
                i += 1
            }
        }
    }

    /// A cross-reference stream at `offset`, its entries kept; its dict.
    private func stream(at offset: Int) -> [String: PdfObject]? {
        guard case .stream(let dict, let raw)? = objectAt(offset), let data = decode(dict, raw),
              case .array(let wl)? = dict["W"] else { return nil }
        let w = wl.map { item -> Int in
            if case .number(let n) = item { return min(max(pdfWhole(n), 0), 8) }
            return 0
        }
        guard w.count >= 3 else { return nil }
        var size = 0
        if case .number(let n)? = dict["Size"] { size = pdfWhole(n) }
        var index = [0, size]
        if case .array(let list)? = dict["Index"] {
            index = list.map { item -> Int in
                if case .number(let n) = item { return pdfWhole(n) }
                return 0
            }
        }
        let step = w[0] + w[1] + w[2]
        guard step > 0 else { return dict }
        var p = 0
        func field(_ n: Int, _ fallback: Int) -> Int {
            guard n > 0 else { return fallback }
            var v = 0
            for _ in 0..<n {
                v = (v << 8) | Int(data[p])
                p += 1
            }
            return v
        }
        for k in 0..<(index.count / 2) {
            let count = max(index[2 * k + 1], 0)
            var i = 0
            while i < count {
                if p + step > data.count { return dict }
                let num = index[2 * k] + i
                let type = field(w[0], 1)
                let a = field(w[1], 0)
                _ = field(w[2], 0)
                i += 1
                if offsets[num] != nil || packed[num] != nil { continue }
                if type == 1 { offsets[num] = a } else if type == 2 { packed[num] = a }
            }
        }
        return dict
    }

    /// Every "n g obj" in the file, the last of a number winning, and the
    /// trailer — or the catalog — found the same way.
    private func scan() {
        offsets.removeAll()
        packed.removeAll()
        let text = pdfLatin1(bytes)
        let ns = text as NSString
        if let re = try? NSRegularExpression(pattern: #"(?<![0-9])(\d+)\s+(\d+)\s+obj\b"#) {
            for m in re.matches(in: text, range: NSRange(location: 0, length: ns.length)) {
                if let n = Int(ns.substring(with: m.range(at: 1))) { offsets[n] = m.range.location }
            }
        }
        if let t = find(Array("trailer".utf8), from: 0, backwards: true),
           case .dict(let found)? = PdfLexer(bytes, t + 7).next(), present(found["Root"]) {
            trailer = found
            return
        }
        // Object streams' contents, then the catalog among everything.
        for num in offsets.keys.sorted() {
            guard case .stream(let d, _)? = get(.ref(num, 0)) else { continue }
            if case .name("XRef")? = d["Type"] { trailer = d }
            if case .name("ObjStm")? = d["Type"] {
                for key in unpack(num).map({ Array($0.keys) }) ?? [] where offsets[key] == nil { packed[key] = num }
            }
        }
        if present(trailer["Root"]) { return }
        let catalog = (offsets.keys.sorted() + packed.keys.sorted()).first { num in
            if case .dict(let d)? = get(.ref(num, 0)), case .name("Catalog")? = d["Type"] { return true }
            return false
        }
        if let catalog { trailer = ["Root": .ref(catalog, 0)] }
    }

    /// Whether the bytes from `at` start, past white space, with
    /// "endstream".
    private func endsStream(at start: Int) -> Bool {
        var p = start
        let limit = min(bytes.count, start + 20)
        while p < limit, [9, 10, 11, 12, 13, 28, 29, 30, 31, 32, 0x85, 0xA0].contains(bytes[p]) { p += 1 }
        let word = Array("endstream".utf8)
        guard p + word.count <= limit else { return false }
        return Array(bytes[p..<(p + word.count)]) == word
    }

    /// The object at byte `offset`: "n g obj" and what follows.
    func objectAt(_ offset: Int) -> PdfObject? {
        let lex = PdfLexer(bytes, offset)
        _ = lex.next(refs: false)
        _ = lex.next(refs: false)
        guard case .op("obj")? = lex.next(refs: false) else { return nil }
        let value = lex.next()
        if case .dict(let dict)? = value {
            lex.skip()
            let save = lex.pos
            if lex.word() == "stream" {
                if lex.peek() == 13 { lex.pos += 1 }
                if lex.peek() == 10 { lex.pos += 1 }
                let start = min(lex.pos, bytes.count)
                var declared: Int?
                if case .number(let l)? = dict["Length"] { declared = pdfWhole(l) }
                if case .ref? = dict["Length"], case .number(let l)? = get(dict["Length"]) { declared = pdfWhole(l) }
                let end: Int
                if let d = declared, d >= 0, start + d <= bytes.count, endsStream(at: start + d) {
                    end = start + d
                } else {
                    end = find(Array("endstream".utf8), from: start) ?? bytes.count
                }
                return .stream(dict, Array(bytes[start..<max(start, end)]))
            }
            lex.pos = save
        }
        return value
    }

    /// `v`, followed through its reference when it is one; nil for none or
    /// the null object.
    func get(_ v: PdfObject?) -> PdfObject? {
        guard let v else { return nil }
        guard case .ref(let num, _) = v else {
            if case .null = v { return nil }
            return v
        }
        if let hit = cache[num] {
            if case .null = hit { return nil }
            return hit
        }
        cache[num] = .null
        let found = offsets[num].flatMap { objectAt($0) } ?? packed[num].flatMap { unpack($0)?[num] }
        cache[num] = found ?? .null
        if case .null? = found { return nil }
        return found
    }

    /// The objects packed in object stream `num`, by their numbers.
    func unpack(_ num: Int) -> [Int: PdfObject]? {
        if let done = packs[num] { return done }
        packs[num] = [:]
        guard case .stream(let d, let raw)? = get(.ref(num, 0)), let data = decode(d, raw),
              let n = number(d["N"]).map(pdfWhole), let first = number(d["First"]).map(pdfWhole) else { return nil }
        let lex = PdfLexer(data)
        var pairs: [(Int, Int)] = []
        for _ in 0..<max(n, 0) {
            let a = lex.next(refs: false)
            let b = lex.next(refs: false)
            if case .number(let x)? = a, case .number(let y)? = b { pairs.append((pdfWhole(x), pdfWhole(y))) }
            if lex.atEnd { break }
        }
        var out: [Int: PdfObject] = [:]
        for (obj, off) in pairs { out[obj] = PdfLexer(data, first + off).next() ?? .null }
        packs[num] = out
        return out
    }

    func dict(_ v: PdfObject?) -> [String: PdfObject]? {
        switch get(v) {
        case .dict(let d)?: return d
        case .stream(let d, _)?: return d
        default: return nil
        }
    }

    func list(_ v: PdfObject?) -> [PdfObject]? {
        if case .array(let l)? = get(v) { return l }
        return nil
    }

    func number(_ v: PdfObject?) -> Double? {
        if case .number(let n)? = get(v) { return n }
        return nil
    }

    func name(_ v: PdfObject?) -> String? {
        if case .name(let n)? = get(v) { return n }
        return nil
    }

    /// The leaves of the page tree, in order, each with what it takes from
    /// the nodes above it: Resources, MediaBox and CropBox.
    func pages() -> [[String: PdfObject]] {
        guard let root = dict(trailer["Root"]) else { return [] }
        var out: [[String: PdfObject]] = []
        var seen = Set<[Int]>()
        func walk(_ node: PdfObject?, _ inherited: [String: PdfObject], _ depth: Int) {
            if depth > 64 || out.count > 10000 { return }
            if case .ref(let n, let g)? = node, !seen.insert([n, g]).inserted { return }
            guard let d = dict(node) else { return }
            var carried = inherited
            for k in ["Resources", "MediaBox", "CropBox"] where present(d[k]) { carried[k] = d[k] }
            var isPage = false
            if case .name("Page")? = d["Type"] { isPage = true }
            if let kids = list(d["Kids"]), !isPage {
                for kid in kids { walk(kid, carried, depth + 1) }
            } else {
                var leaf = d
                for (k, v) in carried { leaf[k] = v }
                out.append(leaf)
            }
        }
        walk(root["Pages"], [:], 0)
        return out
    }

    /// A stream's bytes decoded, or nil when a filter is not FlateDecode.
    func decode(_ dict: [String: PdfObject], _ raw: [UInt8]) -> [UInt8]? {
        var filters: [String] = []
        switch get(dict["Filter"]) {
        case nil: break
        case .name(let n)?: filters = [n]
        case .array(let l)?: filters = l.compactMap { name($0) }
        default: return nil
        }
        var parms: [[String: PdfObject]?] = []
        if case .array(let l)? = get(dict["DecodeParms"]) {
            parms = l.map { self.dict($0) }
        } else {
            parms = [self.dict(dict["DecodeParms"])]
        }
        var data = raw
        for (i, f) in filters.enumerated() {
            guard f == "FlateDecode" || f == "Fl" else { return nil }
            data = PDFUpdate.inflated(Data(data)).map { [UInt8]($0) } ?? []
            guard i < parms.count, let parm = parms[i] else { continue }
            let predictor = number(parm["Predictor"]).map(pdfWhole) ?? 1
            if predictor >= 10 {
                let colors = number(parm["Colors"]).map(pdfWhole) ?? 1
                let bits = number(parm["BitsPerComponent"]).map(pdfWhole) ?? 8
                data = unpredict(data, columns: number(parm["Columns"]).map(pdfWhole) ?? 1, bpp: colors * (bits + 7) / 8)
            }
        }
        return data
    }

    /// The PNG predictors, a row of `columns` times `bpp` bytes each with
    /// its filter byte first.
    private func unpredict(_ data: [UInt8], columns: Int, bpp: Int) -> [UInt8] {
        let width = columns * bpp
        guard width > 0, bpp > 0 else { return data }
        var out: [UInt8] = []
        var prior = [UInt8](repeating: 0, count: width)
        var p = 0
        while p + width + 1 <= data.count {
            let filter = data[p]
            var row = Array(data[(p + 1)..<(p + 1 + width)])
            for i in 0..<width {
                let a = i >= bpp ? Int(row[i - bpp]) : 0
                let b = Int(prior[i])
                let c = i >= bpp ? Int(prior[i - bpp]) : 0
                let x = Int(row[i])
                let v: Int
                switch filter {
                case 1: v = x + a
                case 2: v = x + b
                case 3: v = x + (a + b) / 2
                case 4:
                    let pa = abs(b - c), pb = abs(a - c), pc = abs(a + b - 2 * c)
                    v = x + (pa <= pb && pa <= pc ? a : (pb <= pc ? b : c))
                default: v = x
                }
                row[i] = UInt8(truncatingIfNeeded: v)
            }
            out += row
            prior = row
            p += width + 1
        }
        return out
    }

    // MARK: a page

    func page(_ leaf: [String: PdfObject]) -> PdfText.TextPage {
        var box = [0.0, 0.0, 612.0, 792.0]
        if let read = (list(leaf["CropBox"]) ?? list(leaf["MediaBox"]))?.compactMap({ number($0) }), read.count == 4 {
            box = read
        }
        let x0 = min(box[0], box[2])
        let y0 = min(box[1], box[3])
        let width = abs(box[2] - box[0])
        let height = abs(box[3] - box[1])
        var contents: [(dict: [String: PdfObject], raw: [UInt8])] = []
        switch get(leaf["Contents"]) {
        case .stream(let d, let raw)?: contents = [(d, raw)]
        case .array(let l)?:
            for item in l {
                if case .stream(let d, let raw)? = get(item) { contents.append((d, raw)) }
            }
        default: break
        }
        var all: [UInt8] = []
        for s in contents {
            if let bytes = decode(s.dict, s.raw) { all += bytes }
            all.append(10)
        }
        let reader = PdfContent(doc: self, resources: dict(leaf["Resources"]) ?? [:], x0: x0, y0: y0, height: height)
        reader.run(all)
        return PdfText.TextPage(width: width, height: height, runs: reader.runs, type3: reader.type3)
    }
}

// MARK: - fonts

private struct PdfFont {
    var name: String
    var bold: Bool
    var italic: Bool
    var type3: Bool
    var twoByte: Bool
    var unicode: [Int: String]
    var encoding: [String?]?
    var widths: [Int: Double]
    var missing: Double

    func width(_ code: Int) -> Double { widths[code] ?? missing }

    func text(_ code: Int) -> String {
        if let u = unicode[code] { return u }
        if let e = encoding, code >= 0, code < e.count, let s = e[code] { return s }
        return ""
    }

    static func read(_ doc: PdfDoc, _ ref: PdfObject?) -> PdfFont? {
        guard let d = doc.dict(ref) else { return nil }
        let subtype = doc.name(d["Subtype"])
        let base = PdfText.withoutSubset(doc.name(d["BaseFont"]) ?? "")
        let lower = base.lowercased()
        let bold = lower.contains("bold")
        let italic = lower.contains("italic") || lower.contains("oblique")
        var unicode: [Int: String] = [:]
        if case .stream(let sd, let raw)? = doc.get(d["ToUnicode"]), let data = doc.decode(sd, raw) { unicode = cmap(data) }
        if subtype == "Type0" {
            let descendant = doc.dict(doc.list(d["DescendantFonts"])?.first) ?? [:]
            return PdfFont(name: base, bold: bold, italic: italic, type3: false, twoByte: true, unicode: unicode,
                           encoding: nil, widths: cidWidths(doc, doc.list(descendant["W"]) ?? []),
                           missing: doc.number(descendant["DW"]) ?? 1000)
        }
        var widths: [Int: Double] = [:]
        let firstChar = doc.number(d["FirstChar"]).map(pdfWhole) ?? 0
        for (k, v) in (doc.list(d["Widths"]) ?? []).enumerated() {
            if let w = doc.number(v) { widths[firstChar + k] = w }
        }
        let missing = doc.number(doc.dict(d["FontDescriptor"])?["MissingWidth"]).flatMap { $0 > 0 ? $0 : nil } ?? 500
        let fallback = subtype == "Type1" || subtype == "MMType1" ? PdfText.standard : PdfText.winAnsi
        return PdfFont(name: base, bold: bold, italic: italic, type3: subtype == "Type3", twoByte: false,
                       unicode: unicode, encoding: encoding(doc, d["Encoding"], fallback: fallback), widths: widths,
                       missing: missing)
    }

    /// A Type0 font's /W: "c [w1 w2 …]" and "c1 c2 w".
    private static func cidWidths(_ doc: PdfDoc, _ w: [PdfObject]) -> [Int: Double] {
        var widths: [Int: Double] = [:]
        var i = 0
        while i < w.count {
            guard let first = doc.number(w[i]).map(pdfWhole) else { break }
            let next = i + 1 < w.count ? doc.get(w[i + 1]) : nil
            if case .array(let list)? = next {
                for (k, v) in list.enumerated() {
                    if let n = doc.number(v) { widths[first + k] = n }
                }
                i += 2
            } else {
                guard let last = doc.number(next).map(pdfWhole), i + 2 < w.count, let width = doc.number(w[i + 2]) else { break }
                if last >= first && last - first <= 65535 {
                    for c in first...last { widths[c] = width }
                }
                i += 3
            }
        }
        return widths
    }

    /// A simple font's codes as words: its named encoding, or its base
    /// encoding with its /Differences, else `fallback`.
    private static func encoding(_ doc: PdfDoc, _ value: PdfObject?, fallback: [String?]) -> [String?] {
        func named(_ n: String?) -> [String?]? {
            switch n {
            case "WinAnsiEncoding": return PdfText.winAnsi
            case "MacRomanEncoding": return PdfText.macRoman
            case "StandardEncoding": return PdfText.standard
            default: return nil
            }
        }
        switch doc.get(value) {
        case .name(let n)?:
            return named(n) ?? fallback
        case .dict(let e)?:
            var table = named(doc.name(e["BaseEncoding"])) ?? fallback
            var code = 0
            for item in doc.list(e["Differences"]) ?? [] {
                switch doc.get(item) {
                case .number(let n)?:
                    code = pdfWhole(n)
                case .name(let n)?:
                    if code >= 0 && code <= 255 { table[code] = PdfText.glyph(n) }
                    code += 1
                default:
                    break
                }
            }
            return table
        default:
            return fallback
        }
    }

    /// A ToUnicode CMap's codes and their words.
    private static func cmap(_ data: [UInt8]) -> [Int: String] {
        var out: [Int: String] = [:]
        let lex = PdfLexer(data)
        var tokens: [PdfObject] = []
        while true {
            lex.skip()
            if lex.atEnd { break }
            tokens.append(lex.next(refs: false) ?? .null)
        }
        func codeOf(_ t: PdfObject) -> Int? {
            guard case .string(let b) = t else { return nil }
            return b.reduce(0) { ($0 &<< 8) | Int($1) }
        }
        func wordsOf(_ t: PdfObject) -> String? {
            switch t {
            case .string(let b): return utf16(b)
            case .name(let n): return PdfText.glyph(n)
            default: return nil
            }
        }
        func isOp(_ t: PdfObject, _ name: String) -> Bool {
            if case .op(let o) = t { return o == name }
            return false
        }
        var i = 0
        while i < tokens.count {
            let t = tokens[i]
            if isOp(t, "beginbfchar") {
                i += 1
                while i + 1 < tokens.count && !isOp(tokens[i], "endbfchar") {
                    if let c = codeOf(tokens[i]), let w = wordsOf(tokens[i + 1]) { out[c] = w }
                    i += 2
                }
            } else if isOp(t, "beginbfrange") {
                i += 1
                while i + 2 < tokens.count && !isOp(tokens[i], "endbfrange") {
                    if let lo = codeOf(tokens[i]), let hi = codeOf(tokens[i + 1]), hi >= lo, hi - lo <= 65535 {
                        switch tokens[i + 2] {
                        case .array(let dst):
                            for (k, d) in dst.enumerated() where lo + k <= hi {
                                if let w = wordsOf(d) { out[lo + k] = w }
                            }
                        case .string(let dst) where !dst.isEmpty:
                            for c in lo...hi {
                                var bytes = dst
                                let last = bytes.count - 1
                                let v = Int(bytes[last]) + (c - lo)
                                bytes[last] = UInt8(truncatingIfNeeded: v)
                                if last > 0 { bytes[last - 1] = UInt8(truncatingIfNeeded: Int(bytes[last - 1]) + (v >> 8)) }
                                out[c] = utf16(bytes)
                            }
                        default:
                            break
                        }
                    }
                    i += 3
                }
            }
            i += 1
        }
        return out
    }

    private static func utf16(_ bytes: [UInt8]) -> String {
        guard bytes.count % 2 == 0 else { return pdfLatin1(bytes) }
        let units = stride(from: 0, to: bytes.count, by: 2).map { UInt16(bytes[$0]) << 8 | UInt16(bytes[$0 + 1]) }
        return String(decoding: units, as: UTF16.self)
    }
}

// MARK: - content

/// A page's content read: its runs, and whether a Type3 font is used.
private final class PdfContent {
    let doc: PdfDoc
    let resources: [String: PdfObject]
    let x0: Double
    let y0: Double
    let height: Double
    var runs: [PdfText.PdfRun] = []
    var type3 = false

    private struct State {
        var ctm: [Double] = [1, 0, 0, 1, 0, 0]
        var fill = "#000000"
        var tc = 0.0
        var tw = 0.0
        var th = 1.0
        var tl = 0.0
        var rise = 0.0
        var font: PdfFont?
        var size = 0.0
    }

    private var g = State()
    private var stack: [State] = []
    private var tm: [Double] = [1, 0, 0, 1, 0, 0]
    private var tlm: [Double] = [1, 0, 0, 1, 0, 0]
    private var fonts: [String: PdfFont?] = [:]

    init(doc: PdfDoc, resources: [String: PdfObject], x0: Double, y0: Double, height: Double) {
        self.doc = doc
        self.resources = resources
        self.x0 = x0
        self.y0 = y0
        self.height = height
    }

    func run(_ data: [UInt8]) {
        let lex = PdfLexer(data)
        var operands: [PdfObject] = []
        var count = 0
        while true {
            lex.skip()
            if lex.atEnd { break }
            let t = lex.next(refs: false) ?? .null
            guard case .op(let name) = t else {
                operands.append(t)
                continue
            }
            count += 1
            if count > 2_000_000 { break }
            if name == "ID" { skipInlineImage(lex) } else { op(name, operands) }
            operands.removeAll()
        }
    }

    /// An inline image's bytes, to the "EI" after them.
    private func skipInlineImage(_ lex: PdfLexer) {
        let b = lex.b
        var p = lex.pos + 1
        while p + 2 < b.count {
            if b[p] == 0x45 && b[p + 1] == 0x49 && PdfLexer.white(Int(b[p - 1]))
                && (p + 2 >= b.count || PdfLexer.white(Int(b[p + 2]))) {
                lex.pos = p + 2
                return
            }
            p += 1
        }
        lex.pos = b.count
    }

    private func n(_ o: [PdfObject], _ i: Int) -> Double {
        guard i < o.count, case .number(let v) = o[i] else { return 0 }
        return v
    }

    private func shown(_ o: [PdfObject]) -> [PdfObject]? {
        if case .string? = o.last, let last = o.last { return [last] }
        return nil
    }

    private func op(_ op: String, _ o: [PdfObject]) {
        switch op {
        case "q": stack.append(g)
        case "Q": if let top = stack.popLast() { g = top }
        case "cm": if o.count >= 6 { g.ctm = multiply((0..<6).map { n(o, $0) }, g.ctm) }
        case "BT":
            tm = [1, 0, 0, 1, 0, 0]
            tlm = tm
        case "Tf":
            g.size = n(o, 1)
            if let first = o.first, case .name(let key) = first {
                if let cached = fonts[key] {
                    g.font = cached
                } else {
                    let read = PdfFont.read(doc, doc.dict(resources["Font"])?[key])
                    fonts[key] = .some(read)
                    g.font = read
                }
            } else {
                g.font = nil
            }
        case "Tc": g.tc = n(o, 0)
        case "Tw": g.tw = n(o, 0)
        case "Tz": g.th = n(o, 0) / 100
        case "TL": g.tl = n(o, 0)
        case "Ts": g.rise = n(o, 0)
        case "Td": move(n(o, 0), n(o, 1))
        case "TD":
            g.tl = -n(o, 1)
            move(n(o, 0), n(o, 1))
        case "Tm":
            if o.count >= 6 {
                tm = (0..<6).map { n(o, $0) }
                tlm = tm
            }
        case "T*": move(0, -g.tl)
        case "Tj": if let items = shown(o) { show(items) }
        case "TJ": if case .array(let items)? = o.last { show(items) }
        case "'":
            move(0, -g.tl)
            if let items = shown(o) { show(items) }
        case "\"":
            g.tw = n(o, 0)
            g.tc = n(o, 1)
            move(0, -g.tl)
            if let items = shown(o) { show(items) }
        case "rg": if o.count >= 3 { g.fill = hex(n(o, 0), n(o, 1), n(o, 2)) }
        case "g": if !o.isEmpty { g.fill = hex(n(o, 0), n(o, 0), n(o, 0)) }
        case "k":
            if o.count >= 4 {
                let k = n(o, 3)
                g.fill = hex((1 - n(o, 0)) * (1 - k), (1 - n(o, 1)) * (1 - k), (1 - n(o, 2)) * (1 - k))
            }
        default:
            break
        }
    }

    private func move(_ tx: Double, _ ty: Double) {
        tlm = multiply([1, 0, 0, 1, tx, ty], tlm)
        tm = tlm
    }

    /// One Tj, TJ, ' or " shown: a run where it starts, the text matrix
    /// then moved past it.
    private func show(_ items: [PdfObject]) {
        guard let font = g.font else { return }
        if font.type3 {
            type3 = true
            return
        }
        let start = multiply(tm, g.ctm)
        var text = ""
        var advance = 0.0
        for item in items {
            switch item {
            case .number(let v):
                advance += -v / 1000 * g.size * g.th
                if v < -250, let last = text.last, !last.isWhitespace { text += " " }
            case .string(let bytes):
                var i = 0
                while i < bytes.count {
                    let code: Int
                    if font.twoByte && i + 1 < bytes.count {
                        code = Int(bytes[i]) << 8 | Int(bytes[i + 1])
                        i += 2
                    } else {
                        code = Int(bytes[i])
                        i += 1
                    }
                    text += font.text(code)
                    let space = !font.twoByte && code == 32 ? g.tw : 0
                    advance += (font.width(code) / 1000 * g.size + g.tc + space) * g.th
                }
            default:
                break
            }
        }
        let origin = apply(start, 0, g.rise)
        let scaleX = hypot(start[0], start[1])
        let scaleY = hypot(start[2], start[3])
        if !text.isEmpty {
            runs.append(PdfText.PdfRun(text: text, x: origin.x - x0, y: height - (origin.y - y0), size: g.size * scaleY,
                                    font: font.name, bold: font.bold, italic: font.italic, colour: g.fill,
                                    width: advance * scaleX))
        }
        tm = multiply([1, 0, 0, 1, advance, 0], tm)
    }

    private func hex(_ r: Double, _ gr: Double, _ b: Double) -> String {
        func c(_ v: Double) -> Int { Int((min(max(v, 0), 1) * 255 + 0.5).rounded(.down)) }
        return String(format: "#%02x%02x%02x", c(r), c(gr), c(b))
    }

    /// `a` then `b`, as PDF matrices [a b c d e f] multiply.
    private func multiply(_ a: [Double], _ b: [Double]) -> [Double] {
        [a[0] * b[0] + a[1] * b[2],
         a[0] * b[1] + a[1] * b[3],
         a[2] * b[0] + a[3] * b[2],
         a[2] * b[1] + a[3] * b[3],
         a[4] * b[0] + a[5] * b[2] + b[4],
         a[4] * b[1] + a[5] * b[3] + b[5]]
    }

    private func apply(_ m: [Double], _ x: Double, _ y: Double) -> (x: Double, y: Double) {
        (x * m[0] + y * m[2] + m[4], x * m[1] + y * m[3] + m[5])
    }
}
