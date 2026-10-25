// A PowerPoint deck (.pptx) opened as a new design — the Android twin's
// PptxReader, rule for rule, so the same file is the same design on either
// phone (the shared fixture, Tests/Fixtures/deck.pptx, holds them to it).
// PptxExporter goes the other way, and a deck it wrote reads back with its
// words, places and notes.
//
// What is read, and how, where the format left a choice:
//
//   • the slide size is ppt/presentation.xml's p:sldSz, and the slides are
//     p:sldIdLst's, in its order, through the presentation's relationships
//   • a length is EMU ÷ 9525 page pixels and an angle 60000ths of a
//     degree, neither rounded; a group's children are placed by its
//     chOff / chExt, its own turn and flips left out
//   • a page's background is the slide's p:bg, else its layout's, else its
//     master's: a colour, a two-stop-or-more linear gradient, or a picture;
//     none, or anything else, is white
//   • p:sp and p:cxnSp: a preset line or straight connector is a line
//     (line(from:)); otherwise a rectangle, rounded rectangle, oval or
//     triangle with a fill or a border shows as a shape — any other outline
//     that would show is a shape left out — and its words, when it has any,
//     as a text box over it, inset by its bodyPr insets
//   • a shape with no a:xfrm of its own that is a placeholder takes its
//     place from its layout's placeholder with the same idx (else type),
//     else from its master's of the same type (Walk.inherited)
//   • words (words(of:)): a paragraph a line, runs as they are; a run's
//     look is its own a:rPr, else its box's a:lstStyle at level 1, else —
//     for a placeholder — its layout's placeholder's, else its master's,
//     else the master's text style for its kind of box (title for a title;
//     other for a date, footer, slide number or a shape that is no
//     placeholder; else body) at level 1, else 18 pt black in the theme's
//     body font; a placeholder's anchor and insets are its own bodyPr's,
//     else its layout's placeholder's, else its master's; the box takes
//     the first run's size, colour and font that has words other than
//     spaces, and is bold, italic or underlined when every one is — a run
//     that is when the box is not is written in RichText's markers, and a
//     run's own colour, size or font is a span (Spans)
//   • a paragraph's list and lvl, the first paragraph's line spacing and
//     the room round it, are its pPr's, else its level's in the box's
//     lstStyle, its placeholder's layout's and master's, else the master's
//     body or other style (words(of:), list(bullet:autoNum:)); a run's
//     spc and strike (its own or its list styles' defRPr) and hlinkClick its
//     letter spacing, ~~ and link (spaced, jumped); normAutofit's fontScale
//     and lnSpcReduction are applied, so shrunk type comes in at the size
//     it showed
//   • every *, _, ~ and backslash of the deck's own words is escaped
//     (RichText.escapeLiteral), so the words read exactly as the deck has
//     them and only the runs' own styles are markers
//   • a typeface is a bundled family when its name or id matches, capitals,
//     accents, spaces and dashes aside (family(of:)); any other — the
//     theme's fonts among them — is Modern Sans, and said as a font left
//     out, once a face
//   • p:pic is a photo of its picture in ppt/media, when that is a PNG,
//     JPEG, GIF, BMP or WebP; any other picture, a video or a sound is
//     left out
//   • a p:graphicFrame table is a table (table(_:)): a rectangle and a text
//     per cell, as Tables keeps them, gridSpan and rowSpan its merges; a
//     cell's picture fill is a picture left out, the cell white; a chart,
//     SmartArt or anything else in one is left out
//   • mc:AlternateContent is read as its mc:Fallback
//   • groups (and fallbacks) within one another past maxDepth are not a
//     deck the phone opens: the read is nil
//   • the notes slide's body placeholder is the page's notes, a paragraph a
//     line; the slide's title placeholder's words, on one line with single
//     spaces between them, its title
//   • ids are made by read's `ids` in reading order — the design's, then
//     each page's followed by its elements' bottom up, a group's id when it
//     is met, and a table's group and table ids before its cells, row by
//     row, the rectangles then the texts
//
// Pure: the pictures come out as "media:<name in the deck>" with the part
// of the file their bytes are in, for the app to store (placed).

import Foundation

enum PptxReader {

    static let fileExtension = PptxExporter.fileExtension
    static let mimeType = PptxExporter.mimeType
    /// The type a deck is shared and opened as.
    static let typeIdentifier = "org.openxmlformats.presentationml.presentation"

    /// EMU in a page pixel: 914400 to the inch at 96 dpi.
    static let emuPerPixel = 9525.0
    /// Hundredths of a point in a page pixel at 96 dpi.
    static let sizePerPixel = 75.0

    /// Past any real deck a phone can open; read no further.
    static let maxFileBytes = 200 * 1024 * 1024
    /// The most of one part of the file that is read: past it, the part is
    /// as good as missing, so a file that inflates without end stops here.
    static let maxPartBytes = 64 * 1024 * 1024

    /// The pictures that come in as photos, by their file's extension.
    static let pictureTypes: Set<String> = ["png", "jpg", "jpeg", "gif", "bmp", "webp"]

    /// A run's type with no size of its own anywhere: 18 pt.
    static let defaultType = 1800.0

    /// The most groups within groups (and fallbacks) read; one deeper and
    /// the deck is not read.
    static let maxDepth = 64

    /// A table's border, as a new table's hairline.
    static let tableBorder = "#00000022"

    // What was left out, by kind, in the order the summary says them.
    static let chart = "chart"
    static let smartArt = "SmartArt"
    static let video = "video"
    static let sound = "sound"
    static let picture = "picture"
    static let shape = "shape"
    static let font = "font"
    static let other = "other"
    static let kinds = [chart, smartArt, video, sound, picture, shape, font, other]

    /// What a file is said to be when it is not a deck with slides.
    static let notADeck = tr("That file isn't a PowerPoint presentation.")
    static let tooBig = tr("That PowerPoint is too big to open.")

    private static let mediaPrefix = "media:"

    // MARK: the file

    /// The file's parts by name, read when asked for — from a ZIP mapped
    /// from the file, so its pictures are inflated one at a time. Names are
    /// matched without regard to case, as the format's are.
    struct Parts {
        private let byName: [String: String]
        private let reader: (String) -> Data?

        init(names: [String], reader: @escaping (String) -> Data?) {
            byName = Dictionary(names.map { ($0.lowercased(), $0) }, uniquingKeysWith: { first, _ in first })
            self.reader = reader
        }

        /// An archive's files, each read only while it is within
        /// maxPartBytes.
        init(zip: ZipStore.Reader) {
            self.init(names: Array(zip.entries.keys)) { name in
                guard let size = zip.size(of: name), size <= PptxReader.maxPartBytes else { return nil }
                return zip.file(name)
            }
        }

        /// A whole file's bytes; nil when it is not a ZIP.
        static func of(_ data: Data) -> Parts? {
            guard let zip = try? ZipStore.Reader(data: data, inflating: true), !zip.entries.isEmpty else { return nil }
            return Parts(zip: zip)
        }

        func has(_ path: String) -> Bool { byName[path.lowercased()] != nil }

        func bytes(_ path: String) -> Data? { byName[path.lowercased()].flatMap(reader) }
    }

    /// Whether `head` — a file's first bytes — opens a ZIP, as a .pptx does.
    static func isZip(_ head: Data) -> Bool {
        Array(head.prefix(4)) == [0x50, 0x4b, 0x03, 0x04]
    }

    /// A deck read: the design, each picture it shows as "media:<key>" with
    /// the part of the file its bytes are in, and how many things of each
    /// kind (`kinds`) were left out.
    struct Imported {
        var design: Design
        var media: [String: String]
        var skipped: [String: Int]

        var summary: String { PptxReader.summary(slides: design.pages.count, skipped: skipped) }
    }

    /// "Quarterly review" for "Quarterly review.pptx"; an untitled design's
    /// name for none.
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

    /// What the sheet after an import says: "Imported 12 slides." and, when
    /// anything was left out, "3 items couldn't be brought in (2 charts, 1
    /// SmartArt)." — each kind in `kinds`' order.
    static func summary(slides: Int, skipped: [String: Int]) -> String {
        let head = trn("Imported %d slide.|Imported %d slides.", slides)
        let counted = kinds.compactMap { kind -> (String, Int)? in
            guard let n = skipped[kind], n > 0 else { return nil }
            return (kind, n)
        }
        let total = counted.reduce(0) { $0 + $1.1 }
        guard total > 0 else { return head }
        let parts = counted.map { label($0.0, $0.1) }.joined(separator: ", ")
        return head + " " + trn("%d item couldn't be brought in (%@).|%d items couldn't be brought in (%@).", total, parts)
    }

    /// "2 charts", "1 SmartArt": `n` of `kind`.
    private static func label(_ kind: String, _ n: Int) -> String {
        switch kind {
        case chart: return trn("%d chart|%d charts", n)
        case smartArt: return trn("%d SmartArt|%d SmartArt", n)
        case video: return trn("%d video|%d videos", n)
        case sound: return trn("%d sound|%d sounds", n)
        case picture: return trn("%d picture|%d pictures", n)
        case shape: return trn("%d shape|%d shapes", n)
        case font: return trn("%d font|%d fonts", n)
        case other: return trn("%d other item|%d other items", n)
        default: return "\(n) " + (n == 1 ? kind : kind + "s")
        }
    }

    /// The deck in `parts` as a new design called `title`, made at `now`
    /// (milliseconds), every id from `ids` (by its prefix: "doc", "page",
    /// "el", "grp", "tbl"); nil when it is not a deck or has no slides.
    static func read(parts: Parts, title: String, now: Double = Date().timeIntervalSince1970 * 1000,
                     ids: @escaping (String) -> String = { UID.make($0) }) -> Imported? {
        DeckReader(parts: parts, ids: ids).read(title: title, now: now)
    }

    /// The same, of a whole file's bytes.
    static func read(_ data: Data, title: String, now: Double = Date().timeIntervalSince1970 * 1000,
                     ids: @escaping (String) -> String = { UID.make($0) }) -> Imported? {
        Parts.of(data).flatMap { read(parts: $0, title: title, now: now, ids: ids) }
    }

