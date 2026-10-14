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
// A font of your own is "custom:<sha1 first 12 hex>" (see CustomFonts),
// drawn from the face of its family nearest the weight and italic asked;
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
/// "700i", and from Light "300" to Black "900" where it has them);
/// `postScript` is each face's PostScript name, which is how it is asked for
/// here. A system family has none. `weights` are the upright weights it has,
/// lightest first — a bundled family's files, a system family's the cuts
/// both phones' own faces have — the same list on both phones.
struct FontDef: Decodable, Identifiable, Equatable {
    var id: String
    var name: String
    var category: String
    var system: Bool = false
    var licence: String?
    var files: [String: String] = [:]
    var postScript: [String: String] = [:]
    var weights: [Int] = []

    private enum CodingKeys: String, CodingKey { case id, name, category, system, licence, files, postScript, weights }

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
        weights = (try? c.decodeIfPresent([Int].self, forKey: .weights)) ?? []
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
    static let allCategories = tr("All")

    /// How many fonts Recently used keeps, newest first.
    static let recentLimit = 8

    /// What the Weight row calls each weight it offers, Light to Black: a
    /// weight's "Light" and "Black", not the theme's or the colour's.
    static let weightNames: [Int: String] = [
        300: tr("Light", context: "font weight"),
        400: tr("Regular"),
        500: tr("Medium"),
        600: tr("Semibold"),
        700: tr("Bold"),
        800: tr("Extra bold"),
        900: tr("Black", context: "font weight"),
    ]

    /// `weight`'s name, as the Weight row and VoiceOver say it; a weight the
    /// row does not offer by its number.
    static func weightName(_ weight: Int) -> String {
        weightNames[weight] ?? String(weight)
    }

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

    /// The weights the font `key` has, lightest first: its family's — an
    /// alias's family's, a font of your own's family's on this phone
    /// (customWeights), and Modern Sans's for an unknown key or a font of
    /// your own that is missing, which is what one draws as.
    static func weights(_ key: String?) -> [Int] {
        customWeights(key) ?? of(key).weights
    }

    /// The weights the family of a font of your own offers on this phone —
    /// each face's, a variable font's hundreds inside its axis — or nil
    /// when `key` is not one of yours here.
    static func customWeights(_ key: String?) -> [Int]? {
        CustomFonts.isCustom(key) ? FontStore.familyWeights(key) : nil
    }

    /// The weight a text at `requested` in the font `key` is drawn and
    /// measured at, the rule both phones share: the nearest weight the font
    /// has (`weights`), ties to the heavier — so 550 in Lora (400, 700) is
    /// 700, and 600 in Modern Sans (300, 400, 500, 700) is 700. `requested`
    /// itself for a font with none listed.
    static func resolveWeight(_ key: String?, _ requested: Int) -> Int {
        nearest(weights(key), to: requested) ?? requested
    }

