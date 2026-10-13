// The fonts: about forty Google Fonts families, OFL or Apache, bundled as
// TTF files, plus the system's sans, serif and mono — read from Fonts.json,
// the very file the Android twin ships, byte for byte (its
// tools/generate_fonts.py writes both, with the files). The files are
// registered with CoreText for this process the first time a font is asked
// for, so both phones draw and measure every bundled family from the same
// bytes. A design names a family, never a file; each one resolves to a
// concrete UIFont for canvas rendering, measurement and export alike.
//
// The twelve type personalities earlier designs stored ("didone",
// "script"…) are aliases of the families they now draw with; "sans",
// "serif" and "mono" are system families themselves, as they always were.
// A font of your own is "custom:<sha1 first 12 hex>" (see CustomFonts);
// anything else — or a font of your own that is not on this phone — draws
// as Modern Sans. The licences are bundled beside the files
// (Fonts/licenses).

import SwiftUI
import UIKit
import CoreText

/// One font family: its id — the key a text box's `fontFamily` stores —
/// what the picker calls it, its category, and its faces. A bundled
/// family's faces are files in the app ("lora-400.ttf"), keyed by weight
/// with "i" after for the family's true italic ("400", "400i", "700",
/// "700i"); `postScript` is each face's PostScript name, which is how it is
/// asked for here. A system family has none.
struct FontDef: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var system: Bool = false
    var licence: String?
    var files: [String: String] = [:]
    var postScript: [String: String] = [:]

    private enum CodingKeys: String, CodingKey { case id, name, category, system, licence, files, postScript }

    init(id: String, name: String, category: String, system: Bool = false) {
        self.id = id
        self.name = name
        self.category = category
        self.system = system
    }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decode(String.self, forKey: .id)
        name = try c.decode(String.self, forKey: .name)
        category = try c.decode(String.self, forKey: .category)
        system = (try? c.decodeIfPresent(Bool.self, forKey: .system)) ?? false
        licence = try? c.decodeIfPresent(String.self, forKey: .licence)
        files = (try? c.decodeIfPresent([String: String].self, forKey: .files)) ?? [:]
        postScript = (try? c.decodeIfPresent([String: String].self, forKey: .postScript)) ?? [:]
    }
}

/// The face of a family a text is set in: its file, its PostScript name and
/// its own weight.
struct FontFace: Equatable {
    var file: String
    var postScript: String
    var weight: Int
}

enum FontLibrary {

    /// The chip that shows every category.
    static let allCategories = "All"

    /// How many fonts Recently used keeps, newest first.
    static let recentLimit = 8

    /// The file's shape. "source" is informational.
    private struct Catalogue: Decodable {
        var categories: [String]
        var aliases: [String: String]
        var families: [FontDef]
    }

    /// Read once, on first use.
    private static let catalogue: Catalogue = {
        guard let url = Bundle.main.url(forResource: "Fonts", withExtension: "json"),
              let data = try? Data(contentsOf: url),
              let decoded = try? JSONDecoder().decode(Catalogue.self, from: data), !decoded.families.isEmpty else {
            assertionFailure("Fonts.json missing or invalid")
            return Catalogue(categories: ["Sans"], aliases: [:],
                             families: [FontDef(id: "sans", name: "Modern Sans", category: "Sans", system: true)])
        }
        return decoded
    }()

    /// Every family, in the picker's order: category by category.
    static var all: [FontDef] { catalogue.families }

    /// The categories, in the order the chips show them after "All".
    static var categories: [String] { catalogue.categories }

    /// Older keys, and the family each now means.
    static var aliases: [String: String] { catalogue.aliases }