    /// `imported`'s design with its pictures where the phone stored them:
    /// "media:<key>" as `stored` gives it. A photo whose bytes could not be
    /// stored is taken out, a page's picture behind it is white, and each
    /// is a picture left out.
    static func placed(_ imported: Imported, stored: [String: String]) -> Imported {
        var missed = 0
        /// Where `src` went: itself when it is not one of the deck's
        /// pictures, nil when that was not stored.
        func moved(_ src: String?) -> String? {
            guard let src, src.hasPrefix(mediaPrefix) else { return src }
            let key = String(src.dropFirst(mediaPrefix.count))
            guard imported.media[key] != nil else { return src }
            return stored[key]
        }
        var design = imported.design
        for p in design.pages.indices {
            if case .image(let src) = design.pages[p].background {
                if let to = moved(src) {
                    design.pages[p].background = .image(to)
                } else {
                    design.pages[p].background = .color("#ffffff")
                    missed += 1
                }
            }
            design.pages[p].elements = design.pages[p].elements.compactMap { el -> Element? in
                var out = el
                if el.type == .image {
                    guard let to = moved(el.src) else {
                        missed += 1
                        return nil
                    }
                    out.src = to
                } else if el.fill?.kind == "image" {
                    guard let to = moved(el.fill?.src) else {
                        missed += 1
                        return nil
                    }
                    out.fill = .image(to)
                }
                return out
            }
        }
        var skipped = imported.skipped
        if missed > 0 { skipped[picture] = (skipped[picture] ?? 0) + missed }
        return Imported(design: design, media: imported.media, skipped: skipped)
    }

    // MARK: fonts

    private static func fontKey(_ text: String) -> String {
        String(FontLibrary.folded(text).filter { $0.isLetter || $0.isNumber })
    }

    /// The bundled family a deck's `typeface` is: the one whose name or id
    /// it is, capitals, accents, spaces and dashes aside ("Playfair
    /// Display", "playfair-display", "PlayfairDisplay"); nil for any other.
    static func family(of typeface: String?) -> String? {
        guard let typeface else { return nil }
        let key = fontKey(typeface)
        guard !key.isEmpty else { return nil }
        return FontLibrary.all.first { fontKey($0.name) == key || fontKey($0.id) == key }?.id
    }

    /// A bundled family's cut a deck's `typeface` names, as the writer names
    /// one ("Montserrat Light", "Lora Bold"): the family and the weight of
    /// the cut, by the Weight row's English names
    /// (FontLibrary.englishWeightNames) or its number; nil for a family
    /// alone, or any other face. The Android twin's PptxReader.cut.
    static func cut(_ typeface: String?) -> (family: String, weight: Int)? {
        guard let face = typeface?.trimmingCharacters(in: .whitespaces), !face.isEmpty else { return nil }
        let last = face.split(separator: " ", omittingEmptySubsequences: false).last.map(String.init) ?? ""
        // The longest name that fits: "Extra bold" before "Bold".
        let named = FontLibrary.englishWeightNames
            .filter { face.lowercased().hasSuffix(" " + $0.value.lowercased()) }
            .max { $0.value.count < $1.value.count }
        let weight: Int
        let cut: String
        if let named {
            weight = named.key
            cut = named.value
        } else if let number = Int(last), Spans.weightRange.contains(number) {
            weight = number
            cut = last
        } else {
            return nil
        }
        guard let family = family(of: String(face.dropLast(cut.count + 1))) else { return nil }
        return (family, weight)
    }

    // MARK: numbers

    fileprivate static func px(_ emu: Double) -> Double { emu / emuPerPixel }

    fileprivate static func number(_ node: SvgImport.Node?, _ key: String) -> Double? {
        guard let raw = node?.attributes[key]?.trimmingCharacters(in: .whitespaces),
              let value = Double(raw), value.isFinite else { return nil }
        return value
    }

    fileprivate static func flag(_ node: SvgImport.Node?, _ key: String) -> Bool? {
        switch node?.attributes[key]?.trimmingCharacters(in: .whitespaces) {
        case "1", "true", "on": return true
        case "0", "false", "off": return false
        default: return nil
        }
    }

    /// Degrees turned into 0 up to 360.
    fileprivate static func turned(_ degrees: Double) -> Double {
        let t = (degrees.truncatingRemainder(dividingBy: 360) + 360).truncatingRemainder(dividingBy: 360)
        return t >= 360 ? 0 : t
    }

    /// Whether a UTF-16 unit is white space, as the Android twin's
    /// Char.isWhitespace has it.
    fileprivate static func isSpace(_ unit: UInt16) -> Bool {
        Unicode.Scalar(unit)?.properties.isWhitespace ?? false
    }

    fileprivate static func isBlank(_ text: String) -> Bool {
        text.utf16.allSatisfy(isSpace)
    }

    /// Whether a UTF-16 unit is what a page title is split on and joined
    /// with one space: ASCII white space only, " \t\n\u{0B}\u{0C}\r", as the
    /// Android twin's Regex("\\s+") has it — a no-break space stays in its
    /// word.
    fileprivate static func isTitleSpace(_ unit: UInt16) -> Bool {
        unit == 0x20 || (0x09...0x0D).contains(unit)
    }

    /// The fills DeckReader.fill reads, the first of them a shape's own.
    fileprivate static let fillNames: Set<String> = ["noFill", "solidFill", "gradFill", "pattFill", "blipFill"]

    // MARK: parts and relationships

    /// A relationship's type, by its last word, and where it points.
    fileprivate struct Rel {
        var type: String
        var target: String
        var external: Bool
    }

    /// One XML part, read, and its relationships, their targets resolved,
    /// by id and in the order written.
    fileprivate final class Part {
        let path: String
        let root: SvgImport.Node
        let rels: [String: Rel]
        let order: [Rel]

        init(path: String, root: SvgImport.Node, rels: [String: Rel], order: [Rel]) {
            self.path = path
            self.root = root
            self.rels = rels
            self.order = order
        }
    }

    /// The part `target` names, from part `base`'s folder.
    fileprivate static func resolve(_ base: String, _ target: String) -> String {
        if target.hasPrefix("/") { return String(target.drop { $0 == "/" }) }
        var out = base.split(separator: "/").dropLast().map(String.init)
        for segment in target.split(separator: "/", omittingEmptySubsequences: false).map(String.init) {
            switch segment {
            case "", ".": continue
            case "..": if !out.isEmpty { out.removeLast() }
            default: out.append(segment)
            }
        }
        return out.joined(separator: "/")
    }

    fileprivate static func relsPath(_ part: String) -> String {
        guard let slash = part.lastIndex(of: "/") else { return "_rels/\(part).rels" }
        return "\(part[..<slash])/_rels/\(part[part.index(after: slash)...]).rels"
    }

    /// An XML document's own first tag, as a tree, each tag by its name
    /// without its namespace (the SVG reader's).
    fileprivate static func document(_ data: Data?) -> SvgImport.Node? {
        guard let data else { return nil }
        return SvgImport.parse(String(decoding: data, as: UTF8.self))
    }

    // MARK: looks

    /// The theme's colours by name and its two fonts.
    fileprivate struct Theme {
        var colours: [String: String] = [:]
        var major: String?
        var minor: String?
    }

    /// A look a text style gives words: any of size (hundredths of a point),
    /// bold, italic, underline, colour, typeface and alignment.
    fileprivate struct Look {
        var size: Double?
        var bold: Bool?
        var italic: Bool?
        var underline: Bool?
        var colour: String?
        var typeface: String?
        var align: String?
        /// Struck through (strike sngStrike or dblStrike; noStrike false).
        var strike: Bool?
        /// Its spc, hundredths of a point between letters.
        var spacing: Double?

        /// This, its gaps filled from `under`.
        func over(_ under: Look?) -> Look {
            guard let under else { return self }
            return Look(size: size ?? under.size, bold: bold ?? under.bold, italic: italic ?? under.italic,
                        underline: underline ?? under.underline, colour: colour ?? under.colour,
                        typeface: typeface ?? under.typeface, align: align ?? under.align,
                        strike: strike ?? under.strike, spacing: spacing ?? under.spacing)
        }
    }

    /// A run of words in one look, from `start` until `end` in the box's
    /// plain words, in UTF-16 offsets.
    fileprivate struct Run {
        var start: Int
        var end: Int
        var size: Double
        var bold: Bool
        var italic: Bool
        var underline: Bool
        var colour: String
        var font: String
        /// The cut its face names ("Montserrat Light"), as the words' own
        /// weight; nil for a family alone.
        var weight: Int? = nil
        /// Its a:highlight's colour, "#rrggbb" or "#rrggbbaa"; nil for none.
        var highlight: String? = nil
        /// Raised or lowered (TextSpan.script), from its a:rPr's baseline.
        var script: String? = nil
        /// In capitals: its a:rPr's cap="all".
        var caps = false
        /// Struck through: its a:rPr's strike, sngStrike or dblStrike.
        var strike = false
        /// Its a:rPr's spc, hundredths of a point between letters; nil for
        /// none said.
        var spacing: Double? = nil
        /// Where its a:hlinkClick goes: a followable address, or a jump to
        /// a slide (slideLink) until the slides' pages are known.
        var link: String? = nil
    }

    /// A paragraph's line spacing or the room before or after it, as the
    /// deck says it: a share of the type (spcPct, 100000 the whole) or
    /// hundredths of a point (spcPts).
    fileprivate enum Gap {
        case pct(Double)
        case pts(Double)

        /// In ems of type `size` page pixels high.
        func ems(size: Double) -> Double {
            switch self {
            case .pct(let value): return value / 100_000
            case .pts(let value): return size > 0 ? value / PptxReader.sizePerPixel / size : 0
            }
        }
    }

    /// The line height a deck's single spacing (lnSpc spcPct 100%) is: a
    /// new text's own, 1.25 — so a deck at single spacing comes in at the
    /// default, and the writer's lnSpc is lineHeight ÷ 1.25. Both phones'
    /// rule (the Android twin's PptxWriter.LINE_SPACING_EM).
    static let singleSpacing = 1.25