    /// The one of `weights` nearest `weight`, ties to the heavier; nil for
    /// none.
    private static func nearest(_ weights: [Int], to weight: Int) -> Int? {
        weights.min { a, b in
            let da = abs(a - weight), db = abs(b - weight)
            return da != db ? da < db : a > b
        }
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
        guard let closest = nearest(weights, to: weight) else { return nil }
        let key = "\(closest)\(italic ? "i" : "")"
        guard let file = font.files[key], let postScript = font.postScript[key] else { return nil }
        return FontFace(file: file, postScript: postScript, weight: closest)
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
    /// and on a page from the bottom layer up, a box's words' after its own —
    /// fonts of your own included.
    static func usedIn(_ design: Design) -> [String] {
        var seen = Set<String>()
        var out: [String] = []
        for page in design.pages {
            for el in page.elements {
                // The box's face, then any its words are set in.
                for family in el.fontKeys {
                    let id = resolve(family)
                    if seen.insert(id).inserted { out.append(id) }
                }
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

    /// The system's own cut of each weight the system families list, by
    /// category — Light, Medium and Bold by name rather than bold made on
    /// top — so Modern Sans at 300, 400, 500 and 700, Classic Serif and
    /// Typewriter at 400 and 700, draw as the Android twin draws its own.
    /// Any bundled face that cannot be read falls back to these too.
    private static let systemCuts: [String: [Int: String]] = [
        "Sans": [300: "HelveticaNeue-Light", 400: "HelveticaNeue", 500: "HelveticaNeue-Medium", 700: "HelveticaNeue-Bold"],
        "Serif": [400: "Georgia", 700: "Georgia-Bold"],
        "Mono": [400: "Menlo-Regular", 700: "Menlo-Bold"],
    ]

    /// The cuts `font` falls back on: its category's, or Modern Sans's.
    private static func fallbackCuts(_ font: FontDef) -> [Int: String] {
        systemCuts[font.category] ?? systemCuts["Sans"] ?? [:]
    }

    /// What the system draws the system families with, by category, when
    /// the cut asked for is not there. Candidate PostScript names, tried in
    /// order.
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

    /// What a text's type is set by — TextOutliner keeps its outlines by it
    /// too.
    struct TypographyKey: Hashable {
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
            weight = FontLibrary.weight(of: el)
            italic = FontLibrary.isItalic(el)
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
        let paragraphs: [TextParagraph]?
        let paragraphsText: String?
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
    /// TextOutliner keeps as many outlines.
    static let cacheLimit = 256

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
        TextOutliner.fontsChanged()
    }

    /// A font of your own when the box is set in one and this phone has it;
    /// else the bundled face of its family at the nearest weight, else the
    /// system's cut of the nearest weight it has (resolveWeight's rule) —
    /// Modern Sans for a font of your own that is missing. A
    /// bundled face is used at its own weight — Anton has only one, and it is
    /// already black — and only italic is made on top, by slanting, where
    /// the family has no italic of its own. A font of your own is drawn
    /// from the face of its family nearest the weight and italic asked
    /// (CustomFonts.drawnFace) — a family of one face at that face's own
    /// weight whatever the text asks, never thickened — and italic slants
    /// it unless the face is an italic itself. The Android twin's
    /// FontLibrary.drawnWeight is the same rule.
    private static func buildFont(family key: String?, size: Double,
                                  weight: Int, italic: Bool) -> UIFont {
        registerBundledFonts()
        if CustomFonts.isCustom(key), let own = FontStore.uiFont(key, size: size, weight: weight, italic: italic) {
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
        let cuts = fallbackCuts(font)
        let drawn = nearest(Array(cuts.keys), to: weight) ?? weight
        if let name = cuts[drawn], let cut = UIFont(name: name, size: size) {
            return styled(cut, size: size, bold: false, italic: italic)
        }
        var base: UIFont?
        for name in systemNames(font) {
            if let f = UIFont(name: name, size: size) { base = f; break }
        }
        return styled(base ?? UIFont.systemFont(ofSize: size, weight: uiWeight(drawn)),
                      size: size, bold: drawn >= 600, italic: italic)
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
                          weight: FontLibrary.weight(of: el), italic: FontLibrary.isItalic(el))
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
        // where the text after the marker does. The box-wide keys only —
        // what the cache is keyed by; a box's own paragraphs are set over
        // this a line at a time (setParagraphStyles).
        let indent = Double(indentLevel(of: el)) * size * indentEm
        let boxList = el.listStyle.map { $0 != "none" } ?? false
        paragraph.firstLineHeadIndent = indent
        paragraph.headIndent = indent + (boxList ? size * markerEm : 0)
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
    /// Words in a colour, a size, a font or a link of their own (see Spans)
    /// are set so on top — in capitals, moved as the runs are.
    static func attributedString(for el: Element) -> NSAttributedString {
        let marked = markedDisplayText(for: el, pageNumber: nil, pageCount: nil)
        return styledWords(marked, of: el, capitals: el.uppercase == true, spans: displaySpans(for: el, marked: marked))
    }

    /// The words as the field typed in on the canvas lays them out: as they
    /// read, styled as the canvas draws them, but neither in capitals nor
    /// after a list's markers, as the field types the words as they are
    /// kept (InlineTextField). Where a tap puts the caret is found in it.
    static func typedAttributedString(for el: Element) -> NSAttributedString {
        let spans = el.textFill?.kind == "gradient" ? Spans.withoutColours(el.liveSpans) : el.liveSpans
        return styledWords(el.text ?? "", of: el, capitals: false, spans: spans)
    }

    /// Each line of `text` — the words of `el`, markers in or out, a line
    /// for each of its own — pushed in by its own level, a list item's
    /// marker hanging so wrapped lines start where the words after it do,
    /// over the paragraph style each run already has (the box's, or one
    /// made roomier for a larger word): the Android twin's LeadingMarginSpan
    /// per paragraph. A box with no paragraphs of its own keeps the one
    /// style it has (attributes(for:)), indented as a whole.
    static func setParagraphStyles(_ text: NSMutableAttributedString, for el: Element) {
        guard let lines = TextLists.paragraphsOf(el),
              let base = attributes(for: el)[.paragraphStyle] as? NSParagraphStyle else { return }
        let ns = text.string as NSString
        let size = el.fontSize ?? 42
        var start = 0
        for line in lines {
            guard start <= ns.length else { break }
            let lineEnd = ns.range(of: "\n", range: NSRange(location: start, length: ns.length - start)).location
            // The line and the break after it, which carries its style.
            let end = lineEnd == NSNotFound ? ns.length : lineEnd + 1
            if end > start {
                let indent = Double(line.level) * size * indentEm
                let hang = indent + (line.isListed ? size * markerEm : 0)
                // Each run keeps the style it has — the room a larger word
                // was given (RichText.makeRoom) — and takes only the indents.
                let range = NSRange(location: start, length: end - start)
                text.enumerateAttribute(.paragraphStyle, in: range) { value, part, _ in
                    let had = (value as? NSParagraphStyle) ?? base
                    let paragraph = (had.mutableCopy() as? NSMutableParagraphStyle) ?? NSMutableParagraphStyle()
                    paragraph.firstLineHeadIndent = indent
                    paragraph.headIndent = hang
                    text.addAttribute(.paragraphStyle, value: paragraph.copy(), range: part)
                }
            }
            start = end
            if lineEnd == NSNotFound { break }
        }
    }

    /// `marked` — words with their style markers — in `el`'s type, the runs
    /// and `spans` on them, in capitals when `capitals`.
    private static func styledWords(_ marked: String, of el: Element, capitals: Bool,
                                    spans: [TextSpan]) -> NSAttributedString {
        let base = attributes(for: el)
        guard RichText.hasMarkup(marked) || !spans.isEmpty else {
            let plain = NSMutableAttributedString(string: capitals ? marked.uppercased() : marked, attributes: base)
            setParagraphStyles(plain, for: el)
            return plain
        }
        let size = el.fontSize ?? 42
        let weight = FontLibrary.weight(of: el)
        let italic = FontLibrary.isItalic(el)
        // A word's own face at the box's size and weight, bold and italic
        // by the same rule as the box's own words; a plain word in a font
        // of its own with no weight or slant set is drawn at that face's
        // (weight(of:in:)), as on the Android twin.
        let face = { (family: String, bold: Bool, slanted: Bool) -> UIFont in
            let plain = !bold && !slanted
            let base = plain ? FontLibrary.weight(of: el, in: family) : weight
            let lean = plain ? FontLibrary.isItalic(el, in: family) : italic
            return FontLibrary.uiFont(family: family, size: size, weight: FontLibrary.resolveWeight(base, bold: bold),
                                      italic: slanted || lean)
        }
        // Under gradient letters a link takes no colour, as words' colours
        // do not (displaySpans), on both phones.
        let linkColour = el.textFill?.kind != "gradient"
        let styled = RichText.attributed(marked, base: base, uppercase: capitals, spans: spans,
                                         linkColour: linkColour, face: face) { bold, slanted in
            uiFont(family: el.fontFamily, size: size, weight: resolveWeight(weight, bold: bold), italic: slanted || italic)
        }
        guard TextLists.paragraphsOf(el) != nil else { return styled }
        let lined = NSMutableAttributedString(attributedString: styled)
        setParagraphStyles(lined, for: el)
        return lined
    }

    /// The weight `el` is set at: its own weight, else — set in a font of
    /// your own — that face's (CustomFonts.ownWeight), so a text set in a
    /// Bold file before faces were grouped still draws bold; else 400. The
    /// Android twin's FontLibrary.weightOf.
    static func weight(of el: Element) -> Int {
        weight(of: el, in: el.fontFamily)
    }

    /// The weight `el`'s words in the font `key` are set at (weight(of:)'s
    /// rule, with that font's face).
    static func weight(of el: Element, in key: String?) -> Int {
        if let own = el.fontWeight { return own }
        guard CustomFonts.isCustom(key) else { return 400 }
        return CustomFonts.ownWeight(key, among: FontStore.faces()) ?? 400
    }

    /// Whether `el` is set in italic: its own say, else its font of your
    /// own's face's (weight(of:)'s rule). The Android twin's
    /// FontLibrary.italicOf.
    static func isItalic(_ el: Element) -> Bool {
        isItalic(el, in: el.fontFamily)
    }

    /// Whether `el`'s words in the font `key` are set in italic.
    static func isItalic(_ el: Element, in key: String?) -> Bool {
        if let own = el.italic { return own }
        guard CustomFonts.isCustom(key) else { return false }
        return CustomFonts.ownItalic(key, among: FontStore.faces()) ?? false
    }

    /// The weight a box's words at `weight` are drawn at, **bold** ones
    /// heavier: 700, or 900 when the box is already bold — on both phones,
    /// a word's own face too.
    static func resolveWeight(_ weight: Int, bold: Bool) -> Int {
        bold ? (weight >= 700 ? 900 : 700) : weight
    }

    /// Display text with the inline style markers still in it.
    static func markedDisplayText(for el: Element, pageNumber: Int?, pageCount: Int?) -> String {
        var raw = el.text ?? ""
        if let pageNumber { raw = raw.replacingOccurrences(of: "{page}", with: String(pageNumber)) }
        if let pageCount { raw = raw.replacingOccurrences(of: "{pages}", with: String(pageCount)) }
        guard isList(el) else { return raw }
        let lines = raw.components(separatedBy: "\n")
        return zip(listPrefixes(for: el), lines).map { $0 + $1 }.joined(separator: "\n")
    }

    /// The marker each line of a list starts with, by line: none for a
    /// blank one, which is not counted, and each line's own by its level
    /// when the box sets its lines one by one (TextLists.items).
    private static func listPrefixes(for el: Element) -> [String] {
        TextLists.markers(el).map { $0 ?? "" }
    }

    // MARK: colours, sizes, fonts and links on words

    /// The element's colours, sizes, fonts and links on words, moved from
    /// the words as they read onto the display text before capitals — past
    /// a list's markers, a line at a time. Colours are left out while the
    /// letters are a gradient, which they would not show through. None when
    /// the words do not read as the spans expect.
    static func displaySpans(for el: Element, marked: String) -> [TextSpan] {
        var spans = el.liveSpans
        guard !spans.isEmpty else { return [] }
        if el.textFill?.kind == "gradient" {
            spans = Spans.withoutColours(spans)
            guard !spans.isEmpty else { return [] }
        }
        guard isList(el) else { return spans }
        // Each line moves along by the markers before it, its own included.
        let typed = RichText.strip(el.text ?? "").components(separatedBy: "\n")
        let raw = (el.text ?? "").components(separatedBy: "\n")
        guard typed.count == raw.count else { return [] }
        let prefixes = listPrefixes(for: el)
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
    /// what text round a curve, along a path or down a column is drawn in —
    /// linked words in the link colour unless they have their own. Sizes
    /// and faces are left out there, where the letters keep the box's type.
    static func displayColours(for el: Element) -> [TextSpan] {
        let marked = markedDisplayText(for: el, pageNumber: nil, pageCount: nil)
        let gradient = el.textFill?.kind == "gradient"
        let colours = displaySpans(for: el, marked: marked).compactMap { span -> TextSpan? in
            let linked = span.link != nil && !gradient ? Spans.linkColour : nil
            return (span.color ?? linked).map { TextSpan(start: span.start, end: span.end, color: $0) }
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

    /// Whether some words are set larger or smaller than the box's type, or
    /// in a face of their own, so measuring has to take them in.
    static func hasSizedWords(_ el: Element) -> Bool {
        el.liveSpans.contains { $0.scale != nil || $0.font != nil }
    }

    /// One indent level, in ems.
    static let indentEm = 1.5
    /// Room a list marker takes, in ems; wrapped lines hang under the text.
    static let markerEm = 1.4

    static let listStyles = ["none", "bullet", "number", "letter"]
    static let maxIndent = 4

    /// Whether any line is a list item: the box-wide style, or any of its
    /// own paragraphs' (TextLists).
    static func isList(_ el: Element) -> Bool {
        TextLists.isList(el)
    }

    static func indentLevel(of el: Element) -> Int {
        min(maxIndent, max(0, el.indent ?? 0))
    }

    /// The prefix a line of a box-wide list gets, by style and one-based
    /// position among the non-blank lines: the first level's marker
    /// (TextLists.marker). Letters run a…z then aa, ab… so the 27th item is
    /// not a crash and not "{".
    static func listMarker(style: String?, index: Int) -> String? {
        TextLists.marker(style, level: 0, index: index)
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
                             spans: el.spans, spansText: el.spansText,
                             paragraphs: el.paragraphs, paragraphsText: el.paragraphsText)
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
        // Words set larger or smaller are measured as they are drawn, and
        // each line at its own indent.
        let str: NSAttributedString
        if hasSizedWords(el) {
            str = attributedString(for: el)
        } else {
            let plain = NSMutableAttributedString(string: displayText(for: el), attributes: attributes(for: el))
            setParagraphStyles(plain, for: el)
            str = plain
        }
        let bounds = str.boundingRect(
            with: CGSize(width: el.w, height: .greatestFiniteMagnitude),
            options: [.usesLineFragmentOrigin, .usesFontLeading],
            context: nil)
        let lineHeight = (el.fontSize ?? 42) * (el.lineHeight ?? 1.25)
        return max(ceil(bounds.height), lineHeight)
    }
}