    private static let byId: [String: FontDef] = Dictionary(
        catalogue.families.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })

    /// The family a stored key means; an unknown or missing key — and a font
    /// of your own, which is drawn from its own file when this phone has it
    /// — reads as Modern Sans, which is what a text box is created with.
    static func of(_ key: String?) -> FontDef {
        let id = key.map { aliases[$0] ?? $0 }
        return id.flatMap { byId[$0] } ?? all[0]
    }

    /// A stored key as the family id it means — a font of your own as
    /// itself — so "didone" and "playfair-display" are the same choice.
    static func resolve(_ key: String?) -> String {
        if let key, CustomFonts.isCustom(key) { return key }
        return of(key).id
    }

    /// The face of `font` a text at `weight` is set in: the nearest weight
    /// it has, ties to the heavier — so a 900 takes the 700 rather than a
    /// 400 made bold, and a 550 the 700. Italic asks for the family's true
    /// italic, and is nil where it has none (the upright is then slanted).
    /// Nil for a system family.
    static func face(_ font: FontDef, weight: Int, italic: Bool = false) -> FontFace? {
        let weights = font.files.keys
            .filter { $0.hasSuffix("i") == italic }
            .compactMap { Int(italic ? String($0.dropLast()) : $0) }
        guard let nearest = weights.min(by: { a, b in
            let da = abs(a - weight), db = abs(b - weight)
            return da != db ? da < db : a > b
        }) else { return nil }
        let key = "\(nearest)\(italic ? "i" : "")"
        guard let file = font.files[key], let postScript = font.postScript[key] else { return nil }
        return FontFace(file: file, postScript: postScript, weight: nearest)
    }

    // MARK: search and the picker's lists

    /// The text as a search compares it: no accents, no case — "Café" is
    /// "cafe" — and no spaces either side.
    static func folded(_ text: String) -> String {
        var kept = String.UnicodeScalarView()
        for scalar in text.decomposedStringWithCanonicalMapping.unicodeScalars {
            switch scalar.properties.generalCategory {
            case .nonspacingMark, .spacingMark, .enclosingMark: continue
            default: kept.append(scalar)
            }
        }
        return String(kept).lowercased().trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// Whether a font called `name` is found by `query`: the name has it,
    /// case and accents aside. A blank query finds everything.
    static func matches(_ name: String, _ query: String) -> Bool {
        let needle = folded(query)
        return needle.isEmpty || folded(name).contains(needle)
    }

    /// The families the picker lists for `query` in `category`
    /// (allCategories for every one), in catalogue order.
    static func search(_ query: String, category: String = allCategories) -> [FontDef] {
        all.filter { (category == allCategories || $0.category == category) && matches($0.name, query) }
    }

    /// Recently used after `key` is chosen: it first, once, then the rest as
    /// they were, recentLimit in all. Keys are kept as resolved, so an alias
    /// and its family are one entry.
    static func recent(_ list: [String], adding key: String) -> [String] {
        let id = resolve(key)
        return Array(([id] + list.filter { $0 != id }).prefix(recentLimit))
    }

    /// The fonts the design sets text in — each once, resolved, page by page
    /// and on a page from the bottom layer up — fonts of your own included.
    static func usedIn(_ design: Design) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for page in design.pages {
            for el in page.elements {
                guard let family = el.fontFamily else { continue }
                let id = resolve(family)
                if seen.insert(id).inserted { out.append(id) }
            }
        }
        return out
    }

    // MARK: the bundled files

    /// A bundled face's file. Resources in the app's folder are copied to
    /// the top of the bundle; a build that kept the folder finds it there.
    static func bundledURL(_ file: String) -> URL? {
        let name = (file as NSString).deletingPathExtension
        let ext = (file as NSString).pathExtension
        return Bundle.main.url(forResource: name, withExtension: ext)
            ?? Bundle.main.url(forResource: name, withExtension: ext, subdirectory: "Fonts")
    }

    /// Every bundled face registered for this process, once: each is then
    /// found by its PostScript name.
    private static let registered: Void = {
        for font in catalogue.families {
            for name in font.files.values.sorted() {
                guard let url = bundledURL(name) else { continue }
                _ = CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            }
        }
    }()

    /// Registers the bundled faces, if they are not yet: at launch, and
    /// before any font is made.
    static func registerBundledFonts() {
        _ = registered
    }

    /// What the system draws the system families with, by category — and
    /// any bundled face that cannot be read. Candidate PostScript names,
    /// tried in order.
    private static func systemNames(_ font: FontDef) -> [String] {
        switch font.category {
        case "Serif": return ["Georgia"]
        case "Mono": return ["Menlo-Regular", "CourierNewPSMT"]
        default: return ["HelveticaNeue"]
        }
    }

    /// How far a face with no italic of its own leans when one is asked for,
    /// as the Android twin slants it.
    static let slant = 0.25

    // MARK: memoisation
    //
    // None of this was cached. attributes(for:) finds a face calling
    // UIFont(name:), rebuilds a descriptor, allocates a paragraph
    // style and parses a hex colour; measuredHeight(for:) then runs a full
    // CoreText layout on top. They are called on every keystroke while
    // editing text, on every frame of a text resize, and once per text
    // element when a document opens — always with the same handful of
    // distinct inputs. Memoising turns a per-frame layout into a dictionary
    // lookup.
    //
    // Guarded by a lock rather than isolated to the main actor: document
    // decoding measures text off the main thread.

    private struct TypographyKey: Hashable {
        let family: String?
        let size: Double
        let weight: Int
        let italic: Bool
        let underline: Bool
        let align: String?
        let lineHeight: Double
        let letterSpacing: Double
        let color: String?
        let listStyle: String?
        let indent: Int
        let paragraphSpacing: Double
        let rightToLeft: Bool

        init(_ el: Element) {
            rightToLeft = FontLibrary.isRightToLeft(el.text ?? "")
            listStyle = el.listStyle
            indent = FontLibrary.indentLevel(of: el)
            paragraphSpacing = el.paragraphSpacing ?? 0
            family = el.fontFamily
            size = el.fontSize ?? 42
            weight = el.fontWeight ?? 400
            italic = el.italic ?? false
            underline = el.underline ?? false
            align = el.align
            lineHeight = el.lineHeight ?? 1.25
            letterSpacing = el.letterSpacing ?? 0
            color = el.color
        }
    }

    private struct MeasureKey: Hashable {
        let typography: TypographyKey
        let text: String?
        let listStyle: String?
        let uppercase: Bool
        let width: Double
        let spans: [TextSpan]?
        let spansText: String?
    }

    private struct FontKey: Hashable {
        let family: String?
        let size: Double
        let weight: Int
        let italic: Bool
    }

    private static let lock = NSLock()
    private static var fontCache: [FontKey: UIFont] = [:]
    private static var attrCache: [TypographyKey: [NSAttributedString.Key: Any]] = [:]
    private static var heightCache: [MeasureKey: Double] = [:]

    /// Scrubbing a size slider would otherwise grow these without bound.
    private static let cacheLimit = 256

    private static func memoized<K: Hashable, V>(_ key: K,
                                                 _ cache: inout [K: V],
                                                 _ make: () -> V) -> V {
        lock.lock()
        if let hit = cache[key] { lock.unlock(); return hit }
        lock.unlock()
        let value = make()
        lock.lock()
        if cache.count >= cacheLimit { cache.removeAll(keepingCapacity: true) }
        cache[key] = value
        lock.unlock()
        return value
    }

    /// Resolve a concrete UIFont for an element's typography.
    static func uiFont(family key: String?, size: Double, weight: Int, italic: Bool) -> UIFont {
        memoized(FontKey(family: key, size: size, weight: weight, italic: italic),
                 &fontCache) { buildFont(family: key, size: size, weight: weight, italic: italic) }
    }

    /// Forgets every font, attribute and height worked out so far: a font of
    /// your own has arrived or gone, and the texts set in it draw in it, or
    /// in Modern Sans, from now on.
    static func fontsChanged() {
        lock.lock()
        fontCache.removeAll()
        attrCache.removeAll()
        heightCache.removeAll()
        lock.unlock()
    }

    /// A font of your own when the box is set in one and this phone has it;
    /// else the bundled face of its family at the nearest weight, else the
    /// system's — Modern Sans for a font of your own that is missing. A
    /// bundled face is used at its own weight — Anton has only one, and it is
    /// already black — and only italic is made on top, by slanting, where
    /// the family has no italic of its own. A font of your own is one face,
    /// as Anton is, and is drawn at its own weight whatever the text asks:
    /// bold neither thickens it nor swaps it for another face of its family
    /// registered here — another font of your own, or a bundled one — and
    /// italic slants it unless it is an italic itself. The Android twin's
    /// FontLibrary.drawnWeight is the same rule.
    private static func buildFont(family key: String?, size: Double,
                                  weight: Int, italic: Bool) -> UIFont {
        registerBundledFonts()
        if CustomFonts.isCustom(key), let own = FontStore.uiFont(key, size: size) {
            return italic && !own.fontDescriptor.symbolicTraits.contains(.traitItalic) ? slanted(own, size: size) : own
        }
        let font = of(key)
        if !font.system {
            let trueItalic = italic ? face(font, weight: weight, italic: true) : nil
            if let chosen = trueItalic ?? face(font, weight: weight),
               let ui = UIFont(name: chosen.postScript, size: size) {
                return italic && trueItalic == nil ? slanted(ui, size: size) : ui
            }
        }
        var base: UIFont?
        for name in systemNames(font) {
            if let f = UIFont(name: name, size: size) { base = f; break }
        }
        return styled(base ?? UIFont.systemFont(ofSize: size, weight: uiWeight(weight)),
                      size: size, bold: weight >= 600, italic: italic)
    }

    /// A system font with bold and italic from its family where it has
    /// them; an italic it has not, slanted.
    private static func styled(_ font: UIFont, size: Double, bold: Bool, italic: Bool) -> UIFont {
        var traits: UIFontDescriptor.SymbolicTraits = []
        if bold { traits.insert(.traitBold) }
        if italic { traits.insert(.traitItalic) }
        guard !traits.isEmpty else { return font }
        var out = font
        // Only the family's own, never some other family's.
        if let d = font.fontDescriptor.withSymbolicTraits(font.fontDescriptor.symbolicTraits.union(traits)) {
            let traited = UIFont(descriptor: d, size: size)
            if traited.familyName == font.familyName { out = traited }
        }
        if italic && !out.fontDescriptor.symbolicTraits.contains(.traitItalic) {
            out = slanted(out, size: size)
        }
        return out
    }

    /// The upright leaning as an italic would.
    private static func slanted(_ font: UIFont, size: Double) -> UIFont {
        let matrix = CGAffineTransform(a: 1, b: 0, c: CGFloat(slant), d: 1, tx: 0, ty: 0)
        return UIFont(descriptor: font.fontDescriptor.withMatrix(matrix), size: size)
    }

    /// SwiftUI Font for an element's typography (UIFont is toll-free
    /// bridged to CTFont, but Swift needs the explicit cast).
    static func font(family key: String?, size: Double, weight: Int, italic: Bool) -> Font {
        Font(uiFont(family: key, size: size, weight: weight, italic: italic) as CTFont)
    }

    static func uiWeight(_ weight: Int) -> UIFont.Weight {
        switch weight {
        case ..<300: return .light
        case ..<500: return .regular
        case ..<600: return .medium
        case ..<700: return .semibold
        case ..<800: return .bold
        case ..<900: return .heavy
        default: return .black
        }
    }

    /// Attributes shared by canvas rendering, measurement and export.
    static func attributes(for el: Element) -> [NSAttributedString.Key: Any] {
        memoized(TypographyKey(el), &attrCache) { buildAttributes(for: el) }
    }

    private static func buildAttributes(for el: Element) -> [NSAttributedString.Key: Any] {
        let size = el.fontSize ?? 42
        let font = uiFont(family: el.fontFamily, size: size,
                          weight: el.fontWeight ?? 400, italic: el.italic ?? false)
        let paragraph = NSMutableParagraphStyle()
        paragraph.alignment = {
            switch el.align ?? "center" {
            case "left": return .left
            case "right": return .right
            case "justify": return .justified
            default: return .center
            }
        }()
        paragraph.paragraphSpacing = size * max(0, el.paragraphSpacing ?? 0)
        let lineHeight = size * (el.lineHeight ?? 1.25)
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.lineBreakMode = .byWordWrapping
        // Hebrew, Arabic and the other right-to-left scripts lay out from
        // the right, and the indents and list markers below follow, since
        // head indents are measured from the leading edge.
        paragraph.baseWritingDirection = isRightToLeft(el.text ?? "") ? .rightToLeft : .natural
        // Indent levels push the whole paragraph in; a list marker then
        // hangs: the first line starts at the marker, wrapped lines start
        // where the text after the marker does.
        let indent = Double(indentLevel(of: el)) * size * indentEm
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent + (isList(el) ? size * markerEm : 0)
        var attrs: [NSAttributedString.Key: Any] = [
            .font: font,
            .paragraphStyle: paragraph.copy(),
            .foregroundColor: UIColor(hex: el.color ?? "#1f2430"),
            .kern: el.letterSpacing ?? 0,
        ]
        if el.underline == true {
            attrs[.underlineStyle] = NSUnderlineStyle.single.rawValue
        }
        return attrs
    }

    /// True when the first letter of the text is from a right-to-left
    /// script: Hebrew, Arabic, Syriac, Thaana, NKo and the Arabic
    /// presentation forms. Digits and punctuation before it do not decide.
    static func isRightToLeft(_ text: String) -> Bool {
        for scalar in text.unicodeScalars where scalar.properties.isAlphabetic {
            let v = scalar.value
            return (0x0590...0x08FF).contains(v) || (0xFB1D...0xFDFF).contains(v) || (0xFE70...0xFEFF).contains(v)
        }
        return false
    }

    /// Display text including bullet prefixes.
    static func displayText(for el: Element) -> String {
        displayText(for: el, pageNumber: nil, pageCount: nil)
    }

    /// "{page}" and "{pages}" in a text element become the page's number and
    /// the document's page count when the caller knows them; left as they
    /// are when it does not, so measuring is honest about the width. Inline
    /// style markers (**bold** and the like) are stripped: this is what is
    /// measured and what plain drawing shows — in capitals, when the box is
    /// set in them.
    static func displayText(for el: Element, pageNumber: Int?, pageCount: Int?) -> String {
        let plain = RichText.strip(markedDisplayText(for: el, pageNumber: pageNumber, pageCount: pageCount))
        return el.uppercase == true ? plain.uppercased() : plain
    }

    /// The text as drawn with its inline styles applied: the plain display
    /// text with bold, italic, underline and strike runs on top of the
    /// element's own attributes. In capitals the markers are read first and
    /// each run uppercased on its own, so a styled word keeps its style
    /// however much a letter grows.
    /// Words in a colour or a size of their own (see Spans) are set so on
    /// top — in capitals, moved as the runs are.
    static func attributedString(for el: Element) -> NSAttributedString {
        let marked = markedDisplayText(for: el, pageNumber: nil, pageCount: nil)
        let base = attributes(for: el)
        let capitals = el.uppercase == true
        let spans = displaySpans(for: el, marked: marked)
        guard RichText.hasMarkup(marked) || !spans.isEmpty else {
            return NSAttributedString(string: capitals ? marked.uppercased() : marked, attributes: base)
        }
        let size = el.fontSize ?? 42
        let weight = el.fontWeight ?? 400
        return RichText.attributed(marked, base: base, uppercase: capitals, spans: spans) { bold, italic in
            uiFont(family: el.fontFamily, size: size,
                   weight: bold ? (weight >= 700 ? 900 : 700) : weight,
                   italic: italic || el.italic == true)
        }
    }

    /// Display text with the inline style markers still in it.
    static func markedDisplayText(for el: Element, pageNumber: Int?, pageCount: Int?) -> String {
        var raw = el.text ?? ""
        if let pageNumber { raw = raw.replacingOccurrences(of: "{page}", with: String(pageNumber)) }
        if let pageCount { raw = raw.replacingOccurrences(of: "{pages}", with: String(pageCount)) }
        guard isList(el) else { return raw }
        let lines = raw.components(separatedBy: "\n")
        return zip(listPrefixes(for: el, lines: lines), lines).map { $0 + $1 }.joined(separator: "\n")
    }

    /// The marker each line of a list starts with, by line: none for a
    /// blank one, which is not counted.
    private static func listPrefixes(for el: Element, lines: [String]) -> [String] {
        var n = 0
        return lines.map { line in
            guard !line.trimmingCharacters(in: .whitespaces).isEmpty else { return "" }
            n += 1
            return listMarker(style: el.listStyle, index: n) ?? ""
        }
    }

    // MARK: colours and sizes on words

    /// The element's colours and sizes on words, moved from the words as
    /// they read onto the display text before capitals — past a list's
    /// markers, a line at a time. Colours are left out while the letters
    /// are a gradient, which they would not show through. None when the
    /// words do not read as the spans expect.
    static func displaySpans(for el: Element, marked: String) -> [TextSpan] {
        var spans = el.liveSpans
        guard !spans.isEmpty else { return [] }
        if el.textFill?.kind == "gradient" {
            spans = Spans.normalised(spans.map { TextSpan(start: $0.start, end: $0.end, scale: $0.scale) })
            guard !spans.isEmpty else { return [] }
        }
        guard isList(el) else { return spans }
        // Each line moves along by the markers before it, its own included.
        let typed = RichText.strip(el.text ?? "").components(separatedBy: "\n")
        let raw = (el.text ?? "").components(separatedBy: "\n")
        guard typed.count == raw.count else { return [] }
        let prefixes = listPrefixes(for: el, lines: raw)
        guard zip(prefixes, typed).map({ $0 + $1 }).joined(separator: "\n") == RichText.strip(marked) else { return [] }
        var pieces: [TextSpan] = []
        var lineStart = 0, shift = 0
        for (prefix, line) in zip(prefixes, typed) {
            shift += prefix.utf16.count
            // The line and the break after it.
            let next = lineStart + line.utf16.count + 1
            for span in spans where span.start < next && span.end > lineStart {
                var piece = span
                piece.start = max(span.start, lineStart) + shift
                piece.end = min(span.end, next) + shift
                pieces.append(piece)
            }
            lineStart = next
        }
        return Spans.normalised(pieces)
    }

    /// The colours on words over the display text itself, capitals and all:
    /// what text round a curve, along a path or down a column is drawn in.
    /// Sizes are left out there, where the letters keep the box's size.
    static func displayColours(for el: Element) -> [TextSpan] {
        let marked = markedDisplayText(for: el, pageNumber: nil, pageCount: nil)
        let colours = displaySpans(for: el, marked: marked).compactMap { span -> TextSpan? in
            span.color.map { TextSpan(start: span.start, end: span.end, color: $0) }
        }
        guard !colours.isEmpty else { return [] }
        guard el.uppercase == true else { return colours }
        let capitals = RichText.inCapitals(RichText.Parsed(plain: RichText.strip(marked), runs: []), spans: colours)
        return capitals.parsed.plain == displayText(for: el) ? capitals.spans : []
    }

    /// `text` with the colours of `spans` on it, each moved by `shift`.
    static func colourWords(_ text: NSMutableAttributedString, _ spans: [TextSpan], shift: Int = 0) {
        for span in spans {
            guard let color = span.color else { continue }
            let start = max(span.start + shift, 0), end = min(span.end + shift, text.length)
            guard end > start else { continue }
            let range = NSRange(location: start, length: end - start)
            text.addAttribute(.foregroundColor, value: UIColor(hex: color), range: range)
            text.addAttribute(Spans.colourKey, value: color, range: range)
        }
    }

    /// Whether some words are set larger or smaller than the box's type,
    /// so measuring has to take them in.
    static func hasSizedWords(_ el: Element) -> Bool {
        el.liveSpans.contains { $0.scale != nil }
    }

    /// One indent level, in ems.
    static let indentEm = 1.5
    /// Room a list marker takes, in ems; wrapped lines hang under the text.
    static let markerEm = 1.4

    static let listStyles = ["none", "bullet", "number", "letter"]
    static let maxIndent = 4

    static func isList(_ el: Element) -> Bool {
        el.listStyle.map { $0 != "none" } ?? false
    }

    static func indentLevel(of el: Element) -> Int {
        min(maxIndent, max(0, el.indent ?? 0))
    }

    /// The prefix a line gets, by style and one-based position among the
    /// non-blank lines. Letters run a…z then aa, ab… so the 27th item is
    /// not a crash and not "{".
    static func listMarker(style: String?, index: Int) -> String? {
        switch style {
        case "bullet": return "•  "
        case "number": return "\(index).  "
        case "letter":
            var n = index, s = ""
            while n > 0 {
                n -= 1
                s = String(UnicodeScalar(UInt8(97 + n % 26))) + s
                n /= 26
            }
            return s + ".  "
        default: return nil
        }
    }

    /// The height a text element's box needs — the one everything outside this
    /// file should ask for.
    ///
    /// Curving a line makes it much taller than its flat measurement, so a
    /// caller that reached past this to measuredHeight would keep resetting a
    /// curved element's box to the straight height and clip the arc away. That
    /// is why this exists rather than each call site deciding.
    static func layoutHeight(for el: Element) -> Double {
        // Text on a path keeps the box it was given: the box is the path.
        // Vertical text keeps its box too; its columns are cut to it.
        if let data = el.textPath, !data.isEmpty { return max(el.h, (el.fontSize ?? 42) * 1.25) }
        if el.vertical == true { return max(el.h, (el.fontSize ?? 42) * 1.25) }
        if let degrees = el.curve, abs(degrees) >= TextOutliner.straightBelowDegrees,
           let curved = TextOutliner.curvedSize(for: el, degrees: degrees) {
            return max(curved.height, el.fontSize ?? 42)
        }
        // A fitted box is the size the user made it; the type fits inside.
        if el.fitText == true { return max(el.h, 8) }
        let measured = measuredHeight(for: el)
        // A vertically aligned box may be taller than its text — that is
        // the whole point of aligning within it — and must not snap shut.
        if el.vAlign != nil { return max(el.h, measured) }
        return measured
    }

    /// The largest type size, up to `maxSize`, at which the text fits inside
    /// the element's own box. Binary search over the measurement, which is
    /// what the box would do by hand: bigger until it spills, then back.
    static func fittingFontSize(for el: Element, maxSize: Double = 400) -> Double {
        guard el.w > 8, el.h > 8, !(el.text ?? "").isEmpty else { return el.fontSize ?? 42 }
        var probe = el
        probe.fitText = nil
        probe.vAlign = nil
        var lo = 6.0, hi = maxSize
        for _ in 0..<18 {
            let mid = (lo + hi) / 2
            probe.fontSize = mid
            let fits = measuredHeight(for: probe) <= el.h && naturalWidth(for: probe) <= el.w
            if fits { lo = mid } else { hi = mid }
        }
        // Down to the half-point, never up: `lo` is the largest size proven
        // to fit, and rounding above it spilled by a pixel.
        return (lo * 2).rounded(.down) / 2
    }

    /// The width the longest word needs at this size — the point below which
    /// a box does not narrow the text, it breaks it.
    static func naturalWidth(for el: Element) -> Double {
        if hasSizedWords(el) {
            return widest(attributedString(for: el), splitAtSpaces: true)
        }
        let attrs = attributes(for: el)
        let words = displayText(for: el).split(whereSeparator: { $0 == " " || $0 == "\n" })
        return words.reduce(0.0) { widest, word in
            max(widest, ceil(NSAttributedString(string: String(word), attributes: attrs).size().width))
        }
    }

    /// The width of the widest line, so a box can shrink onto its text.
    static func lineWidth(for el: Element) -> Double {
        if hasSizedWords(el) {
            return widest(attributedString(for: el), splitAtSpaces: false)
        }
        let attrs = attributes(for: el)
        return displayText(for: el).components(separatedBy: "\n").reduce(0.0) { widest, line in
            max(widest, ceil(NSAttributedString(string: line, attributes: attrs).size().width))
        }
    }

    /// The widest line of `text` as it is set — or, splitting at spaces
    /// too, its widest word — sized words and all.
    private static func widest(_ text: NSAttributedString, splitAtSpaces: Bool) -> Double {
        let ns = text.string as NSString
        var widest = 0.0
        var start = 0
        func close(at end: Int) {
            if end > start {
                let width = text.attributedSubstring(from: NSRange(location: start, length: end - start)).size().width
                widest = max(widest, ceil(width))
            }
            start = end + 1
        }
        for i in 0..<ns.length {
            let unit = ns.character(at: i)
            if unit == 10 || (splitAtSpaces && unit == 32) { close(at: i) }
        }
        close(at: ns.length)
        return widest
    }

    // MARK: drop caps

    static let dropCapLines = 3.0

    /// The drop cap's letter and box, and the rest of the text: the cap is
    /// the first letter at three lines' height, the body wraps beside and
    /// then below it.
    struct DropCapLayout {
        var letter: String
        var rest: String
        var capRect: CGRect
        var capFontSize: Double
    }

    static func dropCapLayout(for el: Element) -> DropCapLayout? {
        let text = displayText(for: el)
        guard el.dropCap == true, el.curve == nil, !isList(el),
              let first = text.first, first.isLetter || first.isNumber else { return nil }
        let size = el.fontSize ?? 42
        let line = size * (el.lineHeight ?? 1.25)
        let capSize = line * dropCapLines * 0.82
        var capEl = el
        capEl.fontSize = capSize
        capEl.lineHeight = 1
        let letter = String(first)
        let width = ceil(NSAttributedString(string: letter, attributes: attributes(for: capEl)).size().width)
        let rest = String(text.dropFirst()).trimmingCharacters(in: .init(charactersIn: " "))
        return DropCapLayout(letter: letter, rest: rest,
                             capRect: CGRect(x: 0, y: 0, width: width + size * 0.25, height: line * dropCapLines),
                             capFontSize: capSize)
    }

    /// The body beside a drop cap as it is drawn — its inline styles and the
    /// words' own colours and sizes on it, past the cap's letter and the
    /// spaces after it, as the Android twin sets it — and the colour of the
    /// word the cap starts, when that word has one of its own.
    static func dropCapText(for el: Element, _ layout: DropCapLayout) -> (body: NSAttributedString, capColour: UIColor?) {
        let drawn = attributedString(for: el)
        guard drawn.string.hasPrefix(layout.letter) else {
            return (NSAttributedString(string: layout.rest, attributes: attributes(for: el)), nil)
        }
        let ns = drawn.string as NSString
        var start = (layout.letter as NSString).length
        while start < ns.length, ns.character(at: start) == 32 { start += 1 }
        var end = ns.length
        while end > start, ns.character(at: end - 1) == 32 { end -= 1 }
        let capColour = drawn.attribute(Spans.colourKey, at: 0, effectiveRange: nil) as? String
        return (drawn.attributedSubstring(from: NSRange(location: start, length: end - start)),
                capColour.map { UIColor(hex: $0) })
    }

    /// The size the canvas draws a text element at: its own, or the one
    /// that fits its box.
    static func effectiveFontSize(for el: Element) -> Double {
        el.fitText == true ? fittingFontSize(for: el) : (el.fontSize ?? 42)
    }

    /// Natural height of a text element at its wrap width, ignoring any curve.
    static func measuredHeight(for el: Element) -> Double {
        let key = MeasureKey(typography: TypographyKey(el), text: el.text,
                             listStyle: el.listStyle, uppercase: el.uppercase == true, width: el.w,
                             spans: el.spans, spansText: el.spansText)
        return memoized(key, &heightCache) { measure(el) }
    }

    private static func measure(_ el: Element) -> Double {
        if let layout = dropCapLayout(for: el) {
            // The body beside the cap, then below it: measured as the text
            // at the narrow width for three lines, and the full width after,
            // words set larger or smaller as they are drawn.
            let line = (el.fontSize ?? 42) * (el.lineHeight ?? 1.25)
            let narrow = max(el.w - layout.capRect.width, 20)
            let body = dropCapText(for: el, layout).body
            let besideHeight = body.boundingRect(with: CGSize(width: narrow, height: .greatestFiniteMagnitude),
                                                 options: [.usesLineFragmentOrigin, .usesFontLeading], context: nil).height
            if besideHeight <= line * dropCapLines + 1 { return ceil(max(besideHeight, layout.capRect.height)) }
            let overflowLines = (besideHeight - line * dropCapLines) / max(line, 1)
            // Lines that spill below the cap get the full width, so fewer.
            let below = ceil(overflowLines * narrow / el.w) * line
            return ceil(layout.capRect.height + below)
        }
        // Words set larger or smaller are measured as they are drawn.
        let str = hasSizedWords(el) ? attributedString(for: el)
            : NSAttributedString(string: displayText(for: el), attributes: attributes(for: el))
        let bounds = str.boundingRect(
            with: CGSize(width: el.w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil)
        let lineHeight = (el.fontSize ?? 42) * (el.lineHeight ?? 1.25)
        return max(ceil(bounds.height), lineHeight)
    }
}