    /// The list an a:pPr's bullet makes, the rule both phones share:
    /// buChar (and a picture's buBlip) a bullet, buAutoNum arabic… a
    /// number, alphaLc… or alphaUc… letters, roman… — and any other
    /// numbering — a number; buNone none. Nil when it names none of them.
    static func list(bullet: String?, autoNum: String? = nil) -> String? {
        switch bullet {
        case "buChar", "buBlip": return "bullet"
        case "buNone": return "none"
        case "buAutoNum":
            let scheme = autoNum ?? ""
            return scheme.hasPrefix("alphaLc") || scheme.hasPrefix("alphaUc") ? "letter" : "number"
        default: return nil
        }
    }

    /// What a jump to a slide reads as until the slides' pages are known:
    /// a page link to the slide's place in the deck's list.
    fileprivate static let slidePrefix = "pptx-slide-"

    fileprivate static func slideLink(_ index: Int) -> String { Links.pageLink(slidePrefix + String(index)) }

    /// The script an a:rPr's baseline — thousandths of a percent of the
    /// size, as "30000" — gives its words: above 0 raised, below 0 lowered,
    /// none on the line, on both phones.
    static func script(baseline: String?) -> String? {
        guard let raw = baseline?.trimmingCharacters(in: .whitespaces), let value = Int(raw), value != 0 else {
            return nil
        }
        return value > 0 ? Spans.raised : Spans.lowered
    }

    /// A box's words: with the first run's own a:rPr (`props`), where the
    /// writer's styling (a shadow, a glow, an outline) is read back.
    fileprivate struct Words {
        var plain: String
        var runs: [Run]
        var align: String?
        var props: SvgImport.Node? = nil
        /// Each line's own alignment, a paragraph's and its line breaks';
        /// nil where it says none.
        var aligns: [String?] = []
        /// Each line's list and level, a paragraph's and its line breaks'.
        var lines: [TextParagraph] = []
        /// The first paragraph's a:lnSpc, a:spcBef and a:spcAft, as its
        /// pPr, else its list style's level, says them.
        var lineSpacing: Gap? = nil
        var before: Gap? = nil
        var after: Gap? = nil
    }

    /// A box in EMU on the slide: where, how big, turned and flipped.
    fileprivate struct Box {
        var x: Double
        var y: Double
        var w: Double
        var h: Double
        var rotation: Double
        var flipH: Bool
        var flipV: Bool
    }

    /// Where a group's children go: x' = ox + (x − chx) × sx, and so for y.
    fileprivate struct Place {
        var ox: Double
        var oy: Double
        var chx: Double
        var chy: Double
        var sx: Double
        var sy: Double

        static let slide = Place(ox: 0, oy: 0, chx: 0, chy: 0, sx: 1, sy: 1)

        func box(_ b: Box) -> Box {
            Box(x: ox + (b.x - chx) * sx, y: oy + (b.y - chy) * sy, w: b.w * sx, h: b.h * sy,
                rotation: b.rotation, flipH: b.flipH, flipV: b.flipV)
        }

        /// A group inside this one, at `frame`, its children's own box — its
        /// chOff and chExt — at `chx`, `chy`, `chw` by `chh`.
        func inside(_ frame: Box, chx: Double, chy: Double, chw: Double, chh: Double) -> Place {
            let gx = chw > 0 ? frame.w / chw : 1
            let gy = chh > 0 ? frame.h / chh : 1
            return Place(ox: ox + (frame.x - self.chx) * sx, oy: oy + (frame.y - self.chy) * sy,
                         chx: chx, chy: chy, sx: gx * sx, sy: gy * sy)
        }
    }

    /// The shapes a placeholder follows on its layout and its master.
    fileprivate struct Inherited {
        var layout: SvgImport.Node?
        var master: SvgImport.Node?

        /// Their level-1 list styles, the layout's first.
        var levels: [SvgImport.Node] {
            [layout?.at("txBody", "lstStyle", "lvl1pPr"), master?.at("txBody", "lstStyle", "lvl1pPr")].compactMap { $0 }
        }

        /// Their whole list styles, every level, the layout's first.
        var listStyles: [SvgImport.Node] {
            [layout?.at("txBody", "lstStyle"), master?.at("txBody", "lstStyle")].compactMap { $0 }
        }

        /// Their bodyPrs, the layout's first.
        var bodies: [SvgImport.Node] {
            [layout?.at("txBody", "bodyPr"), master?.at("txBody", "bodyPr")].compactMap { $0 }
        }
    }

    fileprivate struct Border {
        var colour: String
        var width: Double
        var dash: String
    }

    fileprivate struct Insets {
        var left: Double
        var top: Double
        var right: Double
        var bottom: Double
    }

    /// Which of the master's text styles a box's words follow.
    fileprivate enum TextKind: String {
        case title, body, other
    }

    /// A box's a:xfrm in EMU: its offset, its size, its turn in degrees and
    /// its flips; nil without an offset and a size.
    fileprivate static func box(of xfrm: SvgImport.Node?) -> Box? {
        guard let xfrm, let off = xfrm.child("off"), let ext = xfrm.child("ext") else { return nil }
        return Box(x: number(off, "x") ?? 0, y: number(off, "y") ?? 0,
                   w: max(0, number(ext, "cx") ?? 0), h: max(0, number(ext, "cy") ?? 0),
                   rotation: (number(xfrm, "rot") ?? 0) / 60000,
                   flipH: flag(xfrm, "flipH") == true, flipV: flag(xfrm, "flipV") == true)
    }

    /// The box's words with each run's bold, italic and underline that the
    /// box as a whole does not have, and its strike, written in RichText's
    /// markers — "**", "*", "__" and "~~", outermost first — round the run's words, line by line,
    /// spaces at either end left outside, and the deck's own marker
    /// characters escaped. Read back, they must give the same words in the
    /// same styles; when they do not, the words go in plain, escaped.
    fileprivate static func marked(_ words: Words, bold: Bool, italic: Bool, underline: Bool) -> String {
        let units = Array(words.plain.utf16)
        let count = units.count
        var want = [RichText.Style](repeating: RichText.Style(), count: count)
        for r in words.runs where 0 <= r.start && r.start < r.end && r.end <= count {
            // A run with a cut of its own ("Montserrat Semibold") has its
            // weight in its span; its b="1" is only the writer saying the
            // cut is heavy, and a ** round it would draw it bolder still.
            let style = RichText.Style(bold: r.bold && r.weight == nil && !bold, italic: r.italic && !italic,
                                       underline: r.underline && !underline, strike: r.strike)
            for k in r.start..<r.end { want[k] = style }
        }
        let plainly = RichText.escapeLiteral(words.plain)
        if want.allSatisfy(\.isPlain) { return plainly }
        var opens: [Int: String] = [:]
        var closes: [Int: String] = [:]
        var k = 0
        while k < count {
            let style = want[k]
            if style.isPlain || units[k] == 0x0A {
                k += 1
                continue
            }
            var e = k
            while e < count && want[e] == style && units[e] != 0x0A { e += 1 }
            var s = k
            var t = e
            while s < t && isSpace(units[s]) { s += 1 }
            while t > s && isSpace(units[t - 1]) { t -= 1 }
            if s < t {
                let open = (style.bold ? "**" : "") + (style.italic ? "*" : "") + (style.underline ? "__" : "")
                    + (style.strike ? "~~" : "")
                opens[s, default: ""] += open
                closes[t] = String(open.reversed()) + (closes[t] ?? "")
            }
            k = e
        }
        var out: [UInt16] = []
        for i in 0...count {
            if let close = closes[i] { out += Array(close.utf16) }
            if let open = opens[i] { out += Array(open.utf16) }
            guard i < count else { continue }
            if units[i] == 0x2A || units[i] == 0x5F || units[i] == 0x7E || units[i] == 0x5C { out.append(0x5C) }
            out.append(units[i])
        }
        let text = String(decoding: out, as: UTF16.self)
        let read = RichText.parse(text)
        guard read.plain == words.plain else { return plainly }
        for i in 0..<count where !isSpace(units[i]) {
            let got = read.runs.first { NSLocationInRange(i, $0.range) }?.style ?? RichText.Style()
            if got != want[i] { return plainly }
        }
        return text
    }

    /// `pages` with each jump to a slide (slideLink) a link to the page
    /// that slide became, by `made`; a jump to a slide that made none goes
    /// nowhere and is dropped.
    fileprivate static func jumped(_ pages: [Page], to made: [String: String]) -> [Page] {
        func moved(_ link: String?) -> String? {
            guard let id = Links.pageId(link), id.hasPrefix(slidePrefix) else { return link }
            return made[id].map(Links.pageLink)
        }
        var out = pages
        for p in out.indices {
            for i in out[p].elements.indices {
                var el = out[p].elements[i]
                el.link = moved(el.link)
                if let spans = el.spans {
                    el.spans = spans.map { span -> TextSpan in
                        var kept = span
                        kept.link = moved(span.link)
                        return kept
                    }
                }
                out[p].elements[i] = el
            }
        }
        return out
    }

    /// The link every run with words shares, when they all have one and
    /// it is the same: the box's own link; nil otherwise.
    fileprivate static func wholeLink(_ words: Words) -> String? {
        let units = Array(words.plain.utf16)
        let shown = words.runs.filter { r in
            !units[max(0, r.start)..<min(r.end, units.count)].allSatisfy(isSpace)
        }
        guard let link = shown.first?.link, shown.allSatisfy({ $0.link == link }) else { return nil }
        return link
    }

    // MARK: reading

    private final class DeckReader {
        let parts: Parts
        let ids: (String) -> String
        var skipped: [String: Int] = [:]
        var media: [String: String] = [:]
        var missingFonts = Set<String>()
        private var loaded: [String: Part?] = [:]
        var theme = Theme()
        /// The master the words being read are under, for their defaults.
        var currentMaster: Part?
        /// The slide the words being read are on, for their links.
        var currentSlide: Part?
        /// The slides' parts in the deck's order, for a jump to one.
        var slideOrder: [String] = []
        /// The master's level-1 look for words in a kind of box, by master.
        var masterLooks: [String: Look?] = [:]
        /// Groups nested past maxDepth end the read, as on the Android
        /// twin.
        var tooDeep = false

        init(parts: Parts, ids: @escaping (String) -> String) {
            self.parts = parts
            self.ids = ids
        }

        func skip(_ kind: String) {
            skipped[kind, default: 0] += 1
        }

        func load(_ path: String) -> Part? {
            let key = path.lowercased()
            if let known = loaded[key] { return known }
            var part: Part?
            if let root = PptxReader.document(parts.bytes(path)) {
                var rels: [String: Rel] = [:]
                var order: [Rel] = []
                for rel in PptxReader.document(parts.bytes(PptxReader.relsPath(path)))?.children(named: "Relationship") ?? [] {
                    guard let id = rel.attributes["Id"], let target = rel.attributes["Target"] else { continue }
                    let external = rel.attributes["TargetMode"] == "External"
                    let type = String((rel.attributes["Type"] ?? "").split(separator: "/").last ?? "")
                    let found = Rel(type: type, target: external ? target : PptxReader.resolve(path, target),
                                    external: external)
                    rels[id] = found
                    order.append(found)
                }
                part = Part(path: path, root: root, rels: rels, order: order)
            }
            loaded[key] = .some(part)
            return part
        }

        func related(_ part: Part, _ type: String) -> Part? {
            guard let rel = part.order.first(where: { $0.type == type && !$0.external }) else { return nil }
            return load(rel.target)
        }

        func read(title: String, now: Double) -> Imported? {
            // The package's own relationships name its main part.
            let main = PptxReader.document(parts.bytes("_rels/.rels"))?.children(named: "Relationship")
                .first { ($0.attributes["Type"] ?? "").hasSuffix("/officeDocument") }?.attributes["Target"]
            guard let presentation = load(main.map { PptxReader.resolve("", $0) } ?? "ppt/presentation.xml"),
                  presentation.root.name == "presentation" else { return nil }
            if let part = related(presentation, "theme") { theme = readTheme(part.root) }
            let size = presentation.root.child("sldSz")
            let width = PptxReader.number(size, "cx").flatMap { $0 > 0 ? PptxReader.px($0) : nil } ?? 1280
            let height = PptxReader.number(size, "cy").flatMap { $0 > 0 ? PptxReader.px($0) : nil } ?? 720
            let slides = (presentation.root.child("sldIdLst")?.children(named: "sldId") ?? []).compactMap { id -> String? in
                guard let rel = id.attributes["r:id"].flatMap({ presentation.rels[$0] }), !rel.external else { return nil }
                return rel.target
            }
            let designId = ids("doc")
            slideOrder = slides
            var made: [String: String] = [:]
            var pages: [Page] = []
            for (n, path) in slides.enumerated() {
                guard let read = load(path).flatMap(page) else { continue }
                made[PptxReader.slidePrefix + String(n)] = read.id
                pages.append(read)
            }
            guard !pages.isEmpty, !tooDeep else { return nil }
            pages = PptxReader.jumped(pages, to: made)
            skipped[PptxReader.font] = missingFonts.count
            var design = Design(title: title, width: width, height: height)
            design.id = designId
            design.createdAt = now
            design.updatedAt = now
            design.pages = pages
            // Named by its file, which someone chose.
            design.titleAuto = false
            return Imported(design: design, media: media, skipped: skipped.filter { $0.value > 0 })
        }

        func readTheme(_ root: SvgImport.Node) -> Theme {
            let elements = root.child("themeElements")
            var found = Theme()
            for slot in elements?.child("clrScheme")?.children ?? [] {
                let raw = slot.child("srgbClr")?.attributes["val"] ?? slot.child("sysClr")?.attributes["lastClr"]
                if let value = hex(raw) { found.colours[slot.name] = value }
            }
            let fonts = elements?.child("fontScheme")
            found.major = fonts?.at("majorFont", "latin")?.attributes["typeface"]
            found.minor = fonts?.at("minorFont", "latin")?.attributes["typeface"]
            return found
        }

        // MARK: a slide

        /// The slide `slide` as a page: its background, its shapes bottom
        /// up, its notes and its title.
        func page(_ slide: Part) -> Page? {
            guard slide.root.name == "sld" else { return nil }
            let layout = related(slide, "slideLayout")
            let master = layout.flatMap { related($0, "slideMaster") }
            let id = ids("page")
            currentMaster = master
            currentSlide = slide
            var shown: Background?
            for part in [slide, layout, master].compactMap({ $0 }) {
                guard let bg = part.root.at("cSld", "bg") else { continue }
                if let found = background(bg, part) {
                    shown = found
                    break
                }
            }
            var walk = Walk(reader: self, slide: slide, layout: layout, master: master)
            if let tree = slide.root.at("cSld", "spTree") { walk.tree(tree, place: .slide, group: nil, depth: 0) }
            let said = related(slide, "notesSlide").flatMap(notes(of:)).flatMap { PptxReader.isBlank($0) ? nil : $0 }
            var page = Page(id: id, background: shown ?? .color("#ffffff"), elements: walk.out, notes: said)
            page.title = walk.title.flatMap(PageTitles.cleaned)
            return page
        }

        func background(_ bg: SvgImport.Node, _ part: Part) -> Background? {
            if let props = bg.child("bgPr") {
                guard let paint = fill(props, part, style: nil) else { return nil }
                switch paint.kind {
                case "solid": return .color(paint.color ?? "#ffffff")
                case "gradient": return .gradient(paint)
                case "image": return paint.src.map { .image($0) } ?? .color("#ffffff")
                default: return .color("#ffffff")
                }
            }
            // A theme's background by reference: its colour.
            return bg.child("bgRef").flatMap(colour(in:)).map { .color($0) }
        }

        /// The words of the notes slide's body placeholder, a paragraph a
        /// line.
        func notes(of notes: Part) -> String? {
            guard let body = shapes(notes.root.at("cSld", "spTree")).first(where: { placeholderType($0) == "body" }),
                  let text = body.child("txBody") else { return nil }
            return text.children(named: "p").map(plain(of:)).joined(separator: "\n")
        }

        /// Every p:sp in a tree, groups' included, bottom up.
        func shapes(_ tree: SvgImport.Node?) -> [SvgImport.Node] {
            (tree?.children ?? []).flatMap { child -> [SvgImport.Node] in
                switch child.name {
                case "sp": return [child]
                case "grpSp": return shapes(child)
                default: return []
                }
            }
        }

        func plain(of paragraph: SvgImport.Node) -> String {
            var out = ""
            for part in paragraph.children {
                switch part.name {
                case "r", "fld": out += part.child("t")?.text ?? ""
                case "br": out += "\n"
                default: break
                }
            }
            return out
        }

        /// A placeholder's type, "obj" when it has none; nil for a shape
        /// that is not one.
        func placeholderType(_ node: SvgImport.Node) -> String? {
            node.at("nvSpPr", "nvPr", "ph").map { $0.attributes["type"] ?? "obj" }
        }

        /// The master's placeholder a slide's of `type` follows.
        func masterType(_ type: String) -> String {
            switch type {
            case "ctrTitle", "title": return "title"
            case "dt", "ftr", "sldNum": return type
            default: return "body"
            }
        }

        /// The master's text style a box's words follow: a date, footer or
        /// slide number the other style, as a shape that is no placeholder.
        func kind(of type: String?) -> TextKind {
            switch type {
            case nil, "dt", "ftr", "sldNum": return .other
            case "title", "ctrTitle": return .title
            default: return .body
            }
        }

        // MARK: words

        func masterLook(_ kind: TextKind, _ master: Part?) -> Look? {
            guard let master else { return nil }
            let key = "\(master.path.lowercased())\u{0}\(kind.rawValue)"
            if let known = masterLooks[key] { return known }
            var look: Look?
            if let styles = master.root.child("txStyles"),
               let level = styles.child("\(kind.rawValue)Style")?.child("lvl1pPr") {
                look = levelLook(level)
            }
            masterLooks[key] = .some(look)
            return look
        }

        /// A list style's level: its defRPr and its alignment.
        func levelLook(_ level: SvgImport.Node) -> Look {
            var found = look(level.child("defRPr"))
            found.align = align(level.attributes["algn"])
            return found
        }

        /// The paragraphs of `body` as one box's words: a paragraph a line,
        /// a line break a line, a field's words as they were last shown;
        /// each run's look its own, else its a:lstStyle's level 1, else
        /// each of `levels` (its placeholder's layout's and master's) in
        /// turn, else the master's for a `kind` of box, else 18 pt black in
        /// the theme's body font. Nil when there is no run and not `empty`.
        ///
        /// Each paragraph's list (PptxReader.list) and its lvl, and the
        /// first paragraph's spacing, are its own a:pPr's, else its level's
        /// in its a:lstStyle, else in each of `listStyles` (its
        /// placeholder's layout's and master's), else in the master's body
        /// or other text style for its kind of box — the first that says.
        /// A line break's line is its paragraph's.
        func words(of body: SvgImport.Node, kind: TextKind, empty: Bool = false,
                   levels: [SvgImport.Node] = [], listStyles: [SvgImport.Node] = []) -> Words? {
            let base = Look(size: PptxReader.defaultType, bold: false, italic: false, underline: false,
                            colour: "#000000", typeface: theme.minor)
            var defaults = (masterLook(kind, currentMaster) ?? Look()).over(base)
            let own = body.at("lstStyle", "lvl1pPr").map { [$0] } ?? []
            for level in (own + levels).reversed() { defaults = levelLook(level).over(defaults) }
            var plain = ""
            var length = 0
            var runs: [Run] = []
            var alignment: String?
            var aligns: [String?] = []
            var lines: [TextParagraph] = []
            var spacing: (line: Gap?, before: Gap?, after: Gap?) = (nil, nil, nil)
            var props: SvgImport.Node?
            let styles = (body.child("lstStyle").map { [$0] } ?? []) + listStyles + masterLists(kind)
            for (k, paragraph) in body.children(named: "p").enumerated() {
                if k > 0 {
                    plain += "\n"
                    length += 1
                }
                let own = align(paragraph.child("pPr")?.attributes["algn"]) ?? defaults.align
                if k == 0 { alignment = own }
                aligns.append(own)
                let pPr = paragraph.child("pPr")
                let level = min(TextLists.maxLevel, max(0, Int(PptxReader.number(pPr, "lvl") ?? 0)))
                let chain = [pPr].compactMap { $0 } + styles.compactMap { $0.child("lvl\(level + 1)pPr") }
                let line = TextParagraph(list: listOf(chain), level: level)
                lines.append(line)
                if k == 0 {
                    spacing = (gap(chain, "lnSpc"), gap(chain, "spcBef"), gap(chain, "spcAft"))
                }
                for part in paragraph.children {
                    switch part.name {
                    case "r", "fld":
                        let said = part.child("t")?.text ?? ""
                        if said.isEmpty { continue }
                        if props == nil, !PptxReader.isBlank(said) { props = part.child("rPr") }
                        let look = self.look(part.child("rPr")).over(defaults)
                        let start = length
                        plain += said
                        length += said.utf16.count
                        // A face named with its cut ("Lora Bold") is its
                        // family, the cut the word's own weight.
                        let cut = PptxReader.cut(look.typeface)
                        runs.append(Run(start: start, end: length,
                                        size: (look.size ?? PptxReader.defaultType) / PptxReader.sizePerPixel,
                                        bold: look.bold == true, italic: look.italic == true,
                                        underline: look.underline == true, colour: look.colour ?? "#000000",
                                        font: cut?.family ?? font(look.typeface), weight: cut?.weight,
                                        highlight: part.child("rPr")?.child("highlight").flatMap(colour(in:)),
                                        script: PptxReader.script(baseline: part.child("rPr")?.attributes["baseline"]),
                                        caps: part.child("rPr")?.attributes["cap"] == "all",
                                        strike: look.strike == true,
                                        spacing: look.spacing,
                                        link: link(part.child("rPr")?.child("hlinkClick"))))
                    case "br":
                        plain += "\n"
                        length += 1
                        aligns.append(own)
                        lines.append(line)
                    default:
                        break
                    }
                }
            }
            if runs.isEmpty && !empty { return nil }
            return Words(plain: plain, runs: runs, align: alignment, props: props, aligns: aligns, lines: lines,
                         lineSpacing: spacing.line, before: spacing.before, after: spacing.after)
        }

        /// The master's text style a `kind` of box takes its lists from:
        /// its body style, or its other style; a title none.
        func masterLists(_ kind: TextKind) -> [SvgImport.Node] {
            guard kind != .title, let style = currentMaster?.root.child("txStyles")?.child("\(kind.rawValue)Style") else {
                return []
            }
            return [style]
        }

        /// The list the first of `chain` that names a bullet makes; none
        /// when none does. A picture bullet is a bullet, the picture said
        /// left out.
        func listOf(_ chain: [SvgImport.Node]) -> String {
            for node in chain {
                let named = node.children.first { PptxReader.list(bullet: $0.name, autoNum: nil) != nil }
                guard let bullet = named else { continue }
                if bullet.name == "buBlip" { skip(PptxReader.picture) }
                return PptxReader.list(bullet: bullet.name, autoNum: bullet.attributes["type"]) ?? "none"
            }
            return "none"
        }

        /// The first of `chain`'s `tag` (a:lnSpc, a:spcBef or a:spcAft):
        /// its spcPct or its spcPts.
        func gap(_ chain: [SvgImport.Node], _ tag: String) -> Gap? {
            for node in chain {
                guard let holder = node.child(tag) else { continue }
                if let pct = PptxReader.number(holder.child("spcPct"), "val") { return .pct(pct) }
                if let pts = PptxReader.number(holder.child("spcPts"), "val") { return .pts(pts) }
            }
            return nil
        }

        /// Where an a:hlinkClick goes, through the slide's relationships: an
        /// address to follow, or a jump to a slide of the deck
        /// (ppaction://hlinksldjump) as its place in the deck's list, which
        /// read turns into that slide's page; nil for anything else.
        func link(_ click: SvgImport.Node?) -> String? {
            guard let click, let id = click.attributes["r:id"], let rel = currentSlide?.rels[id] else { return nil }
            if rel.external { return Links.followable(rel.target) }
            guard (click.attributes["action"] ?? "").contains("hlinksldjump") else { return nil }
            let key = rel.target.lowercased()
            return slideOrder.firstIndex { $0.lowercased() == key }.map(PptxReader.slideLink)
        }

        /// The styling the writer gives a text box, read back from its first
        /// run's properties and its body — the mapping both phones share, in
        /// reverse (PptxExporter.styledParts): an outerShdw is the Shadow
        /// effect (its colour, its offset, direction and blur from dist, dir
        /// and blurRad for type `size` high, its transparency from the
        /// alpha); a glow is Neon (its intensity from rad); an a:ln with
        /// noFill is Hollow (its thickness from w), with a fill Outline (its
        /// thickness and colour); a highlight is Highlight in its colour; a
        /// gradFill is gradient letters; prstTxWarp textArchUp or
        /// textArchDown is a curve of adj degrees, and vert eaVert or
        /// wordArtVert a column. An effect's colour is read without its
        /// alpha, which the effect's own transparency says.
        func styled(_ el: Element, props: SvgImport.Node?, body: SvgImport.Node?, size: Double) -> Element {
            var out = el
            let fs = max(size, 1)
            let emu = PptxReader.emuPerPixel
            // To a tenth, so what the writer wrote from a default reads back as it.
            func pct(_ node: SvgImport.Node?, _ key: String, _ scale: Double) -> Double {
                min(max(((PptxReader.number(node, key) ?? 0) / scale * 50 * 10).rounded() / 10, 0), 100)
            }
            func ink(_ holder: SvgImport.Node?) -> String? {
                holder.flatMap(colour(in:)).map { String($0.prefix(7)) }
            }
            let line = props?.child("ln")
            let effects = props?.child("effectLst")
            let shadow = effects?.child("outerShdw")
            let glow = effects?.child("glow")
            if let line, props?.child("noFill") != nil {
                let spec = TextEffectSpec(type: "outline", thickness: pct(line, "w", max(2.5, 0.035 * fs) * emu))
                out.effect = spec.tidied
            } else if let line {
                let spec = TextEffectSpec(type: "outlined", thickness: pct(line, "w", max(1.5, 0.04 * fs) * emu),
                                          color: ink(line.child("solidFill")))
                out.effect = spec.tidied
            } else if let shadow {
                var dir = (PptxReader.number(shadow, "dir") ?? 0) / 60000
                if dir > 180 { dir -= 360 }
                let alpha = shadow.children.first.flatMap { PptxReader.number($0.child("alpha"), "val") }
                    .map { $0 / 100_000 } ?? 1
                let spec = TextEffectSpec(type: "shadow",
                                          offset: pct(shadow, "dist", 0.06 * 2.0.squareRoot() * fs * emu),
                                          direction: min(max(dir, -180), 180),
                                          blur: pct(shadow, "blurRad", 0.12 * fs * emu),
                                          transparency: min(max(((1 - alpha) * 1000).rounded() / 10, 0), 100),
                                          color: ink(shadow))
                out.effect = spec.tidied
            } else if let glow {
                out.effect = TextEffectSpec(type: "neon", intensity: pct(glow, "rad", 0.35 * fs * emu)).tidied
            } else if let highlight = props?.child("highlight") {
                out.effect = TextEffectSpec(type: "highlight", color: ink(highlight)).tidied
            }
            if let grad = props?.child("gradFill") {
                let stops = (grad.child("gsLst")?.children(named: "gs") ?? []).compactMap { gs -> GradientStop? in
                    guard let hex = colour(in: gs) else { return nil }
                    return GradientStop(offset: (PptxReader.number(gs, "pos") ?? 0) / 100_000, color: hex)
                }
                let angle = PptxReader.turned((PptxReader.number(grad.child("lin"), "ang") ?? 0) / 60000 + 90)
                if stops.count >= 2 { out.textFill = Paint(kind: "gradient", color: nil, angle: angle, stops: stops) }
            }
            if let warp = body?.child("prstTxWarp") {
                let adj = warp.child("avLst")?.children(named: "gd").first { $0.attributes["name"] == "adj" }?.attributes["fmla"]
                let value = adj.flatMap { Double($0.replacingOccurrences(of: "val", with: "").trimmingCharacters(in: .whitespaces)) }
                let degrees = (value ?? 10_800_000) / 60000
                switch warp.attributes["prst"] {
                case "textArchUp": out.curve = degrees
                case "textArchDown": out.curve = -degrees
                // A ring, as this app writes one past half a ring: a whole one.
                case "textCircle": out.curve = TextPaths.maxCurve
                default: break
                }
            }
            if let vert = body?.attributes["vert"], vert == "eaVert" || vert == "wordArtVert" { out.vertical = true }
            return out
        }

        func look(_ props: SvgImport.Node?) -> Look {
            guard let props else { return Look() }
            let u = props.attributes["u"]
            let strike = props.attributes["strike"]
            return Look(size: PptxReader.number(props, "sz").flatMap { $0 > 0 ? $0 : nil },
                        bold: PptxReader.flag(props, "b"), italic: PptxReader.flag(props, "i"),
                        underline: u.map { $0 != "none" },
                        colour: props.child("solidFill").flatMap(colour(in:)),
                        typeface: props.child("latin")?.attributes["typeface"].flatMap { $0.isEmpty ? nil : $0 },
                        strike: strike.map { $0 == "sngStrike" || $0 == "dblStrike" },
                        spacing: PptxReader.number(props, "spc"))
        }

        func align(_ algn: String?) -> String? {
            switch algn {
            case "l": return "left"
            case "ctr": return "center"
            case "r": return "right"
            case "just", "dist", "justLow", "thaiDist": return "justify"
            default: return nil
            }
        }

        /// A typeface as a font key: the theme's when it names one, a
        /// bundled family's, else Modern Sans, the face said left out.
        func font(_ typeface: String?) -> String {
            let fallback = FontLibrary.all[0].id
            var named = typeface
            if let given = typeface, given.hasPrefix("+mj") { named = theme.major }
            if let given = typeface, given.hasPrefix("+mn") { named = theme.minor }
            guard let face = named, !face.isEmpty else { return fallback }
            if let found = PptxReader.family(of: face) { return found }
            missingFonts.insert(face)
            return fallback
        }

        // MARK: fills, lines and colours

        /// A colour: "#rrggbb", lower-case; nil for anything not one.
        func hex(_ value: String?) -> String? {
            guard let v = value?.trimmingCharacters(in: .whitespaces).lowercased(),
                  v.utf8.count == 6, v.allSatisfy(\.isHexDigit) else { return nil }
            return "#" + v
        }

        /// The colour inside `holder` — an a:srgbClr, a:sysClr (its last
        /// colour) or a:schemeClr (the theme's, its tx/bg names as the usual
        /// map has them) — with its a:alpha as "#rrggbbaa" when that is under
        /// 100%; its other changes left out.
        func colour(in holder: SvgImport.Node) -> String? {
            for c in holder.children {
                let base: String?
                switch c.name {
                case "srgbClr":
                    base = hex(c.attributes["val"])
                case "sysClr":
                    base = hex(c.attributes["lastClr"])
                case "schemeClr":
                    var name = c.attributes["val"] ?? ""
                    switch name {
                    case "tx1": name = "dk1"
                    case "bg1": name = "lt1"
                    case "tx2": name = "dk2"
                    case "bg2": name = "lt2"
                    default: break
                    }
                    base = theme.colours[name]
                default:
                    continue
                }
                guard let base else { return nil }
                guard let alpha = PptxReader.number(c.child("alpha"), "val"), alpha < 100_000 else { return base }
                let a = String(Int((min(max(alpha, 0), 100_000) / 100_000 * 255).rounded()), radix: 16)
                return base + (a.count < 2 ? "0" + a : a)
            }
            return nil
        }

        /// The fill in `props`: none, a colour, a linear gradient (its angle
        /// as the model keeps it, 90 more than DrawingML's), a pattern's
        /// foreground colour or a picture; else, with `style`, its
        /// a:fillRef's colour unless that is index 0. Nil for none given.
        func fill(_ props: SvgImport.Node?, _ part: Part, style: SvgImport.Node?) -> Paint? {
            for c in props?.children ?? [] {
                switch c.name {
                case "noFill":
                    return .clear
                case "solidFill":
                    return colour(in: c).map { .solid($0) }
                case "gradFill":
                    let stops = (c.child("gsLst")?.children(named: "gs") ?? []).compactMap { gs -> GradientStop? in
                        guard let hex = colour(in: gs) else { return nil }
                        let at = min(max((PptxReader.number(gs, "pos") ?? 0) / 100_000, 0), 1)
                        return GradientStop(offset: at, color: hex)
                    }
                    if stops.isEmpty { return nil }
                    if stops.count == 1 { return .solid(stops[0].color) }
                    let angle = PptxReader.turned((PptxReader.number(c.child("lin"), "ang") ?? 0) / 60000 + 90)
                    return Paint(kind: "gradient", color: nil, angle: angle, stops: stops)
                case "pattFill":
                    return c.child("fgClr").flatMap(colour(in:)).map { .solid($0) }
                case "blipFill":
                    if let src = picture(c, part) { return .image(src) }
                    skip(PptxReader.picture)
                    return .clear
                default:
                    continue
                }
            }
            guard let ref = style?.child("fillRef"), ref.attributes["idx"] != "0" else { return nil }
            return colour(in: ref).map { .solid($0) }
        }

        /// Whether `props` (else `style`) give a fill that shows, as fill
        /// reads it, without bringing a picture in: a picture fill shows
        /// whether or not its picture can be read.
        func fills(_ props: SvgImport.Node?, _ part: Part, style: SvgImport.Node?) -> Bool {
            let own = props?.children.first { PptxReader.fillNames.contains($0.name) }
            if own?.name == "blipFill" { return true }
            return fill(props, part, style: style).map { $0.kind != "none" } ?? false
        }

        /// A picture's "media:<key>" — its file's name in the deck — when its
        /// bytes are there and of a kind brought in (pictureTypes).
        func picture(_ blipFill: SvgImport.Node?, _ part: Part) -> String? {
            guard let embed = blipFill?.child("blip")?.attributes["r:embed"],
                  let rel = part.rels[embed], !rel.external else { return nil }
            let name = String(rel.target.split(separator: "/", omittingEmptySubsequences: false).last ?? "")
            let ext = name.contains(".") ? String(name.split(separator: ".", omittingEmptySubsequences: false).last ?? "") : ""
            guard PptxReader.pictureTypes.contains(ext.lowercased()), parts.has(rel.target) else { return nil }
            if let existing = media.first(where: { $0.value.lowercased() == rel.target.lowercased() })?.key {
                return PptxReader.mediaPrefix + existing
            }
            var candidate = name
            var n = 2
            while media[candidate] != nil {
                candidate = "\(n)-\(name)"
                n += 1
            }
            media[candidate] = rel.target
            return PptxReader.mediaPrefix + candidate
        }

        /// The border in `props`' a:ln: its colour — its own, else `style`'s
        /// a:lnRef colour unless that is index 0 — its width in pixels (1
        /// when it gives none) and its dashes. Nil for no line or none drawn.
        func border(_ props: SvgImport.Node?, style: SvgImport.Node?) -> Border? {
            let ln = props?.child("ln")
            if ln?.child("noFill") != nil { return nil }
            let own = ln?.child("solidFill").flatMap(colour(in:))
            let ref = style?.child("lnRef").flatMap { $0.attributes["idx"] == "0" ? nil : $0 }
            guard let hex = own ?? ref.flatMap(colour(in:)) else { return nil }
            let width = PptxReader.number(ln, "w").flatMap { $0 > 0 ? PptxReader.px($0) : nil } ?? 1
            let dash: String
            switch ln?.child("prstDash")?.attributes["val"] {
            case "dot", "sysDot": dash = "dotted"
            case nil, "solid": dash = "solid"
            default: dash = "dashed"
            }
            return Border(colour: hex, width: width, dash: dash)
        }
    }

    // MARK: a slide's shapes

    /// One slide's shape tree walked, bottom up, into `out`.
    private struct Walk {
        let reader: DeckReader
        let slide: Part
        let layout: Part?
        let master: Part?
        var out: [Element] = []
        var title: String?

        init(reader: DeckReader, slide: Part, layout: Part?, master: Part?) {
            self.reader = reader
            self.slide = slide
            self.layout = layout
            self.master = master
        }

        mutating func tree(_ node: SvgImport.Node, place: Place, group: String?, depth: Int) {
            guard depth <= PptxReader.maxDepth else {
                reader.tooDeep = true
                return
            }
            for child in node.children {
                switch child.name {
                case "nvGrpSpPr", "grpSpPr", "extLst":
                    continue
                case "sp", "cxnSp":
                    shape(child, place: place, group: group)
                case "pic":
                    picture(child, place: place, group: group)
                case "graphicFrame":
                    frame(child, place: place, group: group)
                case "grpSp":
                    // The outermost group is every member's group; a group
                    // inside it one of their subgroups (Groups), its id made
                    // as it is met.
                    let level = reader.ids("grp")
                    let start = out.count
                    let xfrm = child.at("grpSpPr", "xfrm")
                    if let frame = PptxReader.box(of: xfrm) {
                        let off = xfrm?.child("chOff")
                        let ext = xfrm?.child("chExt")
                        let inner = place.inside(frame, chx: PptxReader.number(off, "x") ?? frame.x,
                                                 chy: PptxReader.number(off, "y") ?? frame.y,
                                                 chw: PptxReader.number(ext, "cx") ?? frame.w,
                                                 chh: PptxReader.number(ext, "cy") ?? frame.h)
                        tree(child, place: inner, group: group ?? level, depth: depth + 1)
                    } else {
                        tree(child, place: place, group: group ?? level, depth: depth + 1)
                    }
                    // Its own level goes in front of the levels inside it.
                    // A table keeps a group of its own, outside this one.
                    if let group {
                        for i in start..<out.count where out[i].group == group {
                            out[i].subgroups = [level] + (out[i].subgroups ?? [])
                        }
                    }
                case "AlternateContent":
                    if let fallback = child.child("Fallback") {
                        tree(fallback, place: place, group: group, depth: depth + 1)
                    } else {
                        reader.skip(PptxReader.other)
                    }
                default:
                    reader.skip(PptxReader.other)
                }
            }
        }

        /// The shapes a placeholder `node` follows: its layout's placeholder
        /// with the same idx (else type), and its master's of the same
        /// master type (masterType); none for a shape that is not a
        /// placeholder.
        func inherited(_ node: SvgImport.Node) -> Inherited {
            guard let ph = node.child(node.name == "pic" ? "nvPicPr" : "nvSpPr")?.at("nvPr", "ph") else {
                return Inherited(layout: nil, master: nil)
            }
            let idx = ph.attributes["idx"]
            let type = ph.attributes["type"] ?? "obj"
            let fromLayout = reader.shapes(layout?.root.at("cSld", "spTree")).first { other in
                guard let theirs = other.at("nvSpPr", "nvPr", "ph") else { return false }
                if let idx { return theirs.attributes["idx"] == idx }
                return (theirs.attributes["type"] ?? "obj") == type
            }
            let kind = reader.masterType(type)
            let fromMaster = reader.shapes(master?.root.at("cSld", "spTree")).first { other in
                guard let theirs = other.at("nvSpPr", "nvPr", "ph") else { return false }
                return reader.masterType(theirs.attributes["type"] ?? "obj") == kind
            }
            return Inherited(layout: fromLayout, master: fromMaster)
        }

        /// Where a shape is: its own xfrm, else a placeholder's — its
        /// layout's, else its master's (`from`).
        func placed(_ props: SvgImport.Node?, _ place: Place, from: Inherited) -> Box? {
            if let own = PptxReader.box(of: props?.child("xfrm")) { return place.box(own) }
            if let box = PptxReader.box(of: from.layout?.at("spPr", "xfrm")) { return place.box(box) }
            return PptxReader.box(of: from.master?.at("spPr", "xfrm")).map(place.box)
        }

        mutating func shape(_ node: SvgImport.Node, place: Place, group: String?) {
            let nv = node.child("nvSpPr") ?? node.child("nvCxnSpPr")
            if PptxReader.flag(nv?.child("cNvPr"), "hidden") == true { return }
            let props = node.child("spPr")
            let from = inherited(node)
            // A placeholder with nowhere to be is only missed when it has
            // words to show.
            guard let box = placed(props, place, from: from) else {
                if let body = node.child("txBody"), let words = reader.words(of: body, kind: .other),
                   !PptxReader.isBlank(words.plain) {
                    reader.skip(PptxReader.other)
                }
                return
            }
            let style = node.child("style")
            let geometry = props?.child("prstGeom")?.attributes["prst"] ?? (props?.child("custGeom") != nil ? "custom" : nil)
            if geometry == "line" || geometry == "straightConnector1" {
                out.append(line(box, reader.border(props, style: style), group: group))
                return
            }
            // The fill is read — its picture brought in — only for an
            // outline that is kept; any other that would show is counted.
            switch geometry {
            case nil, "rect", "roundRect", "ellipse", "triangle":
                let paint = reader.fill(props, slide, style: style).flatMap { $0.kind == "none" ? nil : $0 }
                let edge = reader.border(props, style: style)
                if paint != nil || edge != nil {
                    out.append(shapeElement(box, geometry: geometry, props: props, fill: paint, border: edge, group: group))
                }
            default:
                if reader.fills(props, slide, style: style) || reader.border(props, style: style) != nil {
                    reader.skip(PptxReader.shape)
                }
            }
            let type = reader.placeholderType(node)
            guard let body = node.child("txBody"),
                  let words = reader.words(of: body, kind: reader.kind(of: type), levels: from.levels,
                                           listStyles: from.listStyles) else { return }
            let bodies = (body.child("bodyPr").map { [$0] } ?? []) + from.bodies
            if var made = text(words, bodies: bodies, box: box, place: place, group: group) {
                // The shape's own click, as the writer writes an element's
                // link, unless its words already go somewhere as a whole.
                if made.link == nil { made.link = reader.link(nv?.child("cNvPr")?.child("hlinkClick")) }
                out.append(made)
            }
            if title == nil && (type == "title" || type == "ctrTitle") {
                let joined = Array(words.plain.utf16).split(whereSeparator: PptxReader.isTitleSpace)
                    .map { String(decoding: $0, as: UTF16.self) }.joined(separator: " ")
                title = joined.isEmpty ? nil : joined
            }
        }

        mutating func picture(_ node: SvgImport.Node, place: Place, group: String?) {
            let nv = node.child("nvPicPr")
            if PptxReader.flag(nv?.child("cNvPr"), "hidden") == true { return }
            let nvPr = nv?.child("nvPr")
            if nvPr?.child("videoFile") != nil || nvPr?.child("quickTimeFile") != nil {
                return reader.skip(PptxReader.video)
            }
            if nvPr?.child("audioFile") != nil || nvPr?.child("wavAudioFile") != nil || nvPr?.child("audioCd") != nil {
                return reader.skip(PptxReader.sound)
            }
            guard let box = placed(node.child("spPr"), place, from: inherited(node)) else { return reader.skip(PptxReader.other) }
            guard let src = reader.picture(node.child("blipFill"), slide) else { return reader.skip(PptxReader.picture) }
            var el = Element.image(src, w: PptxReader.px(box.w), h: PptxReader.px(box.h))
            el.filter = nil
            el.id = reader.ids("el")
            el.x = PptxReader.px(box.x)
            el.y = PptxReader.px(box.y)
            el.rotation = PptxReader.turned(box.rotation)
            el.flipH = box.flipH
            el.flipV = box.flipV
            el.group = group
            out.append(el)
        }

        mutating func frame(_ node: SvgImport.Node, place: Place, group: String?) {
            let data = node.at("graphic", "graphicData")
            let uri = data?.attributes["uri"] ?? ""
            if uri.hasSuffix("/table") {
                guard let box = PptxReader.box(of: node.child("xfrm")).map(place.box),
                      let table = data?.child("tbl") else { return reader.skip(PptxReader.other) }
                if !self.table(table, box: box, place: place) { reader.skip(PptxReader.other) }
            } else if uri.hasSuffix("/chart") || uri.hasSuffix("/chartex") {
                reader.skip(PptxReader.chart)
            } else if uri.hasSuffix("/diagram") {
                reader.skip(PptxReader.smartArt)
            } else {
                reader.skip(PptxReader.other)
            }
        }

        /// A table at `box`: its columns a:tblGrid's widths and its rows
        /// a:tr's heights, from the frame's corner; each cell that is not
        /// covered by another (hMerge, vMerge) a rectangle — its own fill,
        /// else white, with a new table's hairline — and a text box inside
        /// its margins, each carrying its place, its spans clipped to the
        /// table. False when there are no cells.
        mutating func table(_ table: SvgImport.Node, box: Box, place: Place) -> Bool {
            let widths = (table.child("tblGrid")?.children(named: "gridCol") ?? [])
                .map { (PptxReader.number($0, "w") ?? 0) * place.sx }
            let rows = table.children(named: "tr")
            guard !widths.isEmpty, !rows.isEmpty else { return false }
            let heights = rows.map { (PptxReader.number($0, "h") ?? 0) * place.sy }
            let group = reader.ids("grp")
            let id = reader.ids("tbl")
            for (r, row) in rows.enumerated() {
                var rects: [Element] = []
                var texts: [Element] = []
                for (c, cell) in row.children(named: "tc").enumerated() {
                    if c >= widths.count { break }
                    if PptxReader.flag(cell, "hMerge") == true || PptxReader.flag(cell, "vMerge") == true { continue }
                    let colSpan = Self.span(PptxReader.number(cell, "gridSpan"), most: widths.count - c)
                    let rowSpan = Self.span(PptxReader.number(cell, "rowSpan"), most: rows.count - r)
                    let x = box.x + widths[..<c].reduce(0, +)
                    let y = box.y + heights[..<r].reduce(0, +)
                    let w = widths[c..<(c + colSpan)].reduce(0, +)
                    let h = heights[r..<(r + rowSpan)].reduce(0, +)
                    let props = cell.child("tcPr")
                    // A picture fill is not read — no file is kept for a
                    // fill the cell does not show — and is said.
                    let own = props?.children.first { PptxReader.fillNames.contains($0.name) }
                    var paint: Paint?
                    if own?.name == "blipFill" {
                        reader.skip(PptxReader.picture)
                    } else {
                        paint = reader.fill(props, slide, style: nil).flatMap { $0.kind == "solid" ? $0 : nil }
                    }
                    let at = TableCell(id: id, row: r, col: c, rowSpan: rowSpan, colSpan: colSpan)
                    var rect = Element.shape("rect", w: PptxReader.px(w), h: PptxReader.px(h))
                    rect.id = reader.ids("el")
                    rect.x = PptxReader.px(x)
                    rect.y = PptxReader.px(y)
                    rect.fill = paint ?? .solid("#ffffff")
                    rect.stroke = PptxReader.tableBorder
                    rect.strokeWidth = 1
                    rect.radius = 0
                    rect.group = group
                    rect.table = at
                    rects.append(rect)
                    let inset = Insets(left: PptxReader.number(props, "marL") ?? 91440,
                                       top: PptxReader.number(props, "marT") ?? 45720,
                                       right: PptxReader.number(props, "marR") ?? 91440,
                                       bottom: PptxReader.number(props, "marB") ?? 45720)
                    let words = cell.child("txBody").flatMap { reader.words(of: $0, kind: .other, empty: true) }
                        ?? Words(plain: "", runs: [], align: nil)
                    let frame = Box(x: x, y: y, w: w, h: h, rotation: 0, flipH: false, flipV: false)
                    if var text = textBox(words, anchor: props?.attributes["anchor"], inset: inset, box: frame,
                                          place: .slide, group: group, empty: true) {
                        text.table = at
                        texts.append(text)
                    }
                }
                out += rects
                out += texts
            }
            return true
        }

        /// A merge's span as written, a whole number within 1…`most`.
        static func span(_ value: Double?, most: Int) -> Int {
            guard let value, value >= 1 else { return 1 }
            return value >= Double(most) ? most : max(1, Int(value))
        }

        /// A rectangle, rounded rectangle (its corner adj of the shorter
        /// side), oval or triangle at `box`.
        func shapeElement(_ box: Box, geometry: String?, props: SvgImport.Node?, fill: Paint?, border: Border?,
                          group: String?) -> Element {
            let w = PptxReader.px(box.w)
            let h = PptxReader.px(box.h)
            let id: String
            switch geometry {
            case "ellipse": id = "circle"
            case "triangle": id = "triangle"
            default: id = "rect"
            }
            var radius = 0.0
            if geometry == "roundRect" {
                let guide = props?.at("prstGeom", "avLst")?.children(named: "gd").first { $0.attributes["name"] == "adj" }
                let formula = guide?.attributes["fmla"] ?? ""
                let value = formula.hasPrefix("val") ? String(formula.dropFirst(3)) : formula
                let adj = Double(value.trimmingCharacters(in: .whitespaces)) ?? 16667
                radius = adj / 100_000 * min(w, h)
            }
            var el = Element.shape(id, w: w, h: h)
            el.id = reader.ids("el")
            el.x = PptxReader.px(box.x)
            el.y = PptxReader.px(box.y)
            el.rotation = PptxReader.turned(box.rotation)
            el.flipH = box.flipH
            el.flipV = box.flipV
            el.fill = fill ?? .clear
            el.radius = radius
            el.stroke = border?.colour
            el.strokeWidth = border?.width
            el.group = group
            return el
        }

        /// The words of a shape at `box`, inset and anchored by the first of
        /// `bodies` — its own bodyPr, then its placeholder's layout's and
        /// master's — that says.
        func text(_ words: Words, bodies: [SvgImport.Node], box: Box, place: Place, group: String?) -> Element? {
            func said(_ key: String, _ otherwise: Double) -> Double {
                bodies.lazy.compactMap { PptxReader.number($0, key) }.first ?? otherwise
            }
            let inset = Insets(left: said("lIns", 91440), top: said("tIns", 45720),
                               right: said("rIns", 91440), bottom: said("bIns", 45720))
            let anchor = bodies.lazy.compactMap { $0.attributes["anchor"] }.first
            // The first body that says how its words fit: shrunk on
            // overflow (normAutofit) comes in at the size it showed.
            let fit = bodies.lazy.compactMap { b in
                b.children.first { ["normAutofit", "spAutoFit", "noAutofit"].contains($0.name) }
            }.first
            let shrink = fit?.name == "normAutofit" ? fit : nil
            return textBox(words, anchor: anchor, inset: inset, box: box, place: place, group: group, empty: false,
                           body: bodies.first,
                           fontScale: (PptxReader.number(shrink, "fontScale") ?? 100_000) / 100_000,
                           lineReduction: (PptxReader.number(shrink, "lnSpcReduction") ?? 0) / 100_000)
        }

        /// A text box of `words` inside `box` less `inset` (scaled as its
        /// group is by `place`), the box's look its first run's with words
        /// and the rest as markers and spans; nil for no words, unless
        /// `empty` — a table's cell, which always has its text. Type shrunk
        /// to fit comes in at the size it showed: `fontScale` times its
        /// own, its lines `lineReduction` closer (normAutofit).
        func textBox(_ given: Words, anchor: String?, inset: Insets, box: Box, place: Place, group: String?,
                     empty: Bool, body: SvgImport.Node? = nil, fontScale: Double = 1,
                     lineReduction: Double = 0) -> Element? {
            if !empty && PptxReader.isBlank(given.plain) { return nil }
            // The runs' offsets are into the words as they read, which the
            // escapes leave as they are.
            let words = given
            let units = Array(words.plain.utf16)
            let shown = words.runs.filter { r in
                !units[max(0, r.start)..<min(r.end, units.count)].allSatisfy(PptxReader.isSpace)
            }
            let first = shown.first ?? words.runs.first
            let own = first?.size ?? PptxReader.defaultType / PptxReader.sizePerPixel
            let size = own * (fontScale > 0 ? fontScale : 1)
            let colour = first?.colour ?? "#000000"
            let face = first?.font ?? FontLibrary.all[0].id
            let bold = !shown.isEmpty && shown.allSatisfy(\.bold)
            let italic = !shown.isEmpty && shown.allSatisfy(\.italic)
            let underline = !shown.isEmpty && shown.allSatisfy(\.underline)
            let left = inset.left * place.sx
            let top = inset.top * place.sy
            let w = max(0, box.w - left - inset.right * place.sx)
            let h = max(0, box.h - top - inset.bottom * place.sy)
            let text = PptxReader.marked(words, bold: bold, italic: italic, underline: underline)
            // Where the markers cannot keep a run's bold or italic apart
            // from the words' own stars, the runs keep them as their words'
            // own weight and slant (Spans) instead, as on the Android twin.
            let plainOnly = text == RichText.escapeLiteral(words.plain)
                && words.runs.contains { r in (r.bold && r.weight == nil && !bold) || (r.italic && !italic) }
            var el = Element.text(text, fontSize: size, w: PptxReader.px(w))
            // No effect key, as a text box from the Android twin has none.
            el.effect = nil
            el.id = reader.ids("el")
            el.x = PptxReader.px(box.x + left)
            el.y = PptxReader.px(box.y + top)
            el.h = PptxReader.px(h)
            // Words are never mirrored: PowerPoint keeps a flipped box's
            // words as they read, and turns them over for flipV.
            el.rotation = PptxReader.turned(box.flipV ? box.rotation + 180 : box.rotation)
            el.fontFamily = face
            el.fontWeight = bold ? 700 : 400
            el.italic = italic ? true : nil
            el.underline = underline ? true : nil
            el.align = words.align ?? "left"
            el.color = colour
            el.group = group
            switch anchor {
            case "ctr": el.vAlign = "middle"
            case "b": el.vAlign = "bottom"
            default: break
            }
            el = reader.styled(el, props: given.props, body: body, size: size)
            // Every run marked alike is the box's Highlight, as the writer
            // writes it; runs marked apart are highlights on their words
            // (TextSpan.highlight), and the box has no Highlight then — the
            // rule both phones share.
            let marks = words.runs.map(\.highlight)
            let boxMarked = !marks.isEmpty && marks.allSatisfy { $0 != nil && $0 == marks[0] }
            if !boxMarked, el.effect?.type == "highlight" { el.effect = nil }
            // Every shown run in capitals is the box set in Uppercase; some
            // of them, those words' own (TextSpan.caps), as on the Android
            // twin.
            // `shown` (the runs with words, above) is the same set.
            let allCaps = !shown.isEmpty && shown.allSatisfy(\.caps)
            // The spans are made for the plain words, which the escapes keep.
            if RichText.strip(text) == words.plain {
                let boxWeight = bold ? 700 : 400
                // A run that goes where every other run goes is the box's
                // link instead (below).
                let whole = PptxReader.wholeLink(words)
                el.setSpans(words.runs.map { r in
                    let scale = r.size / own
                    // A run's cut is its words' weight; a bold run the
                    // markers could not keep is 700, an italic one slanted.
                    let weight: Int? = r.weight ?? (plainOnly && r.bold && !bold ? 700 : nil)
                    return TextSpan(start: r.start, end: r.end, color: r.colour == colour ? nil : r.colour,
                                    scale: size > 0 && abs(scale - 1) > Spans.scaleTolerance ? scale : nil,
                                    font: r.font == face ? nil : r.font, link: whole == nil ? r.link : nil,
                                    weight: weight == boxWeight ? nil : weight,
                                    italic: plainOnly && r.italic && !italic ? true : nil,
                                    highlight: boxMarked ? nil : r.highlight, script: r.script,
                                    caps: r.caps && !allCaps ? true : nil)
                })
            }
            el.link = PptxReader.wholeLink(words)
            spaced(&el, words, size: own, lineReduction: lineReduction)
            if allCaps { el.uppercase = true }
            // Each paragraph's own algn, where they differ: the box's is the
            // first paragraph's, the rest on their lines (TextLists); and
            // each paragraph's list and level, the box-wide listStyle when
            // every line is alike (setLines).
            let aligned = Set(words.aligns.map { $0 ?? "left" }).count > 1
            let listed = words.lines.contains { $0.isListed || $0.level > 0 }
            if aligned || listed {
                el.setLines(TextLists.lines(el).enumerated().map { i, line -> TextParagraph in
                    var p = i < words.lines.count ? words.lines[i] : line
                    p.align = aligned && i < words.aligns.count ? words.aligns[i] ?? "left" : nil
                    return p
                })
            }
            return el
        }

        /// The box's spacing from its words, the rule both phones share:
        /// its letters' the spc of its dominant run (the longest of all its
        /// runs, spaces too, the first of those alike; a run's spc its own
        /// or its list styles' defRPr) ÷ 75, as the writer writes
        /// letterSpacing × 75; its lines' the first paragraph's lnSpc — a
        /// spcPct × singleSpacing, a spcPts over the type — `lineReduction`
        /// closer (the normAutofit of the first bodyPr that says how its
        /// words fit: the shape's, its layout's, its master's); and the room
        /// between paragraphs its spcBef and spcAft together, in ems of the
        /// type `size` (pixels) high. No number is rounded.
        func spaced(_ el: inout Element, _ words: Words, size: Double, lineReduction: Double) {
            var dominant: Run?
            for r in words.runs where r.end - r.start > (dominant.map { $0.end - $0.start } ?? 0) { dominant = r }
            if let spc = dominant?.spacing { el.letterSpacing = spc / PptxReader.sizePerPixel }
            var lineHeight: Double?
            switch words.lineSpacing {
            case .pct(let value)?: lineHeight = value / 100_000 * PptxReader.singleSpacing
            case .pts?: lineHeight = words.lineSpacing?.ems(size: size)
            case nil: lineHeight = nil
            }
            if lineReduction > 0 { lineHeight = (lineHeight ?? PptxReader.singleSpacing) * (1 - lineReduction) }
            if let lineHeight, lineHeight > 0 { el.lineHeight = lineHeight }
            let room = (words.before?.ems(size: size) ?? 0) + (words.after?.ems(size: size) ?? 0)
            if room > 0 { el.paragraphSpacing = room }
        }

        /// A line from corner to corner of `box` — the other two corners
        /// when it is flipped — as a line element: as long as that, turned
        /// to its angle and the box's own, centred where the box is.
        func line(_ box: Box, _ border: Border?, group: String?) -> Element {
            let x0 = box.flipH ? box.x + box.w : box.x
            let x1 = box.flipH ? box.x : box.x + box.w
            let y0 = box.flipV ? box.y + box.h : box.y
            let y1 = box.flipV ? box.y : box.y + box.h
            let length = PptxReader.px((box.w * box.w + box.h * box.h).squareRoot())
            let angle = atan2(y1 - y0, x1 - x0) * 180 / .pi + box.rotation
            let thickness = border?.width ?? 1
            let h = max(8, thickness)
            var el = Element.line(w: length)
            el.id = reader.ids("el")
            el.x = PptxReader.px(box.x + box.w / 2) - length / 2
            el.y = PptxReader.px(box.y + box.h / 2) - h / 2
            el.w = length
            el.h = h
            el.rotation = PptxReader.turned(angle)
            el.color = border?.colour ?? "#000000"
            el.thickness = thickness
            el.dash = border?.dash ?? "solid"
            // No end keys, as a line from the Android twin has none: none
            // is no cap.
            el.startCap = nil
            el.endCap = nil
            el.group = group
            return el
        }
    }
}

// The tree's lookups, by a tag's name without its namespace.
extension SvgImport.Node {
    /// The first child called `name`.
    fileprivate func child(_ name: String) -> SvgImport.Node? {
        children.first { $0.name == name }
    }

    /// Every child called `name`, in order.
    fileprivate func children(named name: String) -> [SvgImport.Node] {
        children.filter { $0.name == name }
    }

    /// The child down `path`, a name a step.
    fileprivate func at(_ path: String...) -> SvgImport.Node? {
        var node: SvgImport.Node? = self
        for name in path { node = node?.child(name) }
        return node
    }
}
